#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2019 TextMaster
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subjfect to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Author: Krzysztof Knapik
#

help()
{
    echo "This script installs Haproxy for Elasticsearch cluster on Ubuntu"
    echo "Parameters:"
    echo "-a System Username"
    echo "-b Private ssh key"
    echo "-h View this help content"
    echo "-b Label prefix"
    echo "-i VM index"
    echo "-l Loggly account id"
    echo "-p Public port number"
    echo "-s SSL certificate"
    echo "-u Basic auth user"
    echo "-w Basic auth backend password"
    echo "-x Basic auth stats password"
}

log()
{
  if [ -n "${LOGGLY_ACCOUNT_ID}" ]; then
    curl -H "content-type:text/plain" -d "[${HOSTNAME}][install-haproxy] - $1" "http://logs-01.loggly.com/bulk/${LOGGLY_ACCOUNT_ID}/tag/bulk/"
  fi
  echo "$1"
  echo " | "
}

log "Begin execution of install-haproxy script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ]; then
  log "Script executed without root permissions"
  echo "You must be root to run this program." >&2
  exit 3
fi

export DEBIAN_FRONTEND=noninteractive

# Script Parameters
VM_INDEX=1
SSL_CERT=""
LOGGLY_ACCOUNT_ID=""
PUBLIC_PORT="9200"
AUTH_USER="user1"
BACKEND_PASSWORD="password1"
STATS_PASSWORD="password1"
CLUSTER_NAME="es-cluster"
PRIVATE_SSH_KEY=""
SYSTEM_USER=""

# Loop through options passed
while getopts :a:b:i:l:n:p:s:u:w:x: optname; do
  log "Option $optname set"
  case $optname in
    a) # set private ssh key
      SYSTEM_USER=${OPTARG}
      ;;
    b) # set user name
      PRIVATE_SSH_KEY=${OPTARG}
      ;;
    i) # set vm count
      VM_INDEX=${OPTARG}
      ;;
    l) # set loggly account id
      LOGGLY_ACCOUNT_ID=${OPTARG}
      ;;
    n) # set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    p) # set public port
      PUBLIC_PORT=${OPTARG}
      ;;
    s) # set ssl cert
      SSL_CERT=${OPTARG}
      ;;
    u) # set user
      AUTH_USER=${OPTARG}
      ;;
    w) # set backend password
      BACKEND_PASSWORD=${OPTARG}
      ;;
    x) # set stats password
      STATS_PASSWORD=${OPTARG}
      ;;
    h) # show help
      help
      exit 2
      ;;
    \?) # unrecognized option - show help
      log "Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

log "VM_INDEX: ${VM_INDEX}"
log "PUBLIC_PORT: ${PUBLIC_PORT}"
log "CLUSTER_NAME: ${CLUSTER_NAME}"
log "SYSTEM_USER: ${SYSTEM_USER}"

# Install packages
log "Installing apt packages"
DEBIAN_FRONTEND=noninteractive apt-get -y -qq update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends haproxy monit openssl whois

BACKEND_PASSWORD_SHA=$(mkpasswd -m sha-512 -s $BACKEND_PASSWORD)

# Set ENV vars
log "Setting env vars"
echo "LC_ALL=en_US.UTF-8" >> /etc/environment
echo "LANG=en_US.UTF-8" >> /etc/environment

# Save SSL cert
log "Saving SSL cert to /etc/ssl/private/cert.pem"
echo -en "${SSL_CERT}" > /etc/ssl/private/cert.pem

# Configure haproxy
log "Configuring haproxy"
cat <<EOT > /etc/haproxy/haproxy.cfg
global
  log /dev/log  local0
  log /dev/log  local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin
  stats timeout 30s
  user haproxy
  group haproxy
  daemon

  # Default SSL material locations
  ca-base /etc/ssl/certs
  crt-base /etc/ssl/private

  # Default ciphers to use on SSL-enabled listening sockets.
  # For more information, see ciphers(1SSL). This list is from:
  #  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
  ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS
  ssl-default-bind-options no-sslv3

defaults
  log global
  mode  http
  option  httplog
  option  dontlognull
  timeout connect 5m
  timeout client  1d
  timeout server  1d
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http
  errorfile 502 /etc/haproxy/errors/502.http
  errorfile 503 /etc/haproxy/errors/503.http
  errorfile 504 /etc/haproxy/errors/504.http

userlist UsersFor_EsCluster
  user ${AUTH_USER} insecure-password ${BACKEND_PASSWORD}

frontend esgateway
  bind *:10200 ssl crt /etc/ssl/private/cert.pem
  default_backend esbackend_secured

backend esbackend_secured
  server esbackend 10.0.0.100:9200
  stats enable
  stats hide-version
  stats realm Haproxy\ Statistics
  stats uri /haproxy_stats
  stats auth ${AUTH_USER}:${STATS_PASSWORD}
  acl AuthOk_EsCluster http_auth(UsersFor_EsCluster)
  http-request auth realm EsCluster if !AuthOk_EsCluster
EOT

# Configure monit
log "Configuring monit"
cat <<EOT > /etc/monit/conf.d/haproxy
check process haproxy with pidfile /var/run/haproxy.pid
   start program = "/etc/init.d/haproxy start"
   stop  program = "/etc/init.d/haproxy stop"
   if 5 restarts within 5 cycles then timeout
   if failed host 127.0.0.1 port ${PUBLIC_PORT} protocol https then restart
EOT

# ssh
log "Configuring local ssh"
mkdir -p "/home/${SYSTEM_USER}/.ssh"
touch "/home/${SYSTEM_USER}/.ssh/config"
echo -en "${PRIVATE_SSH_KEY}" > "/home/${SYSTEM_USER}/.ssh/id_rsa"
chown -R ${SYSTEM_USER}:${SYSTEM_USER} "/home/${SYSTEM_USER}/.ssh"
chmod 600 "/home/${SYSTEM_USER}/.ssh/id_rsa"

cat <<EOT > "/home/${SYSTEM_USER}/.ssh/config"
Host node1
 HostName 10.0.0.11
 Port 22
 User ${SYSTEM_USER}
Host node2
 HostName 10.0.0.12
 Port 22
 User ${SYSTEM_USER}
Host node3
 HostName 10.0.0.13
 Port 22
 User ${SYSTEM_USER}
Host node4
 HostName 10.0.0.14
 Port 22
 User ${SYSTEM_USER}
Host node5
 HostName 10.0.0.15
 Port 22
 User ${SYSTEM_USER}
EOT

# Start the service
log "Starting haproxy on ${HOSTNAME}"
update-rc.d haproxy defaults 95 10
service monit reload
log "Completed"
exit 0
