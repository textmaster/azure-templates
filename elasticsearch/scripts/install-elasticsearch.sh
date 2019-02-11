#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
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
# Customised by Krzysztof Knapik @ Textmaster
#
help()
{
    echo "This script installs Elasticsearch node on Ubuntu"
    echo "Parameters:"
    echo "-d static discovery hosts 10.0.0.1-3"
    echo "-n elasticsearch cluster name"
    echo "-v elasticsearch version"
    echo "-l loggly customer token"
    echo "-h view this help content"
}

log()
{
  if [ -n "${LOGGLY_TOKEN}" ]; then
    curl -H "content-type:text/plain" -d "[${HOSTNAME}][install-elasticsearch] - $1" "http://logs-01.loggly.com/bulk/${LOGGLY_TOKEN}/tag/bulk/"
  fi
  echo "$1"
  echo " | "
}

log "Begin execution of install-elasticsearch script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ]; then
  log "Script executed without root permissions"
  echo "You must be root to run this program." >&2
  exit 3
fi

export DEBIAN_FRONTEND=noninteractive
# Script Parameters
CLUSTER_NAME="elasticsearch"
ES_VERSION="1.7.6"
DISCOVERY_HOSTS=""
LOGGLY_TOKEN=""

# Loop through options passed
while getopts :d:n:v:l:h optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    d) # static discovery endpoints
      DISCOVERY_HOSTS=${OPTARG}
      ;;
    n) # set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    v) # elasticsearch version number
      ES_VERSION=${OPTARG}
      ;;
    l) # set loggly account id
      LOGGLY_TOKEN=${OPTARG}
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

# Expand a list of successive ip range and filter my local local ip from the list
# Ip list is represented as a prefix and that is appended with a 1 to N index
# 10.0.0.1-3 would be converted to "10.0.0.11 10.0.0.12 10.0.0.13"
expand_ip_range() {
  IFS='-' read -a HOST_IPS <<< "$1"

  # Get the IP Addresses on this machine
  declare -a MY_IPS=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
  declare -a EXPAND_STATICIP_RANGE_RESULTS=()
  declare -a IP_COUNT=("${HOST_IPS[1]}"+1)
  for (( n=1; n<IP_COUNT; n++))
  do
    HOST="${HOST_IPS[0]}${n}"
    if ! [[ "${MY_IPS[@]}" =~ "${HOST}" ]]; then
      EXPAND_STATICIP_RANGE_RESULTS+=($HOST)
    fi
  done

  echo "${EXPAND_STATICIP_RANGE_RESULTS[@]}"
}

# Install Oracle Java
install_java()
{
  log "Installing Java"
  add-apt-repository -y ppa:webupd8team/java
  DEBIAN_FRONTEND=noninteractive apt-get -y -qq update
  echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
  echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends oracle-java8-installer
}

# Install Elasticsearch
install_es()
{
  log "Installing Elasticsearch Version - $ES_VERSION"
  if [[ "${ES_VERSION}" == \6* ]]; then
    DOWNLOAD_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ES_VERSION.deb"
  else
    DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-$ES_VERSION.deb"
  fi

  log "Download location - $DOWNLOAD_URL"
  wget -q "$DOWNLOAD_URL" -O /tmp/elasticsearch.deb
  dpkg -i /tmp/elasticsearch.deb

  log "Creating elasticsearch dirs and changing permissions"
  mkdir -p /usr/share/elasticsearch/logs
  mkdir -p /var/log/elasticsearch
  mkdir -p /etc/elasticsearch
  mkdir -p /data/elasticsearch

  if [[ "${ES_VERSION}" == \6* ]]; then
    # download some hunspell dictionaries
    # fr
    mkdir -p /etc/elasticsearch/hunspell/fr_FR
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/fr_FR/fr_FR.aff > /etc/elasticsearch/hunspell/fr_FR/fr_FR.aff
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/fr_FR/fr_FR.dic > /etc/elasticsearch/hunspell/fr_FR/fr_FR.dic
    # en
    mkdir -p /etc/elasticsearch/hunspell/en_US
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/en_US/en_US.aff > /etc/elasticsearch/hunspell/en_US/en_US.aff
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/en_US/en_US.dic > /etc/elasticsearch/hunspell/en_US/en_US.dic
    # it
    mkdir -p /etc/elasticsearch/hunspell/it_IT
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/it_IT/it_IT.aff > /etc/elasticsearch/hunspell/it_IT/it_IT.aff
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/it_IT/it_IT.dic > /etc/elasticsearch/hunspell/it_IT/it_IT.dic
    # es
    mkdir -p /etc/elasticsearch/hunspell/es_ES
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/es_ES/es_ES.aff > /etc/elasticsearch/hunspell/es_ES/es_ES.aff
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/es_ES/es_ES.dic > /etc/elasticsearch/hunspell/es_ES/es_ES.dic
    # nl
    mkdir -p /etc/elasticsearch/hunspell/nl_NL
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/nl_NL/nl_NL.aff > /etc/elasticsearch/hunspell/nl_NL/nl_NL.aff
    curl https://raw.githubusercontent.com/textmaster/azure-templates/master/elasticsearch/data/hunspell/nl_NL/nl_NL.dic > /etc/elasticsearch/hunspell/nl_NL/nl_NL.dic
    # end download some hunspell dictionaries
  fi

  chown -R elasticsearch:elasticsearch /usr/share/elasticsearch
  chown -R elasticsearch:elasticsearch /var/log/elasticsearch
  chown -R elasticsearch:elasticsearch /etc/elasticsearch
  chown -R elasticsearch:elasticsearch /etc/init.d/elasticsearch
  chown -R elasticsearch:elasticsearch /data/elasticsearch

  chmod 775 /usr/share/elasticsearch
  chmod 775 /var/log/elasticsearch
  chmod 775 /etc/elasticsearch
  chmod 775 /data/elasticsearch
  chmod +rx /etc/init.d/elasticsearch

}

