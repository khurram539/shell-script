aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --targets "Key=InstanceIds,Values=i-09662a8e5a01956f8,i-02f4cb01ee5b3da30" \
  --parameters '{"Operation":["Install"],"RebootOption":["RebootIfNeeded"]}' \
  --comment "Install Windows updates via Patch Manager" \
  --timeout-seconds 600 \
  --region us-east-1
