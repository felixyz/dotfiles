#!/usr/bin/env bash
# bwrap-sandbox: Run a command inside a bubblewrap sandbox with restricted
# filesystem and network access. Adapted for NixOS from:
# https://patrickmccanna.net/a-better-way-to-limit-claude-code-and-other-coding-agents-access-to-secrets/
#
# Usage: bwrap-sandbox <command> [args...]
#
# Four personas with different home-dir scoping, see the mount strategy below.
# "claude", "opencode", "juggler", and "openchamber", auto-detected from the command basename
# or set explicitly via BWRAP_PERSONA.
#
# Domain allowlists (merged at startup into an immutable snapshot):
#   Global:      ~/.config/bwrap-sandbox/allowed-hosts.txt
#   Per-project: ./.sandbox/allowed-hosts
# Add a host on the fly from another terminal: bwrap-allow-host <domain>
#
# A devenv proxy hostname listed exactly in allowed-hosts is reachable inside at http://<name>/,
# whichever port devenv allocated.
#
# Every sandbox can write to /code/shared-docs, for notes that apply across projects.

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: bwrap-sandbox <command> [args...]" >&2
  exit 1
fi

# The stale-session sweep below cannot see the enclosing session's script
# from inside its PID namespace, so a nested run kills that session's socat bridges.
if [ -n "${BWRAP_SANDBOX_DIR:-}" ]; then
  echo "Error: already inside a bwrap sandbox ($BWRAP_SANDBOX_DIR)" >&2
  exit 1
fi

# Fail-closed persona detection: unknown commands error out rather than
# defaulting to the more-permissive "claude" scoping.
if [ -z "${BWRAP_PERSONA:-}" ]; then
  case "$(basename -- "$1")" in
    claude) BWRAP_PERSONA=claude ;;
    opencode) BWRAP_PERSONA=opencode ;;
    juggler) BWRAP_PERSONA=juggler ;;
    openchamber) BWRAP_PERSONA=openchamber ;;
    *)
      echo "Error: cannot auto-detect persona from command '$(basename -- "$1")'" >&2
      echo "       set BWRAP_PERSONA=claude, opencode, juggler, or openchamber explicitly" >&2
      exit 1
      ;;
  esac
fi

if ! command -v tidewave-mcp-filter >/dev/null; then
  echo "Error: tidewave-mcp-filter is not on PATH, it bridges the tidewave-cli port" >&2
  exit 1
fi

if ! command -v jq >/dev/null; then
  echo "Error: jq is not on PATH, it reads the devenv proxy's routes" >&2
  exit 1
fi

PROJECT_DIR="$(realpath "$(pwd)")"

