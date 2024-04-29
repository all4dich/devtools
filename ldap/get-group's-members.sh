#!/bin/bash
workdir=$(dirname $0)
target_group=${1:-np-application}
source ${workdir}/set-credentials.sh
ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "uid=${user},${BASE_DN}" -w ${pass} -b "${GROUP_BASE}" -s sub "cn=${target_group}"| grep member:|sed 's/member: uid=//g'|sed 's/,${USER_BASE}//g'