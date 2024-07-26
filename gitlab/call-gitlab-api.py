import requests
import os
import argparse

arg_parser = argparse.ArgumentParser(description='Call GitLab API')
arg_parser.add_argument('--gitlab-token', required=True, help='GitLab token')
arg_parser.add_argument('--gitlab-url', required=True, help='GitLab URL')
arg_parser.add_argument('--org-name', required=True, help='Organization name')
arg_parser.add_argument('--repo-name', required=True, help='Repository name')
arg_parser.add_argument('--ssh-cert-verify', default=True, help='Action to perform')
args = arg_parser.parse_args()

GITLAB_TOKEN: str = args.gitlab_token
GITLAB_URL: str = args.gitlab_url
ORG_NAME: str = args.org_name
REPO_NAME: str = args.repo_name
SSL_CERT_VERIFY: bool = args.ssh_cert_verify


def get_project_list():
    url = f"{GITLAB_URL}/api/v4/projects"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}"}
    response = requests.get(url, headers=headers, verify=SSL_CERT_VERIFY)
    print(response.json())


def get_namespace_id(org_name: str):
    url = f"{GITLAB_URL}/api/v4/namespaces"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}", "Content-Type": "application/json"}
    response = requests.get(url, headers=headers, verify=SSL_CERT_VERIFY)
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
    response = requests.post(url, headers=headers, data=data, verify=SSL_CERT_VERIFY)
    print(response.json())
    print(response.status_code)


def get_projects_list(per_page: int = 100):
    projects = {}
    url = f"{GITLAB_URL}/api/v4/projects?per_page={per_page}"
    headers = {"PRIVATE-TOKEN": f"{GITLAB_TOKEN}"}
    response = requests.get(url, headers=headers, verify=SSL_CERT_VERIFY)
    while len(response.json()) > 0:
        for project in response.json():
            id = project["id"]
            name = project["name"]
            path_with_namespace = project["path_with_namespace"]
            web_url = project["web_url"]
            projects[path_with_namespace] = {"id": id, "name": name, "path_with_namespace": path_with_namespace,
                                             "web_url": web_url}
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers=headers, verify=SSL_CERT_VERIFY)
    return projects


def delete_project_repo(namespace_name: str, repo_name: str):
    projects = get_projects_list()
    project_id = projects[f"{namespace_name}/{repo_name}"]["id"]
    url = f"{GITLAB_URL}/api/v4/projects/{project_id}"
    headers = {"Authorization": f"Bearer {GITLAB_TOKEN}"}
    response = requests.delete(url, headers=headers, verify=SSL_CERT_VERIFY)
    print(response.json())
    print(response.status_code)


if __name__ == "__main__":
    # get_project_list()
    #create_project_repo(ORG_NAME, REPO_NAME)
    delete_project_repo(ORG_NAME, REPO_NAME)
    # get_project_id("nota-infra", "test-repo2")
    # r = get_projects_list()
    # print(r)
