import json
import urllib3
import boto3

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
    url = "https://hooks.slack.com/services/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"
    event_message = event['Records'][0]['Sns']['Message']
    event_obj = json.loads(event_message)
    principal_id = event_obj['Records'][0]['userIdentity']['principalId']
    bucket_name = event_obj['Records'][0]['s3']['bucket']['name']
    file_path = event_obj['Records'][0]['s3']['object']['key']

    user_name = None
    role_name = None

    user_name = get_user_name(principal_id)
    role_name = get_role_name(principal_id)

    output = {
        'principalId': principal_id,
        'userName': user_name,
        'roleName': role_name,
        'bucketName': bucket_name,
        'filePath': file_path
    }
    msg = {
        "channel": "#general",
        "text": "s3://" + bucket_name + "/" + file_path + " uploaded by " + (user_name or role_name),
        "icon_emoji": ":white_check_mark:"
    }

    encoded_msg = json.dumps(msg).encode('utf-8')
    resp = http.request('POST', url, body=encoded_msg)
    print({
        "message": event['Records'][0]['Sns']['Message'],
        "status_code": resp.status,
        "response": resp.data
    })
    return {
        'statusCode': 200,
        'body': json.dumps(output)
    }
