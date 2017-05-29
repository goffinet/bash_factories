#!/bin/bash

## 1. Set variables
SITE="blog1"
ZONE="example.com"
MAIL="root@example.com"
CF_TOKEN="your_api"
## Do not touch any others
CF_EMAIL=$MAIL
CF_ZONE=$ZONE
CF_NAME=$SITE
CF_API_URL="https://api.cloudflare.com/client/v4"
curl_command='curl'
ip_wan=$(curl -s ipinfo.io/ip)
tcp_port=$(shuf -i 8184-65000 -n 1)

## 2. Check root and distro
check_env () {
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi
if [ ! $(lsb_release -rs) == "16.04" ]; then
 echo "This script must be run on Ubuntu 16.04 Xenial" 1>&2  
 exit 1
fi
}

## 3. Update and upgrade the system
system_update () {
apt-get update && apt-get -y upgrade && apt-get -y dist-upgrade
}

## 4. Create an DNS entry to Cloudflare

set_dns () {
apt-get -y install curl  
## 2. Get Zone ID
zones=`${curl_command} -s -X GET "${CF_API_URL}/zones?name=${CF_ZONE}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_TOKEN}" -H "Content-Type: application/json"`
zone=$(echo "${zones}" | grep -Po '(?<="id":")[^"]*' | head -1)
## 3. Get Record ID et IP Address of hostanme
records=`${curl_command} -s -X GET "${CF_API_URL}/zones/${zone}/dns_records?type=A&name=${CF_NAME}.${CF_ZONE}&page=1&per_page=20&order=type&direction=desc&match=all" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_TOKEN}" -H "Content-Type: application/json"`
records_id=`echo "${records}" | grep -Po '(?<="id":")[^"]*'`
ip=`echo "${records}" | grep -Po '(?<="content":")[^"]*'`
## Check if Record exists
if [ "${ip}" == "${ip_wan}" ]; then
 echo "Noting to do"
fi
if [ ! "${ip}" == "${ip_wan}" ]; then
 echo "do update"
 ${curl_command} -s -X PUT "${CF_API_URL}/zones/${zone}/dns_records/${records_id}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_TOKEN}" -H "Content-Type: application/json" --data "{\"id\":\"${zone}\",\"type\":\"A\",\"name\":\"${CF_NAME}.${CF_ZONE}\",\"content\":\"${ip_wan}\"}"
fi
if [ -z "$records_id" ]; then
 echo "Please create the record ${CF_NAME}.${CF_ZONE}"
 ${curl_command} -s -X POST "${CF_API_URL}/zones/${zone}/dns_records" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_TOKEN}" -H "Content-Type: application/json" --data "{\"id\":\"${zone}\",\"type\":\"A\",\"name\":\"${CF_NAME}.${CF_ZONE}\",\"content\":\"${ip_wan}\"}"
fi
}

## 5. Get and install Node.js
set_nodejs () {
curl -sL https://deb.nodesource.com/setup_4.x | sudo bash -
apt-get install -y nodejs
}

## 6. Get and Install Ghost Software
set_ghost () {
cd ~
wget https://ghost.org/zip/ghost-latest.zip
mkdir /var/www
apt-get install unzip
unzip -d /var/www/$SITE ghost-latest.zip
cd /var/www/$SITE
npm install --production
cp config.example.js config.js
sed -i s/my-ghost-blog.com/${SITE}.${ZONE}/ config.js
sed -i s/2368/${tcp_port}/ config.js
adduser --shell /bin/bash --gecos 'Ghost application' ghost --disabled-password
chown -R ghost:ghost /var/www/$SITE
cat << EOF > /etc/systemd/system/$SITE.service
[Unit]
Description="Ghost $SITE"
After=network.target

[Service]
Type=simple

WorkingDirectory=/var/www/$SITE
User=ghost
Group=ghost

ExecStart=/usr/bin/npm start --production
ExecStop=/usr/bin/npm stop --production
Restart=always
SyslogIdentifier=Ghost

[Install]
WantedBy=multi-user.target
EOF
systemctl enable $SITE.service
systemctl start $SITE.service
rm ~/ghost-latest.zip
}

## 7. Get and install Nginx
set_nginx () {
apt-get install -y nginx
systemctl enable nginx
rm /etc/nginx/sites-enabled/default
if [ ! -f /etc/ssl/certs/dhparam.pem ]; then
openssl dhparam  -dsaparam -out /etc/ssl/certs/dhparam.pem 2048
fi
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
cat << EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
	worker_connections 768;
	# multi_accept on;
}

