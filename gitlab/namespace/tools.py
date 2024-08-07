import os
import requests
import logging

logging.basicConfig(level=logging.INFO)

def get_ns_list():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/namespaces"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    print(response.status_code)
    ns_list = response.json()
    for ns in ns_list:
        logging.info(f"Namespace ID: {ns['id']}, Namespace Name: {ns['name']}")
    return ns_list


def get_groups_list():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    print(response.status_code)
    groups_list = response.json()
    for group in groups_list:
        id = group["id"]
        name = group["name"]
        path = group["path"]
        full_path = group["full_path"]
        full_name = group["full_name"]
        web_url = group["web_url"]
        logging.info(f"Group ID: {id}, Name: {name}, Path: {path}, Full Path: {full_path}, Full Name: {full_name}, Web URL: {web_url}")
    return groups_list


