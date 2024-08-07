import os
import requests
import logging
import json

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
        logging.info(
            f"Group ID: {id}, Name: {name}, Path: {path}, Full Path: {full_path}, Full Name: {full_name}, Web URL: {web_url}")
    return groups_list


def get_ns_id(ns_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/namespaces"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    ns_id = ""
    for ns in response.json():
        if ns["name"] == ns_name:
            ns_id = ns["id"]
            break
    return ns_id


def get_group_id(group_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    group_id = ""
    for group in response.json():
        if group["name"] == group_name:
            group_id = group["id"]
            break
    return group_id


def get_user_id(user_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/users"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    user_id = ""
    for user in response.json():
        if user["username"] == user_name:
            user_id = user["id"]
            logging.info(f"Found! = User ID: {user_id}, User Name: {user_name}")
            break
    return user_id


def get_user_groups(user_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    # Get User Id
    user_id = get_user_id(user_name)
    if user_id == "":
        logging.error(f"User not found! = User Name: {user_name}")
        return []
    # Get User Memberships: Namepace/Project
    url = f"{GITLAB_URL}api/v4/users/{user_id}/memberships"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    memberships = response.json()
    groups = []
    for membership in memberships:
        source_id = membership["source_id"]
        source_name = membership["source_name"]
        source_type = membership["source_type"]
        if source_type == "Namespace":  # Namespace is a group on Gitlab web page.
            logging.info(
                f"User ID: {user_id}, User Name: {user_name}, Group ID: {source_id}, Group Name: {source_name}")
            group_info = requests.get(f"{GITLAB_URL}api/v4/namespaces/{source_id}",
                                      headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
            groups.append(group_info.json())
    return groups


def get_group_members(group_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    # Get Group Id
    group_id = get_group_id(group_name)
    if group_id == "":
        logging.error(f"Group not found! = Group Name: {group_name}")
        return []
    # Get Group Members
    url = f"{GITLAB_URL}api/v4/groups/{group_id}/members/all?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    members = response.json()
    users = []
    while len(members) > 0:
        for member in members:
            user_id = member["id"]
            user_info = requests.get(f"{GITLAB_URL}api/v4/users/{user_id}", headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
            users.append(user_info.json())
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
            members = response.json()
    return users


def get_project_lists():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    projects = []
    while len(response.json()) > 0:
        for project in response.json():
            id = project["id"]
            name = project["name"]
            path_with_namespace = project["path_with_namespace"]
            web_url = project["web_url"]
            projects.append(project)
            logging.info(
                f"Project ID: {id}, Name: {name}, Path with Namespace: {path_with_namespace}, Web URL: {web_url}")
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})

    return projects


def get_project_id(project_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    project_id = ""
    while len(response.json()) > 0:
        for project in response.json():
            if project["path_with_namespace"] == project_name:
                project_id = project["id"]
                break
        if project_id != "":
            break
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    return project_id


def get_project_info(project_id):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects/{project_id}"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    project_info = response.json()
    logging.info(
        f"Project ID: {project_info['id']}, Name: {project_info['name']}, Path with Namespace: {project_info['path_with_namespace']}, Web URL: {project_info['web_url']}")
    return project_info


def get_project_members(project_id):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects/{project_id}/members/all?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    members = response.json()
    users = []
    while len(members) > 0:
        for member in members:
            user_id = member["id"]
            user_info = requests.get(f"{GITLAB_URL}api/v4/users/{user_id}", headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
            users.append(user_info.json())
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
            members = response.json()
    return users