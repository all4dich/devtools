#!/bin/bash
workdir=$(dirname $0)
source ${workdir}/set-credentials.sh
target_user=${1:-${user}}
ldapsearch -x -LLL -H ldap://${LDAP_HOST} -D "uid=${user},${BASE_DN}" -w ${pass} -b "${GROUP_BASE}" -s sub "member=uid=${target_user},${USER_BASE}" | grep cn:|sed 's/cn: //g'

