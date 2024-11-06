import os
from gitlab.namespace.tools import get_users
from gitlab.users.tools import delete_user
import argparse
import logging
import requests
import json

logging.basicConfig(level=logging.INFO)

arg_parser = argparse.ArgumentParser(description='Delete user')
arg_parser.add_argument('--user_name', required=True, help='User name')
arg_parser.add_argument('--hard_delete', action='store_true', help='Hard delete user')
args = arg_parser.parse_args()

if __name__ == "__main__":
    GITLAB_URL = os.environ["GITLAB_URL"]
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    print(args.user_name)
    print(args.hard_delete)
    delete_user(args.user_name, args.hard_delete)