install_packages()
{
  log "Installing apt packages"
  DEBIAN_FRONTEND=noninteractive apt-get -y -qq update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends monit
}

install_java
install_packages
install_es

# Set ENV vars
log "Setting env vars"
echo "LC_ALL=en_US.UTF-8" >> /etc/environment
echo "LANG=en_US.UTF-8" >> /etc/environment

S=$(expand_ip_range "$DISCOVERY_HOSTS")
HOSTS_CONFIG="[\"${S// /\",\"}\"]"
log "Hosts config: ${HOSTS_CONFIG}"

#Configure Elasticsearch settings
#---------------------------
#Backup the current Elasticsearch configuration file
mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak

# Set cluster and machine names - just use hostname for our node.name
echo "cluster.name: $CLUSTER_NAME" >> /etc/elasticsearch/elasticsearch.yml
echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml

# Configure data path
log "Update configuration for data path"
echo "path.data: /data/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml

# Configure discovery
log "Update configuration with hosts configuration of $HOSTS_CONFIG"

if [[ "${ES_VERSION}" == \1* ]]; then
  echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
fi

echo "discovery.zen.ping.unicast.hosts: $HOSTS_CONFIG" >> /etc/elasticsearch/elasticsearch.yml

# Configure Elasticsearch node type
log "Configure node as master & data"
echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml

echo "discovery.zen.minimum_master_nodes: 2" >> /etc/elasticsearch/elasticsearch.yml

if [[ "${ES_VERSION}" == \6* ]]; then
  echo "network.host: _site_" >> /etc/elasticsearch/elasticsearch.yml
fi

# DNS Retry
echo "options timeout:1 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
resolvconf -u

# Increase maximum mmap count
echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

# Set ES_HEAP_SIZE - max 31g
ES_HEAP=`free -m | grep Mem | awk '{if ($2/2 >31744) print 31744; else print $2*0.6;}'`
ES_HEAP=`printf "%.0f" $ES_HEAP` # round value
log "Configure elasticsearch heap size - $ES_HEAP"
echo "ES_HEAP_SIZE=${ES_HEAP}m" >> /etc/default/elasticsearch

# Install kopf/plugins
if [[ "${ES_VERSION}" == \2* ]]; then
  log "Installing Kopf Plugin for 2.x"
  /usr/share/elasticsearch/bin/plugin install lmenezes/elasticsearch-kopf/2.0
elif [[ "${ES_VERSION}" == \1* ]]; then
  log "Installing Kopf Plugin for 1.x"
  /usr/share/elasticsearch/bin/plugin install lmenezes/elasticsearch-kopf/1.0
else
  log "Installing analysis-stempel Plugin for 6.x"
  /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch analysis-stempel
fi

# Configure monit
cat <<EOT > /etc/monit/conf.d/elasticsearch
check process elasticsearch with pidfile /var/run/elasticsearch/elasticsearch.pid
   start program = "/etc/init.d/elasticsearch start"
   stop  program = "/etc/init.d/elasticsearch stop"
   if 10 restarts within 20 cycles then timeout
   if failed host 127.0.0.1 port 9200 protocol http then restart
EOT

# Start the service
log "Starting Elasticsearch on ${HOSTNAME}"
update-rc.d elasticsearch defaults 95 10
service monit reload
service elasticsearch stop
service elasticsearch start
log "Completed Elasticsearch setup"
exit 0

