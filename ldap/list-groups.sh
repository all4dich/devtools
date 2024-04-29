#!/bin/bash
workdir=$(dirname $0)
source ${workdir}/set-credentials.sh
ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "uid=${user},${BASE_DN}" -w ${pass} -b "${GROUP_BASE}" \
  -s sub "objectClass=posixGroup" | grep cn:|sed 's/cn: //g'
