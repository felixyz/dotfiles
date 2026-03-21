#!/usr/bin/env bash
# bwrap-sandbox: Run a command inside a bubblewrap sandbox with restricted
# filesystem and network access. Adapted for NixOS from:
# https://patrickmccanna.net/a-better-way-to-limit-claude-code-and-other-coding-agents-access-to-secrets/
#
# Usage: bwrap-sandbox <command> [args...]
#
# The sandbox provides:
#   - Read-only access to /nix/store (all binaries/libraries)
#   - Read-only access to system and user nix profiles (PATH works normally)
#   - NO direct network access (--unshare-net)
#   - Network only via squid proxy through a unix socket bridge (mandatory)
#   - Read-write access to the current directory (your project)
#   - Read-only access to ~/.claude (subdirs selectively writable)
#   - Read-only access to ~/.claude.json
#   - No access to ~/.ssh, ~/.aws, ~/.gnupg, browser profiles, etc.
#
# Domain allowlists:
#   Global:      ~/.config/bwrap-sandbox/allowed-hosts.txt
#   Per-project:  ./.sandbox/allowed-hosts (in project directory, read at startup)
#
# Add a host on the fly (from another terminal):
#   bwrap-allow-host <domain>

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: bwrap-sandbox <command> [args...]" >&2
  exit 1
fi

PROJECT_DIR="$(pwd)"

# Guard against dangerous PROJECT_DIR values (allowlist, not blocklist)
case "$PROJECT_DIR" in
  "$HOME"/.ssh*|"$HOME"/.gnupg*|"$HOME"/.aws*|"$HOME"/.config/secrets*)
    echo "Error: refusing to sandbox inside sensitive directory $PROJECT_DIR" >&2
    exit 1
    ;;
  "$HOME"/*)
    ;; # OK — under $HOME but not in a sensitive subdir
  /code/*)
    ;; # OK — shared code directory
  *)
    echo "Error: PROJECT_DIR must be under \$HOME or /code (got $PROJECT_DIR)" >&2
    exit 1
    ;;
esac

GLOBAL_ALLOWLIST="$HOME/.config/bwrap-sandbox/allowed-hosts.txt"
PROJECT_ALLOWLIST="$PROJECT_DIR/.sandbox/allowed-hosts"
SANDBOX_DIR=$(mktemp -d --tmpdir="$HOME/.cache" "bwrap-sandbox.$(basename "$PROJECT_DIR").XXXXXX")
PIDS=()

# Pick a random available port for squid
pick_free_port() {
  local port
  while true; do
    port=$((RANDOM % 16384 + 49152))
    if ! ss -tlnp 2>/dev/null | grep -q ":$port "; then
      echo "$port"
      return
    fi
  done
}
SQUID_PORT=$(pick_free_port)
INNER_PROXY_PORT=$SQUID_PORT

cleanup() {
  for pid in "${PIDS[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$SANDBOX_DIR"
}
trap cleanup EXIT

# Clean up orphaned processes from previous sessions that didn't exit cleanly.
# Only remove dirs where the squid process is no longer running (truly orphaned).
# Active sessions (squid still running) are left alone.
for stale_dir in "$HOME/.cache"/bwrap-sandbox.*/; do
  [ -d "$stale_dir" ] || continue
  [ "$stale_dir" = "$SANDBOX_DIR/" ] && continue
  stale_pid_file="$stale_dir/squid.pid"
  if [ -f "$stale_pid_file" ]; then
    stale_pid=$(cat "$stale_pid_file" 2>/dev/null)
    if [ -n "$stale_pid" ] && kill -0 "$stale_pid" 2>/dev/null; then
      continue  # squid still running — this is an active session, leave it alone
    fi
  fi
  # Squid is gone (or never started) — clean up orphaned socat and stale dir
  pkill -f "socat.*$stale_dir" 2>/dev/null || true
  rm -rf "$stale_dir"
done

# Ensure global allowlist directory exists
mkdir -p "$(dirname "$GLOBAL_ALLOWLIST")"
touch "$GLOBAL_ALLOWLIST"

# --- Squid proxy setup ---
# Merge three sources into an immutable snapshot:
#   1. Built-in defaults (updated with the script)
#   2. Global allowlist (~/.config/bwrap-sandbox/allowed-hosts.txt, user additions via bwrap-allow-host -g)
#   3. Per-project allowlist (.sandbox/allowed-hosts in project dir)

