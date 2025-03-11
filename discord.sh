#!/bin/bash

# This script updates Discord to the latest version on an Ubuntu system.
# It downloads the latest Discord .deb package from the official website,
# installs it, and resolves any dependency issues without removing the existing installation.

# Steps:
# 1. Download the latest Discord package using wget.
# 2. Install the downloaded package using dpkg.
# 3. Fix any dependency issues using apt-get.
# 4. Clean up by removing the downloaded .deb file.

# Usage:
# Save this script to a file with a .sh extension, make it executable, and run it to update Discord.
# Example:
# chmod +x update_discord.sh
# ./update_discord.sh

# Download the latest Discord package
wget -O ~/discord.deb "https://discordapp.com/api/download?platform=linux&format=deb"

# Install the downloaded package
sudo dpkg -i ~/discord.deb

# Fix any dependency issues
sudo apt-get install -f -y

# Clean up
rm ~/discord.deb

echo "Discord has been updated to the latest version."

