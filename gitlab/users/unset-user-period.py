import os
from gitlab.namespace.tools import get_users
import argparse
import logging
import requests

logging.basicConfig(level=logging.INFO)

arg_parser = argparse.ArgumentParser(description='Add user to namespace/group')
arg_parser.add_argument('--ns_name', required=False, help='Namespace/Group name')
arg_parser.add_argument('--user_name', required=False, help='User name')
arg_parser.add_argument('--access_level', type=str, required=False,
                        help='Access level, https://docs.gitlab.com/ee/user/permissions.html')
args = arg_parser.parse_args()

if __name__ == "__main__":
    GITLAB_URL = os.environ["GITLAB_URL"]
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    EMAIL_DOMAIN = os.environ["EMAIL_DOMAIN"]
    users = get_users()
    for user in users:
        email = user['email'].split('@')
        user_id = user['id']
        email_id = email[0]
        email_domain = email[1]
        #expire_date = user['expires_at']
        if email_domain == EMAIL_DOMAIN:
            logging.info(f"Unset user period for user ID: {user_id}, Email: {email[0]}, Domain: {email[1]}")
            user_url = f"{GITLAB_URL}/api/v4/users/{user_id}"
            response = requests.put(user_url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, json={"expires_at": None})
            logging.info(f"Status: {response.status_code}, User Name: {user['name']}, User ID: {user['id']}, Username: {user['username']}, Email: {user['email']}")