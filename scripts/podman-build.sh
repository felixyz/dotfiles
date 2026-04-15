#!/usr/bin/env bash
# podman-build: wrapper that dereferences symlinks in the build context
# before calling podman build. Works around podman rejecting symlinks
# pointing outside the context (Docker allowed this).
set -euo pipefail

# Find the build context: last positional argument that is a directory
args=("$@")
context_idx=-1
for ((i=${#args[@]}-1; i>=0; i--)); do
  if [ -d "${args[$i]}" ]; then
    context_idx=$i
    break
  fi
done

if [ "$context_idx" -ge 0 ]; then
  context="${args[$context_idx]}"
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  # Build rsync exclude list from .dockerignore (if present)
  excludes=()
  if [ -f "$context/.dockerignore" ]; then
    while IFS= read -r line; do
      # Skip comments and blank lines
      [[ "$line" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
      excludes+=(--exclude "$line")
    done < "$context/.dockerignore"
  fi

  # Copy context, dereferencing only symlinks pointing outside the context.
  # --copy-unsafe-links dereferences external symlinks (podman rejects these),
  # leaves internal symlinks intact (e.g. node_modules/.bin).
  rsync -rlpt --copy-unsafe-links "${excludes[@]}" "$context/" "$tmp/ctx/"
  args[$context_idx]="$tmp/ctx"
fi

exec podman build "${args[@]}"
