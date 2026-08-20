#!/bin/sh
# Pre-pulls every image listed in prepull-images.txt so a real run never
# pays the image-download cost - only the microVM boot cost.
set -e

LIST=/srv/agent/etc/prepull-images.txt

grep -v '^\s*#' "$LIST" | grep -v '^\s*$' | while read -r image; do
  echo "pre-pulling $image"
  nerdctl pull "$image"
done
