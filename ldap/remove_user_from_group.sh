#!/bin/bash
workdir=$(dirname 0)
. ${workdir}/set-credentials.sh

GROUP_DN=`ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "${BIND_DN}" -w ${BIND_PW} -b "${GROUP_BASE}" -s sub "cn=${1}" | grep dn:|sed 's/dn: //g'`
echo $GROUP_DN
# Search User and get dn
USER_DN=`ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "${BIND_DN}" -w ${BIND_PW} -b "${USER_BASE}" -s sub "uid=${2}" | grep dn:|sed 's/dn: //g'`
echo $USER_DN

rm -fv *.ldif

cat << EOF >  remove_member.ldif
dn: $GROUP_DN
changetype: modify
delete: member
member: $USER_DN
EOF

cat << EOF >  remove_memberUid.ldif
dn: ${GROUP_DN}
changetype: modify
delete: memberUid
memberUid: ${2}
EOF

set -x
ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f remove_member.ldif
ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f remove_memberUid.ldif
set +x
