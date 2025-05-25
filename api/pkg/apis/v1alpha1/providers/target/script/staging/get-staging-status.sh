#!/bin/bash
##
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.
## SPDX-License-Identifier: MIT
##

deployment=$1 # first parameter file is the deployment object
references=$2 # second parameter file contains the reference components

cp "$deployment" /tmp/deployment.json
cp "$references" /tmp/references.json
# read the deployment and references files
deployment_content=$(cat $deployment)
references_content=$(cat $references)

check_acr_script="check-acr-images.sh"

generate_check_acr_script() {
  # generate the script to check ACR images
# Define the name of the script to be generated

# Use a "here document" to define the content of the script.
# Note the 'EOF' delimiter. It can be any string, but EOF is common.
# Using 'EOF' (with single quotes) prevents variable expansion and command substitution
# within the here document by the parent script, ensuring the content is written literally.
# This is crucial because variables like $ACR_BASE, $REPO_PATH, etc., are meant to be
# interpreted when the generated script (check-acr-images.sh) itself runs.
local generated_script_name=$1

cat > "$generated_script_name" << 'EOF'
#!/bin/bash

# === CONFIGURATION ===
ACR_BASE="/var/acr/data/storage"

# === FUNCTIONS ===

# Auto-detect the dynamic ACR hash folder and set ACR_STORAGE_ROOT
detect_acr_root() {
  HASH_FOLDER=$(find "$ACR_BASE" -maxdepth 1 -type d ! -path "$ACR_BASE" | head -n 1)
  if [ -z "$HASH_FOLDER" ]; then
    echo "Could not find hash folder under $ACR_BASE"
    exit 1
  fi
  ACR_STORAGE_ROOT="$HASH_FOLDER/v2"
}

# Parse repository and tag from "repo:tag"
parse_repo_tag() {
  IFS=':' read -r REPO_PATH TAG <<< "$1"
  if [ -z "$REPO_PATH" ] || [ -z "$TAG" ]; then
    echo "Invalid image format: '$1'. Expected format is <repo>:<tag>"
    return 1
  fi
  return 0
}

# Check whether the manifest and layers for a given repo:tag are fully present
check_image() {
  local REPO_PATH="$1"
  local TAG="$2"
  local TAG_PATH="$ACR_STORAGE_ROOT/repositories/$REPO_PATH/_manifests/tags/$TAG"
  local LINK_FILE="$TAG_PATH/current/link"

  echo ""
  echo "Checking image '$REPO_PATH:$TAG'..."

  if [ ! -f "$LINK_FILE" ]; then
    echo "Tag '$TAG' does not exist in repository '$REPO_PATH'"
    return
  fi

  MANIFEST_DIGEST=$(sed 's/^sha256://' "$LINK_FILE")
  if [ -z "$MANIFEST_DIGEST" ]; then
    echo "Failed to read manifest digest from $LINK_FILE"
    return
  fi

  MANIFEST_BLOB_PATH="$ACR_STORAGE_ROOT/blobs/sha256/${MANIFEST_DIGEST:0:2}/$MANIFEST_DIGEST/data"
  if [ ! -f "$MANIFEST_BLOB_PATH" ]; then
    echo "Manifest blob missing: $MANIFEST_BLOB_PATH"
    return
  fi

  echo "Manifest found: sha256:$MANIFEST_DIGEST"
  echo "Checking layer blobs..."

  LAYER_DIGESTS=$(grep -o '"digest": *"sha256:[a-f0-9]\{64\}"' "$MANIFEST_BLOB_PATH" | sed 's/.*"sha256:\([a-f0-9]\{64\}\)".*/\1/')

  if [ -z "$LAYER_DIGESTS" ]; then
    echo "No layers found in manifest (or invalid format)"
    return
  fi

  ALL_LAYERS_PRESENT=true

  while IFS= read -r layer_hash; do
    LAYER_BLOB_PATH="$ACR_STORAGE_ROOT/blobs/sha256/${layer_hash:0:2}/$layer_hash/data"
    if [ -f "$LAYER_BLOB_PATH" ]; then
      echo "Layer present: sha256:$layer_hash"
    else
      echo "Layer missing: sha256:$layer_hash"
      ALL_LAYERS_PRESENT=false
    fi
  done <<< "$LAYER_DIGESTS"

  if $ALL_LAYERS_PRESENT; then
    echo "All blobs present. Image '$REPO_PATH:$TAG' is fully downloaded."
  else
    echo "Some blobs missing. Image '$REPO_PATH:$TAG' is incomplete."
  fi
}

# === MAIN ===

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <repo1:tag1> [<repo2:tag2> ...]"
  exit 1
fi

detect_acr_root

# Loop through all provided images, return all images that are fully downloaded
for IMAGE in "$@"; do
  parse_repo_tag "$IMAGE" || continue
  check_image "$REPO_PATH" "$TAG"
done
EOF

# Make the generated script executable
chmod +x "$generated_script_name"
}

