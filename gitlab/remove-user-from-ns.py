import os
from gitlab.namespace.tools import remove_user_from_ns, add_user_to_ns, update_user_access_level
import argparse
import logging

logging.basicConfig(level=logging.INFO)

arg_parser = argparse.ArgumentParser(description='Add user to namespace/group')
arg_parser.add_argument('--ns_name', required=True, help='Namespace/Group name')
arg_parser.add_argument('--user_name', required=True, help='User name')
args = arg_parser.parse_args()

if __name__ == "__main__":
    # get_users_in_ns(args.ns_name)
    # Access Level
    remove_user_from_ns(args.ns_name, args.user_name)
