import ldap
import os
import logging


def change_password(username, password, filter="(objectClass=inetOrgPerson)"):
    # Set up logging
    logging.basicConfig(level=logging.INFO)
    logging.info("Starting script")
    # Create a connection to the LDAP server
    conn = ldap.initialize(os.environ['LDAP_SERVER'])
    logging.info("Connected to LDAP server")
    # Bind to the server
    conn.simple_bind_s(os.environ['BIND_DN'], os.environ['BIND_PW'])
    # Search for all users
    logging.info("Searching for all users")
    result = conn.search_s(os.environ['USER_BASE'], ldap.SCOPE_SUBTREE, filter)
    # Change the selected user's password
    logging.info("Changing the selected user's password")
    for user, entry in result:
        if entry['uid'][0].decode() == username:
            print(user)
            conn.passwd_s(user, None, password)
    # Unbind from the server
    conn.unbind()


if __name__ == '__main__':
    # Get username and password from standard input
    username = input("Enter username: ")
    password = input("Enter password: ")
    # Change the user's password
    change_password(username, password)
