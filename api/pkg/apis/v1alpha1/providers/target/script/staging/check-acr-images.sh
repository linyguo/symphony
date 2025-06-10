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