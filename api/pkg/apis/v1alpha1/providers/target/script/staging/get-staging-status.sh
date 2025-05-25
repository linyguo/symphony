#!/bin/bash
##
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.
## SPDX-License-Identifier: MIT
##

deployment=$1 # first parameter file is the deployment object
references=$2 # second parameter file contains the reference components

# generate the script to check ACR images
# Define the name of the script to be generated
generated_script_name="check-acr-images.sh"

# Use a "here document" to define the content of the script.
# Note the 'EOF' delimiter. It can be any string, but EOF is common.
# Using 'EOF' (with single quotes) prevents variable expansion and command substitution
# within the here document by the parent script, ensuring the content is written literally.
# This is crucial because variables like $ACR_BASE, $REPO_PATH, etc., are meant to be
# interpreted when the generated script (check-acr-images.sh) itself runs.

cat > "$generated_script_name" << 'EOF'
#!/bin/bash

# === CONFIGURATION ===
ACR_BASE="/var/acr/data/storage" # Path to the connected ACR storage on the node

# === FUNCTIONS ===

# Auto-detect the dynamic ACR hash folder and set ACR_STORAGE_ROOT
detect_acr_root() {
  # Find the first subdirectory under ACR_BASE (this is usually the hash-named folder)
  HASH_FOLDER=$(find "$ACR_BASE" -maxdepth 1 -type d ! -path "$ACR_BASE" | head -n 1)
  if [ -z "$HASH_FOLDER" ]; then
    echo "Error: Could not find connected ACR storage hash folder under $ACR_BASE" >&2
    exit 1
  fi
  ACR_STORAGE_ROOT="$HASH_FOLDER/v2" # The actual OCI layout starts inside v2
  echo "Detected ACR storage root: $ACR_STORAGE_ROOT"
}

# Parse repository and tag from "repo:tag" or "repo@digest"
# Handles simple tags and digests. Does not handle FQDNs with ports in the repo part.
parse_repo_tag() {
  local input_image="$1"
  REPO_PATH=""
  TAG="" # This will hold tag or digest

  if [[ "$input_image" == *@sha256:* ]]; then # Check for digest
    REPO_PATH="${input_image%%@sha256:*}"
    TAG="${input_image#*@sha256:}"
    TAG="sha256:$TAG" # Prepend sha256: back for consistency if needed, or handle as digest
  elif [[ "$input_image" == *:* ]]; then # Check for tag
    REPO_PATH="${input_image%:*}"
    TAG="${input_image#*:}"
  else
    echo "Error: Invalid image format: '$input_image'. Expected format is <repo>:<tag> or <repo>@<digest>" >&2
    return 1
  fi

  if [ -z "$REPO_PATH" ] || [ -z "$TAG" ]; then
    echo "Error: Could not parse repository or tag/digest from '$input_image'" >&2
    return 1
  fi
  return 0
}

