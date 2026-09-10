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
# Tidewave injects a second MCP server at 127.0.0.1:9832 (tidewave-cli's
# socket, carrying the browser tools) into every agent it launches, so
# bridge it unconditionally. NOTE: that port also serves tidewave-cli's
# unauthenticated host file API (/read, /write, /delete, ...), so this
# hands the sandboxed agent host-filesystem access as the user. See
# decisions/0009.
export BWRAP_EXTRA_PORTS="${BWRAP_EXTRA_PORTS:-} 9832"
exec "$HOME/.nix-profile/bin/bwrap-sandbox" "$HOME/.nix-profile/bin/opencode" "$@"
