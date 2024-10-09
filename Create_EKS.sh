#!/bin/bash

# Define variables
CLUSTER_NAME="EKS-Cluster"
VERSION="1.30"
REGION="us-east-1"
NODEGROUP_NAME="Worker"
NODE_TYPE="t2.micro"
NODE_VOLUME_SIZE=20
NODE_VOLUME_TYPE="gp3"
NODES=2
ZONES="us-east-1b,us-east-1c"
NAMESPACE="ns-khurram"
CONTEXT_NAME="k.khoja@EKS-Cluster.us-east-1.eksctl.io"

# Run eksctl create cluster command
eksctl create cluster --name $CLUSTER_NAME --version $VERSION --region $REGION --nodegroup-name $NODEGROUP_NAME --node-type $NODE_TYPE --nodes $NODES --zones $ZONES --node-volume-size $NODE_VOLUME_SIZE --node-volume-type $NODE_VOLUME_TYPE

# Create namespace
kubectl create namespace $NAMESPACE

# Set the default namespace for the specified context
kubectl config set-context $CONTEXT_NAME --namespace=$NAMESPACE




# #!/bin/bash
# # Define variables
# CLUSTER_NAME="EKS-Cluster"
# VERSION="1.30"
# REGION="us-east-1"
# NODEGROUP_NAME="Worker"
# NODE_TYPE="t2.medium"
# NODE_VOLUME_SIZE=20
# NODE_VOLUME_TYPE="gp3"
# NODES=2
# ZONES="us-east-1b,us-east-1c"

# # Run eksctl create cluster command
# eksctl create cluster --name $CLUSTER_NAME --version $VERSION --region $REGION --nodegroup-name $NODEGROUP_NAME --node-type $NODE_TYPE --nodes $NODES --zones $ZONES --node-volume-size $NODE_VOLUME_SIZE --node-volume-type $NODE_VOLUME_TYPE



# kubectl config get-contexts
# kubectl config use-context k.khoja@EKS-Cluster.us-east-1.eksctl.io
# kubectl get nodes

# minikube start
# minikube dashboard