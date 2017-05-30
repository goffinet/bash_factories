#!/bin/bash
# Original source : https://raw.githubusercontent.com/GNS3/gns3-server/master/scripts/remote-install.sh

function log {
  echo "=> $1"  >&2
}

# Read the options
USE_VPN=1
UNSTABLE=1

# Exit in case of error
set -e

export DEBIAN_FRONTEND="noninteractive"

UBUNTU_VERSION=`lsb_release -r -s`

if [ "$UBUNTU_VERSION" == "16.04" ]
then
    UBUNTU_CODENAME="xenial"
else
    echo "Ubuntu Xenial 16.04 LTS only !" ; exit 1
fi

log "Add GNS3 repository"

# Install gns3 apt source
if [ $UNSTABLE == 1 ]
then
cat <<EOFLIST > /etc/apt/sources.list.d/gns3.list
deb http://ppa.launchpad.net/gns3/unstable/ubuntu $UBUNTU_CODENAME main
deb-src http://ppa.launchpad.net/gns3/unstable/ubuntu $UBUNTU_CODENAME main
EOFLIST
else
cat <<EOFLIST > /etc/apt/sources.list.d/gns3.list
deb http://ppa.launchpad.net/gns3/ppa/ubuntu $UBUNTU_CODENAME main
deb-src http://ppa.launchpad.net/gns3/ppa/ubuntu $UBUNTU_CODENAME main
EOFLIST
fi

apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A2E3EF7B

log "Update system packages"
apt-get update

log "Upgrade packages"
apt-get upgrade -y


# Install gns3
log " Install GNS3 packages"
apt-get install -y gns3-server virt-manager git build-essential

# Install ubridge
git clone https://github.com/GNS3/ubridge
apt-get install -y libpcap-dev
cd ubridge
make
make install

log "Create user GNS3 with /opt/gns3 as home directory"
if [ ! -d "/opt/gns3/" ]
then
  useradd -d /opt/gns3/ -m gns3
fi

log "Install docker"
if [ ! -f "/usr/bin/docker" ]
then
  curl -sSL https://get.docker.com | bash
fi

log "Add GNS3 to the docker group"
usermod -aG docker gns3

log "Add gns3 to the kvm group"
usermod -aG kvm gns3

log "Setup GNS3 server"

mkdir -p /etc/gns3
cat <<EOFC > /etc/gns3/gns3_server.conf
[Server]
host = 0.0.0.0
port = 3080 
images_path = /opt/gns3/images
projects_path = /opt/gns3/projects
report_errors = True

[Qemu]
enable_kvm = True
EOFC

chown -R gns3:gns3 /etc/gns3
chmod -R 700 /etc/gns3

# Install systemd service
cat <<EOFI > /lib/systemd/system/gns3.service
[Unit]
Description=GNS3 server

[Service]
Type=forking
User=gns3
Group=gns3
PermissionsStartOnly=true
ExecStartPre=/bin/mkdir -p /var/log/gns3 /var/run/gns3
ExecStartPre=/bin/chown -R gns3:gns3 /var/log/gns3 /var/run/gns3
ExecStart=/usr/bin/gns3server --log /var/log/gns3/gns3.log \
     --pid /var/run/gns3/gns3.pid --daemon
Restart=on-abort
PIDFile=/var/run/gns3/gns3.pid

[Install]
WantedBy=multi-user.target
EOFI
chmod 755 /lib/systemd/system/gns3.service
chown root:root /lib/systemd/system/gns3.service

log "Start GNS3 service"
systemctl enable gns3
systemctl start gns3

log "GNS3 installed with success"

# Install and configure OpenVPN
if [ $USE_VPN == 1 ]
then
log "Setup VPN"

cat <<EOFSERVER > /etc/gns3/gns3_server.conf
[Server]
host = 172.16.253.1
port = 3080 
images_path = /opt/gns3/images
projects_path = /opt/gns3/projects
report_errors = True

[Qemu]
enable_kvm = True
EOFSERVER

log "Install packages for Open VPN"

apt-get install -y openvpn uuid dnsutils nginx-light

MY_IP_ADDR=$(dig @ns1.google.com -t txt o-o.myaddr.l.google.com +short | sed 's/"//g')

log "IP detected: $MY_IP_ADDR"

UUID=$(uuid)

log "Update motd"

cat <<EOFMOTD > /etc/update-motd.d/70-openvpn
#!/bin/sh
echo ""
echo "_______________________________________________________________________________________________"
echo "Download the VPN configuration here:"
echo "http://$MY_IP_ADDR:8003/$UUID/$HOSTNAME.ovpn"
echo ""
echo "And add it to your openvpn client."
echo ""
echo "apt-get remove nginx-light to disable the HTTP server."
echo "And remove this file with rm /etc/update-motd.d/70-openvpn"
EOFMOTD
chmod 755 /etc/update-motd.d/70-openvpn


