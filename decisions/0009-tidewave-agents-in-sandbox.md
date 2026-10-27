# 0009. Sandbox tidewave-spawned agents

## Context

`tidewave-cli` (decisions/0008) spawns claude via `claude-agent-acp` and
opencode via the cached download shim. By default both run on the host
with full filesystem and network access — strictly weaker than the user's
interactive `jean-claude` / `jean-luc`, which always run inside
`bwrap-sandbox`. The threat models are the same (an LLM driving tools);
the boundary should be too.

## Decision

**Wrap the agent binaries, not the JS bridge or tidewave itself.** The
sandbox boundary is at the claude/opencode binary, the same point as the
interactive aliases. `CLAUDE_CODE_EXECUTABLE` (already used to override
the SDK's bundled binary, decisions/0008) repoints to a wrapper that
`exec`s `bwrap-sandbox claude`. The opencode download-cache shim is
swapped for an analogous wrapper. The bun shim is left untouched — bun
runs the JS bridge that *itself* invokes the wrapper via
`CLAUDE_CODE_EXECUTABLE`; sandboxing bun would force npm fetches through
the squid allowlist and break the bunx fetch path.

**Wrappers walk up to the nearest `.sandbox/` ancestor before invoking
`bwrap-sandbox`.** Tidewave Web pins session cwd at whatever path the
user typed in the project picker — often a subapp like
`/code/foo/ui` — but the user-declared umbrella root (where
`.sandbox/allowed-hosts` and `.sandbox/allowed-ports` live, and what
should be the writable bind mount) is one or more levels up. The
wrappers walk up until they find a directory containing `.sandbox/`,
`cd` there, and only then `exec bwrap-sandbox`. Falls through to
current cwd if no marker is found. `bwrap-sandbox.sh` itself stays
unchanged — interactive `jean-claude`/`jean-luc` users who do
`cd subapp && jean-claude` to deliberately scope tighter still get the
narrower root.

**Otherwise wrappers are plain passthroughs.** The probe (CLAUDE_CODE_EXECUTABLE
pointed at a logging shim, with the user opening a real Tidewave session)
revealed two things that keep them simple:

- The JS bridge already `chdir`s to the session's project root before
  spawning claude (`cwd: /code/truthtable/ui` in the probe log; parent
  cmdline `node .../claude-agent-acp` and grandparent `bun x ...` both
  agree). So `bwrap-sandbox`'s `$(pwd)` is the project root with no extra
  plumbing — it enforces the existing project-root allowlist as-is.
- Tidewave already passes `--allow-dangerously-skip-permissions`,
  `--permission-prompt-tool stdio`, `--permission-mode default`, and an
  MCP config in argv. The SDK's permission loop is wired to Tidewave Web,
  not to the CLI. Injecting `--dangerously-skip-permissions` (as the
  `jean-claude` alias does) would either be redundant or conflict with
  the SDK's setup. Wrappers forward argv unchanged.

**Port bridging stays the user's responsibility.** Inside the sandbox
(`--unshare-net`), claude can only reach host TCP ports listed in the
project's `.sandbox/allowed-ports` (or added at runtime via
`bwrap-allow-port`). Tidewave-spawned agents need *two* localhost
endpoints bridged, not just one:

- The per-project Phoenix dev server (typically `:4000`) for the
  `/tidewave/mcp` plug.
- **`:9832`, the tidewave-cli MCP socket itself** — claude is launched
  with an MCP config pointing at
  `http://127.0.0.1:9832/socket/mcp-remote-client?sessionId=...`, and
  the Tidewave-Web MCP tools depend on that connection.

The user manages `.sandbox/allowed-ports` per project for the app
port; nothing in home.nix or `tidewave-init.sh` writes ports
automatically. Documented here so the requirement is explicit when a
session reports "Tidewave-Web MCP not connected" inside the sandbox.

Amended by decisions/0012, which bridges `:9832` automatically.

Superseded in part by decisions/0019.

## Consequences

- Threat-model parity with `jean-claude` / `jean-luc`: same persona-scoped
  `~/.claude` mounts (decisions/0007), same domain allowlist, same
  `--unshare-net`, same writable PROJECT_DIR. Cross-persona credential
  isolation still holds.
- Squid stderr leaks into the JS bridge's stderr (and so into tidewave
  journal logs). Cosmetic; doesn't break JSON-RPC.
- `--die-with-parent` means `systemctl --user restart tidewave` kills any
  active sandboxed sessions hard. Same as host-side restarts of
  long-running agents — accept it.
- The probe disproved the prior assumption that tidewave-cli's
  `WorkingDirectory=/home/felix` would propagate to the spawned ACP
  process. The chdir happens later in the chain (bun or the JS bridge),
  so wrappers don't need to reconstruct project context from env or
  argv. If a future tidewave-cli release changes the spawn path and the
  cwd reverts to `$HOME`, `bwrap-sandbox` will fail-closed at L42-55 —
  which is the right outcome (better than mounting `$HOME` writable).

## Dead ends

- Auto-writing the per-project Phoenix port to `.sandbox/allowed-ports`
  in `tidewave-init.sh`: rejected because the port varies across
  projects and the user already maintains those files manually. The MCP
  port (`9832`) is bridged by every Tidewave-launched session instead
  (decisions/0012).
- `BWRAP_ALLOW_ANY_DIR=1` as a fallback for sessions launched outside
  the project-root allowlist: would defeat the safety check exactly when
  it matters (a sandbox rooted at `$HOME` mounts `$HOME` writable).
  Fail-closed instead.
