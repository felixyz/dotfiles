#!/usr/bin/env bash
# Bootstrap Tidewave MCP in an Elixir project. See docs/tidewave-project-setup.md.
# Usage: tidewave-init [PORT]    # PORT defaults to 4000

set -euo pipefail

PORT="${1:-4000}"
MCP_URL="http://localhost:${PORT}/tidewave/mcp"

if [ ! -f mix.exs ]; then
  echo "Error: mix.exs not found. Run this from an Elixir project root." >&2
  exit 1
fi

echo "==> Tidewave MCP bootstrap for $(basename "$PWD") on port ${PORT}"

if grep -q ':tidewave' mix.exs; then
  echo "  mix.exs already references :tidewave, skipping dep install"
else
  if command -v mix >/dev/null 2>&1; then
    echo "  Installing :tidewave via igniter..."
    mix archive.install --force hex igniter_new >/dev/null 2>&1 || true
    mix igniter.install tidewave --yes
  else
    echo "  mix not on PATH — add {:tidewave, \"~> 0.5\", only: :dev} to mix.exs manually" >&2
    echo "  and plug Tidewave into your endpoint (see docs/tidewave-project-setup.md)" >&2
  fi
fi

if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q '^tidewave'; then
    echo "  Claude Code: tidewave MCP already registered"
  else
    echo "  Registering tidewave MCP with Claude Code (project scope)..."
    claude mcp add --transport http --scope project tidewave "$MCP_URL"
  fi
else
  echo "  claude CLI not found, skipping Claude Code registration"
fi

OC_CONFIG="opencode.json"
if [ ! -f "$OC_CONFIG" ]; then
  cat > "$OC_CONFIG" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tidewave": {
      "type": "remote",
      "url": "${MCP_URL}",
      "enabled": true
    }
  }
}
EOF
  echo "  Created $OC_CONFIG with tidewave MCP"
elif command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg url "$MCP_URL" \
     '.mcp.tidewave = {type: "remote", url: $url, enabled: true}' \
     "$OC_CONFIG" > "$tmp" && mv "$tmp" "$OC_CONFIG"
  echo "  Updated $OC_CONFIG (merged tidewave MCP entry)"
else
  echo "  $OC_CONFIG exists and jq is unavailable — edit it manually:" >&2
  echo '    "mcp": { "tidewave": { "type": "remote", "url": "'"$MCP_URL"'", "enabled": true } }' >&2
fi

NUDGE='## Tidewave MCP

This project exposes Tidewave MCP at /tidewave/mcp on the dev server.
Prefer Tidewave tools over ad-hoc alternatives:

- `project_eval`: run Elixir in the running app instead of writing one-off scripts.
- `execute_sql_query`: query the dev database directly instead of shelling to psql.
- `get_logs`: read recent server logs instead of asking the user for a stacktrace.
- `get_docs` / `get_source_location`: resolve any module or function, including unused deps.
- `get_ecto_schemas`: enumerate schemas when planning migrations or queries.
- `search_package_docs`: search hexdocs restricted to this project'\''s dep versions.
'

if [ -f AGENTS.md ] && grep -q 'Tidewave MCP' AGENTS.md; then
  echo "  AGENTS.md already mentions Tidewave MCP, leaving alone"
else
  printf '\n%s\n' "$NUDGE" >> AGENTS.md
  echo "  Appended Tidewave MCP section to AGENTS.md"
fi

echo ""
echo "Done. Ensure 'plug Tidewave' is in your endpoint's :dev block, start"
echo "mix phx.server, and verify with:"
echo "  curl -sS -o /dev/null -w '%{http_code}\\n' -X POST ${MCP_URL} \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'Accept: application/json, text/event-stream' \\"
echo "    --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}'"
