#!/bin/bash
region="par1" # 'par1' or 'ams1'
type="VC1S" # 'VC1S' for test or 'C2S' for CCNA or or 'C2M' for advanced labs
basename=$@
mailto="goffinet@goffinet.eu"
mailfrom="lab@goffinet.eu"
start_time=$(date)
image="Ubuntu_Xenial" # 'Ubuntu_Xenial' 'Ubuntu_Trusty' 'Docker' 'Centos'
images_path="/root/gns3_images/"

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
scp -q -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${server}:/root/install-log.txt /tmp/${server}-install-log.txt
cat /tmp/${server}* > /tmp/${server}-message.txt
ssmtp $mailto < /tmp/${server}-message.txt
rm -rf /tmp/${server}*
done
}


ssh_know_hosts () {
for server in ${basename} ; do
ssh-keygen -f "/root/.ssh/known_hosts" -R ${server}
ssh -q -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ${server} "exit"
done
}

install_gns3_server () {
for server in ${basename} ; do
scp -q -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null gns3_install.sh root@${server}:/root/
ssh -q -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${server} "bash gns3_install.sh" & > /dev/null
done
wait $(jobs -p)
}

synchronize_files () {
for server in ${basename} ; do
rsync -ave "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null" ${images_path} root@${basename}:/opt/gns3/images & > /dev/null
done
wait $(jobs -p)
}

reboot_server () {
for server in ${basename} ; do
ssh -q -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${server} "shutdown -r now"
done
}

ssh_know_hosts
install_gns3_server
synchronize_files
mailto_client
reboot_server
echo "Task executed"
exit 0
