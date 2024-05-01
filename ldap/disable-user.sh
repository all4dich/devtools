#!/bin/bash
set -e
workdir=$(dirname $0)
. ${workdir}/set-credentials.sh

TARGET_USER=${1:-${user}}
# Search User and get dn
USER_DN="uid=${TARGET_USER},${USER_BASE}"
echo $USER_DN

# Set shadowExpire to 1
cat << EOF >  disable_user.ldif
dn: $USER_DN
changetype: modify
replace: shadowExpire
shadowExpire: 1
EOF

ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f disable_user.ldif