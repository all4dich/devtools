#!/bin/bash
# Backup all entities in LDAP with openldap command line tools
#
# Usage: backup-all-entities.sh
#
# This script will backup all entities in LDAP to a file named
# ldap-entities.ldif in the current directory.
#
 The script will prompt for the LDAP admin password.
#
# The script will use the following environment variables:
# - LDAP_SERVER: the LDAP server URL (default: ldap://localhost)
# - BIND_DN: the LDAP admin DN (default: cn=admin,dc=example,dc=com)
# - ROOT_DN: the LDAP root DN (default: dc=example,dc=com)
# - BACKUP_FILE: the backup file name (default: ldap-entities.ldif)
#
# Example:
# $ LDAP_SERVER=ldap://ldap.example.com BIND_DN=cn=admin,dc=example,dc=com \
#   ROOT_DN=dc=example,dc=com BACKUP_FILE=ldap-entities.ldif ./backup-all-entities.sh
#
# Exit on error
set -e
# Load credentials
workdir=$(dirname $0)
# Set $1 to BACKUP_FILE
BACKUP_FILE=${1:-ldap-entities.ldif}
echo "INFO: Load credentials"
. ${workdir}/set-credentials.sh
# Backup all entities
echo "INFO: Backup all entities to ${BACKUP_FILE}"
ldapsearch -x -LLL -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -b "${ROOT_DN}" > ${BACKUP_FILE}
echo "INFO: Backup completed"
echo "INFO: Backup file: ${BACKUP_FILE}"
echo "INFO: Done"