mkdir -p /etc/openvpn/

[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

log "Create keys"

[ -f /etc/openvpn/dh.pem ] || openssl dhparam -out /etc/openvpn/dh.pem 2048
[ -f /etc/openvpn/key.pem ] || openssl genrsa -out /etc/openvpn/key.pem 2048
chmod 600 /etc/openvpn/key.pem
[ -f /etc/openvpn/csr.pem ] || openssl req -new -key /etc/openvpn/key.pem -out /etc/openvpn/csr.pem -subj /CN=OpenVPN/
[ -f /etc/openvpn/cert.pem ] || openssl x509 -req -in /etc/openvpn/csr.pem -out /etc/openvpn/cert.pem -signkey /etc/openvpn/key.pem -days 24855

log "Create client configuration"
cat <<EOFCLIENT > /root/client.ovpn
client
nobind
comp-lzo
dev tun
route 192.168.122.0 255.255.255.0
<key>
`cat /etc/openvpn/key.pem`
</key>
<cert>
`cat /etc/openvpn/cert.pem`
</cert>
<ca>
`cat /etc/openvpn/cert.pem`
</ca>
<dh>
`cat /etc/openvpn/dh.pem`
</dh>
<connection>
remote $MY_IP_ADDR 1194 udp
</connection>
EOFCLIENT

cat <<EOFUDP > /etc/openvpn/udp1194.conf
server 172.16.253.0 255.255.255.0
verb 3
duplicate-cn
comp-lzo
key key.pem
ca cert.pem
cert cert.pem
dh dh.pem
keepalive 10 60
persist-key
persist-tun
proto udp
port 1194
dev tun1194
status openvpn-status-1194.log
log-append /var/log/openvpn-udp1194.log
EOFUDP

echo "Setup HTTP server for serving client certificate"
mkdir -p /usr/share/nginx/openvpn/$UUID
cp /root/client.ovpn /usr/share/nginx/openvpn/$UUID/$HOSTNAME.ovpn
touch /usr/share/nginx/openvpn/$UUID/index.html
touch /usr/share/nginx/openvpn/index.html

cat <<EOFNGINX > /etc/nginx/sites-available/openvpn
server {
	listen 8003;
    root /usr/share/nginx/openvpn;
}
EOFNGINX

[ -f /etc/nginx/sites-enabled/openvpn ] || ln -s /etc/nginx/sites-available/openvpn /etc/nginx/sites-enabled/
service nginx stop
service nginx start

log "Restart OpenVPN"

set +e
service openvpn stop
service openvpn start

log "Download http://$MY_IP_ADDR:8003/$UUID/$HOSTNAME.ovpn to setup your OpenVPN client after rebooting the server"
fi

echo "1. Download an OpenVPN Client : " > ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please download an openvpn client for Windows : https://openvpn.net/index.php/open-source/downloads.html" >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please download an openvpn client for Mac OS x : https://tunnelblick.net/ " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo "2. Please download your OpenVPN configuration file : " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please download http://$MY_IP_ADDR:8003/$UUID/$HOSTNAME.ovpn to setup your OpenVPN client"  >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo "3. Download GNS3-GUI : " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please download and install GNS3-GUI for Windows : https://github.com/GNS3/gns3-gui/releases/download/v$(gns3server -v)/GNS3-$(gns3server -v)-all-in-one.exe " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please download and install GNS3-GUI for Mac OS X : https://github.com/GNS3/gns3-gui/releases/download/v$(gns3server -v)/GNS3-$(gns3server -v).dmg " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo "4. Download GNS3 aplliances : " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please Download Cisco IOSvL2 appliances : https://raw.githubusercontent.com/GNS3/gns3-registry/master/appliances/cisco-iosvl2.gns3a " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please Download Cisco IOS appliances : https://raw.githubusercontent.com/GNS3/gns3-registry/master/appliances/cisco-iosv.gns3a " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please Download Cisco 3725 appliances : https://raw.githubusercontent.com/GNS3/gns3-registry/master/appliances/cisco-3725.gns3a " >> ~/install-log.txt
echo " " >> ~/install-log.txt
echo " \* Please Download some other appliances : https://get.goffinet.org/gns3a/ " >> ~/install-log.txt
echo " " >> ~/install-log.txt

apt-get -y install at fail2ban
at tomorrow <<< 'apt-get -y remove nginx-light'
#shutdown -r now
