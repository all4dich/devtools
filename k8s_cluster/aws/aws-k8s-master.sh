#!/bin/bash
INSTANCE_ID="i-0d665c48ee9bfa2bd"
REGION_NAME="ap-northeast-2"


echo "Starting instance..."
aws ec2 start-instances --instance-ids ${INSTANCE_ID} --region ${REGION_NAME}
#echo "Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID} --region ${REGION_NAME}

INSTANCE_IP=`aws ec2 describe-instances \
  --instance-ids ${INSTANCE_ID} \
  --region ${REGION_NAME} \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text`

echo "k8s worker : ${INSTANCE_IP}"
echo "Region: ${REGION_NAME}"
ssh -i ~/.ssh/all4dich-aws-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${INSTANCE_IP}
