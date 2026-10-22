#!/bin/bash
INSTANCE_IDS=(
    "i-045e0374c3b6a8135"
    "i-0faeb6d01bfc3e90e"
)
REGION_NAME="us-west-1"


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
