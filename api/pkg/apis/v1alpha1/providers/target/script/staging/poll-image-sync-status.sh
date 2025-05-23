#!/bin/bash
##
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.
## SPDX-License-Identifier: MIT
##

deployment=$1 # first parameter file is the deployment object
references=$2 # second parmeter file contains the reference components

echo "$references"
image_list=($(echo "$references" | jq -r '.properties.imageList[]'))
echo "Image list: ${image_list[@]}"

# move file to the CR pod and grant execute permission
kubectl cp check-acr-images.sh connected-registry/jdconnected2-54fc99d484-xjsfr:/tmp/
kubectl exec -it jdconnected2-54fc99d484-xjsfr  -n connected-registry  -- chmod +x /tmp/check-acr-images.sh

kubectl exec -it  jdconnected2-54fc99d484-xjsfr  -n connected-registry -- /bin/bash -c "/tmp/check-acr-images.sh cbl-mariner/base/prometheus:2.37"

output_components=$(jq -r '[.[] | .component]' "$references")
echo "$output_components" > ${deployment%.*}-get-output.${deployment##*.}