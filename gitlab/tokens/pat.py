import requests
import os
import json
import logging

logging.basicConfig(level=logging.INFO)


def get_pat_list(uid: str = None, per_page: int = 100):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    pat_list = []
    if uid is None:
        # If uid is None, get all PATs
        url = f"{GITLAB_URL}/api/v4/personal_access_tokens?per_page={per_page}"
    else:
        # If uid is provided, get PATs for that user
        url = f"{GITLAB_URL}/api/v4/personal_access_tokens?user_id={uid}&per_page={per_page}"
    response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
    while len(response.json()) > 0:
        # Loop through all PATs and merge them in a list
        for pat in response.json():
            logging.info(f"ID: {pat['id']}, Name: {pat['name']}, Expires At: {pat['expires_at']}")
            pat_list.append(pat)
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
    return pat_list


def check_if_user_has_impersonation_tokens(token_state="active"):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}/api/v4/users?per_page=100"
    response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
    users = response.json()
    # Loop through all users
    while len(users) > 0:
        for user in users:
            user_id = user["id"]
            user_name = user["name"]
            url = f"{GITLAB_URL}/api/v4/users/{user_id}/impersonation_tokens?state={token_state}&per_page=100"
            # Get impersonation tokens for the user with token state is $token_state
            response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
            impersonation_tokens = response.json()
            # Loop through all impersonation tokens
            while len(impersonation_tokens) > 0:
                # Print impersonation tokens
                for impersonation_token in impersonation_tokens:
                    logging.info(
                        f"User ID: {user_id}, User Name: {user_name}, Impersonation Token ID: {impersonation_token['id']}, Name: {impersonation_token['name']}, active: {impersonation_token['active']}, imersonation: {impersonation_token['impersonation']}")
                if "next" not in response.links:
                    break
                else:
                    # If there is next page then get the next page URL and get the next page
                    url = response.links["next"]["url"]
                    response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
        if "next" not in response.links:
            break
        else:
            # If there is next page then get the next page URL and get the next page
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"Authorization": f"Bearer {GITLAB_TOKEN}"})
            users = response.json()
