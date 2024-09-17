#!/bin/bash

# Perform a full upgrade of packages and dependencies
sudo apt update
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
# pip list --outdated

# Prompt: Notify that the update is completed
echo "Your DevBox is updated!"
 
#  The script is self-explanatory. It updates the packages and dependencies, restarts necessary services, removes old kernels and unnecessary files,
#  and reloads Apache configuration if needed. 
#  You can also uncomment the lines to transfer data to S3, list outdated pip packages, or perform any other tasks you want to automate. 
#  To run the script, you can use the following command: 
#  $ bash update.sh
 
#  You can also make the script executable and run it as follows: 
#  $ chmod +x update.sh