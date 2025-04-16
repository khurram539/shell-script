#!/bin/bash

# Perform a full upgrade of packages and dependencies
sudo apt update
sudo apt upgrade -y
sudo apt dist-upgrade -y

# Restart necessary services
sudo systemctl restart docker
sudo systemctl restart kubelet

# Remove old kernels and unnecessary files
sudo apt autoremove -y
sudo apt-get clean

# Uncomment the following lines to reload Apache configuration if needed
# sudo systemctl reload apache2

# Uncomment the following lines to transfer data to S3
# aws s3 sync /home/ubuntu s3://aws-163544304364-backup/DevBox
# aws s3 cp /root/100-days-of-Python/ s3://aws-163544304364-devbox/100-days-of-python/ --recursive

# Uncomment the following line to list outdated pip packages
 pip list --outdated # List Outdated Packages
 sleep 3
#  pip list --outdated --format=columns > outdated.txt # Generate a list of outdated packages
 for pkg in $(pip list --outdated --format=columns | awk 'NR>2 {print $1}'); do pip install --upgrade $pkg; done # Extract package names and update each package
 pip list --outdated # List Outdated Packages
 sleep 3
 sudo apt update
# Transfer Data to S3 Bucket

# Define the S3 bucket name
S3_BUCKET="s3://aws-163544304364-repo"

# Define the directories and files to back up
ITEMS=(
    "/home/kkhoja/Code/100-days-of-Python"
    # "/home/kkhoja/Code/Ansible"
    "/home/kkhoja/Code/Boto3"
    "/home/kkhoja/Code/My-Notes"
    "/home/kkhoja/Code/Terraform-Notes"   
    # "/home/kkhoja/Code/Kubernetes"
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
