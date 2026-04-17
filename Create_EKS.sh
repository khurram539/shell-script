#!/bin/bash

set -euo pipefail

# Define variables
CLUSTER_NAME="EKS-Cluster"
VERSION="1.34"
REGION="us-east-1"
NODEGROUP_NAME="Worker"
NODE_TYPE="t2.small"
NODE_VOLUME_SIZE=20
NODE_VOLUME_TYPE="gp3"
NODES=3
ZONES="us-east-1a,us-east-1b,us-east-1c"
NAMESPACE="ns-khurram"
STACK_NAME="eksctl-${CLUSTER_NAME}-cluster"

# Preflight checks - prevent collision with existing cluster or stale stacks
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "EKS cluster '$CLUSTER_NAME' already exists in $REGION. Delete it or change CLUSTER_NAME before rerunning."
    exit 1
fi

if aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    echo "CloudFormation stack '$STACK_NAME' still exists or is deleting. Wait for cleanup to finish before rerunning."
    exit 1
fi

# Create EKS cluster with managed node group
eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --version "$VERSION" \
    --region "$REGION" \
    --nodegroup-name "$NODEGROUP_NAME" \
    --node-type "$NODE_TYPE" \
    --nodes "$NODES" \
    --zones "$ZONES" \
    --node-volume-size "$NODE_VOLUME_SIZE" \
    --node-volume-type "$NODE_VOLUME_TYPE"

# Refresh kubeconfig using the supported AWS EKS path
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Create namespace (idempotent)
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Set the default namespace for the current context
kubectl config set-context --current --namespace="$NAMESPACE"

# Useful commands for reference:
# kubectl config get-contexts
# kubectl config use-context k.khoja@EKS-Cluster.us-east-1.eksctl.io
# kubectl get nodes
#
# To edit the cluster configuration YAML file:
# eksctl get cluster --name <cluster_name> -o yaml > cluster.yaml
# vim cluster.yaml
# eksctl update cluster -f cluster.yaml
