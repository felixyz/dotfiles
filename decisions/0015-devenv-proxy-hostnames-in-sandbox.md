# 0015. Reach devenv proxy hostnames from the sandbox

## Context

devenv's process proxy (devenv 2.3+) serves each dev server at a stable `<name>.localhost` on host `127.0.0.1:80` and routes by Host header to whatever port the process was allocated. Projects point their Tidewave MCP URL at that hostname so the URL survives port moves. Inside the sandbox the URL fails with ECONNREFUSED: clients connect straight to `127.0.0.1:80` in the sandbox's own network namespace, where nothing listens, and an unprivileged process cannot bind a port below 1024 there.

Bridging host port 80 into the sandbox the way `.sandbox/allowed-ports` bridges app ports would hand every sandbox every project behind the proxy. honey_ops serves Livebook with `LIVEBOOK_TOKEN_ENABLED=false`, attached to its Phoenix node, so any sandbox could run code on the host through `livebook.honeyops.localhost`.

## Decision

**Port 80 in the sandbox leads to a hostname filter, not to the devenv proxy.** The per-sandbox squid gets a second, reverse-proxy (`accel vhost`) port whose only peer is the devenv proxy. It forwards a request only when the Host header is a `.localhost` name in the session's allowlist snapshot. An inner socat on sandbox `127.0.0.1:80` reaches that port through a unix socket, like every other bridge.

**The sandbox's network namespace is created before bwrap.** `unshare --user --net --keep-caps` creates it, brings up `lo`, and lowers `net.ipv4.ip_unprivileged_port_start` to 80 in it. `setpriv` then drops every capability before exec'ing bwrap, which no longer passes `--unshare-net`. Inside, no process holds a capability, the sysctl cannot be changed back, and ports below 80 stay privileged. bwrap's own `--cap-add CAP_NET_BIND_SERVICE` does not work for this: the capability shows up in the sandbox, but bind(80) still fails with EACCES. That was observed from a nested bwrap and is untested on the host directly.

**Allowlist entries for `.localhost` must be exact hostnames.** `localhost`, `.localhost`, `*.localhost`, and subdomain wildcards such as `.honeyops.localhost` are dropped at snapshot time with a warning, and `bwrap-allow-host` refuses them. A project lists each hostname it may reach.

**Ports 80, 443, and the devenv proxy's own port are never bridged raw.** `.sandbox/allowed-ports`, `BWRAP_EXTRA_PORTS`, and `bwrap-allow-port` refuse them, since a raw bridge would skip the filter.

**The dev server's own port follows its route.** As observed from a Tidewave-launched session, Tidewave Web reads `local_port` from the dev server's `/tidewave/config` and points the agent it launches at `http://localhost:<local_port>/tidewave/mcp`. Every 2 seconds the launcher sends `{"command":"list"}` to the devenv proxy's control socket (`$XDG_RUNTIME_DIR/devenv/proxy.sock`, or `DEVENV_PROXY_SOCKET`). For each route whose hostname is an allowed `.localhost` name and whose upstream is on loopback, it bridges the upstream port into the sandbox. A bridge whose port no longer backs an allowed route is removed. This reaches exactly the servers the hostname filter reaches, so `.sandbox/allowed-ports` is not needed for a devenv-proxied dev server. The control socket can register routes, so it stays outside the sandbox. `/run/user` is a tmpfs inside.

Supporting pieces:

- `.localhost` joins `NO_PROXY`, so clients that match NO_PROXY entries exactly still connect directly. NO_PROXY is not a boundary. A direct connection can only reach the in-sandbox port 80 and its filter, and the forward squid port denies every `.localhost` name.
- The sandbox's `/etc/hosts` maps each allowed `.localhost` name to `127.0.0.1`, for resolvers that do not special-case the TLD. `bwrap-allow-host` appends to it in running sessions.
- The squid peer follows `DEVENV_PROXY_LISTEN` (default `127.0.0.1:80`). It is read from the shell that starts the sandbox, so a proxy moved off port 80 needs the variable set globally, not only for `devenv up`.

Per project, the hostname appears in `devenv.nix` as `proxy.hostname` and in the MCP URL, and once in `.sandbox/allowed-hosts`. No port appears anywhere, and the sandbox and `devenv up` can start in either order. Requests made before `devenv up` get a 502. When the devenv proxy itself starts after the sandbox, the first request through it can fail too, and later ones succeed.

## Consequences

- When a port passes from one project's route to another's, the old bridge can stay up for up to 2 seconds.
- The filter keeps per-project scoping for `jean-claude` and `jean-luc` sessions. Tidewave-launched sessions already reach tidewave-cli's host file API on `:9832` (decisions/0012), so for them the filter is not the weakest link.
- decisions/0004 still holds. The sandbox has no route to the host network, only the bridges.
- HTTPS through the devenv proxy (`proxy.https.enable`) is not reachable. MCP URLs use `http://`. Whether the proxy redirects plain HTTP to HTTPS for such hosts is unverified, and if it does, those projects keep a port URL.

## Dead ends

- Forwarding `.localhost` names through the existing forward squid port, by dropping `localhost` from NO_PROXY and giving squid a hosts file. It depends on every client honouring HTTP_PROXY for loopback names. Claude Code's MCP client connected directly regardless.
- One fixed high port for the devenv proxy, bridged raw. Works without the netns step, but puts a port in every URL and has no Host filter.
