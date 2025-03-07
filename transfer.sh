#!/bin/bash

# Define the S3 bucket name
S3_BUCKET="s3://aws-163544304364-repo"

# Define the directories and files to back up
ITEMS=(
    "/home/ubuntu/100-days-of-Python"
    "/home/ubuntu/Ansible"
    "/home/ubuntu/Boto3"
    "/home/ubuntu/My-Notes"
    "/home/ubuntu/Terraform-Notes"   
    "/home/ubuntu/Kubernetes"
    "/home/ubuntu/shell-script"
    "/home/ubuntu/Docker"
    "/home/ubuntu/Flask"
    

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