import ldap
import os
import logging


# List all users
def list_users(filter="(objectClass=inetOrgPerson)", exclude_disabled=True):
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
    if exclude_disabled:
        filter = f"(&{filter}(shadowExpire=-1))"
    result = conn.search_s(os.environ['USER_BASE'], ldap.SCOPE_SUBTREE, filter)
    # Print the results
    logging.info("Printing all users")
    for user, entry in result:
        print(entry)
    # Unbind from the server
    conn.unbind()


if __name__ == '__main__':
    # Get username and password from standard input
    # Change the user's password
    list_users()
