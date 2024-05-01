#!/bin/bash
set -e
workdir=$(dirname $0)
. ${workdir}/set-credentials.sh

TARGET_USER=${1:-${user}}
# Search User and get dn
USER_DN="uid=${TARGET_USER},${USER_BASE}"
echo $USER_DN
# Create a list from multiple lines
SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
IFS=$'\n'      # Change IFS to newline char
names=($names) # split the `names` string into an array by the same name
GROUPS_DN=(`ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "uid=${user},${BASE_DN}" -w ${pass} -b "${GROUP_BASE}" -s sub "member=uid=${TARGET_USER},${USER_BASE}" | grep cn:|sed 's/cn: //g'`)
IFS=$SAVEIFS   # Restore original IFS
for group in "${GROUPS_DN[@]}"; do
  echo "INFO: Remove ${TARGET_USER} from cn=${group},${GROUP_BASE}"
  cat << EOF >  remove_member.ldif
dn: cn=${group},${GROUP_BASE}
changetype: modify
delete: member
member: $USER_DN
-
delete: memberUid
memberUid: ${TARGET_USER}
EOF
  ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f remove_member.ldif
done

cat << EOF >  delete_user.ldif
dn: $USER_DN
changetype: delete
EOF

ldapmodify -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f delete_user.ldif