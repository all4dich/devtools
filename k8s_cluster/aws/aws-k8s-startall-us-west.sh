#!/bin/bash
set -x
INSTANCE_IDS=(
    "i-045e0374c3b6a8135"
    "i-0faeb6d01bfc3e90e"
)
REGION_NAME="us-west-1"

IFS=' '
INSTANCE_ID="${INSTANCE_IDS[*]}"
echo "Stop instances..."
aws ec2 start-instances --instance-ids ${INSTANCE_ID} --region ${REGION_NAME}
set +x
