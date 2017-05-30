#!/bin/bash
region="par1" # 'par1' or 'ams1'
type="VC1S" # 'VC1S' for test or 'C2S' for CCNA or or 'C2M' for advanced labs
basename=$@
mailto="goffinet@goffinet.eu"
mailfrom="lab@goffinet.eu"
start_time=$(date)
image="Ubuntu_Xenial" # 'Ubuntu_Xenial' 'Ubuntu_Trusty' 'Docker' 'Centos'

mailto_client () {
for server in ${basename} ; do
cat << EOF > /tmp/${server}-header-message.txt
To: $mailto
From: $mailfrom
Subject: ${server} GNS3 installation finished : ${server}

${server} GNS3 installation started at ${start_time} and ended at $(date)

ssh root@${publicip//\"/}

${publicip//\"/} ${server}

EOF
scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${basename}:/root/install-log.txt /tmp/${basename}-install-log.txt
cat /tmp/${server}* > /tmp/${server}-message.txt
ssmtp $mailto < /tmp/${server}-message.txt
rm -rf /tmp/${server}*
done
}


ssh_know_hosts () {
for server in ${basename} ; do
ssh-keygen -f "/root/.ssh/known_hosts" -R ${server}
ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ${server} "exit"
done
}

install_gns3_server () {
for server in ${basename} ; do
scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null gns3_install.sh root@${server}:/root/
ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${server} "bash gns3_install.sh" &
done
wait $(jobs -p)
}

synchronize_images () {
for server in ${basename} ; do
rsync -ave "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null" /root/gns3_images/ root@${basename}:/opt/gns3/images & > /dev/null
done
wait $(jobs -p)
}

ssh_know_hosts
install_gns3_server
synchronize_images
mailto_client
