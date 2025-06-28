#!/bin/bash
INSTANCE_ID="i-0d665c48ee9bfa2bd"
REGION_NAME="ap-northeast-2"

echo "Stop instance..."
aws ec2 stop-instances --instance-ids ${INSTANCE_ID} i-0be712a4a19e8b495 --region ${REGION_NAME}

