import boto3
import os

# Input
# AWS_PROFILE: AWS cli config profile
# BUCKET_NAME
boto3.setup_default_session(profile_name=os.environ['AWS_PROFILE'])
s3 = boto3.client('s3')

# Get a list of all buckets
response = s3.Client.list_buckets()
for bucket in response['Buckets']:
    bucket_name = bucket['Name']
    # Get Bucket region and location
    location = s3.get_bucket_location(Bucket=bucket_name)
    print(f"Bucket: {bucket_name}, Location: {location['LocationConstraint']}, Owner: {bucket_owner}")
    break

