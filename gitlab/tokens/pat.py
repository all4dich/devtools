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