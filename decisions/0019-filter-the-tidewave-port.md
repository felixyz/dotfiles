# 0019. Filter the tidewave-cli port instead of bridging it raw

## Context

decisions/0012 bridges `:9832` into every Tidewave-launched sandbox with a plain socat, and accepts that the port also serves tidewave-cli's file API. The port serves more than files. tidewave-cli 0.4 also has `/shell`, `/cmd`, `/open`, `/proxy`, `/download`, and a terminal channel on `/socket/websocket`, all for the Tidewave Web page in the user's browser. tidewave-cli runs on the host as the user, and its only check is the Origin header, which a request without one passes. So a sandboxed agent could read and write any file the user can, and run any command. A Tidewave agent showed this by reading `~/Documents/gec_elements.csv` with one `curl` to `/read`. The same access can write `~/.config/fish/config.fish` or `home.nix`, which runs the agent's code outside the sandbox. decisions/0009's claim of threat-model parity with `jean-claude` did not hold while that bridge existed.

A request log on the bridge, over one session that called every tool, showed the agent's traffic is MCP Streamable HTTP on a single path:

- `POST /socket/mcp-remote-client?sessionId=…` for `server/discover`, `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, and `notifications/cancelled`
- `GET` on the same path for the SSE stream
- no WebSocket upgrade, no other path
- several requests per connection, each starting right after the previous body

The tools were `browser_eval`, `create_design_canvas`, `restart_app_server`, `task_create`, `task_get`, `task_list`, and `task_update`. `create_design_canvas` takes a `path` from the agent and writes Tidewave's canvas template there on the host. A call with `/tmp/tidewave-tool-check-canvas.html` created that file outside the sandbox, owned by the user.

## Decision

**`bwrap-sandbox` bridges `:9832` through `tidewave-mcp-filter`, a small HTTP proxy, instead of socat.** It parses every request on a connection and passes the response back unchanged, so SSE streams as before. It refuses, with a 403 and a JSON-RPC error, and closes the connection when:

- the method is not `GET`, `POST`, or `DELETE`, or the target is not exactly `/socket/mcp-remote-client?sessionId=<alphanumeric>`
- the head has a bare CR or LF, `Transfer-Encoding`, `Upgrade`, `Expect`, a repeated or non-numeric `Content-Length`, or a body over 1 MiB
- a `POST` body is not a single JSON object with unique keys
- the JSON-RPC method is not one of those seen in the log, plus `ping` and `notifications/roots/list_changed`
- a `tools/call` names a tool not in the list above
- `create_design_canvas` gets a path outside the sandbox's project root, or one that resolves through a symlink or `..`

Refusals are logged to stderr, which for Tidewave sessions lands in the tidewave journal.

Every route into `:9832` goes through the filter. `.sandbox/allowed-ports` gets the filter too, the devenv route bridges skip the port, and `bwrap-allow-port 9832` is refused.

**`create_design_canvas` stays allowed inside the project.** The canvas is useful, and the agent can already write anything in the project itself.

## Consequences

- A new Tidewave tool or MCP method is refused until it is added to the lists in `scripts/tidewave-mcp-filter.py`. The refusal message names it.
- The symlink check races with the agent. An agent can replace a checked file with a symlink between the filter's check and tidewave-cli's write, and tidewave-cli follows it as the user. That writes Tidewave's fixed template over one file outside the project. The agent cannot choose the content, so this cannot run its code. Accepted.
- On a refused request, the response to an earlier request on the same connection may be lost, since the filter closes the connection.
- The browser reaches `localhost:9832` directly, not through the bridge, so the Tidewave Web page keeps its file, shell, and terminal access.
- Other local processes can still use the whole API, since a request without an Origin header passes. Processes running as the user can do the same things without it. tidewave-cli refuses web pages from other origins.

## Dead ends

- Not bridging `:9832`. That loses the browser tools, which are the point of Tidewave sessions.
- Checking only the first request line of a connection. The agent's client reuses connections, so a second request on the same connection would skip the check.
- Running tidewave-cli as a separate system user. That limits the file API to what that user can read, but it costs a second Claude login, mixed file ownership in `/code`, and the devenv control socket. Filtering closes the sandbox hole without any of that.
- Blocking `create_design_canvas`. Rejected because the tool is useful.
