#!/bin/bash
region="ams1" # 'par1' or 'ams1'
type="VC1S" # 'VC1S' 'X64-2GB' for test or 'C2S' for CCNA or or 'C2M' for advanced labs
basename=$@
mailto="goffinet@goffinet.eu"
mailfrom="lab@goffinet.eu"
start_time=$(date)
image="Ubuntu_Xenial" # 'Ubuntu_Xenial' 'Ubuntu_Trusty' 'Docker' 'Centos'

mailto_client () {
cat << EOF > /tmp/${server}-header-message.txt
To: $mailto
From: $mailfrom
Subject: ${server} installation finished

${server} installation started at ${start_time} and ended at $(date)

ssh root@${publicip//\"/}

${publicip//\"/} ${server}

EOF
#scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${server}:/root/install-log.txt /tmp/${server}-install-log.txt
cat /tmp/${server}* > /tmp/${server}-message.txt
ssmtp $mailto < /tmp/${server}-message.txt
rm -rf /tmp/${server}*
}

scw_run () {
for server in ${basename} ; do
uuid=$(scw --region=${region} create --name="${server}" --commercial-type=${type} ${image})
scw --region=${region} start -w ${uuid} &
done
wait $(jobs -p)
}

get_info() {
for server in ${basename} ; do
#uuid=$(scw ps | grep "${server}" | awk '{print $1}')
#privateip=$(scw --region=${region} inspect ${uuid} | jq '.[0].private_ip')
publicip=$(scw ps | grep ${server} | awk '{print $7}')
echo "### added for ${server} at $(date) ###" >> /etc/hosts
echo "${publicip//\"/} ${server}" >> /etc/hosts
mailto_client
done
}

scw_run
get_info
echo "Task executed"
exit 0
