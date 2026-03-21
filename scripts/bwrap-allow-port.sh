#!/usr/bin/env bash
# bwrap-allow-port: Bridge a host port into running bwrap sandboxes.
#
# Usage: bwrap-allow-port <port>
#
# Adds the port to .sandbox/allowed-ports (persistent) and starts a socat bridge
# for each running sandbox. The inner watcher picks up new bridges within ~2s.

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: bwrap-allow-port <port>" >&2
  exit 1
fi

PORT="$1"

if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: port must be a number" >&2
  exit 1
fi

# Append to persistent .sandbox/allowed-ports if not already present
TARGET=".sandbox/allowed-ports"
if ! grep -qxF "$PORT" "$TARGET" 2>/dev/null; then
  echo "$PORT" >> "$TARGET"
  echo "Added port $PORT to $TARGET"
else
  echo "Port $PORT already in $TARGET"
fi

# Start outside socat bridge for each active sandbox
BRIDGED=0
for sandbox_dir in "$HOME/.cache"/bwrap-sandbox.*/; do
  [ -d "$sandbox_dir" ] || continue
  # Check if this sandbox is still alive (squid running)
  pidfile="$sandbox_dir/squid.pid"
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
  else
    continue
  fi
  sock="$sandbox_dir/port-$PORT.sock"
  if [ -S "$sock" ]; then
    echo "Port $PORT already bridged in $sandbox_dir"
    BRIDGED=$((BRIDGED + 1))
    continue
  fi
  socat "UNIX-LISTEN:${sock},fork" "TCP:127.0.0.1:${PORT}" 2>/dev/null &
  BRIDGED=$((BRIDGED + 1))
  echo "Bridge started for port $PORT (sandbox picks up within ~2s)"
done

if [ "$BRIDGED" -eq 0 ]; then
  echo "Note: no running sandbox found. Port will be bridged on next bwrap-sandbox start."
fi