# Check whether the manifest and layers for a given repo:tag are fully present
check_image() {
  local current_repo_path="$1" # Use local variables to avoid clashes
  local current_tag_or_digest="$2"
  local manifest_link_path=""
  local manifest_digest_value=""

  echo "" # Newline for readability
  echo "Checking image '$current_repo_path:$current_tag_or_digest'..."

  if [[ "$current_tag_or_digest" == sha256:* ]]; then
    # Handling direct digest reference - manifest is the digest itself
    manifest_digest_value="${current_tag_or_digest#sha256:}"
    echo "Referencing manifest by digest: $manifest_digest_value"
  else
    # Handling tag reference - need to find the link file
    manifest_link_path="$ACR_STORAGE_ROOT/repositories/$current_repo_path/_manifests/tags/$current_tag_or_digest/current/link"
    if [ ! -f "$manifest_link_path" ]; then
      echo "Error: Tag '$current_tag_or_digest' link file not found at '$manifest_link_path'" >&2
      return 1
    fi
    manifest_digest_value=$(sed 's/^sha256://' "$manifest_link_path")
  fi

  if [ -z "$manifest_digest_value" ]; then
    echo "Error: Failed to determine manifest digest for '$current_repo_path:$current_tag_or_digest'" >&2
    return 1
  fi

  local manifest_blob_path="$ACR_STORAGE_ROOT/blobs/sha256/${manifest_digest_value:0:2}/$manifest_digest_value/data"
  if [ ! -f "$manifest_blob_path" ]; then
    echo "Error: Manifest blob missing: $manifest_blob_path" >&2
    return 1
  fi

  echo "Manifest found: sha256:$manifest_digest_value"
  echo "Checking layer blobs..."

  # Extract layer digests from the manifest
  # This jq command is more robust for parsing JSON than grep/sed
  # It handles different types of manifests (single arch, manifest list)
  # For simplicity, this example assumes a single architecture image manifest.
  # If manifest lists are common, this part needs to be more sophisticated
  # to recursively check manifests listed within a manifest list.
  local layer_digests
  if command -v jq > /dev/null; then
    layer_digests=$(jq -r '.layers[].digest | select(.) | sub("sha256:"; "")' "$manifest_blob_path")
  else
    # Fallback to grep/sed if jq is not available (less robust)
    echo "Warning: jq not found. Using grep/sed for manifest parsing (less robust)." >&2
    layer_digests=$(grep -o '"digest": *"sha256:[a-f0-9]\{64\}"' "$manifest_blob_path" | sed 's/.*"sha256:\([a-f0-9]\{64\}\)".*/\1/')
  fi


  if [ -z "$layer_digests" ]; then
    # Check if it's a manifest list (which has 'manifests' array instead of 'layers')
    local is_manifest_list=false
    if command -v jq > /dev/null; then
        if jq -e '.manifests | length > 0' "$manifest_blob_path" > /dev/null; then
            is_manifest_list=true
        fi
    else # Fallback for manifest list check without jq (very basic)
        if grep -q '"manifests": \[' "$manifest_blob_path"; then
            is_manifest_list=true
        fi
    fi

    if $is_manifest_list; then
        echo "Image '$current_repo_path:$current_tag_or_digest' is a manifest list. Assuming present if manifest blob exists."
        # For a true check, you'd recursively call check_image for each manifest in the list.
        # This simplified version just checks for the manifest list blob itself.
        return 0 # Successfully found the manifest list blob
    else
        echo "Warning: No layer digests found in manifest for '$current_repo_path:$current_tag_or_digest'. It might be an empty image or unsupported manifest type." >&2
        # Depending on requirements, this could be a success (empty image) or failure.
        # Let's assume an image should have layers or be a known manifest list.
        return 1 # Consider it an issue if no layers and not a manifest list
    fi
  fi

  local all_layers_present=true
  while IFS= read -r layer_hash; do
    if [ -z "$layer_hash" ]; then continue; fi # Skip empty lines
    local layer_blob_path="$ACR_STORAGE_ROOT/blobs/sha256/${layer_hash:0:2}/$layer_hash/data"
    if [ -f "$layer_blob_path" ]; then
      echo "Layer present: sha256:$layer_hash"
    else
      echo "Layer missing: sha256:$layer_hash" >&2
      all_layers_present=false
    fi
  done <<< "$layer_digests"

  if $all_layers_present; then
    echo "All blobs present. Image '$current_repo_path:$current_tag_or_digest' is fully downloaded."
    return 0 # Success
  else
    echo "Some blobs missing. Image '$current_repo_path:$current_tag_or_digest' is incomplete." >&2
    return 1 # Failure
  fi
}

# === MAIN ===

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <repo1:tag1|repo1@digest1> [<repo2:tag2|repo2@digest2> ...]" >&2
  exit 1
fi

detect_acr_root # Call once to set ACR_STORAGE_ROOT

downloaded_images_output=() # Array to store successfully downloaded image names for output

