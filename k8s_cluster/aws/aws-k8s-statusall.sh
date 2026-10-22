#!/bin/bash
INSTANCE_IDS=(
    "i-0d665c48ee9bfa2bd"
    "i-0be712a4a19e8b495"
)
REGION_NAME="ap-northeast-2"

echo "Get all instances's status"
IDS="${INSTANCE_IDS[*]}"
NAMES=($(aws ec2 describe-instances --region ${REGION_NAME} --instance-ids ${IDS} --query "Reservations[].Instances[].Tags[?Key=='Name'].Value" --output text))
STATE=`aws ec2 describe-instances --region ${REGION_NAME} --instance-ids ${IDS} --query 'Reservations[].Instances[].State.Name' --output text`

# Convert strings to arrays
read -r -a id_array <<< "$IDS"
read -r -a state_array <<< "$STATE"

echo $name_array
# Header
printf "%-3s %-22s %-15s %-10s\n" "No" "Instance ID" "Name" "State"
printf "%-3s %-22s %-15s %-10s\n" "---" "----------------------" "---------------" "----------"

# Loop and print aligned
for i in "${!id_array[@]}"; do
    printf "%-3s %-22s %-15s %-10s\n" \
           "$((i+1))" \
           "${id_array[$i]}" \
           "${NAMES[$i]}" \
           "${state_array[$i]}"
done
