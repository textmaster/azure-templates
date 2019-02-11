# Install an Elasticsearch cluster on Virtual Machines

[![deploybutton](http://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftextmaster%2Fazure-templates%2Fmaster%2Felasticsearch%2Fazuredeploy.json)

This template deploys Virtual Machines, Managed Disks, Virtual Network, Availability Sets, Public IP addresses, a Load Balancer, and Network Interfaces.

# Deployment

`./run.sh LOCAL_TEMPLATE_NAME ENVIRONMENT_NAME [RESOURCE_GROUP_NAME]`

Useful cli commands:
* List available vm sizes: `az vm list-sizes --location 'West Europe'`
* Delete a group: `azure group delete NAME`
