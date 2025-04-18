#!/bin/bash



# Function to toggle the state of an EventBridge rule
toggle_rule() {
  local rule_name=$1
  local region=$2

  # Get the current state of the rule
  current_state=$(aws events describe-rule --name "$rule_name" --region "$region" --query "State" --output text)

  if [[ "$current_state" == "ENABLED" ]]; then
    # If the rule is enabled, disable it
    echo "Disabling EventBridge rule: $rule_name"
    aws events disable-rule --name "$rule_name" --region "$region"
    echo "Rule $rule_name is now DISABLED."
  elif [[ "$current_state" == "DISABLED" ]]; then
    # If the rule is disabled, enable it
    echo "Enabling EventBridge rule: $rule_name"
    aws events enable-rule --name "$rule_name" --region "$region"
    echo "Rule $rule_name is now ENABLED."
  else
    echo "Unable to determine the state of the rule: $rule_name"
  fi
}

# Function to display the current status of all rules
display_status() {
  local rule_name=$1
  local region=$2

  # Get the current state of the rule
  current_state=$(aws events describe-rule --name "$rule_name" --region "$region" --query "State" --output text)
  echo "Current status of $rule_name: $current_state"
}

# Define the rules and region
rules=("ec2-start-9am" "ec2-stop-5pm")
region="us-east-1"

# Loop through each rule and toggle its state
for rule in "${rules[@]}"; do
  toggle_rule "$rule" "$region"
done

# Display the current status of all rules
echo "Final status of EventBridge rules:"
for rule in "${rules[@]}"; do
  display_status "$rule" "$region"
done

