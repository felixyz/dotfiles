# 0008. Tidewave MCP for Elixir projects

## Context

Tidewave is two pieces: a host daemon (browser UI + agent broker) and a per-project `{:tidewave, "~> 0.5"}` plug that exposes `/tidewave/mcp` on the dev server. Both are needed together.

## Decision

**CLI as a systemd user service, not the menu-bar desktop app.** Tidewave usually installs an interactive tray-icon app; we run the container-oriented CLI as an always-on localhost daemon. Trade-off: no Settings UI, bumps happen in `home.nix`.

**Shim the download cache instead of setting `TIDEWAVE_*_EXECUTABLE`.** When an ACP agent fails to launch on NixOS the UI suggests setting env vars like `TIDEWAVE_OPENCODE_EXECUTABLE` and `TIDEWAVE_CLAUDE_AGENT_ACP_EXECUTABLE`. **CLI v0.4.3 ignores them**, observed both via `systemctl show -p Environment` (env was set) and via `--debug` logs (the process still spawned the cached download path). Instead, `home.file.".cache/tidewave/downloads/<asset-name>"` materializes wrapper scripts at the exact hardcoded paths, forwarding to the nix-profile binaries. If a `tidewave-cli` bump adds new "cannot execute" errors, add the new filename. OpenCode shim is direct; bun is also direct because Tidewave invokes it `bun x --bun @agentclientprotocol/claude-agent-acp@<ver>` to fetch and run the ACP bridge from npm, and bun-from-nix handles that initial step identically to the bundled bun.

**`CLAUDE_CODE_EXECUTABLE` overrides the bundled SDK binary.** From `@anthropic-ai/claude-agent-sdk@0.2.119` onward the SDK prefers a bundled native `claude` over PATH; that binary doesn't run on NixOS. Unlike `TIDEWAVE_*_EXECUTABLE`, this env var *is* honored — it's read inside the ACP bridge's JS (`claudeCliPath()`), not by tidewave-cli.

**Musl CLI, not the AppImage.** AppImage needs `appimage-run` on NixOS; the static musl binary runs unpatched.

**`tidewave_app` versions independently of the `:tidewave` hex package.** App sits at 0.4.x, plug at 0.5.x. Don't assume they move together when bumping.

**Per-project MCP registration, not global.** A global entry in `~/.config/opencode/opencode.json` or Claude's user config makes every agent start in every repo attempt a connection, producing timeouts in non-Elixir projects. `scripts/tidewave-init.sh` handles the per-project bootstrap.

**Container 1:1 port mapping.** `-p 127.0.0.1:4000:4000`, not an arbitrary remap. Tidewave Web can only find the MCP if the URL the user types matches the container-internal one.

## Consequences

- Pro features require a GitHub login inside Tidewave Web; that state lives outside nix.
- The shim filenames include the bundled version (`opencode-linux-x64-baseline-musl-1-4-7`, `bun-linux-x64-musl-1-3-10`). If Tidewave bumps either, the old shim goes stale and the agent will fail with a fresh download path. Check `~/.cache/tidewave/downloads/` for the new filename and update `home.nix`.
