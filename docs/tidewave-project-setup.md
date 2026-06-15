# Tidewave per-project setup (agent instructions)

Audience: coding agents (Claude Code, OpenCode) running inside an Elixir project.
Goal: wire this project to Tidewave MCP so you can use `project_eval`,
`execute_sql_query`, `get_logs`, `get_docs`, `get_source_location`,
`get_ecto_schemas`, and `search_package_docs` instead of greping and
shelling out.

The host-level Tidewave CLI is already installed and running on
`http://localhost:9832` via systemd user service `tidewave.service`. Do not
try to install or start it.

## Preflight: detect the project shape

Run these detections before editing anything. Use them to pick the right
branch below.

1. Elixir project? `test -f mix.exs` must succeed. If not, abort — this
   recipe is Elixir-only.
2. Phoenix? `grep -q ':phoenix' mix.exs`. If yes: Phoenix branch. If no:
   non-Phoenix Elixir branch (plain Bandit).
3. Umbrella? `test -d apps && grep -q 'apps_path' mix.exs`. If yes, the
   `:tidewave` dep and the endpoint plug go into the web sub-app, not the
   umbrella root.
4. Dev server port. Default for Phoenix is `4000`. Confirm by reading
   `config/dev.exs` for `http: [..., port: N]` or `PHX_PORT`. Export as
   `PORT` for the rest of this recipe. If ambiguous, ask the user.
5. Containerized? `test -f docker-compose.yml -o -f compose.yaml -o -f
   compose.yml -o -f .devcontainer/devcontainer.json`. If yes, also apply
   the Containers section.
6. Version managers: `test -f flake.nix`, `test -f devenv.nix`, `test -f
   .tool-versions`. These do not change the Tidewave setup but tell you
   how the user runs `mix`.

## Step 1: Add the `:tidewave` hex dep

### Preferred: igniter

```
mix archive.install --force hex igniter_new
mix igniter.install tidewave
```

Igniter edits `mix.exs` and the endpoint module for Phoenix projects.
Verify with step 3.

### Fallback: manual edit

If igniter is unavailable or the project opts out of it, edit `mix.exs`:

```elixir
defp deps do
  [
    # ...existing deps...
    {:tidewave, "~> 0.5", only: :dev}
  ]
end
```

Then `mix deps.get`.

## Step 2a: Phoenix — wire the plug into the endpoint

Open the endpoint module. Usual path: `lib/<app>_web/endpoint.ex`. For
umbrellas: `apps/<app>_web/lib/<app>_web/endpoint.ex`.

Find the line `if code_reloading? do` and insert immediately above it:

```elixir
if Mix.env() == :dev do
  plug Tidewave
end
```

Do not wrap the existing `code_reloading?` block, just prepend. The plug
must run before `Plug.CodeReloader` or tooling breaks.

If the file already contains `plug Tidewave`, skip this step.

### Phoenix LiveView recommendations (optional, do not fail if absent)

If `config/dev.exs` does not already set these, append to it for better
Tidewave Web inspector fidelity (skip silently for LiveView < 1.1):

```elixir
config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true
```

Phoenix 1.8+ enables these by default. Check
`grep -q debug_heex_annotations config/dev.exs` before appending.

## Step 2b: Non-Phoenix Elixir — add a Bandit runner

Add to `mix.exs` deps:

```elixir
{:tidewave, "~> 0.5", only: :dev},
{:bandit, "~> 1.0", only: :dev}
```

Add an alias:

```elixir
defp aliases do
  [
    # ...existing aliases...
    tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
  ]
end
```

The user will run `mix tidewave` to start the MCP server on :4000.

## Step 3: Verify the MCP endpoint is reachable

Before registering it with any agent, start the dev server
(`mix phx.server` or `mix tidewave`) in a separate terminal, or ask the
user to start it if you cannot. Then:

```
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:${PORT}/tidewave/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

Must print `200`. If it prints `000` the server is not running. If it prints
anything else (commonly `404`, `405`), the plug is not wired. Re-check
step 2a/2b.

## Step 4: Register with Claude Code (project scope)

```
claude mcp add --transport http --scope project tidewave \
  http://localhost:${PORT}/tidewave/mcp
```

This writes `.mcp.json` in the repo root. Commit it — the endpoint is
localhost and unauthenticated. Verify:

```
claude mcp list
```

`tidewave` must appear with status `✔ connected` (only when the dev
server is running).

## Step 5: Register with OpenCode (project scope)

Edit or create `opencode.json` in the repo root. Merge into any existing
content (do not overwrite):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tidewave": {
      "type": "remote",
      "url": "http://localhost:4000/tidewave/mcp",
      "enabled": true
    }
  }
}
```

Replace `4000` with the actual `$PORT`. If `opencode.json` already
contains an `mcp.tidewave` entry, update the URL only.

Also commit `opencode.json`.

