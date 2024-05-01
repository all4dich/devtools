#!/bin/bash
set -e
workdir=$(dirname $0)
echo "INFO: Load credentials"
. ${workdir}/set-credentials.sh

username=${1}
USER_DN="uid=${username},${USER_BASE}"
echo "INFO: User DN = $USER_DN"

maxUid=`ldapsearch -x -LLL -H ${LDAP_SERVER}  -D "${BIND_DN}" -w "${BIND_PW}" -b "${USER_BASE}" "(uidNumber=*)" uidNumber | grep uidNumber | awk '{print $2}' | sort -n | tail -n 1`
echo "INFO: Current Max uid = $maxUid"
#maxUid_next=$((maxUid+1))
maxUid_next=`ldapsearch -x -LLL  -H ldap://${LDAP_HOST} -b "cn=CurID,cn=synoconf,$ROOT_DN" "(uidNumber=*)" uidNumber| grep uidNumber| awk -F ' ' '{print $NF}' | sort -n | tail -1`
echo "INFO: New uid for a user ${username}= ${maxUid_next}"

#Get the last sambaSID
sambaSID=`ldapsearch -x -LLL -H ${LDAP_SERVER}  -D "${BIND_DN}" -w "${BIND_PW}" -b "${USER_BASE}" "(sambaSID=*)" sambaSID| grep sambaSID | awk '{print $2}' | sort -n | tail -n 1`
echo "INFO: Lasted sambaSID on LDAP = "$sambaSID
# Split sambaSID with '-' and get the last part
sambaSID_last=`echo $sambaSID | awk -F '-' '{print $NF}'`
#sambaNextUserRid=$((sambaSID_last+1))
sambaNextUserRid=`ldapsearch -x -LLL  -H ldap://${LDAP_HOST} -b "$ROOT_DN" "(sambaNextUserRid=*)" sambaNextUserRid | grep sambaNextUserRid| awk -F ' ' '{print $NF}' | sort -n | tail -1`
# Replace the last part of sambaSID with the next number
sambaSID_new=`echo $sambaSID | sed "s/${sambaSID_last}/${sambaNextUserRid}/"`
echo "INFO: New sambaSID for a user ${username} = ${sambaSID_new}"

ehco "INFO: Create a new user entry file(LDIF) for ${username}"
cat << EOF >  create-user.ldif
# Define the new user entry
dn: ${USER_DN}
changetype: add
shadowInactive: 0
shadowFlag: 0
mail: ${1}@${DOMAIN}
authAuthority: ;basic;
displayName: ${1}
uid: ${1}
shadowMax: 99999
uidNumber: ${maxUid_next}
gidNumber: 1000001
homeDirectory: /home/${1}
shadowMin: 100000
sn: ${1}
objectClass: top
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: apple-user
objectClass: sambaSamAccount
objectClass: sambaIdmapEntry
objectClass: extensibleObject
cn: ${1}
loginShell: /bin/bash
sambaSID: ${sambaSID_new}
EOF

echo "INFO: Create a new user entry on LDAP"
ldapmodify -x  -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f create-user.ldif

# Set the next RID
sambaNextUserRid_new=$((sambaNextUserRid+1))
echo "INFO: Next sambaNextUserRid = $sambaNextUserRid_new"
cat << EOF >  update-sambaNextUserRid.ldif
dn: sambaDomainName=${DOMAIN_NAME},${ROOT_DN}
changetype: modify
delete: sambaNextUserRid
sambaNextUserRid: ${sambaNextUserRid}
-
add: sambaNextUserRid
sambaNextUserRid: ${sambaNextUserRid_new}
EOF
echo "INFO: Update sambaNextUserRid on LDAP"
ldapmodify -x  -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f update-sambaNextUserRid.ldif

# Set the next UID
maxUid_next_new=$((maxUid_next+1))
echo "INFO: Next uid = $maxUid_next_new"
cat << EOF >  update-next-uidNumber.ldif
dn: cn=CurID,cn=synoconf,$ROOT_DN
changetype: modify
delete: uidNumber
uidNumber: ${maxUid_next}
-
add: uidNumber
uidNumber: ${maxUid_next_new}
EOF
echo "INFO: Update the next uidNumber on LDAP"
ldapmodify -x  -H ${LDAP_SERVER} -D "${BIND_DN}" -w "${BIND_PW}" -f update-next-uidNumber.ldif

echo "INFO: Add the user to the groups"
. ${workdir}/add_user_to_group.sh users ${1}
. ${workdir}/add_user_to_group.sh users_local ${1}
. ${workdir}/add_user_to_group.sh docker_local ${1}
. ${workdir}/add_user_to_group.sh docker_in_adam ${1}
. ${workdir}/add_user_to_group.sh docker_in_beauty_dgx ${1}
. ${workdir}/add_user_to_group.sh "Directory Clients" ${1}
. ${workdir}/add_user_to_group.sh "Directory Consumers" ${1}