import os
import requests
import logging
import json

logging.basicConfig(level=logging.INFO)

SSL_CERT_VERIFY: bool = os.getenv("SSL_CERT_VERIFY", True)
if type(SSL_CERT_VERIFY) == str:
    SSL_CERT_VERIFY = eval(SSL_CERT_VERIFY)


def get_access_level_name(access_level_id):
    access_level_id = int(access_level_id)
    access_level_name = ""
    # Access Level
    # 10 => Guest access
    # 20 => Reporter access
    # 30 => Developer access
    # 40 => Maintainer access
    # 50 => Owner access
    access_levels = {10: "guest", 20: "reporter", 30: "developer", 40: "maintainer", 50: "owner"}
    if access_level_id in access_levels:
        access_level_name = access_levels[access_level_id]
    return access_level_name


def get_access_level_id(access_level_name):
    access_level = access_level_name.lower()
    access_level_id = 0
    # Access Level
    # 10 => Guest access
    # 20 => Reporter access
    # 30 => Developer access
    # 40 => Maintainer access
    # 50 => Owner access
    access_levels_ids = {"guest": 10, "reporter": 20, "developer": 30, "maintainer": 40, "owner": 50}
    if access_level in access_levels_ids:
        access_level_id = access_levels_ids[access_level]
    return access_level_id


def get_ns_list():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/namespaces"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    print(response.status_code)
    ns_list = response.json()
    for ns in ns_list:
        logging.info(f"Namespace ID: {ns['id']}, Namespace Name: {ns['name']}")
    return ns_list


def get_groups_list():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    print(response.status_code)
    groups_list = response.json()
    while len(groups_list) > 0 and response.status_code == 200:
        for group in groups_list:
            id = group["id"]
            name = group["name"]
            path = group["path"]
            full_path = group["full_path"]
            full_name = group["full_name"]
            web_url = group["web_url"]
            logging.info(
                f"Group ID: {id}, Name: {name}, Path: {path}, Full Path: {full_path}, Full Name: {full_name}, Web URL: {web_url}")
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            groups_list = response.json()
    return groups_list


