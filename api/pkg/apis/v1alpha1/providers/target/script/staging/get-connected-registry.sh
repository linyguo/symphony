#!/bin/bash

deployment=$1 # first parameter file is the deployment object
references=$2 # second parmeter file contains the reference components

# install kubectl
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# get connected registry extension name and namespace
connectedRegistryNameNS=$(kubectl get ExtensionConfig -A -o json \
  | jq -r '.items[] | select(.spec.extensionType == "microsoft.containerregistry.connectedregistry") | "\(.metadata.name) \(.metadata.namespace)"')

connectedRegistryName=$(echo $connectedRegistryNameNS | awk '{print $1}')
connectedRegistryNamespace=$(echo $connectedRegistryNameNS | awk '{print $2}')

if [ -z "$connectedRegistryName" ] || [ -z "$connectedRegistryNamespace" ]; then
  echo "No connected registry found"
  exit 1
fi

# get connected registry helm chart values
connectedRegistryHelmChartValues=$(helm get values $connectedRegistryName -n $connectedRegistryNamespace -o json)
serviceIp=$(echo $connectedRegistryHelmChartValues | jq -r '.service.clusterIP')
connectionString=$(echo $connectedRegistryHelmChartValues | jq -r '.connectionString')

if [ -z "$serviceIp" ] || [ -z "$connectionString" ]; then
  echo "Service IP or connection string not found"
  exit 1
fi

# parse the connection string
IFS=';' read -r connectedRegistryName syncTokenName syncTokenPassword parentGatewayEndpoint parentEndpointProtocol <<< "$connectionString"
if [ -z "$connectedRegistryName" ] || [ -z "$syncTokenName" ] || [ -z "$syncTokenPassword" ] || [ -z "$parentGatewayEndpoint" ] || [ -z "$parentEndpointProtocol" ]; then
  echo "Connection string not parsed correctly"
  exit 1
fi

# get connected registry name
connectedRegistryName=$(echo $connectedRegistryName | cut -d '=' -f 2)
acrName=$(echo $parentGatewayEndpoint | cut -d '.' -f 1 | cut -d "=" -f 2)

if [ -z "$connectedRegistryName" ] || [ -z "$acrName" ]; then
  echo "Connected registry name or ACR name not found"
  exit 1
fi

echo "Found connected registry:"
echo "Connected registry name: $connectedRegistryName"
echo "ACR name: $acrName"
echo "Service IP: $serviceIp"

messageContent="{\\\"RegistryName\\\": \\\"$acrName\\\", \\\"ConnectedRegistryName\\\": \\\"$connectedRegistryName\\\", \\\"ServiceIp\\\": \\\"$serviceIp\\\"}"
# messageContent="succeeded to get connected registry: $connectedRegistryName, ACR name: $acrName, Service IP: $serviceIp"
output_results=$(cat <<EOF
{
  "connection-string": {
    "status": 8004,
    "message": "$messageContent"
  }
}
EOF
)

echo "$output_results"
echo "output file ${deployment%.*}-output.${deployment##*.}"
echo "$output_results" > ${deployment%.*}-output.${deployment##*.}