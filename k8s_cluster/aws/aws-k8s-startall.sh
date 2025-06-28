#!/bin/bash
set -x
INSTANCE_IDS=(
    "i-0d665c48ee9bfa2bd"
    "i-0be712a4a19e8b495"
)
REGION_NAME="ap-northeast-2"

IFS=' '
INSTANCE_ID="${INSTANCE_IDS[*]}"
echo "Stop instances..."
aws ec2 start-instances --instance-ids ${INSTANCE_ID} --region ${REGION_NAME}
set +x
