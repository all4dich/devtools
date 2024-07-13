import requests
import os

ORG = os.environ['ORG']
TOKEN = os.environ['TOKEN']


def get_repos_from_org(org_name):
    page_number = 0
    url_main = f"https://api.github.com/search/repositories?q=org:{ORG}&per_page=100"
    url = f"{url_main}&page={page_number}"
    response = requests.get(url, headers={"Authorization": "token " + TOKEN})
    repos = response.json()
    while repos['items']:
        for repo in repos['items']:
            repo_name = repo['name']
            repo_url = repo['url']
            clone_url = repo['clone_url']
            ssh_url = repo['ssh_url']
            created_at = repo['created_at']
            updated_at = repo['updated_at']
            pushed_at = repo['pushed_at']
            print(f"{repo_name}, {clone_url}, {created_at}, {updated_at}, {pushed_at}")
        page_number += 1
        url = f"{url_main}&page={page_number}"
        response = requests.get(url, headers={"Authorization": "token " + TOKEN})
        repos = response.json()


get_repos_from_org(ORG)
