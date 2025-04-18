#!/bin/bash

# Send the command to install Windows updates
command_id=$(aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --targets "Key=InstanceIds,Values=i-09662a8e5a01956f8,i-02f4cb01ee5b3da30" \
  --parameters '{"Operation":["Install"],"RebootOption":["RebootIfNeeded"]}' \
  --comment "Install Windows updates via Patch Manager" \
  --timeout-seconds 600 \
  --region us-east-1 \
  --query "Command.CommandId" \
  --output text)

echo "Command sent. Command ID: $command_id"

# Function to display a progress bar
show_progress() {
  local progress=0
  while [ $progress -le 100 ]; do
    printf "\rProgress: [%-50s] %d%%" $(printf '#%.0s' $(seq 1 $((progress / 2)))) $progress
    sleep 1
    progress=$((progress + 10))
  done
  echo ""
}

# Poll the status of the command
echo "Checking command status..."
while true; do
  status=$(aws ssm list-command-invocations \
    --command-id "$command_id" \
    --details \
    --query "CommandInvocations[0].Status" \
    --output text \
    --region us-east-1)

  if [[ "$status" == "InProgress" ]]; then
    show_progress
  elif [[ "$status" == "Success" ]]; then
    echo "Command completed successfully!"
    break
  elif [[ "$status" == "Failed" ]]; then
    echo "Command failed."
    break
  else
    echo "Current status: $status"
  fi
  sleep 5
done

# Additional command invocation
aws ssm list-command-invocations \
  --command-id "c638a297-0f3c-43a7-bc21-83c8a6e3f2a5" \
  --details \
  --region us-east-1