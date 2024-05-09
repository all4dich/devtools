import boto3
import os
from multiprocessing import Pool

# Input
# AWS_PROFILE: AWS cli config profile
# BUCKET_NAME
boto3.setup_default_session(profile_name=os.environ['AWS_PROFILE'])
s3 = boto3.client('s3')

# Get a list of all buckets
response = s3.list_buckets()
buckets = [bucket['Name'] for bucket in response['Buckets']]


def get_bucket_event_notification(bucket_name):
    try:
        response = s3.get_bucket_notification_configuration(Bucket=bucket_name)
        if response['TopicConfigurations']:
            print(response['TopicConfigurations'])
            return response['TopicConfigurations']
        else:
            return None
        return response
    except Exception as e:
        # print(f"Error getting bucket notification configuration for {bucket_name}: {e}")
        return None


def get_bucket_logging(bucket_name):
    try:
        response = s3.get_bucket_logging(Bucket=bucket_name)
        return response
    except Exception as e:
        print(f"Error getting bucket logging configuration for {bucket_name}: {e}")
        return None


if __name__ == "__main__":
    p = Pool(4)
    with p:
        r = p.map(get_bucket_event_notification, buckets)
        r_filtered = list(filter(lambda x: x, r))
        print(r_filtered)
