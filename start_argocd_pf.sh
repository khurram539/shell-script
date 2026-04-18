.#!/bin/bash
set -euo pipefail

# Ensure predictable PATH in non-interactive boot contexts
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

REGION="us-east-1"
CLUSTER_NAME="EKS-Cluster"
NAMESPACE="argocd"
SERVICE="argocd-server"
LOCAL_PORT="9191"
REMOTE_PORT="443"
LOG_FILE="/home/kkhoja/argocd-port-forward.log"

# Give network and kube API some time after reboot
sleep 20

# Refresh kubeconfig on every boot so context/token is valid
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >> "$LOG_FILE" 2>&1 || true

# Keep port-forward alive even if pod/service restarts
while true; do
  # Clean up stale listeners on the local port if present
  pkill -f "kubectl port-forward svc/${SERVICE} -n ${NAMESPACE} ${LOCAL_PORT}:${REMOTE_PORT}" || true

  kubectl port-forward "svc/${SERVICE}" -n "$NAMESPACE" "${LOCAL_PORT}:${REMOTE_PORT}" --address 0.0.0.0 >> "$LOG_FILE" 2>&1 || true
  sleep 5
done


eksctl get addon 