#!/usr/bin/env bash
# bwrap-allow-host: Add a domain to the bwrap-sandbox allowlist and reload squid.
#
# Usage: bwrap-allow-host <domain>        (add to per-project .allowed-hosts)
#        bwrap-allow-host -g <domain>   (add to global allowlist instead)
#
# Adds to the persistent allowlist file AND to any running squid's snapshot,
# so the change takes effect immediately and persists across restarts.
#
# Prefix with . to include all subdomains (e.g. .example.com)

set -euo pipefail

GLOBAL_ALLOWLIST="$HOME/.config/bwrap-sandbox/allowed-hosts.txt"
GLOBAL=false

while getopts "g" opt; do
  case $opt in
    g) GLOBAL=true ;;
    *) echo "Usage: bwrap-allow-host [-g] <domain>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
  echo "Usage: bwrap-allow-host [-g] <domain>" >&2
  exit 1
fi

DOMAIN="$1"

if [ "$GLOBAL" = true ]; then
  TARGET="$GLOBAL_ALLOWLIST"
else
  TARGET=".allowed-hosts"
fi

# Append to persistent allowlist if not already present
if ! grep -qxF "$DOMAIN" "$TARGET" 2>/dev/null; then
  echo "$DOMAIN" >> "$TARGET"
  echo "Added $DOMAIN to $TARGET"
else
  echo "$DOMAIN already in $TARGET"
fi

# Also append to any running squid's snapshot allowlist and reload.
# The snapshot is in $HOME/.cache/bwrap-sandbox.*/allowed-hosts.txt.
UPDATED=false
for snapshot in "$HOME/.cache"/bwrap-sandbox.*/allowed-hosts.txt; do
  [ -f "$snapshot" ] || continue
  if ! grep -qxF "$DOMAIN" "$snapshot" 2>/dev/null; then
    echo "$DOMAIN" >> "$snapshot"
  fi
  UPDATED=true
done

if [ "$UPDATED" = true ]; then
  RELOADED=0
  for pidfile in "$HOME/.cache"/bwrap-sandbox.*/squid.pid; do
    [ -f "$pidfile" ] || continue
    pid=$(cat "$pidfile" 2>/dev/null)
    [ -n "$pid" ] && kill -HUP "$pid" 2>/dev/null && RELOADED=$((RELOADED + 1))
  done
  [ "$RELOADED" -gt 0 ] && echo "Reloaded $RELOADED squid instance(s)" || echo "Warning: could not reload squid" >&2
else
  echo "Note: no running sandbox found. Domain will take effect on next bwrap-sandbox start."
fi
