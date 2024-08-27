#!/bin/bash

# Define the S3 bucket name
S3_BUCKET="s3://aws-163544304364-scripts"

# Define the directories and files to back up
ITEMS=(
    "/root/100-days-of-Python"
    "/root/Ansible"
    "/root/Boto3"
    "/root/My-Notes"
    "/root/Terraform-Notes"
    "/root/shell-script/update.sh"
    "/root/shell-script/transfer.sh"
)

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
    else
        echo "Failed to back up $ITEM"
    fi
    
    # Pause for 5 seconds
    sleep 3
    done
    
    # Prompt: Tells you that the backup is completed
    echo "Backup to S3 completed!"