import logging
import os
import json

from tools import create_user
from gitlab.users.tools import get_all_users
from gitlab.namespace.tools import get_user_groups, get_test
from multiprocessing import Pool
logging.basicConfig(level=logging.INFO)


def get_groups(user):
    email = user["email"]
    if email.endswith("@samsung.com"):
        target_user_name = email.split("@")[0]
        try:
            user_groups = get_user_groups(target_user_name)
            if len(user_groups) == 0:
                print(f"User: {user['name']}, Email: {email}")
        except Exception as e:
            logging.error("cant get groups for a user " + target_user_name)


if __name__ == "__main__":
    all_users = get_all_users()
    p = Pool(10)
    p.map(get_groups, all_users)