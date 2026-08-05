#!/bin/bash

# Set the default value for INSTANCE_ID
DEFAULT_INSTANCE_ID="1825645722761970039"

# Check if the first argument is provided
if [ -n "$1" ]; then
  INSTANCE_ID="$1"
else
  INSTANCE_ID="$DEFAULT_INSTANCE_ID"
fi

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

# Get the external IP of the VM. The `gcloud compute instances describe` command is used to get detailed information about the instance, and the `--format` option is used to extract the external IP.
VM_EXTERNAL_IP=`gcloud compute instances describe "$NAME" --zone="$ZONE" --format="get(networkInterfaces[0].accessConfigs[0].natIP)"`

# Check if VM_EXTERNAL_IP was successfully retrieved
if [ -z "$VM_EXTERNAL_IP" ]; then
    echo "WARNING: Could not retrieve external IP for instance '${NAME}'. Attempting to ensure instance is running and retry." >&2

    # Attempt to start the instance (it might already be running, this command is idempotent for running instances)
    echo "Attempting to start VM instance '${NAME}'..." >&2
    if ! gcloud compute instances start "${NAME}" --zone=${ZONE} --quiet; then
        echo "ERROR: Failed to initiate start command for VM instance '${NAME}'. Exiting." >&2
        exit 1
    fi

    # Re-attempt to get VM_EXTERNAL_IP after ensuring instance is running
    echo "Re-attempting to retrieve external IP for instance '${NAME}'..." >&2
    VM_EXTERNAL_IP="$(gcloud compute instances describe "${NAME}" --zone=${ZONE} --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

    if [ -z "$VM_EXTERNAL_IP" ]; then
        echo "ERROR: Still unable to retrieve external IP for instance '${NAME}' after restart/wait attempt. Exiting." >&2
        exit 1
    else
        echo "Successfully retrieved external IP after retry: ${VM_EXTERNAL_IP}" >&2
    fi
fi

echo "INFO: External IP for '${NAME}' is: ${VM_EXTERNAL_IP}"
echo "INFO: Attempting to SSH to ubuntu@${VM_EXTERNAL_IP}..."

# Connect to the VM using SSH. Options `-o StrictHostKeyChecking=no` disables host key checking for convenience, and `-i ~/.ssh/id_rsa` specifies the identity file.
ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@${VM_EXTERNAL_IP}

