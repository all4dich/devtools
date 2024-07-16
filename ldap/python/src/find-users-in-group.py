from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email import encoders
from email.mime.text import MIMEText

import ldap
import os
import logging
import argparse
import boto3

logging.basicConfig(level=logging.INFO)

# Parse the agruments
parser = argparse.ArgumentParser(description='List all users in the LDAP server')
parser.add_argument('--filter', type=str, default="(objectClass=inetOrgPerson)", help='Filter for the LDAP search')
parser.add_argument('--include-disabled', action='store_true', help='Exclude disabled users from the search')
args = parser.parse_args()

group_name = os.getenv('GROUP_NAME')
group_base = os.getenv('GROUP_BASE')


# List all users
def find_users_in_group(group_name, group_base, filter=args.filter, include_disabled=args.include_disabled):
    # Set up logging
    logging.info("Starting script")
    # Create a connection to the LDAP server
    conn = ldap.initialize(os.environ['LDAP_SERVER'])
    logging.info("Connected to LDAP server")
    # Bind to the server
    conn.simple_bind_s(os.environ['BIND_DN'], os.environ['BIND_PW'])
    # Search for all users
    logging.info("Searching for all users")
    if not include_disabled:
        filter = f"(&{filter}(shadowExpire=-1))"
    # Search for all users under group
    filter = f"(&(memberOf=cn={group_name},{group_base}){filter})"
    result = conn.search_s(os.environ['USER_BASE'], ldap.SCOPE_SUBTREE, filter)
    all_users = map(lambda *x: x[0][0], result)
    all_users_str = '\n'.join(all_users)
    all_users_str = "User List:\n" + all_users_str + "\n"
    print(all_users_str)
    conn.unbind()


if __name__ == '__main__':
    find_users_in_group(group_name, group_base)
