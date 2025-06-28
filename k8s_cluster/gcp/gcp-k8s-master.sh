#!/bin/bash
INSTANCE_ID="1825645722761970039"
read NAME ZONE <<< $(gcloud compute instances list --filter="id=${INSTANCE_ID}" --format="value(name,zone)")

VM_EXTERNAL_IP=`gcloud compute instances describe "$NAME" --zone="$ZONE" --format="get(networkInterfaces[0].accessConfigs[0].natIP)"`

ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@${VM_EXTERNAL_IP}

