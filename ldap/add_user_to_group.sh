#!/bin/bash
set -e
workdir=$(dirname $0)
. ${workdir}/set-credentials.sh

# Search Group
GROUP_DN=`ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "${BIND_DN}" -w ${BIND_PW} -b "${GROUP_BASE}" -s sub "cn=${1}" | grep dn:|sed 's/dn: //g'`
echo "INFO: Group DN = $GROUP_DN"
# Search User and get dn
USER_DN=`ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "${BIND_DN}" -w ${BIND_PW} -b "${USER_BASE}" -s sub "uid=${2}" | grep dn:|sed 's/dn: //g'`
echo "INFO: User DN = $USER_DN"

rm -fv *.ldif
cat << EOF >  update_group1.ldif
dn: $GROUP_DN
changetype: modify
add: member
member: $USER_DN
-
add: memberUid
memberUid: ${2}
EOF

echo "INFO: Add a user to a group on LDAP"
ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f update_group1.ldif