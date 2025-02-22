#!/bin/bash

# Set strict error handling
set -euo pipefail

# Get the actual username (even when running with sudo)
ACTUAL_USER=$(who am i | awk '{print $1}')
HOME_DIR=$(eval echo ~${ACTUAL_USER})

# Define log file and S3 bucket
LOG_FILE="/var/log/system_update.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
S3_BUCKET="s3://aws-163544304364-repo"

# Function to log messages
log_message() {
    echo "[${TIMESTAMP}] $1"
}

# Function to check AWS credentials
check_aws_credentials() {
    log_message "Checking AWS credentials..."
    # Use the actual user's AWS credentials
    if ! AWS_SHARED_CREDENTIALS_FILE="$HOME_DIR/.aws/credentials" \
        AWS_CONFIG_FILE="$HOME_DIR/.aws/config" \
        aws sts get-caller-identity &>/dev/null; then
        log_message "ERROR: AWS credentials are not configured properly"
        log_message "Please run 'aws configure' to set up your credentials"
        return 1
    fi
    log_message "AWS credentials verified successfully"
    return 0
}

# Function to backup to S3
backup_to_s3() {
    log_message "Starting S3 backup..."
    
    # Check AWS credentials first
    if ! check_aws_credentials; then
        log_message "Skipping backup due to credential issues"
        return 1
    fi
    
    # Define the directories to back up
    local ITEMS=(
        "$HOME_DIR/Code/100-days-of-Python"
        "$HOME_DIR/Code/Ansible"
        "$HOME_DIR/Code/Boto3"
        "$HOME_DIR/Code/My-Notes"
        "$HOME_DIR/Code/Terraform-Notes"   
        "$HOME_DIR/Code/Kubernetes"
        "$HOME_DIR/Code/shell-script"
        "$HOME_DIR/code/CloudFormation"
    )

    # Arrays to keep track of successful and failed transfers
    local SUCCESSFUL_ITEMS=()
    local FAILED_ITEMS=()
    
    # Exclude patterns for .git directories and other unnecessary files
    local EXCLUDE_PATTERN="--exclude=*.git/* --exclude=*.pyc --exclude=__pycache__/*"
    
    for ITEM in "${ITEMS[@]}"; do
        ITEM_NAME=$(basename "$ITEM")
        
        if [ ! -e "$ITEM" ]; then
            log_message "WARNING: $ITEM does not exist, skipping..."
            FAILED_ITEMS+=("$ITEM")
            continue
        fi
        
        log_message "Backing up $ITEM_NAME..."
        
        if [ -d "$ITEM" ]; then
            if AWS_SHARED_CREDENTIALS_FILE="$HOME_DIR/.aws/credentials" \
               AWS_CONFIG_FILE="$HOME_DIR/.aws/config" \
               aws s3 cp "$ITEM/" "$S3_BUCKET/$ITEM_NAME/" \
                --recursive \
                --storage-class GLACIER_IR \
                $EXCLUDE_PATTERN; then
                log_message "Successfully backed up $ITEM"
                SUCCESSFUL_ITEMS+=("$ITEM")
            else
                log_message "Failed to backup $ITEM"
                FAILED_ITEMS+=("$ITEM")
            fi
        else
            if AWS_SHARED_CREDENTIALS_FILE="$HOME_DIR/.aws/credentials" \
               AWS_CONFIG_FILE="$HOME_DIR/.aws/config" \
               aws s3 cp "$ITEM" "$S3_BUCKET/$ITEM_NAME" \
                --storage-class GLACIER_IR; then
                log_message "Successfully backed up $ITEM"
                SUCCESSFUL_ITEMS+=("$ITEM")
            else
                log_message "Failed to backup $ITEM"
                FAILED_ITEMS+=("$ITEM")
            fi
        fi
        
        sleep 2
    done

    # Print summary
    echo "Backup to S3 bucket $S3_BUCKET is completed!"

    if [ ${#SUCCESSFUL_ITEMS[@]} -ne 0 ]; then
        echo "Successfully backed up the following items:"
        for ITEM in "${SUCCESSFUL_ITEMS[@]}"; do
            echo "- $ITEM"
        done
    fi

    if [ ${#FAILED_ITEMS[@]} -ne 0 ]; then
        echo "Failed to back up the following items:"
        for ITEM in "${FAILED_ITEMS[@]}"; do
            echo "- $ITEM"
        done
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    log_message "Starting backup to S3..."
    backup_to_s3
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log_message "Backup process completed successfully!"
    else
        log_message "Backup process completed with errors!"
    fi

    return $EXIT_CODE
}

# Run main function
main
exit $?
