# #!/bin/bash



# Update package lists
 sudo apt update 

# Perform full upgrade
 sudo apt full-upgrade -y

# Reload Apache Configuration
 sudo systemctl reload apache2

 # Restart Docker
sudo systemctl restart docker

# Restart Kubernetes (kubelet)
sudo systemctl restart kubelet

# Remove old Kernal
 sudo apt auto-remove -y 

# Free from unnecessary files
 sudo apt-get clean

# Transfer data to S3
#  aws s3 sync /home/ubuntu s3://aws-163544304364-backup/DevBox

# aws s3 cp /root/100-days-of-Python/ s3://aws-163544304364-devbox/100-days-of-python/ --recursive


# Prompt: Tells you that updates is completed
 echo "Your DexBox is updated!"