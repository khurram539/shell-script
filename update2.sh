#!/bin/bash

# Print start time
echo "Starting system update at $(date)"

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1 completed successfully"
    else
        echo "❌ $1 failed"
        # Optional: exit 1
    fi
}

# Update package lists and upgrade system
echo "📦 Updating system packages..."
sudo apt update
check_status "Package list update"

# Upgrade all packages
sudo apt upgrade -y
check_status "Package upgrade"

# Perform distribution upgrade
sudo apt dist-upgrade -y
check_status "Distribution upgrade"

# Update snap packages
echo "🔄 Updating snap packages..."
sudo snap refresh
check_status "Snap package update"

# Check for specific snap packages
snap info notepad-plus-plus
sudo snap refresh notepad-plus-plus
check_status "Notepad++ snap update"

# Download the latest Discord package
wget -O ~/discord.deb "https://discordapp.com/api/download?platform=linux&format=deb"

# Install the downloaded package
sudo dpkg -i ~/discord.deb

# Fix any dependency issues
sudo apt-get install -f -y

# Clean up
rm ~/discord.deb

echo "Discord has been updated to the latest version."

# Update flatpak packages if installed
if command -v flatpak >/dev/null 2>&1; then
    echo "🔄 Updating flatpak packages..."
    flatpak update -y
    check_status "Flatpak update"
fi

# Python package management
echo "🐍 Managing Python packages..."

# Ensure pip is installed and updated
if ! command -v pip >/dev/null 2>&1; then
    sudo apt install python3-pip -y
    check_status "pip installation"
fi

# Upgrade pip itself
python3 -m pip install --upgrade pip
check_status "pip upgrade"

# Create virtual environment if it doesn't exist
if [ ! -d "$HOME/venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$HOME/venv"
    check_status "Virtual environment creation"
fi

# Activate virtual environment
source "$HOME/venv/bin/activate"

# Update all pip packages
echo "Updating pip packages..."
pip list --outdated --format=columns > outdated.txt
while read -r package version latest type; do
    if [ "$package" != "Package" ] && [ -n "$package" ]; then
        pip install --upgrade "$package"
        check_status "Upgrade of $package"
    fi
done < outdated.txt

# Restart essential services
echo "🔄 Restarting services..."
if systemctl is-active docker >/dev/null 2>&1; then
    sudo systemctl restart docker
    check_status "Docker restart"
fi

if systemctl is-active kubelet >/dev/null 2>&1; then
    sudo systemctl restart kubelet
    check_status "Kubelet restart"
fi

# Cleanup
echo "🧹 Cleaning up system..."
sudo apt autoremove -y
sudo apt-get clean
check_status "System cleanup"

# S3 Backup Section
echo "☁️ Starting S3 backup..."

# Define the S3 bucket name
S3_BUCKET="s3://aws-163544304364-repo"

# Define the directories to back up
ITEMS=(
    "/home/khurram539/Code/100-days-of-Python"
    "/home/khurram539/Code/Ansible"
    "/home/khurram539/Code/Boto3"
    "/home/khurram539/Code/My-Notes"
    "/home/khurram539/Code/Terraform-Notes"
    "/home/khurram539/Code/shell-script"
)

# Arrays to track transfers
SUCCESSFUL_ITEMS=()
FAILED_ITEMS=()

# Verify AWS CLI is installed
if ! command -v aws >/dev/null 2>&1; then
    echo "❌ AWS CLI is not installed. Installing..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    check_status "AWS CLI installation"
fi

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Perform S3 backup with progress monitoring
for ITEM in "${ITEMS[@]}"; do
    if [ -e "$ITEM" ]; then
        ITEM_NAME=$(basename "$ITEM")
        echo "📤 Backing up $ITEM_NAME to S3..."
        
        if [ -d "$ITEM" ]; then
            aws s3 cp "$ITEM/" "$S3_BUCKET/$ITEM_NAME/" \
                --recursive \
                --storage-class GLACIER_IR \
                --only-show-errors
        else
            aws s3 cp "$ITEM" "$S3_BUCKET/$ITEM_NAME" \
                --storage-class GLACIER_IR \
                --only-show-errors
        fi
        
        if [ $? -eq 0 ]; then
            SUCCESSFUL_ITEMS+=("$ITEM")
            echo "✅ Successfully backed up $ITEM_NAME"
        else
            FAILED_ITEMS+=("$ITEM")
            echo "❌ Failed to back up $ITEM_NAME"
        fi
    else
        echo "⚠️ Warning: $ITEM does not exist"
        FAILED_ITEMS+=("$ITEM")
    fi
done

# Print backup summary
echo -e "\n📊 Backup Summary:"
echo "===================="
if [ ${#SUCCESSFUL_ITEMS[@]} -ne 0 ]; then
    echo "✅ Successfully backed up:"
    printf '%s\n' "${SUCCESSFUL_ITEMS[@]}"
fi

if [ ${#FAILED_ITEMS[@]} -ne 0 ]; then
    echo -e "\n❌ Failed to back up:"
    printf '%s\n' "${FAILED_ITEMS[@]}"
fi

# Print completion message with timestamp
echo -e "\n✨ System update and backup completed at $(date)"
echo "Check outdated.txt for a list of updated Python packages"

# Deactivate virtual environment
deactivate