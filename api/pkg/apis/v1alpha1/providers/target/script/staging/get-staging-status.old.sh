#!/bin/bash

deployment=$1 # first parameter file is the deployment object
references=$2 # second parmeter file contains the reference components

# the apply script is called with a list of components to be updated via
# the references parameter
sleep 5

successsFlag=true
message=""
images=()

# Handle empty array case explicitly
if [ "${#images[@]}" -eq 0 ]; then
  images_json="[]"
else
  images_json=$(printf '%s\n' "${images[@]}" | jq -R . | jq -s .)
fi
 
# Now build the final JSON
json=$(jq -n \
  --argjson Success "$successsFlag" \
  --arg Message "$message" \
  --argjson Images "$images_json" \
  '{Success: $Success, Message: $Message, StagedImages: $Images}'
)
encoded=$(jq -cn --argjson obj "$json" '$obj | @json')

output_results=$(cat <<EOF
{
  "staging-status": {
    "status": 8004,
    "message": $encoded
  }
}
EOF
)

echo "$output_results"
echo "output file ${deployment%.*}-output.${deployment##*.}"
echo "$output_results" > ${deployment%.*}-output.${deployment##*.}