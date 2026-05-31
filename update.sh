#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/update.txt"
touch "$LOG_FILE" 2>/dev/null || true

# Print to terminal immediately (not buffered through a pipe).
say() {
    printf '%s\n' "$@" >>"$LOG_FILE"
    if [[ -w /dev/tty ]] 2>/dev/null; then
        printf '%s\n' "$@" >/dev/tty
    else
        printf '%s\n' "$@"
    fi
}

update_already_running() {
    local pid
    while read -r pid; do
        [[ -z "$pid" || "$pid" == "$$" ]] && continue
        return 0
    done < <(pgrep -f '[/]update\.sh' 2>/dev/null || true)
    return 1
}

setup_output_logging() {
    if [[ -w /dev/tty ]] 2>/dev/null; then
        if command -v stdbuf >/dev/null 2>&1; then
            exec > >(stdbuf -oL tee -a "$LOG_FILE" /dev/tty) 2>&1
        else
            exec > >(tee -a "$LOG_FILE" /dev/tty) 2>&1
        fi
    else
        exec >>"$LOG_FILE" 2>&1
    fi
}

# Fast pre-check before sudo.
if [[ "${EUID}" -ne 0 ]]; then
    if update_already_running; then
        say "Update already running — check: ps -ef | grep update.sh"
        ps -ef | grep -E '[/]update\.sh|sudo.*update\.sh' | grep -v grep || true
        exit 1
    fi
    say "DevBox update: you will be prompted for your sudo password next."
    say "If the screen looks blank, type your password and press Enter."
    exec sudo -E bash "$0" "$@"
fi

LOCK_FILE="/tmp/devbox_update.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    say "Update already running (lock held on $LOCK_FILE)"
    fuser -v "$LOCK_FILE" 2>/dev/null || true
    ps -ef | grep -E '[/]update\.sh' | grep -v grep || true
    exit 1
fi

setup_output_logging
export DNF_PROGRESS=1

say "===== DevBox Update Started: $(date) ====="
say "Logging to $LOG_FILE (output also shown here)"

NO_REBOOT_MODE="${NO_REBOOT_MODE:-1}"
CHECK_INSPECTOR_FINDINGS="${CHECK_INSPECTOR_FINDINGS:-1}"
RUN_S3_BACKUP="${RUN_S3_BACKUP:-0}"
INSPECTOR_STATUS="not-run"
INSPECTOR_TOTAL=0
INSPECTOR_REMEDIATE=0
INSPECTOR_RPM_PACKAGES=()
INSPECTOR_PIP_PACKAGES=()

# RPM packages commonly flagged together with kernel/browser CVEs.
INSPECTOR_RPM_FALLBACK=(
    chromium chromium-common firefox thunderbird flatpak flatpak-libs
    openssh openssh-clients dnsmasq protobuf protobuf-lite libvpx
    webkit2gtk3-jsc python3 containernetworking-plugins libsndfile
    glibc glibc-all-langpacks libbrotli kernel kernel-core
)

KNOWN_PIP_PACKAGES=(cryptography Jinja2 pip virtualenv lxml ansible-core idna)

if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
else
    say "No supported package manager found"
    exit 1
fi

say "Using package manager: $PKG_MGR"

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

