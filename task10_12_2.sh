#!/bin/bash
dir_pwd=$(dirname "$0")
dir_pwd=$(cd "$dir_pwd" && pwd)
source ${dir_pwd}/config
#---Install docker-ce
apt-get update
apt-get install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
apt-key fingerprint 0EBFCD88
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install docker-ce -y
#---Install docker compose
curl -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
#---Create DIRs and files
mkdir ${dir_pwd}/certs
mkdir ${dir_pwd}/etc
mkdir -p "$NGINX_LOG_DIR"
touch "$NGINX_LOG_DIR"/access.log
touch ${dir_pwd}/etc/nginx.conf
touch ${dir_pwd}/docker-compose.yml
#---Create certs
$(openssl genrsa -out ${dir_pwd}/certs/root.key 4096 > /dev/null)
$(openssl req -new -x509 -days 365 -key ${dir_pwd}/certs/root.key -out ${dir_pwd}/certs/root.crt -subj "/CN=root" > /dev/null)
$(openssl genrsa -out ${dir_pwd}/certs/web.key 4096 > /dev/null)
echo -e "[ req ]
default_bits = 4096
distinguished_name  = req_distinguished_name
req_extensions     = req_ext
[ req_distinguished_name ]
[ req_ext ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName          = IP:${EXTERNAL_IP},DNS:${HOST_NAME}" > ${dir_pwd}/conf.cnf
$(openssl req -new -key ${dir_pwd}/certs/web.key -config ${dir_pwd}/conf.cnf -reqexts req_ext -out ${dir_pwd}/certs/web.csr -subj "/CN=${HOST_NAME}" > /dev/null)
$(openssl x509 -req -days 365 -CA ${dir_pwd}/certs/root.crt -CAkey ${dir_pwd}/certs/root.key -set_serial 01 -extfile ${dir_pwd}/conf.cnf -extensions req_ext -in ${dir_pwd}/certs/web.csr -out ${dir_pwd}/certs/web.crt > /dev/null)
$(rm ${dir_pwd}/conf.cnf)
#---Create nginx config
cat << EOF > ${dir_pwd}/etc/nginx.conf 
server {
    listen    $NGINX_PORT ssl;
    ssl_prefer_server_ciphers  on;
    ssl_ciphers  'ECDH !aNULL !eNULL !SSLv2 !SSLv3';
    ssl_certificate  /etc/ssl/certs/web.crt;
    ssl_certificate_key  /etc/ssl/certs/web.key;

    location / {
        proxy_pass   http://web2;
    }
}
EOF
#--- Create docker-compose.yml
cat << EOF > ${dir_pwd}/docker-compose.yml
version: '2'
services:
  web:
    image: nginx:1.13
    ports:
     - $NGINX_PORT:443
    volumes:
     - ./certs:/etc/ssl/certs
     - ./etc/nginx.conf:/etc/nginx/conf.d/default.conf:ro
     - "$NGINX_LOG_DIR"/access.log:/var/log/nginx/access.log:rw
    container_name: nginx
  web2:
    image: httpd:2.4
    container_name: httpd
EOF
docker-compose up -d
