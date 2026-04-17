# 0004. Domain allowlist network filtering

## Context

The sandbox needs outbound HTTPS to a known set of hosts and nothing else. CIDR-level filtering is impractical because cloud IPs drift constantly, so filtering has to be by hostname.

## Decision

The sandbox has `--unshare-net` (no network interfaces). The only exit is through a unix socket bridged (via socat) to a per-sandbox squid proxy that filters by destination domain. `HTTP_PROXY` inside points at the inner socat.

With no network interface there is literally nothing for a process to bind or connect against. DNS, raw sockets, `--noproxy '*'` all fail uniformly. The filter is structurally unbypassable from inside, not just by policy.

The allowlist in effect for a session is a frozen snapshot built at startup from script defaults plus `~/.config/bwrap-sandbox/allowed-hosts.txt` plus `./.sandbox/allowed-hosts`. Squid reads the snapshot, not the source files, so an agent that gains write access to either file cannot poison the running session. `bwrap-allow-host` and `bwrap-allow-port` append to the persistent files *and* every running snapshot, then SIGHUP the respective squids.

The same unix-socket-plus-socat bridge is reused in reverse for `.sandbox/allowed-ports`: exposing host ports (docker-compose services) into the sandbox without a real network interface.

## Consequences

- HTTPS uses CONNECT tunneling, so squid sees only the hostname, not path/method/body. Allowlisting a domain is trusting everything on it.
- Write-to-allowlisted-host exfil (gist, issue creation) is gated by credentials not being mounted, not by the filter. If you ever bind `~/.config/gh` or similar into the sandbox, revisit the allowlist.
- Under the "server operators are honest" threat model, URL-path exfil on GET-only hosts (raw.githubusercontent.com, npm registry) is not a real concern.