run_pip_cli() {
    local pip_bin="pip3"
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        local user_home="/home/${SUDO_USER}"
        local user_path="/usr/local/bin:/usr/bin:/bin:${user_home}/.local/bin"
        sudo -u "$SUDO_USER" -H env HOME="$user_home" PATH="$user_path" "$pip_bin" "$@"
    elif command -v "$pip_bin" >/dev/null 2>&1; then
        "$pip_bin" "$@"
    else
        return 1
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

inspector_active_filter_json() {
    printf '{"resourceType":[{"comparison":"EQUALS","value":"AWS_EC2_INSTANCE"}],"resourceId":[{"comparison":"EQUALS","value":"%s"}],"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}' \
        "$INSTANCE_ID"
}

is_known_pip_package() {
    local pkg="$1"
    local known
    for known in "${KNOWN_PIP_PACKAGES[@]}"; do
        [[ "$pkg" == "$known" ]] && return 0
    done
    return 1
}

classify_inspector_package() {
    local pkg="$1"
    if rpm -q "$pkg" &>/dev/null 2>&1; then
        INSPECTOR_RPM_PACKAGES+=("$pkg")
    elif run_pip_cli show "$pkg" &>/dev/null 2>&1; then
        INSPECTOR_PIP_PACKAGES+=("$pkg")
    elif is_known_pip_package "$pkg"; then
        INSPECTOR_PIP_PACKAGES+=("$pkg")
    else
        INSPECTOR_RPM_PACKAGES+=("$pkg")
    fi
}

# Uses small AWS CLI queries (full JSON in env vars hits ARG_MAX).
inspector_refresh_summary() {
    local label="${1:-Inspector}"
    local filter counts_line severities packages_raw pkg sev count parts

    INSPECTOR_TOTAL=0
    INSPECTOR_RPM_PACKAGES=()
    INSPECTOR_PIP_PACKAGES=()

    if [[ "$CHECK_INSPECTOR_FINDINGS" != "1" ]]; then
        INSPECTOR_STATUS="disabled"
        say "$label: checks disabled (CHECK_INSPECTOR_FINDINGS=0)"
        return 1
    fi

    if ! get_ec2_identity; then
        INSPECTOR_STATUS="metadata-unavailable"
        say "$label: EC2 metadata unavailable (not on EC2 or IMDS blocked)"
        return 1
    fi

    filter="$(inspector_active_filter_json)"

    INSPECTOR_TOTAL=$(run_aws_cli inspector2 list-findings \
        --region "$AWS_REGION" \
        --max-results 100 \
        --filter-criteria "$filter" \
        --query 'length(findings)' \
        --output text 2>/dev/null || true)

    if [[ -z "$INSPECTOR_TOTAL" || "$INSPECTOR_TOTAL" == "None" ]]; then
        INSPECTOR_STATUS="query-failed"
        say "$label: AWS Inspector query failed (check aws CLI/credentials/inspector2 permissions)"
        return 1
    fi

    if [[ "$INSPECTOR_TOTAL" -gt 0 ]]; then
        INSPECTOR_STATUS="findings-present"
        INSPECTOR_REMEDIATE=1
    else
        INSPECTOR_STATUS="no-findings"
        INSPECTOR_REMEDIATE=0
        say "$label ($INSTANCE_ID @ $AWS_REGION): TOTAL=0 (clean)"
        return 1
    fi

    declare -A SEV_COUNTS=()
    severities=$(run_aws_cli inspector2 list-findings \
        --region "$AWS_REGION" \
        --max-results 100 \
        --filter-criteria "$filter" \
        --query 'findings[].severity' \
        --output text 2>/dev/null || true)

    if [[ -n "$severities" && "$severities" != "None" ]]; then
        while IFS= read -r sev; do
            [[ -z "$sev" ]] && continue
            SEV_COUNTS["$sev"]=$(( ${SEV_COUNTS["$sev"]:-0} + 1 ))
        done < <(tr '\t' '\n' <<<"$severities")
    fi

    parts=()
    for sev in CRITICAL HIGH MEDIUM LOW INFORMATIONAL UNTRIAGED; do
        count="${SEV_COUNTS[$sev]:-0}"
        [[ "$count" -gt 0 ]] && parts+=("${sev}=${count}")
    done
    counts_line="COUNTS|$(IFS=,; echo "${parts[*]}")|TOTAL=${INSPECTOR_TOTAL}"
    say "$label ($INSTANCE_ID @ $AWS_REGION): $counts_line"

    packages_raw=$(run_aws_cli inspector2 list-findings \
        --region "$AWS_REGION" \
        --max-results 100 \
        --filter-criteria "$filter" \
        --query 'findings[].packageVulnerabilityDetails.vulnerablePackages[].name' \
        --output text 2>/dev/null || true)

    if [[ -n "$packages_raw" && "$packages_raw" != "None" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            classify_inspector_package "$pkg"
        done < <(tr '\t' '\n' <<<"$packages_raw" | awk 'NF && !seen[$0]++')
    fi

    say "$label packages (rpm): ${INSPECTOR_RPM_PACKAGES[*]-}"
    say "$label packages (pip): ${INSPECTOR_PIP_PACKAGES[*]-}"
    return 0
}

unique_packages() {
    printf '%s\n' "$@" | awk 'NF && !seen[$0]++'
}

prepare_dnf_for_upgrade() {
    [[ "$PKG_MGR" != "dnf" && "$PKG_MGR" != "yum" ]] && return 0

    say "Preparing RPM database (remove duplicates, skip broken)..."
    if [[ "$PKG_MGR" == "dnf" ]]; then
        dnf remove --duplicates -y 2>&1 || true
        # Broken partial kernel installs block all dnf transactions.
        dnf upgrade -y --refresh --exclude=kernel --exclude=kernel-core --skip-broken 2>&1 || true
    else
        yum remove --duplicates -y 2>&1 || true
        yum update -y --exclude=kernel --exclude=kernel-core --skip-broken 2>&1 || true
    fi
}

pkg_manager_upgrade() {
    local exclude_kernel="${1:-0}"
    local rc=0

    if [[ "$PKG_MGR" == "dnf" ]]; then
        if [[ "$exclude_kernel" == "1" ]]; then
            dnf upgrade -y --refresh --exclude=kernel --exclude=kernel-core --skip-broken || rc=$?
        else
            dnf upgrade -y --refresh --skip-broken || rc=$?
        fi
        dnf remove --duplicates -y 2>&1 || true
    elif [[ "$PKG_MGR" == "yum" ]]; then
        if [[ "$exclude_kernel" == "1" ]]; then
            yum update -y --exclude=kernel --exclude=kernel-core --skip-broken || rc=$?
        else
            yum update -y --skip-broken || rc=$?
        fi
    else
        apt update || rc=$?
        apt upgrade -y || rc=$?
    fi

    if [[ "$rc" -ne 0 ]]; then
        say "WARNING: package manager upgrade exited with code $rc (see lines above)"
    fi
    return 0
}

upgrade_inspector_rpm_packages() {
    local -a rpm_targets=()
    local pkg

    for pkg in "${INSPECTOR_RPM_PACKAGES[@]}" "${INSPECTOR_RPM_FALLBACK[@]}"; do
        rpm_targets+=("$pkg")
    done

    mapfile -t rpm_targets < <(unique_packages "${rpm_targets[@]}")
    [[ "${#rpm_targets[@]}" -eq 0 ]] && return 0

    say "Upgrading Inspector-related RPM packages (${#rpm_targets[@]} names)..."
    if [[ "$PKG_MGR" == "dnf" ]]; then
        dnf upgrade -y --skip-broken "${rpm_targets[@]}" 2>&1 || true
    elif [[ "$PKG_MGR" == "yum" ]]; then
        yum update -y --skip-broken "${rpm_targets[@]}" 2>&1 || true
    else
        apt install --only-upgrade -y "${rpm_targets[@]}" 2>&1 || true
    fi
}

upgrade_inspector_pip_packages() {
    local -a pip_targets=()
    local pkg

    for pkg in "${INSPECTOR_PIP_PACKAGES[@]}"; do
        pip_targets+=("$pkg")
    done

    mapfile -t pip_targets < <(unique_packages "${pip_targets[@]}")
    [[ "${#pip_targets[@]}" -eq 0 ]] && return 0

    if ! command -v pip3 >/dev/null 2>&1 && ! run_pip_cli --version &>/dev/null; then
        say "pip3 not available; skipping pip remediation"
        return 0
    fi

    say "Upgrading Inspector-related pip packages (${#pip_targets[@]} names)..."
    for pkg in "${pip_targets[@]}"; do
        if run_pip_cli show "$pkg" &>/dev/null; then
            say "  pip install --upgrade $pkg"
            run_pip_cli install --upgrade "$pkg" 2>&1 || true
        else
            say "  pip install --upgrade $pkg (not currently installed)"
            run_pip_cli install --upgrade "$pkg" 2>&1 || true
        fi
    done
}

remediate_inspector_findings() {
    say "===== Inspector remediation ====="
    upgrade_inspector_rpm_packages

    if command -v flatpak >/dev/null 2>&1; then
        say "Updating flatpak runtimes/apps..."
        flatpak update -y 2>&1 || true
    fi

    upgrade_inspector_pip_packages
    say "===== Inspector remediation pass complete ====="
}

prepare_dnf_for_upgrade

# --- Always check Inspector before updates ---
INSPECTOR_REMEDIATE=0
say "Checking AWS Inspector (before update)..."
if inspector_refresh_summary "Inspector (before update)"; then
    say "Active Inspector findings detected"
else
    say "Inspector status: $INSPECTOR_STATUS"
fi

say "Refreshing system packages (dnf may take several minutes)..."
if [[ "$INSPECTOR_REMEDIATE" == "1" ]]; then
    say "Active Inspector findings -> full upgrade including kernel"
    pkg_manager_upgrade 0
else
    if [[ "$NO_REBOOT_MODE" == "1" && ( "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ) ]]; then
        pkg_manager_upgrade 1
    else
        pkg_manager_upgrade 0
    fi
fi

if [[ "$INSPECTOR_REMEDIATE" == "1" ]]; then
    remediate_inspector_findings
elif [[ "$INSPECTOR_STATUS" == "no-findings" ]]; then
    say "No active Inspector findings; standard refresh only"
else
    say "Inspector status: $INSPECTOR_STATUS (skipping targeted remediation)"
fi

for svc in docker kubelet; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" || true
    fi
done

if [[ "$PKG_MGR" == "dnf" ]]; then
    dnf autoremove -y 2>&1 || true
    dnf clean all 2>&1 || true
elif [[ "$PKG_MGR" == "yum" ]]; then
    yum autoremove -y 2>&1 || true
    yum clean all 2>&1 || true
else
    apt autoremove -y 2>&1 || true
    apt clean 2>&1 || true
fi

# Kernel findings remain until the system boots into the latest installed kernel.
if [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    CURRENT_KERNEL="$(uname -r)"
    LATEST_KERNEL="$(rpm -q --last kernel 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/^kernel-//' || true)"
    if [[ -n "$LATEST_KERNEL" && "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]]; then
        say "Kernel reboot pending: running=$CURRENT_KERNEL latest_installed=$LATEST_KERNEL"
        say "Reboot required to clear kernel-related Inspector findings"
    fi
fi

# --- Always re-check Inspector after updates ---
INSPECTOR_REMEDIATE=0
say "Checking AWS Inspector (after update)..."
if inspector_refresh_summary "Inspector (after update)"; then
    say "WARNING: Active Inspector findings remain. Re-run after reboot if kernel was upgraded."
    say "  sudo NO_REBOOT_MODE=0 $SCRIPT_DIR/update.sh && sudo reboot"
else
    if [[ "$INSPECTOR_STATUS" == "no-findings" ]]; then
        say "Inspector: no active CRITICAL/HIGH/MEDIUM/LOW findings"
    fi
fi

if [[ "$RUN_S3_BACKUP" == "1" ]]; then
    say "Running S3 backup..."
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

say "===== DevBox Update Completed: $(date) ====="
