#!/bin/bash

deployment=$1 # first parameter file is the deployment object
references=$2 # second parmeter file contains the reference components

# the apply script is called with a list of components to be updated via
# the references parameter
sleep 5

successsFlag=true
message=""
images="[]"

messageContent="{\\\"Success\\\": \\\"$successsFlag\\\", \\\"Message\\\": \\\"$message\\\", \\\"StagedImages\\\": \\\"$images\\\"}"
output_results=$(cat <<EOF
{
  "staging-status": {
    "status": 8004,
    "message": "$messageContent"
  }
}
EOF
)

echo "$output_results"
echo "output file ${deployment%.*}-output.${deployment##*.}"
echo "$output_results" > ${deployment%.*}-output.${deployment##*.}