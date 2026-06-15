#!/usr/bin/env bash
# Wrapper installed at the tidewave download-cache shim path, so tidewave
# spawns opencode inside bwrap-sandbox instead of directly on the host.
# Same persona scoping as the `jean-luc` alias.
#
# See tidewave-claude-sandboxed.sh for why we walk up to the .sandbox
# anchor before invoking bwrap-sandbox.
set -euo pipefail
d="$PWD"
while [ "$d" != "/" ]; do
  if [ -d "$d/.sandbox" ]; then
    cd "$d"
    break
  fi
  d="$(dirname "$d")"
done
export BWRAP_PERSONA=opencode
exec "$HOME/.nix-profile/bin/bwrap-sandbox" "$HOME/.nix-profile/bin/opencode" "$@"