## Step 6: Nudge the agent to actually use Tidewave tools

Append to (or create) `AGENTS.md` in the repo root:

```
## Tidewave MCP

This project exposes Tidewave MCP at /tidewave/mcp on the dev server.
Prefer Tidewave tools over ad-hoc alternatives:

- `project_eval`: run Elixir in the running app. Use instead of writing
  one-off `Mix.Task` scripts or `iex -S mix -e`.
- `execute_sql_query`: query the dev database directly. Use instead of
  `psql` shelling.
- `get_logs`: read recent server logs. Use instead of asking the user to
  paste stacktraces.
- `get_docs` / `get_source_location`: resolve any module or function
  (including unused deps) before grepping `deps/`.
- `get_ecto_schemas`: enumerate schemas when planning migrations or
  queries.
- `search_package_docs`: search hexdocs restricted to this project's
  exact dep versions.

Rule of thumb: if a question is about runtime state or specific library
APIs, try a Tidewave tool first.
```

If Claude Code has a `CLAUDE.md` in use, duplicate the section there too,
or ensure `CLAUDE.md` includes `@AGENTS.md` so it inherits.

## Containers section (apply only if preflight #5 matched)

Tidewave Web on the host must reach the MCP endpoint at the same URL the
user types into its address bar. This requires host:container 1:1 port
mapping.

### docker-compose

Edit the web service to ensure:

```yaml
services:
  web:
    # ...
    ports:
      - "127.0.0.1:${PORT}:${PORT}"   # same port on both sides
```

Do **not** use `- "${PORT}:${PORT}"` without the `127.0.0.1:` prefix.
Binding to all interfaces exposes the unauthenticated MCP to the LAN.

The Elixir app must listen on `0.0.0.0` inside the container, else
Docker cannot forward to it. In `config/dev.exs`:

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: ${PORT}],
  # ...
```

### devcontainers

Add to `.devcontainer/devcontainer.json`:

```json
{
  "forwardPorts": [${PORT}],
  "portsAttributes": {
    "${PORT}": { "onAutoForward": "silent" }
  }
}
```

If the user wants Tidewave itself running inside the container (stronger
isolation from the host), add a `postCreateCommand` that downloads the
CLI:

```json
"postCreateCommand": "curl -sL -o /usr/local/bin/tidewave https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-$(uname -m)-unknown-linux-musl && chmod +x /usr/local/bin/tidewave",
"postStartCommand": "nohup tidewave --port 9000 > /tmp/tidewave.log 2>&1 &",
"forwardPorts": [${PORT}, 9000]
```

Then the user points their browser at `http://localhost:9000` instead of
`:9832` for this project.

### For "Open in editor" to work from Tidewave Web

When running the app inside a container, set this env var so Tidewave
can translate container-internal paths to host paths:

```yaml
# docker-compose.yml
services:
  web:
    environment:
      TIDEWAVE_HOST_PATH: "${PWD}"
```

Or pass `-e TIDEWAVE_HOST_PATH=$(pwd)` to `docker run`.

## nix flake / devenv notes

No special plumbing needed. The Tidewave plug runs in-process inside
`mix phx.server`, so whatever shell activates `mix` and friends will
pick it up. Confirm that `elixir`, `erlang`, `nodejs`, and
`inotify-tools` are on PATH (devenv's `languages.elixir.enable = true`
or flake's `buildInputs` handle this).

If the project's `devenv.nix` defines a `processes` block that starts
Phoenix, ensure the `PORT` and bind address match the docker-compose
rules above (only relevant if devenv is used together with
containers, which is unusual).

## Rollback

To remove Tidewave from a project:

1. Delete the `{:tidewave, ...}` line from `mix.exs`.
2. Remove the `plug Tidewave` block from the endpoint.
3. `rm .mcp.json` (or delete just the `tidewave` key).
4. Remove the `mcp.tidewave` block from `opencode.json`.
5. `mix deps.clean tidewave && mix deps.unlock tidewave`.

## Known failure modes

- `/tidewave/mcp` returns 200 but tools don't show up in the agent →
  restart the agent. MCP handshakes happen at agent startup.
- `claude mcp list` shows `✘ failed to connect` → dev server is down or
  port is wrong. Restart `mix phx.server` and check `$PORT`.
- Tidewave Web says "Authentication required" for Claude → user has not
  run `claude` and done `/login` yet. Not fixable from inside the
  project.
- Compression-related hangs: some reverse proxies or Bandit configs
  apply gzip that MCP clients mishandle. Verify with the `curl` in
  step 3 and inspect response headers for `transfer-encoding`. If seen,
  disable compression for `/tidewave/*` in the dev server.
- Inside a bwrap sandbox (`jean-claude`/`jean-luc`): port 4000 is not
  auto-bridged. Run `bwrap-allow-port 4000` in a host shell before
  starting the sandboxed agent. Similarly for any custom `$PORT`.
