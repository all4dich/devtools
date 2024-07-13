import requests
import os
from datetime import datetime, timezone, timedelta

ORG = os.environ('ORG')
TOKEN = os.getenv('TOKEN')
DAYS = os.getenv('DAYS', 1)

yesterday = datetime.now(timezone.utc) - timedelta(days=os.getenv('DAYS', 1))


def get_repos_from_org(org_name):
    results = []
    page_number = 1
    url_main = f"https://api.github.com/search/repositories?q=org:{ORG}&per_page=100"
    url = f"{url_main}&page={page_number}"
    response = requests.get(url, headers={"Authorization": "token " + TOKEN})
    repos = response.json()
    while repos['items']:
        for repo in repos['items']:
            repo_id = repo['id']
            repo_name = repo['name']
            repo_url = repo['url']
            clone_url = repo['clone_url']
            ssh_url = repo['ssh_url']
            created_at = repo['created_at']
            updated_at = repo['updated_at']
            pushed_at = repo['pushed_at']
            pushed_at_object = datetime.strptime(pushed_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            if pushed_at_object > yesterday:
                results.append(
                    {"repo_id": repo_id, "repo_name": repo_name, "repo_url": repo_url, "clone_url": clone_url,
                     "ssh_url": ssh_url, "created_at": created_at, "updated_at": updated_at, "pushed_at": pushed_at})
        page_number += 1
        url = f"{url_main}&page={page_number}"
        response = requests.get(url, headers={"Authorization": "token " + TOKEN})
        repos = response.json()
    return results


r = get_repos_from_org(ORG)
print(r)
