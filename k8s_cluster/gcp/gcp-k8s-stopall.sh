#!/bin/bash
INSTANCE_IDS=("1825645722761970039" "8967329651927190240")

echo "INFO: Connecting to GCP k8s master."

for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    echo "INFO: Attempting to find instance with ID: ${INSTANCE_ID}"

    # Read NAME and ZONE. The read command is used to split the output of gcloud command into two variables.
    read NAME ZONE <<< $(gcloud compute instances list --filter="id=${INSTANCE_ID}" --format="value(name,zone)")

    # Check if NAME and ZONE were successfully retrieved
    if [ -z "$NAME" ] || [ -z "$ZONE" ]; then
        echo "ERROR: Could not find instance with ID ${INSTANCE_ID}. Skipping." >&2
        continue # Skip to the next instance in the list
    fi

    echo "INFO: Found instance '${NAME}' in zone '${ZONE}'."
    echo "Attempting to stop instance..."
    echo "Instance ID: $INSTANCE_ID"
    echo "Zone: $ZONE"
    echo "Executing command: gcloud compute instances stop \"$NAME\" --zone=\"$ZONE\""
    gcloud compute instances stop --async "$NAME" --zone="$ZONE"
done

echo "INFO: All specified instances have been processed."

