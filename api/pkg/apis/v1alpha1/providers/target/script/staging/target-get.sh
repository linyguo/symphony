#!/bin/bash
##
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.
## SPDX-License-Identifier: MIT
##

deployment=$1 # first parameter file is the deployment object
references=$2 # second parmeter file contains the reference components

output_components=$(jq -r '[]' "$references")
echo "$output_components" > ${deployment%.*}-get-output.${deployment##*.}