for IMAGE_ARG in "$@"; do
  # REPO_PATH and TAG are global-like due to parse_repo_tag's IFS usage,
  # or they can be captured if parse_repo_tag echos them.
  # Let's make parse_repo_tag set them and check its return status.
  if parse_repo_tag "$IMAGE_ARG"; then
    # Now REPO_PATH and TAG (or digest) are set by parse_repo_tag
    if check_image "$REPO_PATH" "$TAG"; then # check_image returns 0 on success
      downloaded_images_output+=("$IMAGE_ARG")
    else
      echo "Image '$IMAGE_ARG' check failed or is incomplete." >&2
      # Optionally, set a global error flag if any image fails
    fi
  else
    echo "Skipping invalid image argument: $IMAGE_ARG" >&2
    # Optionally, set a global error flag
  fi
done

# Output only the successfully downloaded images, one per line
if [ ${#downloaded_images_output[@]} -gt 0 ]; then
  printf "%s\n" "${downloaded_images_output[@]}"
  exit 0 # Overall success if at least one image was processed and found
else
  echo "No images were found to be fully downloaded or all checks failed." >&2
  exit 1 # Overall failure if no images were successfully verified
fi
EOF

# Make the generated script executable
chmod +x "$generated_script_name"

# ----------------------------- MAIN SCRIPT -----------------------------
echo "$references"
image_list=($(echo "$references" | jq -r '.properties.imageList[]'))
echo "Image list: ${image_list[@]}"

if [ -z "$image_list" ]; then
  echo "No images found in the references file."
  exit 1
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
  exit 1
fi

# convert image_args to a string for passing to the script
image_args_string=$(printf "%s " "${image_args[@]}")

# get connected registry extension name and namespace
connectedRegistryNameNS=$(kubectl get ExtensionConfig -A -o json \
  | jq -r '.items[] | select(.spec.extensionType == "microsoft.containerregistry.connectedregistry") | "\(.metadata.name) \(.metadata.namespace)"')

connectedRegistryName=$(echo $connectedRegistryNameNS | awk '{print $1}')
connectedRegistryNamespace=$(echo $connectedRegistryNameNS | awk '{print $2}')

if [ -z "$connectedRegistryName" ] || [ -z "$connectedRegistryNamespace" ]; then
  echo "No connected registry found"
  exit 1
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
  exit 1
fi

# move file to the CR pod and grant execute permission
remote_script_root="/maestro-tmp"
remote_script_name="check-acr-images.sh"
remote_script_path="$remote_script_root/$remote_script_name"
kubectl exec -it $connectedRegistryPodName -n $connectedRegistryNamespace -- mkdir -p $remote_script_root
kubectl cp $remote_script_name "$connectedRegistryNamespace/$connectedRegistryPodName:$remote_script_root"
kubectl exec -it $connectedRegistryPodName  -n $connectedRegistryNamespace  -- chmod +x $remote_script_path

successFlag=true
message=""
downloaded_images=()

# Collect the output from the script
check_acr_output=$(kubectl exec -it $connectedRegistryPodName -n $connectedRegistryNamespace -- /bin/bash -c "$remote_script_path $image_args_string")
if [ $? -ne 0 ]; then
    echo "Error executing the script in the connected registry pod."
    successFlag=false
fi
if [ -n "$check_acr_output" ]; then
    # Read each line from the output
    echo "$check_acr_output" | while IFS= read -r line; do
        # Check if the line indicates a fully downloaded image
        if echo "$line" | grep -q "is fully downloaded."; then
            # Extract the image name. It's enclosed in single quotes.
            # Using awk: set field delimiter to ' and print the 2nd field.
            image_name=$(echo "$line" | awk -F"'" '{print $2}')
            
            # Add to the images array if an image name was extracted
            if [ -n "$image_name" ]; then
                downloaded_images+=("$image_name")
            fi
        fi
    done
fi

if [ "${#downloaded_images[@]}" -eq 0 ]; then
  downloaded_images_json="[]"
else
  downloaded_images_json=$(printf '%s\n' "${downloaded_images[@]}" | jq -R . | jq -s .)
fi

# Now build the final JSON
json=$(jq -n \
  --argjson Success "$successFlag" \
  --arg Message "$message" \
  --argjson StagedImages "$downloaded_images_json" \
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