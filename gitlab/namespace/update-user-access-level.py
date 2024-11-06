import os
from gitlab.namespace.tools import update_user_access_level
import argparse
import logging

logging.basicConfig(level=logging.INFO)

arg_parser = argparse.ArgumentParser(description='Add user to namespace/group')
arg_parser.add_argument('--ns_name', required=True, help='Namespace/Group name')
arg_parser.add_argument('--user_name', required=True, help='User name')
arg_parser.add_argument('--access_level', type=str, required=True,
                        help='Access level, https://docs.gitlab.com/ee/user/permissions.html')
args = arg_parser.parse_args()

if __name__ == "__main__":
    # get_users_in_ns(args.ns_name)
    # Access Level
    # 10 => Guest access
    # 20 => Reporter access
    # 30 => Developer access
    # 40 => Maintainer access
    # 50 => Owner access
    update_user_access_level(args.ns_name, args.user_name, args.access_level)
