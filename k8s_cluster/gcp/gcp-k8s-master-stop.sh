#!/bin/bash
INSTANCE_ID="1825645722761970039"

echo "INFO: Connecting to GCP k8s master."
echo "INFO: Attempting to find instance with ID: ${INSTANCE_ID}"

# Read NAME and ZONE. The read command is used to split the output of gcloud command into two variables. [1]
read NAME ZONE <<< $(gcloud compute instances list --filter="id=${INSTANCE_ID}" --format="value(name,zone)")

# Check if NAME and ZONE were successfully retrieved
if [ -z "$NAME" ] || [ -z "$ZONE" ]; then
    echo "ERROR: Could not find instance with ID ${INSTANCE_ID}. Exiting." >&2
    exit 1
fi

echo "INFO: Found instance '${NAME}' in zone '${ZONE}'."
echo "Attempting to stop instance..."
echo "Instance ID: $INSTANCE_ID"
echo "Zone: $ZONE"
echo "Executing command: gcloud compute instances stop $INSTANCE_ID --zone=$ZONE"
gcloud compute instances stop $INSTANCE_ID --zone=$ZONE

