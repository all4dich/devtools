import os
from gitlab.namespace.tools import get_ns_id
import requests
import argparse

arg_parser = argparse.ArgumentParser(description='Get users in namespace')
arg_parser.add_argument('--ns_name', required=True, help='Namespace name')
args = arg_parser.parse_args()
SSL_CERT_VERIFY: bool = os.getenv("SSL_CERT_VERIFY", True)
if type(SSL_CERT_VERIFY) == str:
    SSL_CERT_VERIFY = eval(SSL_CERT_VERIFY)

ns_name = os.getenv("NS_NAME", "samsung_lsi")


def get_users_in_ns(ns_name):
    print("Getting users in namespace")
    ns_id = get_ns_id(ns_name)
    print(ns_id)
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/{ns_id}/members?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    member_list = response.json()
    while len(member_list) > 0 and response.status_code == 200:
        for member in member_list:
            try:
                print(ns_name, member["username"], member["email"], member["access_level"])
            except TypeError:
                print("Error")
                print(member)
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            member_list.extend(response)


if __name__ == "__main__":
    get_users_in_ns(args.ns_name)
