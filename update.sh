#!/bin/bash

set -euo pipefail

PKG_MGR=""
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
else
    echo "No supported package manager found (apt/dnf/yum)."
    exit 1
fi

echo "Using package manager: $PKG_MGR"

run_step() {
    local message="$1"
    shift
    echo "$message"
    "$@"
}

package_installed() {
    local package_name="$1"

    if [[ "$PKG_MGR" == "apt" ]]; then
        dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"
    elif [[ "$PKG_MGR" == "dnf" ]]; then
        rpm -q "$package_name" >/dev/null 2>&1
    else
        rpm -q "$package_name" >/dev/null 2>&1
    fi
}

update_selected_packages() {
    local packages=()
    local package_name

    for package_name in "$@"; do
        if package_installed "$package_name"; then
            packages+=("$package_name")
        fi
    done

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi

    echo "Updating installed security-sensitive packages: ${packages[*]}"
    if [[ "$PKG_MGR" == "apt" ]]; then
        sudo apt install --only-upgrade -y "${packages[@]}"
    elif [[ "$PKG_MGR" == "dnf" ]]; then
        sudo dnf upgrade -y --refresh "${packages[@]}"
    else
        sudo yum update -y "${packages[@]}"
    fi
}

update_python_cryptography() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        return 0
    fi

    if python3 -m pip show cryptography >/dev/null 2>&1; then
        echo "Upgrading Python package: cryptography"
        python3 -m pip install --upgrade --user cryptography || true
    fi
}

check_reboot_required() {
    if [[ "$PKG_MGR" == "apt" ]]; then
        if [[ -f /var/run/reboot-required ]]; then
            echo "Reboot required to finish applying kernel or core library updates."
        fi
        return 0
    fi

    if command -v needs-restarting >/dev/null 2>&1; then
        if ! sudo needs-restarting -r; then
            echo "Reboot required to finish applying kernel or core library updates."
        fi
    fi
}

run_step "Refreshing and upgrading system packages..." true
if [[ "$PKG_MGR" == "apt" ]]; then
    sudo apt update
    sudo apt upgrade -y
    sudo apt dist-upgrade -y
elif [[ "$PKG_MGR" == "dnf" ]]; then
    sudo dnf upgrade -y --refresh
else
    sudo yum update -y
fi

if [[ "$PKG_MGR" == "apt" ]]; then
    update_selected_packages firefox thunderbird openssh-client openssh-server dnsmasq libvpx7 libsndfile1
else
    update_selected_packages chromium chromium-common flatpak flatpak-libs firefox thunderbird kernel kernel-core dnsmasq protobuf protobuf-lite libvpx webkit2gtk3-jsc openssh openssh-clients python3 python-unversioned-command containernetworking-plugins libsndfile
fi

if command -v flatpak >/dev/null 2>&1; then
    run_step "Updating Flatpak packages..." sudo flatpak update -y
fi

update_python_cryptography

for service in docker kubelet; do
    if systemctl list-unit-files | grep -q "^${service}\.service"; then
        echo "Restarting ${service}"
        sudo systemctl restart "$service"
    else
        echo "Skipping ${service}: service not installed."
    fi
done

if [[ "$PKG_MGR" == "apt" ]]; then
    sudo apt autoremove -y
    sudo apt-get clean
elif [[ "$PKG_MGR" == "dnf" ]]; then
    sudo dnf autoremove -y || true
    sudo dnf clean all
else
    sudo yum autoremove -y || true
    sudo yum clean all
fi

check_reboot_required

if [[ "$PKG_MGR" == "apt" ]]; then
    sudo apt update
elif [[ "$PKG_MGR" == "dnf" ]]; then
    sudo dnf check-update || true
else
    sudo yum check-update || true
fi
# Transfer Data to S3 Bucket

# Define the S3 bucket name
S3_BUCKET="s3://aws-163544304364-repo"

# Define the directories and files to back up
ITEMS=(
    # "/home/kkhoja/Code/100-days-of-Python"
    "/home/kkhoja/Code/Ansible"
    "/home/kkhoja/Code/Boto3"
    "/home/kkhoja/Code/CloudFormation"
    "/home/kkhoja/Code/My-Notes"
    "/home/kkhoja/Code/Terraform-Notes"
    "/home/kkhoja/Code/Kubernetes"
    "/home/kkhoja/Code/shell-script"
    # "/home/kkhoja/Code/Docker"
    # "/home/kkhoja/Code/Flask"


)

# Arrays to keep track of successful and failed transfers
SUCCESSFUL_ITEMS=()
FAILED_ITEMS=()

# Loop through each item and copy it to the S3 bucket
for ITEM in "${ITEMS[@]}"; do
    # Extract the folder or file name from the path
    ITEM_NAME=$(basename "$ITEM")

    if [ -d "$ITEM" ]; then
        # If it's a directory, use --recursive
        aws s3 cp "$ITEM/" "$S3_BUCKET/$ITEM_NAME/" --recursive --storage-class GLACIER_IR
    else
        # If it's a file, do not use --recursive
        aws s3 cp "$ITEM" "$S3_BUCKET/$ITEM_NAME" --storage-class GLACIER_IR
    fi

    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Successfully backed up $ITEM to $S3_BUCKET/$ITEM_NAME"
        SUCCESSFUL_ITEMS+=("$ITEM")
    else
        echo "Failed to back up $ITEM"
        FAILED_ITEMS+=("$ITEM")
    fi

    # Pause for 5 seconds
    sleep 2
done

# Echo the results
echo "Backup to S3 bucket $S3_BUCKET is completed!"

if [ ${#SUCCESSFUL_ITEMS[@]} -ne 0 ]; then
    echo "Successfully backed up the following items:"
    for ITEM in "${SUCCESSFUL_ITEMS[@]}"; do
        echo "$ITEM"
    done
else
    echo "No items were successfully backed up."
fi

if [ ${#FAILED_ITEMS[@]} -ne 0 ]; then
    echo "Failed to back up the following items:"
    for ITEM in "${FAILED_ITEMS[@]}"; do
        echo "$ITEM"
    done
else
    echo "No items failed to back up."
fi
# Prompt: Notify that the update is completed
echo "Your DevBox is updated!"

#  The script is self-explanatory. It updates the packages and dependencies, restarts necessary services, removes old kernels and unnecessary files,
#  and reloads Apache configuration if needed.
#  You can also uncomment the lines to transfer data to S3, list outdated pip packages, or perform any other tasks you want to automate.
#  To run the script, you can use the following command:
#  $ bash update.sh

#  You can also make the script executable and run it as follows:
#  $ chmod +x update.sh

