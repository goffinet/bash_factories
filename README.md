# Various Bash Scripts

Various Bash Scripts for proof of concept deployments


Checks 

* parameters --> usage
* distribution release

## Requirements

* `curl`
* `wget`
* `ssmtp` working config
* scaleway token
* cloudflare token

## Scripts

* `simple_scw_install.sh` : script to launch multiples instances at time with scw cli (scaleway)
* `ghost-nginx-letsencrypt-cloudflare_installation.sh` : script to automate ghost blog in htts (LetsEncrypt) and Cloudflare DNS entry creation via API 
* `install_remote_gns3server.sh` : remote GNS3server installation with openvpn config

## In preparation

* Apache2.4 source installation
* Apache2 Vhosts automation
* Snort IDS with emerging rules
