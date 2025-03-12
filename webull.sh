#!/bin/bash

# Webull Desktop App update script
# Define the download URL and the installation directory
DOWNLOAD_URL="https://download.webull.com/.../webull-desktop-linux.deb"
INSTALL_DIR="/usr/local/bin"

# Update package lists
sudo apt update

# Download the latest version of the Webull Desktop App
wget -O webull-desktop.deb "$DOWNLOAD_URL"

# Install the downloaded package
sudo dpkg -i webull-desktop.deb

# Fix any dependency issues
sudo apt -f install

# Clean up
rm webull-desktop.deb

echo "Webull Desktop App has been updated successfully."