http {

	##
	# Basic Settings
	##

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	server_tokens off;

	server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	##
	# SSL Settings
	##

  # from https://cipherli.st/
  # and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html

  # Only the TLS protocol family
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_prefer_server_ciphers on;
  # This will block IE6, Android 2.3 and older Java version from accessing your site, but these are the safest settings.
  ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
  # ECDH key exchange prevents all known feasible cryptanalytic attacks
  ssl_ecdh_curve secp384r1;
  # 20MB of cache will host about 80000 sessions
  ssl_session_cache shared:SSL:20m;
  # Session expires every 3 hours
  ssl_session_timeout 180m;
  ssl_session_tickets off;
  ssl_stapling on;
  ssl_stapling_verify on;
  # OCSP stapling using Google public DNS servers
  resolver 8.8.8.8 8.8.4.4 valid=300s;
  resolver_timeout 5s;
  add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;

  ssl_dhparam /etc/ssl/certs/dhparam.pem;

	##
	# Logging Settings
	##

	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;

	##
	# Gzip Settings
	##

	gzip on;
	gzip_disable "msie6";

	# gzip_vary on;
	# gzip_proxied any;
	# gzip_comp_level 6;
	# gzip_buffers 16 8k;
	# gzip_http_version 1.1;
	# gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

	##
	# Virtual Host Configs
	##

	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}


#mail {
#	# See sample authentication script at:
#	# http://wiki.nginx.org/ImapAuthenticateWithApachePhpScript
#
#	# auth_http localhost/auth.php;
#	# pop3_capabilities "TOP" "USER";
#	# imap_capabilities "IMAP4rev1" "UIDPLUS";
#
#	server {
#		listen     localhost:110;
#		protocol   pop3;
#		proxy      on;
#	}
#
#	server {
#		listen     localhost:143;
#		protocol   imap;
#		proxy      on;
#	}
#}
EOF
cat << EOF > /etc/nginx/sites-available/$SITE
server {
    listen 80;
    server_name ${SITE}.${ZONE};

    location ~ ^/.well-known {
        root /var/www/$SITE;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
ln -s /etc/nginx/sites-available/$SITE /etc/nginx/sites-enabled/$SITE
systemctl stop nginx ; systemctl start nginx
}

## 8. Get and install Letsencrypt
set_letsencrypt () {
apt-get -y install letsencrypt
letsencrypt certonly -a webroot --webroot-path=/var/www/$SITE/ -d ${SITE}.${ZONE} -m $MAIL --agree-tos
cat << EOF > /etc/nginx/sites-available/$SITE
server {
        listen 80;

        server_name ${SITE}.${ZONE};

        location ~ ^/.well-known {
            root /var/www/$SITE;
        }

        location / {
            return 301 https://\$server_name\$request_uri;
        }
}

server {
        listen 443 ssl;

        server_name ${SITE}.${ZONE};

        location / {
                proxy_pass http://localhost:${tcp_port};
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header Host \$http_host;
                proxy_set_header X-Forwarded-Proto \$scheme;
                proxy_buffering off;
                proxy_redirect off;
        }

        ssl on;
        ssl_certificate /etc/letsencrypt/live/${SITE}.${ZONE}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${SITE}.${ZONE}/privkey.pem;

        ssl_prefer_server_ciphers On;
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS;

}
EOF
cat << EOF > /etc/cron.d/le-renew
30 2 * * 1 /usr/bin/letsencrypt renew >> /var/log/le-renew.log
35 2 * * 1 /bin/systemctl reload nginx
EOF
systemctl stop nginx ; systemctl start nginx
cd /var/www/$SITE
sed -i s/http/https/ config.js
chown -R ghost:ghost /var/www/$SITE
systemctl stop $SITE.service ; systemctl start $SITE.service
}

## 9. Set Firewalld and Fail2ban
set_firewall () {
apt-get install -y firewalld
systemctl enable firewalld
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-interface=eth0
firewall-cmd --reload
firewall-cmd --permanent --zone=public --list-all
apt-get install -y fail2ban
systemctl enable fail2ban
}

## 10. Upload some themes

upload_themes () {
apt-get install -y git
cd content/themes
git clone https://github.com/boh717/beautiful-ghost.git beautifulghost
chown -R ghost:ghost beautifulghost
git clone https://github.com/Dennis-Mayk/Practice.git Practice
chown -R ghost:ghost Practice
git clone https://github.com/andreborud/penguin-theme-dark.git penguin-theme-dark
chown -R ghost:ghost penguin-theme-dark
git clone https://github.com/daanbeverdam/buster.git buster
chown -R ghost:ghost buster
git clone https://github.com/godofredoninja/Mapache.git Mapache
chown -R ghost:ghost Mapache
git clone https://github.com/haydenbleasel/ghost-themes.git Phantom
chown -R ghost:ghost Phantom
git clone https://github.com/kagaim/Chopstick.git Chopstick
chown -R ghost:ghost Chopstick
git clone https://github.com/GavickPro/Perfetta-Free-Ghost-Theme.git Perfetta
chown -R ghost:ghost Perfetta
systemctl stop $SITE.service ; systemctl start $SITE.service
}

check_env
system_update
set_dns
set_nodejs
set_ghost
set_nginx
set_letsencrypt
set_firewall
upload_themes
