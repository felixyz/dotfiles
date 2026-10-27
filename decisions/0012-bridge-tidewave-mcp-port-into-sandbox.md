# 0012. Bridge the tidewave MCP port into sandboxed agents

## Context

decisions/0009 left port bridging to the user via `.sandbox/allowed-ports`. Every Tidewave-launched session needs `:9832`, the tidewave-cli MCP socket that carries the browser tools, regardless of project. Forgetting it surfaces only as "Tidewave-Web MCP not connected" inside the sandbox.

## Decision

The `tidewave-*-sandboxed` wrappers export `BWRAP_EXTRA_PORTS=9832`. `bwrap-sandbox` merges it with the per-project file, dedupes, and starts one socat bridge per port. Only Tidewave-launched sessions get it; `jean-claude` / `jean-luc` do not.

Known cost: tidewave-cli serves an unauthenticated host file API on the same port (`/read`, `/write`, `/delete`, `/mkdir`, `/move`, `/copy`), so an agent with `:9832` bridged can read and write anything the user can. This is a sandbox bypass, accepted because the Tidewave browser tools are the point of those sessions.

Do not bridge `:9222` (Chrome DevTools) the same way: it gives full control of the host browser, including logged-in sessions, and an unfiltered exfiltration path around the squid allowlist.

## Consequences

- The app port (typically `:4000`) still needs a `.sandbox/allowed-ports` entry.
- Amends the "Port bridging stays the user's responsibility" section of decisions/0009 for the MCP port only.

Superseded by decisions/0019, which filters `:9832` instead of bridging it raw.
