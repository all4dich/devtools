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


def get_namespace_id(org_name: str):
    url = f"{GITLAB_URL}/api/v4/namespaces"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}", "Content-Type": "application/json"}
    response = requests.get(url, headers=headers, verify=False)
    namespace_id = ""
    for namespace in response.json():
        if namespace["name"] == org_name:
            namespace_id = namespace["id"]
            break
    return namespace_id

def create_project_repo(org_name: str, repo_name: str):
    url = f"{GITLAB_URL}/api/v4/projects"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}"}
    data = {
        "name": repo_name,
        "description": "This is a project",
        "path": repo_name,
        "namespace_id": get_namespace_id(org_name),
        "initialize_with_readme": "false",
        "visibility": "private"
    }
    response = requests.post(url, headers=headers, data=data, verify=False)
    print(response.json())
    print(response.status_code)


if __name__ == "__main__":
    #get_project_list()
    create_project_repo("nota-infra", "test-repo2")
