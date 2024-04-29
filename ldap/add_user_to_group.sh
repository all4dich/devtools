#!/bin/bash
# Define LDAP server and base DN
LDAP_SERVER="ldap://nas-admin.nota.ai"
BASE_DN="dc=nas-admin,dc=nota,dc=ai"

# Group DN and user DN
GROUP_DN="cn=rnd,cn=groups,dc=nas-admin,dc=nota,dc=ai"
USER_DN="uid=soyul.park,cn=users,dc=nas-admin,dc=nota,dc=ai"

rm -fv *.ldif

cat << EOF >  update_group1.ldif
dn: $GROUP_DN
changetype: modify
add: member
member: $USER_DN
EOF

cat << EOF >  update_group2.ldif
dn: $GROUP_DN
changetype: modify
add: memberUid
memberUid: soyul.park
EOF

#cat << EOF >  update_user.ldif
#dn: $USER_DN
#changetype: modify
#add: memberOf
#memberOf: $GROUP_DN
#EOF

ldapmodify -H ${LDAP_SERVER} -D "uid=admin,cn=users,dc=nas-admin,dc=nota,dc=ai" -w "wecgyv-dIjrov-tufxo7" -f update_group1.ldif
ldapmodify -H ${LDAP_SERVER} -D "uid=admin,cn=users,dc=nas-admin,dc=nota,dc=ai" -w "wecgyv-dIjrov-tufxo7" -f update_group2.ldif
#ldapmodify -H ${LDAP_SERVER} -D "uid=admin,cn=users,dc=nas-admin,dc=nota,dc=ai" -w "wecgyv-dIjrov-tufxo7" -f update_user.ldif
