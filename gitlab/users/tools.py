import os
import requests
import logging
import json
from gitlab.namespace.tools import get_user_id

logging.basicConfig(level=logging.INFO)

SSL_CERT_VERIFY: bool = os.getenv("SSL_CERT_VERIFY", True)
if type(SSL_CERT_VERIFY) == str:
    SSL_CERT_VERIFY = eval(SSL_CERT_VERIFY)


def create_user(username: str, email: str, name: str, reset_password: bool = True, skip_confirmation: bool = False,
                external: bool = False) -> object:
    GITLAB_URL = os.environ["GITLAB_URL"]
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    url = f"{GITLAB_URL}/api/v4/users"
    data = {
        "username": username,
        "email": email,
        "name": name,
        "reset_password": reset_password,
        "skip_confirmation": skip_confirmation,
        "external": external
    }
    response = requests.post(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, json=data, verify=SSL_CERT_VERIFY)
    logging.info(f"Status: {response.status_code}, User Name: {name}, Username: {username}, Email: {email}")
    if response.status_code != 201:
        logging.error(f"Error: {response.text}")
    return response.json()


def delete_user(user_name: str, hard_delete: bool = True) -> object:
    user_id = get_user_id(user_name)
    GITLAB_URL = os.environ["GITLAB_URL"]
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    url = f"{GITLAB_URL}/api/v4/users/{user_id}?hard_delete={str(hard_delete).lower()}"
    response = requests.delete(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    logging.info(f"Status: {response.status_code}, User deleted: {user_name}, ")

