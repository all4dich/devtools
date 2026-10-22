#!/bin/bash

# List of GCP instance IDs to look up
INSTANCE_IDS=("1825645722761970039" "8967329651927190240")

# Optional: specify zone and project if needed
ZONE=""            # e.g., "us-central1-a" (leave empty to search all zones)
PROJECT_ID=""      # e.g., "my-project" (leave empty to use default)

echo "INFO: Get all instances' status..."

# Retrieve all instances and filter by ID
FILTER_IDS=$(printf "id=%s OR " "${INSTANCE_IDS[@]}")
FILTER_IDS="${FILTER_IDS% OR }"
printf "%-20s %-25s %-10s %-5s\n" "Instance ID" "Name" "State" "Zone"
printf "%-20s %-25s %-10s %-5s\n" "--------------------" "-------------------------" "----------" "---------------"
lines=$(gcloud compute instances list \
  --format="table[no-heading](id, name, status, zone)" \
  ${ZONE:+--filter="zone:($ZONE)"} \
  ${PROJECT_ID:+--project=$PROJECT_ID} \
  --filter="$FILTER_IDS"
)
echo "${lines[*]}"