# PROJECT_DIR is bind-mounted writable, so only run from explicitly project-ish
# locations. Override with BWRAP_ALLOW_ANY_DIR=1 for one-off experiments.
if [ "${BWRAP_ALLOW_ANY_DIR:-0}" != "1" ]; then
  case "$PROJECT_DIR" in
    "$HOME"/dotfiles|"$HOME"/dotfiles/*|\
    /code|/code/*)
      ;;
    *)
      echo "Error: refusing to sandbox outside project roots: $PROJECT_DIR" >&2
      echo "       allowed: ~/dotfiles, /code" >&2
      echo "       override with BWRAP_ALLOW_ANY_DIR=1" >&2
      exit 1
      ;;
  esac
fi

GLOBAL_ALLOWLIST="$HOME/.config/bwrap-sandbox/allowed-hosts.txt"
PROJECT_ALLOWLIST="$PROJECT_DIR/.sandbox/allowed-hosts"
# Encode PROJECT_DIR into the runtime dir name so bwrap-allow-{host,port}
# can target the right sandbox unambiguously (basenames can collide between
# unrelated projects). '=' substitutes for '/' since it never appears in
# path components on this system.
PROJECT_DIR_TAG="${PROJECT_DIR//\//=}"
SANDBOX_DIR=$(mktemp -d --tmpdir="$HOME/.cache" "bwrap-sandbox.${PROJECT_DIR_TAG}.XXXXXX")
echo $$ > "$SANDBOX_DIR/owner.pid"
# The sandbox gets its own .devenv, so Postgres runs initdb on an empty state dir.
# It also keeps the host's eval cache intact, which holds a single entry that a sandbox's config would replace.
# The host's venv is bind-mounted back in to avoid re-downloading packages.
mkdir -p "$SANDBOX_DIR/devenv/state"
BWRAP_DEVENV_VENV_ARGS=()
if [ -d "$PROJECT_DIR/.devenv/state/venv" ]; then
  BWRAP_DEVENV_VENV_ARGS+=(--bind "$PROJECT_DIR/.devenv/state/venv" "$PROJECT_DIR/.devenv/state/venv")
fi
# The port behind an allowed .localhost name is bridged from the host, so it is taken inside the sandbox.
# devenv with strict ports checks every process port before it starts any process,
# and strict_ports false gives a process whose port is taken the next free one.
# The host file is created as "{}" because bwrap needs a file to mount over.
# It is never removed, since another sandbox of the same project may have it mounted.
BWRAP_DEVENV_LOCAL_ARGS=()
if [ -f "$PROJECT_DIR/devenv.yaml" ]; then
  DEVENV_LOCAL="$PROJECT_DIR/devenv.local.yaml"
  if [ ! -e "$DEVENV_LOCAL" ]; then
    echo '{}' > "$DEVENV_LOCAL"
    echo "Note: created $DEVENV_LOCAL" >&2
  fi
  grep -v '^strict_ports:' "$DEVENV_LOCAL" | grep -vx '{}' > "$SANDBOX_DIR/devenv.local.yaml" || true
  echo 'strict_ports: false' >> "$SANDBOX_DIR/devenv.local.yaml"
  BWRAP_DEVENV_LOCAL_ARGS+=(--ro-bind "$SANDBOX_DIR/devenv.local.yaml" "$DEVENV_LOCAL")
fi
SHARED_DOCS_DIR=/code/shared-docs
# When /code/shared-docs cannot be created, the sandbox starts without it.
mkdir -p "$SHARED_DOCS_DIR" 2>/dev/null || true
if [ ! -d "$SHARED_DOCS_DIR" ]; then
  echo "Warning: cannot create $SHARED_DOCS_DIR, the sandbox runs without it" >&2
fi
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
DEVENV_ACCEL_PORT=$(pick_free_port)
while [ "$DEVENV_ACCEL_PORT" = "$SQUID_PORT" ]; do
  DEVENV_ACCEL_PORT=$(pick_free_port)
done

DEVENV_PROXY_ADDR="${DEVENV_PROXY_LISTEN:-127.0.0.1:80}"
DEVENV_PROXY_HOST="${DEVENV_PROXY_ADDR%:*}"
DEVENV_PROXY_PORT="${DEVENV_PROXY_ADDR##*:}"

cleanup() {
  # Stop containers started via bwrap-podman during this session
  CONTAINER_HOST=unix:///run/bwrap-podman/podman.sock podman --remote stop -a -t 2 2>/dev/null || true
  for pid in "${PIDS[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  # The devenv route bridges and those started by bwrap-allow-port are not in PIDS.
  pkill -f "(socat|tidewave-mcp-filter).*$SANDBOX_DIR/" 2>/dev/null || true
  rm -rf "$SANDBOX_DIR"
}
trap cleanup EXIT

# squid.pid is written after this sweep, so a session starting alongside this one has only owner.pid.
# A dir under a minute old may be between mktemp and writing owner.pid.
for stale_dir in "$HOME/.cache"/bwrap-sandbox.*/; do
  [ -d "$stale_dir" ] || continue
  [ "$stale_dir" = "$SANDBOX_DIR/" ] && continue
  [ -n "$(find "$stale_dir" -maxdepth 0 -mmin -1 2>/dev/null)" ] && continue
  stale_pid=$(cat "$stale_dir/owner.pid" 2>/dev/null || true)
  if [ -n "$stale_pid" ] && kill -0 "$stale_pid" 2>/dev/null; then
    continue
  fi
  pkill -f "(squid|socat|tidewave-mcp-filter).*$stale_dir" 2>/dev/null || true
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
.tidewave.ai
juggler.studio
BUILTIN
cat "$GLOBAL_ALLOWLIST" >> "$SQUID_ALLOWLIST"
if [ -f "$PROJECT_ALLOWLIST" ]; then
  cat "$PROJECT_ALLOWLIST" >> "$SQUID_ALLOWLIST"
