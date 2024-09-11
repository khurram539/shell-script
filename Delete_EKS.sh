#!/bin/bash

# Define variables
CLUSTER_NAME="EKS-Cluster"
REGION="us-east-1"

# Run eksctl delete cluster command
eksctl delete cluster --name $CLUSTER_NAME --region $REGION