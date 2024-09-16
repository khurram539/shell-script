#!/bin/bash

# Define variables
CLUSTER_NAME="EKS-Cluster"
VERSION="1.30"
REGION="us-east-1"
NODEGROUP_NAME="Worker"
NODE_TYPE="t2.medium"
NODE_VOLUME_SIZE=20
NODE_VOLUME_TYPE="gp3"
NODES=2
ZONES="us-east-1a,us-east-1b"

# Run eksctl create cluster command
eksctl create cluster --name $CLUSTER_NAME --version $VERSION --region $REGION --nodegroup-name $NODEGROUP_NAME --node-type $NODE_TYPE --nodes $NODES --zones $ZONES --node-volume-size $NODE_VOLUME_SIZE --node-volume-type $NODE_VOLUME_TYPE