fi
# Strip comments and blank lines
sed -i '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SQUID_ALLOWLIST"
sort -u -o "$SQUID_ALLOWLIST" "$SQUID_ALLOWLIST"
# One devenv proxy serves the dev servers of every project.
# Example: ".honeyops.localhost" would also admit "livebook.honeyops.localhost",
# a server of a different project.
LOCALHOST_WILDCARD='^(localhost|[.*](.*\.)?localhost)$'
if grep -Eiq "$LOCALHOST_WILDCARD" "$SQUID_ALLOWLIST"; then
  echo "Warning: ignoring allowlist entries that are not a single .localhost hostname:" >&2
  grep -Ei "$LOCALHOST_WILDCARD" "$SQUID_ALLOWLIST" | sed 's/^/  /' >&2
  sed -i -E "/$LOCALHOST_WILDCARD/Id" "$SQUID_ALLOWLIST"
fi

# Not every resolver maps .localhost names to loopback on its own.
SANDBOX_HOSTS="$SANDBOX_DIR/hosts"
cat /etc/hosts > "$SANDBOX_HOSTS"
grep -Ei '\.localhost$' "$SQUID_ALLOWLIST" | sed 's/^/127.0.0.1 /' >> "$SANDBOX_HOSTS" || true

cat > "$SANDBOX_DIR/squid.conf" << EOF
# Minimal forward proxy for domain filtering
acl allowed_hosts dstdomain "$SQUID_ALLOWLIST"
acl localhost_names dstdom_regex -i (^|\.)localhost\$
acl devenv_port myportname devenv
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow devenv_port allowed_hosts localhost_names
http_access deny devenv_port
http_access deny localhost_names
http_access allow allowed_hosts
http_access deny all

http_port $SQUID_PORT
# Sandbox port 80 arrives here.
http_port 127.0.0.1:$DEVENV_ACCEL_PORT accel vhost name=devenv
cache_peer $DEVENV_PROXY_HOST parent $DEVENV_PROXY_PORT 0 no-query originserver no-digest name=devenv_proxy
cache_peer_access devenv_proxy allow devenv_port
cache_peer_access devenv_proxy deny all
never_direct allow devenv_port

access_log stdio:$SANDBOX_DIR/access.log
cache_log $SANDBOX_DIR/cache.log
pid_filename $SANDBOX_DIR/squid.pid
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

DEVENV_SOCKET_PATH="$SANDBOX_DIR/devenv-proxy.sock"
socat "UNIX-LISTEN:${DEVENV_SOCKET_PATH},fork" "TCP:127.0.0.1:${DEVENV_ACCEL_PORT}" 2>/dev/null &
PIDS+=($!)