SQUID_ALLOWLIST="$SANDBOX_DIR/allowed-hosts.txt"
cat > "$SQUID_ALLOWLIST" << 'BUILTIN'
.anthropic.com
.claude.ai
platform.claude.com
.github.com
.githubusercontent.com
.npmjs.org
.registry.npmjs.org
.docker.io
.registry-1.docker.io
.production.cloudflare.docker.com
BUILTIN
cat "$GLOBAL_ALLOWLIST" >> "$SQUID_ALLOWLIST"
if [ -f "$PROJECT_ALLOWLIST" ]; then
  cat "$PROJECT_ALLOWLIST" >> "$SQUID_ALLOWLIST"
fi
# Strip comments and blank lines
sed -i '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SQUID_ALLOWLIST"
sort -u -o "$SQUID_ALLOWLIST" "$SQUID_ALLOWLIST"

cat > "$SANDBOX_DIR/squid.conf" << EOF
# Minimal forward proxy for domain filtering
acl allowed_hosts dstdomain "$SQUID_ALLOWLIST"
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow allowed_hosts
http_access deny all

http_port $SQUID_PORT

access_log stdio:$SANDBOX_DIR/access.log
cache_log $SANDBOX_DIR/cache.log
pid_filename $SANDBOX_DIR/squid.pid
cache_dir null $SANDBOX_DIR
coredump_dir $SANDBOX_DIR
cache deny all
EOF

squid -f "$SANDBOX_DIR/squid.conf" -N &
PIDS+=($!)

# Wait for squid to be ready
SQUID_READY=false
for _ in $(seq 1 30); do
  if ss -tlnp 2>/dev/null | grep -q ":$SQUID_PORT"; then
    SQUID_READY=true
    break
  fi
  sleep 0.2
done
if [ "$SQUID_READY" != true ]; then
  echo "Error: squid failed to start on port $SQUID_PORT" >&2
  exit 1
fi

# --- Unix socket bridge (socat) ---
# Outside: listen on unix socket, forward to squid on localhost
# Inside:  listen on localhost:INNER_PROXY_PORT, forward to unix socket
# This is the ONLY network path out of the sandbox.

SOCKET_PATH="$SANDBOX_DIR/proxy.sock"

# Outside socat: unix socket -> squid
socat "UNIX-LISTEN:${SOCKET_PATH},fork" "TCP:127.0.0.1:${SQUID_PORT}" 2>/dev/null &
PIDS+=($!)

# Wait for socket to exist
SOCKET_READY=false
for _ in $(seq 1 20); do
  if [ -S "$SOCKET_PATH" ]; then
    SOCKET_READY=true
    break
  fi
  sleep 0.1
done
if [ "$SOCKET_READY" != true ]; then
  echo "Error: socat failed to create unix socket at $SOCKET_PATH" >&2
  exit 1
fi

