import logging
import os
import json

from tools import create_user
from gitlab.namespace.tools import add_user_to_ns

logging.basicConfig(level=logging.INFO)

users = [
    {
        "name": "Test User Nota",
        "email": "test_user.nota@nota.ai"
    }
]

if __name__ == "__main__":
    reset_password = json.loads(os.getenv("RESET_PASSWORD", "True").lower())
    skip_confirmation = json.loads(os.getenv("SKIP_CONFIRMATION", "False").lower())
    external_user = json.loads(os.getenv("EXTERNAL_USER", "True").lower())
    for user in users:
        user["username"] = user["email"].split("@")[0]
        logging.info(f"Creating user: {user['name']}")
        create_user(user["username"], user["email"], user["name"], reset_password=reset_password,
                    skip_confirmation=skip_confirmation, external=external_user)
        logging.info(f"User created: {user['name']}")
        add_user_to_ns("samsung_lsi", user["username"], "Developer")
