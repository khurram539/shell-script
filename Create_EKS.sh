#!/bin/bash

set -euo pipefail

# Define variables
CLUSTER_NAME="EKS-Cluster"
VERSION="1.34"
REGION="us-east-1"
VPC_ID="vpc-0f238901bc3467b62"
NODEGROUP_NAME="Worker"
SSH_KEYPAIR_NAME="Khurram-key"
NODE_TYPE="t2.small"
NODE_VOLUME_SIZE=20
NODE_VOLUME_TYPE="gp3"
NODES=2
SUBNET_A="subnet-08d90b90e9b121c7e"
SUBNET_B="subnet-01d84fc63df0a696c"
SUBNET_C="subnet-0a9bdb8cd0195ad71"
NAMESPACE="ns-khurram"
STACK_NAME="eksctl-${CLUSTER_NAME}-cluster"
CONFIG_FILE="/tmp/${CLUSTER_NAME}-eksctl.yaml"

SUBNET_IDS=("$SUBNET_A" "$SUBNET_B" "$SUBNET_C")

# Preflight checks - prevent collision with existing cluster or stale stacks
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "EKS cluster '$CLUSTER_NAME' already exists in $REGION. Delete it or change CLUSTER_NAME before rerunning."
    exit 1
fi

if aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    echo "CloudFormation stack '$STACK_NAME' still exists or is deleting. Wait for cleanup to finish before rerunning."
    exit 1
fi

# Ensure subnets used by managed nodes auto-assign public IPs.
# This is required when subnets route to an Internet Gateway and nodegroups are not private-only.
for subnet_id in "${SUBNET_IDS[@]}"; do
    map_public_ip=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].MapPublicIpOnLaunch' \
        --output text)

    if [[ "$map_public_ip" != "True" ]]; then
        echo "Enabling MapPublicIpOnLaunch for subnet $subnet_id"
        aws ec2 modify-subnet-attribute \
            --region "$REGION" \
            --subnet-id "$subnet_id" \
            --map-public-ip-on-launch
    fi
done

# Create EKS cluster config to ensure subnets are passed to managed nodegroup
cat > "$CONFIG_FILE" <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
    name: ${CLUSTER_NAME}
    region: ${REGION}
    version: "${VERSION}"

autoModeConfig:
    enabled: false

vpc:
    id: ${VPC_ID}
    subnets:
        public:
            ${REGION}a:
                id: ${SUBNET_A}
            ${REGION}b:
                id: ${SUBNET_B}
            ${REGION}c:
                id: ${SUBNET_C}

managedNodeGroups:
    - { name: ${NODEGROUP_NAME}, instanceType: ${NODE_TYPE}, desiredCapacity: ${NODES}, volumeSize: ${NODE_VOLUME_SIZE}, volumeType: ${NODE_VOLUME_TYPE}, ssh: { allow: true, publicKeyName: ${SSH_KEYPAIR_NAME} } }
EOF

# Create EKS cluster with managed node group
eksctl create cluster -f "$CONFIG_FILE"

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



# Scale the node group to zero (clean shutdown):
# eksctl scale nodegroup --cluster EKS-Cluster --region us-east-1 --name Worker --nodes 0 --nodes-min 0 --nodes-max 0

# Bring them back later:
# eksctl scale nodegroup --cluster EKS-Cluster --region us-east-1 --name Worker --nodes 1 --nodes-min 1 --nodes-max 1