def get_ns_id(ns_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/namespaces?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    namespaces = response.json()
    ns_id = ""
    while len(namespaces) > 0 and response.status_code == 200:
        for ns in namespaces:
            if ns["name"] == ns_name:
                ns_id = ns["id"]
                break
        if ns_id != "":
            break
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            namespaces = response.json()
    return ns_id


def get_group_id(group_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    groups = response.json()
    group_id = ""
    while len(groups) > 0 and response.status_code == 200:
        for group in groups:
            if group["name"] == group_name:
                group_id = group["id"]
                break
        if group_id != "":
            break
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            groups = response.json()
    return group_id


def get_user_id(user_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/users?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    users = response.json()
    user_id = ""
    while len(users) > 0 and response.status_code == 200:
        for user in users:
            if user["username"] == user_name:
                user_id = user["id"]
                break
        if user_id != "":
            break
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            users = response.json()
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
    url = f"{GITLAB_URL}api/v4/users/{user_id}/memberships?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    memberships = response.json()
    groups = []
    while len(memberships) > 0 and response.status_code == 200:
        groups.append(memberships)
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            memberships = response.json()
        #    if source_type == "Namespace":  # Namespace is a group on Gitlab web page.
        #        logging.info(
        #            f"User ID: {user_id}, User Name: {user_name}, Group ID: {source_id}, Group Name: {source_name}")
        #        group_info = requests.get(f"{GITLAB_URL}api/v4/namespaces/{source_id}",
        #                                  headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
        #        groups.append(group_info.json())
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
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    members = response.json()
    users = []
    while len(members) > 0:
        for member in members:
            user_id = member["id"]
            user_info = requests.get(f"{GITLAB_URL}api/v4/users/{user_id}", headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
                                     verify=SSL_CERT_VERIFY)
            users.append(user_info.json())
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            members = response.json()
    return users


def get_project_lists():
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=False)
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
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)

    return projects


def get_project_id(project_name):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
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
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    return project_id


def get_project_info(project_id):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects/{project_id}"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=False)
    project_info = response.json()
    logging.info(
        f"Project ID: {project_info['id']}, Name: {project_info['name']}, Path with Namespace: {project_info['path_with_namespace']}, Web URL: {project_info['web_url']}")
    return project_info


def get_project_members(project_id):
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/projects/{project_id}/members/all?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    members = response.json()
    users = []
    while len(members) > 0:
        for member in members:
            user_id = member["id"]
            user_info = requests.get(f"{GITLAB_URL}api/v4/users/{user_id}", headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
                                     verify=SSL_CERT_VERIFY)
            users.append(user_info.json())
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            members = response.json()
    return users


def get_users_in_ns(ns_name):
    logging.info("Getting users in namespace")
    ns_id = get_ns_id(ns_name)
    logging.info(f"Namespace ID: {ns_id}, Namespace Name: {ns_name}")
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/{ns_id}/members?per_page=100"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    member_list = response.json()
    while len(member_list) > 0 and response.status_code == 200:
        for member in member_list:
            try:
                # print(ns_name, member["username"], member["email"], member["access_level"])
                access_level_name = get_access_level_name(member["access_level"])
                logging.info(
                    f"Namespace: {ns_name}, User Name: {member['username']}, Email: {member['email']}, Access Level: {access_level_name}")
            except TypeError:
                logging.error("Cannot get member info")
                logging.error(member)
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            member_list.extend(response)
    return member_list


def get_users(search=None):
    logging.info(f"Getting users with {search}")
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/users?per_page=100"
    if search is not None:
        url = f"{url}&search={search}"
    response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    users = response.json()
    users_output = []
    while len(users) > 0 and response.status_code == 200:
        for user in users:
            logging.debug(
                f"User ID: {user['id']}, User Name: {user['name']}, Username: {user['username']}, Email: {user['email']}")
            users_output.append(user)
        if "next" not in response.links:
            break
        else:
            url = response.links["next"]["url"]
            response = requests.get(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
            users.extend(response.json())
    return users_output


def add_user_to_ns(ns_name, user_name, access_level_name="Guest"):
    logging.info("Adding user to namespace")
    ns_id = get_ns_id(ns_name)
    user_id = get_user_id(user_name)
    access_level = get_access_level_id(access_level_name)
    logging.info(f"Namespace ID: {ns_id}, Namespace Name: {ns_name}")
    logging.info(f"User ID: {user_id}, User Name: {user_name}")
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/{ns_id}/members"
    data = {
        "username": user_name,
        "user_id": user_id,
        "access_level": access_level
    }
    response = requests.post(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, data=data, verify=SSL_CERT_VERIFY)
    logging.info(response.text)
    logging.info(response.status_code)


def remove_user_from_ns(ns_name, user_name):
    logging.info("Removing user from namespace")
    ns_id = get_ns_id(ns_name)
    user_id = get_user_id(user_name)
    logging.info(f"Namespace ID: {ns_id}, Namespace Name: {ns_name}")
    logging.info(f"User ID: {user_id}, User Name: {user_name}")
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/{ns_id}/members/{user_id}"
    response = requests.delete(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, verify=SSL_CERT_VERIFY)
    logging.info(response.text)
    logging.info(response.status_code)


def update_user_access_level(ns_name, user_name, access_level_name):
    logging.info("Updating user access level")
    ns_id = get_ns_id(ns_name)
    user_id = get_user_id(user_name)
    access_level = get_access_level_id(access_level_name)
    logging.info(f"Namespace ID: {ns_id}, Namespace Name: {ns_name}")
    logging.info(f"User ID: {user_id}, User Name: {user_name}")
    GITLAB_TOKEN = os.environ["GITLAB_TOKEN"]
    GITLAB_URL = os.environ["GITLAB_URL"]
    url = f"{GITLAB_URL}api/v4/groups/{ns_id}/members/{user_id}"
    data = {
        "access_level": access_level
    }
    response = requests.put(url, headers={"PRIVATE-TOKEN": GITLAB_TOKEN}, data=data, verify=SSL_CERT_VERIFY)
    logging.info(response.text)
    logging.info(response.status_code)


def get_test(user_name):
    print(user_name)
