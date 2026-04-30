#!/bin/bash

CLUSTER_NAME="EKS-Cluster"
REGION="us-east-1"
ACCOUNT_ID="163544304364"
OIDC_ID="8485411A84B1CD457BC54A81914C987D"
ROLE_NAME="AmazonEKSVPCCNIRole"
POLICY_NAME="AmazonEKSVPCCNIPolicy"
NAMESPACE="kube-system"
SERVICE_ACCOUNT="aws-node"

# Create IAM policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://vpc-cni-policy.json \
  --query 'Policy.Arn' --output text)

echo "Policy created: $POLICY_ARN"

# Create trust policy for IRSA
cat > /tmp/vpc-cni-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/vpc-cni-trust.json

echo "Role created: $ROLE_NAME"

# Attach policy to role
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

echo "Policy attached to role"

# Annotate the aws-node service account with the IAM role
kubectl annotate serviceaccount $SERVICE_ACCOUNT \
  -n $NAMESPACE \
  eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} \
  --overwrite

echo "Service account annotated"

# Restart aws-node daemonset to pick up new credentials
kubectl rollout restart daemonset aws-node -n $NAMESPACE

echo "VPC CNI IRSA setup complete!"
