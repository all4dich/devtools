import requests
import os
import argparse

arg_parser = argparse.ArgumentParser(description='Call GitLab API')
arg_parser.add_argument('--gitlab-token', required=True, help='GitLab token')
arg_parser.add_argument('--gitlab-url', required=True, help='GitLab URL')
args = arg_parser.parse_args()

GITLAB_TOKEN: str = args.gitlab_token
GITLAB_URL: str = args.gitlab_url


def get_project_list():
    url = f"{GITLAB_URL}/api/v4/projects"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}"}
    response = requests.get(url, headers=headers, verify=False)
    print(response.json())


if __name__ == "__main__":
    get_project_list()