# --- Port bridging ---
# Bridge host localhost ports into the sandbox. Sources, merged and deduped:
#   1. BWRAP_EXTRA_PORTS (space/comma separated) — set by launcher wrappers
#      for ports every session of that kind needs (tidewave-*-sandboxed
#      add 9832, the tidewave-cli MCP socket).
#   2. Per-project .sandbox/allowed-ports (one port per line, # comments).
# Each bridge: UNIX socket in SANDBOX_DIR -> host localhost:PORT
TIDEWAVE_PORT=9832
BRIDGE_PORTS=()
extra_ports="${BWRAP_EXTRA_PORTS:-}"
for port in ${extra_ports//,/ }; do
  [[ "$port" =~ ^[0-9]+$ ]] && BRIDGE_PORTS+=("$port")
done
SANDBOX_PORTS_FILE="$PROJECT_DIR/.sandbox/allowed-ports"
if [ -f "$SANDBOX_PORTS_FILE" ]; then
  while IFS= read -r port; do
    # Skip comments and blank lines
    [[ "$port" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
    port="${port%%#*}"  # strip inline comments
    port="${port// /}"  # strip whitespace
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    BRIDGE_PORTS+=("$port")
  done < "$SANDBOX_PORTS_FILE"
fi
for port in $(printf '%s\n' ${BRIDGE_PORTS[@]+"${BRIDGE_PORTS[@]}"} | sort -un); do
  # A raw bridge to the devenv proxy would skip the hostname check in squid.
  case "$port" in
    80 | 443 | "$DEVENV_PROXY_PORT")
      echo "Warning: not bridging port $port, list the .localhost hostname in allowed-hosts instead" >&2
      continue
      ;;
  esac
  sock="$SANDBOX_DIR/port-$port.sock"
  # tidewave-cli serves a file API without authentication on the same port. See decisions/0019.
  if [ "$port" = "$TIDEWAVE_PORT" ]; then
    tidewave-mcp-filter "$sock" "$port" "$PROJECT_DIR" &
    PIDS+=($!)
    continue
  fi
  socat "UNIX-LISTEN:${sock},fork" "TCP:127.0.0.1:${port}" 2>/dev/null &
  PIDS+=($!)
done

# Tidewave Web points its agents at the dev server's own port, not its hostname.
# The port behind each allowed .localhost name is bridged,
# and the bridge follows the route when devenv allocates a different port.
DEVENV_CONTROL_SOCKET="${DEVENV_PROXY_SOCKET:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/devenv/proxy.sock}"
devenv_route_ports() {
  [ -S "$DEVENV_CONTROL_SOCKET" ] || return 0
  printf '{"command":"list"}\n' |
    socat -t 2 - "UNIX-CONNECT:${DEVENV_CONTROL_SOCKET}" 2>/dev/null |
    jq -r --rawfile allowed "$SQUID_ALLOWLIST" '
      ($allowed | ascii_downcase | split("\n")) as $names
      | .routes[]?
      | select((.hostname | ascii_downcase) as $h | ($h | endswith(".localhost")) and ($names | index($h)))
      | .upstream
      | capture("^(127\\.0\\.0\\.1|localhost):(?<port>[0-9]+)$").port' 2>/dev/null |
    sort -u
}
sync_devenv_bridges() {
  local wanted port pidfile sock
  wanted=$(devenv_route_ports || true)
  for pidfile in "$SANDBOX_DIR"/devenv-bridge-*.pid; do
    [ -f "$pidfile" ] || continue
    port="${pidfile##*/devenv-bridge-}"
    port="${port%.pid}"
    if ! grep -qx "$port" <<< "$wanted"; then
      kill "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile" "$SANDBOX_DIR/port-$port.sock"
    fi
  done
  for port in $wanted; do
    case "$port" in 80 | 443 | "$DEVENV_PROXY_PORT" | "$TIDEWAVE_PORT") continue ;; esac
    sock="$SANDBOX_DIR/port-$port.sock"
    [ -S "$sock" ] && continue
    socat "UNIX-LISTEN:${sock},fork" "TCP:127.0.0.1:${port}" 2>/dev/null &
    echo $! > "$SANDBOX_DIR/devenv-bridge-$port.pid"
    for _ in $(seq 1 10); do
      [ -S "$sock" ] && break
      sleep 0.1
    done
  done
}
sync_devenv_bridges
(while true; do
  sleep 2
  sync_devenv_bridges
done) &
PIDS+=($!)

# --- Reverse port bridging ---
# BWRAP_EXPOSE_PORTS lists sandbox ports the host reaches at the same
# localhost port, the opposite direction of the bridges above.
# Each bridge runs from host localhost:PORT through a UNIX socket in EXPOSE_DIR
# to sandbox localhost:PORT.
# The inner socat creates the socket, so EXPOSE_DIR is bind-mounted writable
# over the read-only SANDBOX_DIR.
EXPOSE_DIR="$SANDBOX_DIR/expose"
mkdir -p "$EXPOSE_DIR"
EXPOSE_PORTS=()
expose_ports="${BWRAP_EXPOSE_PORTS:-}"
for port in ${expose_ports//,/ }; do
  [[ "$port" =~ ^[0-9]+$ ]] || continue
  if ss -tln 2>/dev/null | grep -q ":$port "; then
    echo "Error: cannot expose sandbox port $port, host port $port is already in use" >&2
    exit 1
  fi
  EXPOSE_PORTS+=("$port")
done
for port in ${EXPOSE_PORTS[@]+"${EXPOSE_PORTS[@]}"}; do
  socat "TCP-LISTEN:${port},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${EXPOSE_DIR}/port-${port}.sock" 2>/dev/null &
  PIDS+=($!)
done

# --- Launch sandbox ---
# The inner socat runs inside the sandbox, bridging localhost:INNER_PROXY_PORT
# to the unix socket. We use a wrapper script so we can background socat
# and then exec the actual command.

INNER_SCRIPT="$SANDBOX_DIR/inner-start.sh"
cat > "$INNER_SCRIPT" << 'INNEREOF'
#!/usr/bin/env bash
# Start inner socat: localhost proxy port -> unix socket
socat "TCP-LISTEN:${BWRAP_PROXY_PORT},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${BWRAP_SOCKET_PATH}" 2>/dev/null &
socat "TCP-LISTEN:80,bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${BWRAP_DEVENV_SOCKET_PATH}" 2>/dev/null &

# Wait for inner socat to be listening
INNER_READY=false
for _ in $(seq 1 20); do
  listening=$(ss -tln 2>/dev/null)
  if grep -q ":${BWRAP_PROXY_PORT} " <<< "$listening" && grep -q ":80 " <<< "$listening"; then
    INNER_READY=true
    break
  fi
  sleep 0.1
done
if [ "$INNER_READY" != true ]; then
  echo "Error: inner socat failed to start on port ${BWRAP_PROXY_PORT} or 80" >&2
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

for port in ${BWRAP_EXPOSE_PORTS//,/ }; do
  [[ "$port" =~ ^[0-9]+$ ]] || continue
  socat "UNIX-LISTEN:${BWRAP_SANDBOX_DIR}/expose/port-${port}.sock,fork" "TCP:127.0.0.1:${port}" 2>/dev/null &
done

# Run the actual command
exec "$@"
INNEREOF
chmod +x "$INNER_SCRIPT"

# --- ~/.claude mount strategy ---
CLAUDE_DIR_ARGS=()
CLAUDE_JSON_ARGS=()
case "$BWRAP_PERSONA" in
  claude | juggler)
    # Parent ro-bind caps top-level creation; subdirs punched through
    # writable except plugins/ (code + manifests), of which only
    # plugins/data/ is re-punched writable below.
    CLAUDE_DIR_ARGS=(--ro-bind "$HOME/.claude" "$HOME/.claude")
    if [ -f "$HOME/.claude/.credentials.json" ]; then
      CLAUDE_DIR_ARGS+=(--bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json")
    fi
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
    # plugins/ stays ro (cache/, marketplaces/, installed_plugins.json are
    # code and manifests) but plugins/data/ is per-plugin scratch state
    # that Claude Code mkdirs (CLAUDE_PLUGIN_DATA) before running any
    # plugin hook. Later binds stack over the ro-bind above.
    mkdir -p "$HOME/.claude/plugins/data"
    CLAUDE_DIR_ARGS+=(--bind "$HOME/.claude/plugins/data" "$HOME/.claude/plugins/data")
    # .claude.json holds MCP config, project history, etc. — claude CLI only.
    if [ -f "$HOME/.claude.json" ]; then
      CLAUDE_JSON_ARGS=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
    fi
    ;;
  opencode)
    # Minimal surface: opencode-claude-auth plugin reads .credentials.json,
    # and Claude-format skills are auto-discovered from ~/.claude/skills/.
    # Both ro — the plugin's writeBackCredentials() EROFSes silently and
    # opencode persists refreshed tokens to ~/.local/share/opencode/auth.json
    # instead; the stale refresh token on disk keeps working until it
    # expires upstream.
    # Skills are trusted code (model instructions + bash tool access); treat
    # ~/.claude/skills/ like $PATH.
    if [ -f "$HOME/.claude/.credentials.json" ]; then
      CLAUDE_DIR_ARGS+=(--ro-bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json")
    fi
    if [ -d "$HOME/.claude/skills" ]; then
      CLAUDE_DIR_ARGS+=(--ro-bind "$HOME/.claude/skills" "$HOME/.claude/skills")
    fi
    ;;
  openchamber)
    if [ -d "$HOME/.claude/skills" ]; then
      CLAUDE_DIR_ARGS+=(--ro-bind "$HOME/.claude/skills" "$HOME/.claude/skills")
    fi
    ;;
  *)
    echo "Error: unknown BWRAP_PERSONA=$BWRAP_PERSONA (expected: claude|opencode|juggler|openchamber)" >&2
    exit 1
    ;;
esac

# --- opencode mount strategy ---
# ro-bind parents cap top-level creation; specific children get writable
# binds only where opencode genuinely needs runtime writes.
OPENCODE_DIR_ARGS=()
if [ "$BWRAP_PERSONA" = "opencode" ] || [ "$BWRAP_PERSONA" = "juggler" ]; then
  # Contents are Nix-managed symlinks; opencode never writes here.
  if [ -d "$HOME/.config/opencode" ]; then
    OPENCODE_DIR_ARGS+=(--ro-bind "$HOME/.config/opencode" "$HOME/.config/opencode")
  fi

  # Writable: OAuth tokens, sessions DB, current-session log.
  # Tmpfs-overlayed: snapshot/ and storage/ — opencode's internal git repo
  # and session_diff dir. Writing through to host would let a compromised
  # agent poison state that future sessions load, so writes go to a
  # per-invocation tmpfs and vanish on exit. Undo still works within a
  # session; cross-session history doesn't.
  # Read-only: tool-output/ — agent can read its past outputs but not
  # poison them.
  if [ -d "$HOME/.local/share/opencode" ]; then
    OPENCODE_DIR_ARGS+=(--ro-bind "$HOME/.local/share/opencode" "$HOME/.local/share/opencode")
    for writable_file in auth.json opencode-stable.db opencode-stable.db-shm opencode-stable.db-wal; do
      target="$HOME/.local/share/opencode/$writable_file"
      if [ -f "$target" ]; then
        OPENCODE_DIR_ARGS+=(--bind "$target" "$target")
      fi
    done
    if [ -d "$HOME/.local/share/opencode/log" ]; then
      OPENCODE_DIR_ARGS+=(--bind "$HOME/.local/share/opencode/log" "$HOME/.local/share/opencode/log")
    fi
    OPENCODE_DIR_ARGS+=(--tmpfs "$HOME/.local/share/opencode/snapshot")
    OPENCODE_DIR_ARGS+=(--tmpfs "$HOME/.local/share/opencode/storage")
  fi

  # Shared with host opencode runs — a writable bind would let the agent
  # poison node_modules/ or drop shims in bin/ that the next unsandboxed
  # invocation executes as the user. packages/ (plugin/LSP staging) is
  # absent from writes; reinforced by OPENCODE_DISABLE_LSP_DOWNLOAD below.
  if [ -d "$HOME/.cache/opencode" ]; then
    OPENCODE_DIR_ARGS+=(--ro-bind "$HOME/.cache/opencode" "$HOME/.cache/opencode")
  fi
fi

# --- juggler mount strategy ---
# The juggler persona is the claude and opencode mounts above combined,
# since juggler spawns both agents inside the sandbox, plus its own
# config, cache, and log dirs. See decisions/0014.
JUGGLER_DIR_ARGS=()
if [ "$BWRAP_PERSONA" = "juggler" ]; then
  for dir in "$HOME/.config/juggler" "$HOME/.cache/juggler" "$HOME/.local/state/juggler"; do
    mkdir -p "$dir"
    JUGGLER_DIR_ARGS+=(--bind "$dir" "$dir")
  done
fi

# --- openchamber mount strategy ---
# OpenChamber runs OpenCode v2, which gets its own config, data, state, and cache dirs
# mounted at opencode's usual paths, so it never reads or migrates v1's sessions.
# See decisions/0016.
OPENCHAMBER_DIR_ARGS=()
if [ "$BWRAP_PERSONA" = "openchamber" ]; then
  for pair in \
    ".config/openchamber-opencode:.config/opencode" \
    ".local/share/openchamber-opencode:.local/share/opencode" \
    ".local/state/openchamber-opencode:.local/state/opencode" \
    ".cache/openchamber-opencode:.cache/opencode" \
    ".config/openchamber:.config/openchamber"; do
    mkdir -p "$HOME/${pair%%:*}"
    OPENCHAMBER_DIR_ARGS+=(--bind "$HOME/${pair%%:*}" "$HOME/${pair##*:}")
  done
fi

# Run the sandbox (not exec, so cleanup trap fires on exit)
# The network namespace is created here rather than by bwrap,
# so that ports from 80 up can be bound inside without any capability.
# bwrap refuses to start while it holds capabilities, so setpriv drops them first.
unshare --user --map-current-user --net --keep-caps -- bash -c '
  ip link set lo up &&
  echo 80 > /proc/sys/net/ipv4/ip_unprivileged_port_start &&
  exec setpriv --inh-caps=-all --ambient-caps=-all -- "$@"
' bwrap-netns bwrap \
  --ro-bind /nix /nix \
  --ro-bind /run/current-system /run/current-system \
  --ro-bind /run/wrappers /run/wrappers \
  --ro-bind /bin /bin \
  --ro-bind /usr /usr \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind "$SANDBOX_HOSTS" /etc/hosts \
  --ro-bind /etc/ssl /etc/ssl \
  --ro-bind /etc/static /etc/static \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/group /etc/group \
  --ro-bind /etc/nix /etc/nix \
  --symlink /nix/var/nix/profiles/per-user/"$USER"/home-manager-path "$HOME/.nix-profile" \
  --ro-bind "$HOME/.config/git" "$HOME/.config/git" \
  --bind "$PROJECT_DIR" "$PROJECT_DIR" \
  --bind "$SANDBOX_DIR/devenv" "$PROJECT_DIR/.devenv" \
  --bind-try "$SHARED_DOCS_DIR" "$SHARED_DOCS_DIR" \
  ${BWRAP_DEVENV_VENV_ARGS[@]+"${BWRAP_DEVENV_VENV_ARGS[@]}"} \
  ${BWRAP_DEVENV_LOCAL_ARGS[@]+"${BWRAP_DEVENV_LOCAL_ARGS[@]}"} \
  ${CLAUDE_DIR_ARGS[@]+"${CLAUDE_DIR_ARGS[@]}"} \
  ${CLAUDE_JSON_ARGS[@]+"${CLAUDE_JSON_ARGS[@]}"} \
  ${OPENCODE_DIR_ARGS[@]+"${OPENCODE_DIR_ARGS[@]}"} \
  ${JUGGLER_DIR_ARGS[@]+"${JUGGLER_DIR_ARGS[@]}"} \
  ${OPENCHAMBER_DIR_ARGS[@]+"${OPENCHAMBER_DIR_ARGS[@]}"} \
  --tmpfs "$PROJECT_DIR/.sandbox" \
  --ro-bind "$SANDBOX_DIR" "$SANDBOX_DIR" \
  --bind "$EXPOSE_DIR" "$EXPOSE_DIR" \
  --bind /run/bwrap-podman /run/bwrap-podman \
  --tmpfs /run/user \
  --dir "/run/user/$(id -u)" \
  ${WAYLAND_DISPLAY:+--ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "/run/user/$(id -u)/$WAYLAND_DISPLAY"} \
  --ro-bind /etc/containers /etc/containers \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --unshare-pid \
  --unshare-ipc \
  --die-with-parent \
  --setenv HOME "$HOME" \
  --setenv PATH "${PATH}:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin" \
  --setenv TERM "$TERM" \
  ${WAYLAND_DISPLAY:+--setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY"} \
  --setenv HTTP_PROXY "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv HTTPS_PROXY "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv http_proxy "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv https_proxy "http://127.0.0.1:$INNER_PROXY_PORT" \
  --setenv no_proxy "localhost,.localhost,127.0.0.1,::1" \
  --setenv NO_PROXY "localhost,.localhost,127.0.0.1,::1" \
  --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" \
  --setenv MIX_HOME "$PROJECT_DIR/.toolchain/mix" \
  --setenv HEX_HOME "$PROJECT_DIR/.toolchain/hex" \
  --setenv DOCKER_BUILD "podman-build" \
  --setenv DOCKER_HOST "unix:///run/bwrap-podman/podman.sock" \
  --setenv CONTAINER_HOST "unix:///run/bwrap-podman/podman.sock" \
  --setenv BWRAP_SANDBOX_DIR "$SANDBOX_DIR" \
  --setenv BWRAP_PROXY_PORT "$INNER_PROXY_PORT" \
  --setenv BWRAP_SOCKET_PATH "$SOCKET_PATH" \
  --setenv BWRAP_DEVENV_SOCKET_PATH "$DEVENV_SOCKET_PATH" \
  --setenv BWRAP_EXPOSE_PORTS "${EXPOSE_PORTS[*]:-}" \
  --setenv OPENCODE_DISABLE_LSP_DOWNLOAD "true" \
  --chdir "$PROJECT_DIR" \
  -- "$INNER_SCRIPT" "$@"
