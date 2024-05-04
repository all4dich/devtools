import json
import urllib3
import boto3
import os

url = os.environ['URL']
http = urllib3.PoolManager()
iam_client = boto3.client('iam')


def get_user_name(principal_id):
    try:
        response = iam_client.list_users()
        users = response.get('Users', [])
        for user in users:
            print(f"debug: {user['UserId']} / {principal_id}")
            if user['UserId'] == principal_id.replace("AWS:", ""):
                return user['UserName']
    except Exception as e:
        print(f"Error retrieving users: {e}")
    return None


def get_role_name(principal_id):
    try:
        response = iam_client.list_roles()
        roles = response.get('Roles', [])
        for role in roles:
            if role['RoleId'] == principal_id.replace("AWS:", ""):
                return role['RoleName']
        return None
    except Exception as e:
        print(f"Error retrieving roles: {e}")
    return None


def lambda_handler(event, context):
    event_message = event['Records'][0]['Sns']['Message']
    message_id = event['Records'][0]['Sns']['MessageId']
    event_obj = json.loads(event_message)
    principal_id = event_obj['Records'][0]['userIdentity']['principalId']
    bucket_name = event_obj['Records'][0]['s3']['bucket']['name']
    file_path = event_obj['Records'][0]['s3']['object']['key']
    event_time = event_obj['Records'][0]['eventTime']
    action = event_obj['Records'][0]['eventName']
    region_name = event_obj['Records'][0]['awsRegion']
    source_ip = event_obj['Records'][0]['requestParameters']['sourceIPAddress']

    user_name = None

    user_name = get_user_name(principal_id)

    msg = {
        "event_time": event_time,
        "message_id": message_id,
        "bucket_name": bucket_name,
        "file_path": file_path,
        "action": action,
        "user": user_name,
        "region_name": region_name,
        "ip": source_ip
    }

    encoded_msg = json.dumps(msg).encode('utf-8')
    resp = http.request('POST', url, body=encoded_msg, headers={'Content-Type': 'application/json'})

    print({
        "message": json.dumps(msg),
        "status_code": resp.status,
        "response": resp.data
    })

    return {
        'statusCode': 200,
        'body': json.dumps(msg)
    }
