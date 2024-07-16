import requests
import os
from datetime import datetime, timezone, timedelta
from sqlalchemy.orm import sessionmaker
from sqlalchemy import Column, Integer, String, DateTime, create_engine, update
from sqlalchemy.ext.declarative import declarative_base
import git
from multiprocessing import Pool

Base = declarative_base()

ORG = os.getenv('ORG')
TOKEN = os.getenv('TOKEN')
DAYS = os.getenv('DAYS', 1)
DB_HOST = os.getenv('DEV_DB_HOST')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
REPO_TABLE = os.getenv('REPO_TABLE', 'github_backup_repositories')
TARGET_DIR = os.getenv('TARGET_DIR')


class GithubBackupRepositories(Base):
    __tablename__ = REPO_TABLE

    id = Column(Integer, primary_key=True, autoincrement=True)
    repo_id = Column(Integer, unique=True, nullable=False)
    repo_name = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=False)
    repo_url = Column(String(255), nullable=False)
    clone_url = Column(String(255), nullable=False)
    ssh_url = Column(String(255))
    created_at = Column(DateTime, nullable=False)
    updated_at = Column(DateTime, nullable=False)
    pushed_at = Column(DateTime, nullable=False)


now = datetime.now(timezone.utc)
yesterday = now - timedelta(days=int(DAYS))

engine = create_engine(f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/nota-infra")
Session = sessionmaker(bind=engine)


def convert_to_datetime(date_string):
    return datetime.strptime(date_string, "%Y-%m-%dT%H:%M:%SZ")


def update_local_mirror(each_repo):
    full_name = each_repo['full_name']
    ssh_url = each_repo['ssh_url']
    download_directory = f"{TARGET_DIR}/{full_name}.git"
    try:
        if not os.path.exists(download_directory):
            print(f"Cloning {full_name} to {download_directory}")
            git.Repo.clone_from(ssh_url, download_directory, mirror=True)
        else:
            print(f"Updating {full_name} to {download_directory}")
            git.Repo(download_directory).remotes.origin.update()
    except Exception as e:
        print(f"Error while cloning or pulling {full_name} in {download_directory}: {e}")
        raise e


def get_repos_from_org(org_name):
    results = []
    page_number = 1
    url_main = f"https://api.github.com/search/repositories?q=org:{ORG}&per_page=100"
    url = f"{url_main}&page={page_number}"
    response = requests.get(url, headers={"Authorization": "token " + TOKEN})
    repos = response.json()

    session = Session()
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
            full_name = repo['full_name']
            pushed_at_object = datetime.strptime(pushed_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            r = session.query(GithubBackupRepositories).filter(GithubBackupRepositories.repo_id == repo_id).all()
            if len(r) == 0:
                print(f"Repo {repo_name} not found in the database")
                results.append(
                    {"repo_id": repo_id, "repo_name": repo_name, "full_name": full_name, "repo_url": repo_url,
                     "clone_url": clone_url,
                     "ssh_url": ssh_url, "created_at": created_at, "updated_at": now, "pushed_at": pushed_at})
                session.add(GithubBackupRepositories(repo_id=repo_id, repo_name=repo_name, full_name=full_name,
                                                     repo_url=repo_url, clone_url=clone_url, ssh_url=ssh_url,
                                                     created_at=convert_to_datetime(created_at),
                                                     updated_at=now, pushed_at=pushed_at_object))
            else:
                # print(f"Repo {repo_name} found in the database to be updated")
                if (pushed_at_object > yesterday):
                    print(f"Repo {repo_name} pushed_at is greater than yesterday")
                    session.query(GithubBackupRepositories).filter(GithubBackupRepositories.repo_id == repo_id).update(
                        {"updated_at": yesterday, "pushed_at": pushed_at_object})
                    results.append(
                        {"repo_id": repo_id, "repo_name": repo_name, "full_name": full_name, "repo_url": repo_url,
                         "clone_url": clone_url,
                         "ssh_url": ssh_url, "created_at": created_at, "updated_at": yesterday,
                         "pushed_at": pushed_at_object})
        page_number += 1
        url = f"{url_main}&page={page_number}"
        response = requests.get(url, headers={"Authorization": "token " + TOKEN})
        repos = response.json()
    session.commit()
    session.close()
    return results


r = get_repos_from_org(ORG)

with Pool(32) as p:
    r = p.map(update_local_mirror, r)
