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
parser.add_argument('--receiver', type=str, help='Email address to receive the list of users')
args = parser.parse_args()


# List all users
def list_users(filter=args.filter, include_disabled=args.include_disabled):
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
    result = conn.search_s(os.environ['USER_BASE'], ldap.SCOPE_SUBTREE, filter)
    all_users = map(lambda *x: x[0][0], result)
    all_users_str = '\n'.join(all_users)
    all_users_str = "User List:\n" + all_users_str + "\n"
    print(all_users_str)
    conn.unbind()
    if args.receiver:
        send_email(all_users_str)


# Send the list of users to email via AWS SES Service and boto3
def send_email(contents, receiver=args.receiver, sender=os.environ['SENDER'],
               aws_access_key=os.environ['AWS_ACCESS_KEY'], aws_secret_key=os.environ['AWS_SECRET_KEY'],
               aws_region=os.environ['AWS_REGION']):
    # Set up the SES client
    ses_client = boto3.client(
        'ses',
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key,
        region_name=aws_region
    )
    # Send the email to the specified address
    msg = MIMEMultipart()
    msg["From"] = sender
    msg["To"] = receiver
    msg["Subject"] = contents.split("\n")[0]
    msg.attach(MIMEText(contents, "plain"))

    part = MIMEBase("application", "octet-stream")
    part.set_payload(contents)
    encoders.encode_base64(part)
    part.add_header("Content-Disposition", f"attachment; filename=result.txt")
    msg.attach(part)
    response = ses_client.send_raw_email(
        Destinations=[
            receiver]
        ,
        Source=sender,
        RawMessage={"Data": msg.as_string()}
    )

    print(response)


if __name__ == '__main__':
    list_users()
