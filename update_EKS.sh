# Download the latest version
curl -LO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"

# Extract the tarball
tar -xzf eksctl_Linux_amd64.tar.gz

# Move the binary to your PATH
sudo mv eksctl /usr/local/bin/eksctl

# Verify the installation
eksctl version

# eksctl upgrade cluster --name EKS-Cluster --version 1.31 --approve