generate_output_json() {
  local success="$1"
  local message="$2"
  local staged_images="$3"

  # Now build the final JSON
  json=$(jq -n \
    --argjson Success "$success" \
    --arg Message "$message" \
    --argjson StagedImages "$staged_images" \
    '{Success: $Success, Message: $Message, StagedImages: $StagedImages}'
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
}

# ----------------------------- MAIN SCRIPT -----------------------------
echo "$references_content"
if 

# if check_acr_script doesn't exist
[ ! -f "$check_acr_script" ]; then
  echo "Check ACR script not found. Generating..."
  generate_check_acr_script "$check_acr_script"
else
  regenerate_check_acr_script=$(echo "$references_content" | jq -r '.[0].properties.regenerateCheckAcrScript' )
  if [ "$regenerate_check_acr_script" == "true" ]; then
    echo "Regenerating the check ACR script..."
    generate_check_acr_script "$check_acr_script"
  else
    echo "Using existing check ACR script."
    chmod +x "$check_acr_script"
  fi
fi

mapfile -t image_list < <(echo "$references_content" | jq -r ".[].properties.imageList[]")
echo "Image list: ${image_list[@]}"

if [ -z "$image_list" ]; then
  echo "No images found in the references file."
  generate_output_json true "No images requested." "[]"
  exit 0 # ignore error and exit with success
fi

# convert the image list to a format suitable for the script
image_args=()
for image in "${image_list[@]}"; do
  # Check if the image is in the format repo:tag or repo@digest
  if [[ "$image" =~ ^[^:]+:[^:]+$ ]] || [[ "$image" =~ ^[^@]+@sha256:[a-f0-9]{64}$ ]]; then
    image_args+=("$image")
  else
    echo "Skipping invalid image format: $image"
  fi
done

if [ ${#image_args[@]} -eq 0 ]; then
  echo "No valid images found in the references file."
  generate_output_json false "No valid images found." "[]"
  exit 0 # ignore error and exit with success
fi

echo "Valid images to check: count: ${#image_args[@]}"

# convert image_args to a string for passing to the script
image_args_string=$(printf "%s " "${image_args[@]}")
echo "Image arguments for the script: $image_args_string"

# get connected registry extension name and namespace
connectedRegistryNameNS=$(kubectl get ExtensionConfig -A -o json \
  | jq -r '.items[] | select(.spec.extensionType == "microsoft.containerregistry.connectedregistry") | "\(.metadata.name) \(.metadata.namespace)"')

connectedRegistryName=$(echo $connectedRegistryNameNS | awk '{print $1}')
connectedRegistryNamespace=$(echo $connectedRegistryNameNS | awk '{print $2}')

if [ -z "$connectedRegistryName" ] || [ -z "$connectedRegistryNamespace" ]; then
  echo "No connected registry found"
  generate_output_json false "No connected registry found." "[]"
  exit 0 # ignore error and exit with success
fi

# get the connected registry pod name according to deployment name
echo "Looking for deployment related to connected registry: $connectedRegistryName in namespace: $connectedRegistryNamespace"

# Get the name of the deployment.
# We'll assume the deployment name is the same as the connectedRegistryName.
# If not, you might need to list deployments and filter by other means (e.g., labels specific to connected registry)
deploymentName=$connectedRegistryName

# Get the label selector from the deployment
# This is a more robust way to find pods managed by the deployment
selector=$(kubectl get deployment -n "$connectedRegistryNamespace" "$deploymentName" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)

if [ -z "$selector" ]; then
  echo "Deployment $deploymentName not found in namespace $connectedRegistryNamespace, or it has no label selectors."
  # Fallback or alternative: try to find pods with a common label pattern if the deployment name itself isn't directly the app label
  # For example, Azure extensions might use a label like 'app.kubernetes.io/name' or 'app'
  # This is an example, you might need to adjust the label based on your connected registry's deployment specifics
  echo "Attempting to find pods using a common label pattern for connected registry name: $connectedRegistryName"
  connectedRegistryPodName=$(kubectl get pods -n "$connectedRegistryNamespace" -l "app=$connectedRegistryName" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$connectedRegistryPodName" ]; then
    echo "Could not find connected registry pod using common label app=$connectedRegistryName."
    # As a last resort, if the connected registry name is part of the pod name prefix:
    echo "Attempting to find pods with prefix derived from connected registry name: $connectedRegistryName"
    connectedRegistryPodName=$(kubectl get pods -n "$connectedRegistryNamespace" --no-headers -o custom-columns=":metadata.name" | grep "^${connectedRegistryName}-" | head -n 1)
  fi
else
  # Convert the JSON selector to a kubectl label selector string
  labelSelectorString=$(echo "$selector" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
  echo "Using label selector for deployment $deploymentName: $labelSelectorString"
  connectedRegistryPodName=$(kubectl get pods -n "$connectedRegistryNamespace" -l "$labelSelectorString" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi


if [ -z "$connectedRegistryPodName" ]; then
  echo "Connected registry pod not found for deployment $deploymentName in namespace $connectedRegistryNamespace."
  generate_output_json false "Connected registry pod not found." "[]"
  exit 0 # ignore error and exit with success
fi

# move file to the CR pod and grant execute permission
remote_script_root="/maestro-tmp"
remote_script_name="check-acr-images.sh"
remote_script_path="$remote_script_root/$remote_script_name"
kubectl exec $connectedRegistryPodName -n $connectedRegistryNamespace -- mkdir -p $remote_script_root
if ! kubectl exec "$connectedRegistryPodName" -n "$connectedRegistryNamespace" -- test -f "$remote_script_path"; then
  echo "Script $remote_script_path not found in pod. Copying..."
  kubectl cp "$remote_script_name" "${connectedRegistryNamespace}/${connectedRegistryPodName}:${remote_script_root}/"
else
  echo "Script $remote_script_path already exists in pod. Skipping copy."
kubectl exec $connectedRegistryPodName  -n $connectedRegistryNamespace -- chmod +x $remote_script_path
fi

successFlag=true
message=""
downloaded_images=()

# Collect the output from the script
echo "Executing the script in the connected registry pod: $connectedRegistryPodName, bash: $remote_script_path $image_args_string"
check_acr_output=$(kubectl exec $connectedRegistryPodName -n $connectedRegistryNamespace -- /bin/bash -c "$remote_script_path $image_args_string")
echo "----> Output from the script execution:"
echo "$check_acr_output"
echo "----> Script execution completed."

if [ $? -ne 0 ]; then
    echo "Error executing the script in the connected registry pod."
    successFlag=false
fi
if [ -n "$check_acr_output" ]; then
    # Read each line from the output using process substitution to avoid a subshell for the loop
    while IFS= read -r line; do
        # Check if the line indicates a fully downloaded image
        echo "Processing line: $line"
        
        if echo "$line" | grep -q "^All blobs present. .*is fully downloaded\.$"; then
            # Extract the image name. It's enclosed in single quotes.
            # Using awk: set field delimiter to ' and print the 2nd field.
            image_name=$(echo "$line" | awk -F"'" '{print $2}')
            
            echo "Extracted image name: $image_name"
            # Add to the images array if an image name was extracted
            if [ -n "$image_name" ]; then
                echo "Added image: $image_name to the downloaded images list."
                downloaded_images+=("$image_name")
            fi
        fi
    done < <(echo "$check_acr_output") # Process substitution here
fi

if [ "${#downloaded_images[@]}" -eq 0 ]; then
  downloaded_images_json="[]"
else
  downloaded_images_json=$(printf '%s\n' "${downloaded_images[@]}" | jq -R . | jq -s .)
fi

echo "Downloaded images: count: ${#downloaded_images[@]}"

if [ ${#downloaded_images[@]} -ne ${#image_args[@]} ]; then
  successFlag=false
  message="Not all images were fully downloaded, requested images: ${#image_args[@]}, fully downloaded: ${#downloaded_images[@]}."
else
  message="Successfully checked the download status of images. Total images checked: ${#image_args[@]}, fully downloaded: ${#downloaded_images[@]}."
fi

generate_output_json "$successFlag" "$message" "$downloaded_images_json"