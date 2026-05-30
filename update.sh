#!/bin/bash
set -euo pipefail

# Fast pre-check before sudo to avoid spawning extra wrapper processes.
if [[ "${EUID}" -ne 0 ]]; then
    if ps -ef | grep -E 'sudo -E bash ./update.sh|/bin/dnf ' | grep -v grep >/dev/null 2>&1; then
        echo "Update already running"
        ps -ef | grep -E '/bin/dnf|./update.sh' | grep -v grep || true
        exit 1
    fi
fi

# Elevate once at startup.
if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

LOCK_FILE="/tmp/devbox_update.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Update already running"
    ps -ef | grep -E '/bin/dnf|./update.sh' | grep -v grep || true
    exit 1
fi
trap 'rm -f "$LOCK_FILE"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/update.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== DevBox Update Started: $(date) ====="

NO_REBOOT_MODE="${NO_REBOOT_MODE:-1}"
CHECK_INSPECTOR_FINDINGS="${CHECK_INSPECTOR_FINDINGS:-1}"
HARDEN_ON_INSPECTOR_ERROR="${HARDEN_ON_INSPECTOR_ERROR:-1}"
RUN_S3_BACKUP="${RUN_S3_BACKUP:-0}"
INSPECTOR_STATUS="not-run"

RUN_TARGETED_HARDENING=0

if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
else
    echo "No supported package manager found"
    exit 1
fi

echo "Using package manager: $PKG_MGR"

AWS_BIN="$(command -v aws || true)"

run_aws_cli() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        local aws_home="/home/${SUDO_USER}"
        local aws_path="/usr/local/bin:/usr/bin:/bin:${aws_home}/.local/bin"
        sudo -u "$SUDO_USER" -H env HOME="$aws_home" PATH="$aws_path" aws "$@"
    else
        if [[ -z "$AWS_BIN" ]]; then
            return 1
        fi
        "$AWS_BIN" "$@"
    fi
}

get_ec2_identity() {
    local token

    token=$(curl -sS -m 2 -X PUT \
        "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)

    [[ -z "$token" ]] && return 1

    INSTANCE_ID=$(curl -sS -m 2 \
        -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/meta-data/instance-id" || true)

    AWS_REGION=$(curl -sS -m 2 \
        -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/dynamic/instance-identity/document" \
        | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    [[ -n "${INSTANCE_ID:-}" && -n "${AWS_REGION:-}" ]]
}

inspector_has_findings() {
    if [[ "$CHECK_INSPECTOR_FINDINGS" != "1" ]]; then
        INSPECTOR_STATUS="disabled"
        return 1
    fi

    if ! get_ec2_identity; then
        INSPECTOR_STATUS="metadata-unavailable"
        return 1
    fi

    local arn
    arn=$(run_aws_cli inspector2 list-findings \
        --region "$AWS_REGION" \
        --max-results 1 \
        --filter-criteria "{\"resourceType\":[{\"comparison\":\"EQUALS\",\"value\":\"AWS_EC2_INSTANCE\"}],\"resourceId\":[{\"comparison\":\"EQUALS\",\"value\":\"$INSTANCE_ID\"}],\"findingStatus\":[{\"comparison\":\"EQUALS\",\"value\":\"ACTIVE\"}]}" \
        --query 'findings[0].findingArn' \
        --output text 2>/dev/null || true)

    if [[ -z "$arn" ]]; then
        INSPECTOR_STATUS="query-failed"
        return 1
    fi

    if [[ "$arn" == "None" ]]; then
        INSPECTOR_STATUS="no-findings"
        return 1
    fi

    INSPECTOR_STATUS="findings-present"
    return 0
}

echo "Refreshing system packages..."
if [[ "$PKG_MGR" == "dnf" ]]; then
    if [[ "$NO_REBOOT_MODE" == "1" ]]; then
        dnf upgrade -y --refresh --exclude=kernel --exclude=kernel-core
    else
        dnf upgrade -y --refresh
    fi
    # Remove duplicate RPM versions; duplicates keep Inspector findings active.
    dnf remove --duplicates -y || true
elif [[ "$PKG_MGR" == "yum" ]]; then
    if [[ "$NO_REBOOT_MODE" == "1" ]]; then
        yum update -y --exclude=kernel --exclude=kernel-core
    else
        yum update -y
    fi
else
    apt update
    apt upgrade -y
fi

if inspector_has_findings; then
    RUN_TARGETED_HARDENING=1
    echo "Inspector ACTIVE -> enabling hardening"
else
    echo "Inspector status: $INSPECTOR_STATUS"
    [[ "$HARDEN_ON_INSPECTOR_ERROR" == "1" ]] && RUN_TARGETED_HARDENING=1
fi

if [[ "$RUN_TARGETED_HARDENING" == "1" ]]; then
    echo "Running targeted hardening..."
    if [[ "$PKG_MGR" == "dnf" ]]; then
        dnf upgrade -y chromium chromium-common firefox thunderbird openssh openssh-clients dnsmasq protobuf protobuf-lite libvpx webkit2gtk3-jsc python3 containernetworking-plugins libsndfile || true
    elif [[ "$PKG_MGR" == "yum" ]]; then
        yum update -y chromium chromium-common firefox thunderbird openssh openssh-clients dnsmasq protobuf protobuf-lite libvpx webkit2gtk3-jsc python3 containernetworking-plugins libsndfile || true
    else
        apt install --only-upgrade -y firefox thunderbird openssh-client openssh-server dnsmasq || true
    fi
fi

if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y || true
fi

echo "Skipping pip upgrades (prevents urllib3/requests conflicts)"

for svc in docker kubelet; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" || true
    fi
done

if [[ "$PKG_MGR" == "dnf" ]]; then
    dnf autoremove -y || true
    dnf clean all || true
elif [[ "$PKG_MGR" == "yum" ]]; then
    yum autoremove -y || true
    yum clean all || true
else
    apt autoremove -y
    apt clean
fi

# Kernel findings remain until the system boots into the latest installed kernel.
if [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    CURRENT_KERNEL="$(uname -r)"
    LATEST_KERNEL="$(rpm -q --last kernel | head -n1 | awk '{print $1}' | sed 's/^kernel-//' || true)"
    if [[ -n "$LATEST_KERNEL" && "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]]; then
        echo "Kernel reboot pending: running=$CURRENT_KERNEL latest_installed=$LATEST_KERNEL"
    fi
fi

if [[ "$RUN_S3_BACKUP" == "1" ]]; then
    echo "Running S3 backup..."
    S3_BUCKET="s3://aws-163544304364-repo"
    ITEMS=(
        "/home/kkhoja/Code/Ansible"
        "/home/kkhoja/Code/Boto3"
        "/home/kkhoja/Code/CloudFormation"
        "/home/kkhoja/Code/My-Notes"
        "/home/kkhoja/Code/Terraform-Notes"
        "/home/kkhoja/Code/Kubernetes"
        "/home/kkhoja/Code/shell-script"
    )

    for item in "${ITEMS[@]}"; do
        name=$(basename "$item")
        if [[ -d "$item" ]]; then
            run_aws_cli s3 cp "$item/" "$S3_BUCKET/$name/" --recursive --storage-class GLACIER_IR || true
        elif [[ -f "$item" ]]; then
            run_aws_cli s3 cp "$item" "$S3_BUCKET/$name" --storage-class GLACIER_IR || true
        fi
    done
fi

echo "===== DevBox Update Completed: $(date) ====="