# --- Port bridging ---
# Read .sandbox/allowed-ports and set up outside socat bridges for each port.
# Each bridge: UNIX socket in SANDBOX_DIR -> host localhost:PORT
SANDBOX_PORTS_FILE="$PROJECT_DIR/.sandbox/allowed-ports"
if [ -f "$SANDBOX_PORTS_FILE" ]; then
  while IFS= read -r port; do
    # Skip comments and blank lines
    [[ "$port" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
    port="${port%%#*}"  # strip inline comments
    port="${port// /}"  # strip whitespace
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    sock="$SANDBOX_DIR/port-$port.sock"
    socat "UNIX-LISTEN:${sock},fork" "TCP:127.0.0.1:${port}" 2>/dev/null &
    PIDS+=($!)
  done < "$SANDBOX_PORTS_FILE"
fi

# --- Launch sandbox ---
# The inner socat runs inside the sandbox, bridging localhost:INNER_PROXY_PORT
# to the unix socket. We use a wrapper script so we can background socat
# and then exec the actual command.

INNER_SCRIPT="$SANDBOX_DIR/inner-start.sh"
cat > "$INNER_SCRIPT" << 'INNEREOF'
#!/usr/bin/env bash
# Start inner socat: localhost proxy port -> unix socket
socat "TCP-LISTEN:${BWRAP_PROXY_PORT},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${BWRAP_SOCKET_PATH}" 2>/dev/null &

# Wait for inner socat to be listening
INNER_READY=false
for _ in $(seq 1 20); do
  if ss -tlnp 2>/dev/null | grep -q ":${BWRAP_PROXY_PORT}"; then
    INNER_READY=true
    break
  fi
  sleep 0.1
done
if [ "$INNER_READY" != true ]; then
  echo "Error: inner socat failed to start on port ${BWRAP_PROXY_PORT}" >&2
  exit 1
fi

# Bridge container ports: poll for port-*.sock files and start inner socat for each.
# Picks up ports defined in .sandbox/allowed-ports at startup and ports added dynamically
# via bwrap-allow-port during the session.
(while true; do
  for sock in "${BWRAP_SANDBOX_DIR}"/port-*.sock; do
    [ -S "$sock" ] || continue
    port="${sock##*/port-}"
    port="${port%.sock}"
    if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      socat "TCP-LISTEN:${port},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${sock}" 2>/dev/null &
    fi
  done
  sleep 2
done) &

# Run the actual command
exec "$@"
INNEREOF
chmod +x "$INNER_SCRIPT"

# --- ~/.claude mount strategy ---
# Mount ~/.claude read-only, then selectively bind each existing subdirectory
# read-write. This keeps top-level files (credentials, settings, etc.) read-only
# without needing to know their names, while allowing Claude to write to its
# operational subdirectories (sessions, cache, etc.).
CLAUDE_DIR_ARGS=(--ro-bind "$HOME/.claude" "$HOME/.claude")
CLAUDE_RO_SUBDIRS=("plugins")
for subdir in "$HOME/.claude"/*/; do
  [ -d "$subdir" ] || continue
  dirname=$(basename "$subdir")
  ro=false
  for ro_dir in "${CLAUDE_RO_SUBDIRS[@]}"; do
    [ "$dirname" = "$ro_dir" ] && ro=true && break
  done
  if [ "$ro" = true ]; then
    CLAUDE_DIR_ARGS+=(--ro-bind "$subdir" "$subdir")
  else
    CLAUDE_DIR_ARGS+=(--bind "$subdir" "$subdir")
  fi
done

# Run bwrap (not exec, so cleanup trap fires on exit)
bwrap \
  --ro-bind /nix /nix \
  --ro-bind /run/current-system /run/current-system \
  --ro-bind /run/wrappers /run/wrappers \
  --ro-bind /bin /bin \
  --ro-bind /usr /usr \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/hosts /etc/hosts \
  --ro-bind /etc/ssl /etc/ssl \
  --ro-bind /etc/static /etc/static \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/group /etc/group \
  --ro-bind /etc/nix /etc/nix \
  --symlink /nix/var/nix/profiles/per-user/"$USER"/home-manager-path "$HOME/.nix-profile" \
  --ro-bind "$HOME/.config/git" "$HOME/.config/git" \
  --bind "$PROJECT_DIR" "$PROJECT_DIR" \
  "${CLAUDE_DIR_ARGS[@]}" \
  --bind "$HOME/.claude.json" "$HOME/.claude.json" \
  --tmpfs "$PROJECT_DIR/.sandbox" \
  --ro-bind "$SANDBOX_DIR" "$SANDBOX_DIR" \
  --bind /run/bwrap-podman /run/bwrap-podman \
  --tmpfs /run/user \
  --dir "/run/user/$(id -u)" \
  ${WAYLAND_DISPLAY:+--ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "/run/user/$(id -u)/$WAYLAND_DISPLAY"} \
  --ro-bind /etc/containers /etc/containers \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --unshare-net \
  --unshare-pid \
  --unshare-ipc \
  --die-with-parent \
  --setenv HOME "$HOME" \
  --setenv PATH "$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin" \
  --setenv TERM "$TERM" \
  ${WAYLAND_DISPLAY:+--setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY"} \
  --setenv HTTP_PROXY "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv HTTPS_PROXY "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv http_proxy "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv https_proxy "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv no_proxy "localhost,127.0.0.1,::1" \
  --setenv NO_PROXY "localhost,127.0.0.1,::1" \
  --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" \
  --setenv MIX_HOME "$PROJECT_DIR/.toolchain/mix" \
  --setenv HEX_HOME "$PROJECT_DIR/.toolchain/hex" \
  --setenv DOCKER_BUILD "podman-build" \
  --setenv DOCKER_HOST "unix:///run/bwrap-podman/podman.sock" \
  --setenv CONTAINER_HOST "unix:///run/bwrap-podman/podman.sock" \
  --setenv BWRAP_SANDBOX_DIR "$SANDBOX_DIR" \
  --setenv BWRAP_PROXY_PORT "$INNER_PROXY_PORT" \
  --setenv BWRAP_SOCKET_PATH "$SOCKET_PATH" \
  --chdir "$PROJECT_DIR" \
  -- "$INNER_SCRIPT" "$@"
