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
            print(f"Bucket: {bucket_name}")
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


# target: s3://infra-backup-archives/database/
# base: s3://nota-infra-test-sunjoo/
TARGET_BUCKET = os.environ['TARGET_BUCKET']
BASE_BUCKET = os.environ['BASE_BUCKET']

if __name__ == "__main__":
    logging_conf_base = get_bucket_logging(BASE_BUCKET)
    logging_conf_target = logging_conf_base['LoggingEnabled']
    logging_conf_target['TargetPrefix'] = TARGET_BUCKET
    print(logging_conf_base)
    print(logging_conf_target)
    response = s3.put_bucket_logging(
        Bucket=TARGET_BUCKET,
        BucketLoggingStatus={
            'LoggingEnabled': logging_conf_target
        }
    )
    print(response)

