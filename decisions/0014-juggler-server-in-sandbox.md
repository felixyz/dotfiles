# 0014. Sandbox the juggler server, not the agents it spawns

## Context

Juggler (https://github.com/juggler-ai/juggler) is a multi-agent coding harness with a web UI. It drives Claude Code through its native provider and other agents over ACP (Agent Client Protocol). It has to run under the same sandbox as `jean-claude` and `jean-luc`.

The obvious move, decisions/0009 again, is to point juggler at wrappers that `exec bwrap-sandbox claude` and `bwrap-sandbox opencode`. That does not work for the Claude Code provider. Juggler spawns `claude -p` with every native tool on `--disallowedTools` and only `mcp__juggler__*` allowed, and serves those tools itself over an in-process MCP server. File reads, edits, and shell commands run inside the juggler server process. The claude subprocess is only the model client, so sandboxing it contains nothing that touches the filesystem.

For ACP agents the boundary would hold today, because juggler's ACP client declines the `fs` and `terminal` capabilities and the agent runs its own tools. The provider's own doc calls that phase one and plans to route `fs/*` and `terminal/*` through juggler's ops later, which would silently hollow the boundary out on an upgrade.

## Decision

**The sandbox boundary is the juggler server.** `jean-juggler` runs `bwrap-sandbox juggler` from the project directory, one instance per project. Claude and opencode are spawned inside the sandbox and need no wrappers. Juggler finds `claude` on PATH and `opencode` through a nix-managed `~/.config/juggler/acp.json` entry running `opencode acp`.

**A `juggler` persona that is the union of the claude and opencode mounts**, plus `~/.config/juggler`, `~/.cache/juggler`, and `~/.local/state/juggler` writable. One instance can switch between both agents. The claude mounts are already the more permissive set, so the union adds only opencode's auth file, sessions database, and log directory.

**Inbound port bridging.** Until now every bridge ran sandbox to host. The web UI listens on `127.0.0.1:3939` inside the sandbox's network namespace, so `BWRAP_EXPOSE_PORTS` adds the reverse direction, host `127.0.0.1:3939` to the sandbox, over a unix socket in a writable subdirectory of the sandbox runtime dir. The browser, or `juggler-app --url http://127.0.0.1:3939` on the host, connects through it. A second sandboxed juggler fails at startup because the host port is taken, rather than silently attaching to the first.

**Built from source** as `pkgs/juggler.nix` from the `nixpkgs-latest` pin, which has Go 1.26 and WebKitGTK 6.0. The package puts Node 22 on juggler's PATH, so the server runs its engine in a Node child process and never opens a WebKitGTK webview.

## Consequences

- `opencode acp` has no `--agent yolo`. Tool permissions go through juggler's own approver.
- `acp.json` is a store symlink, so juggler's settings tab cannot edit it. Add agents in `home.nix`.
- Juggler runs on the sandbox's network. Its update check and any provider API it talks to go through the squid allowlist. `juggler.studio` is in the built-in list.
- `juggler-app` is packaged but unsandboxed. Run it against a `jean-juggler` server with `--url`. Launched without `--url` it spawns an unsandboxed server on the host.

## Dead ends

- `JUGGLER_CLAUDE_PATH` pointing at a sandboxed wrapper. Juggler honours it, but see Context for why it protects nothing.
- Claude over ACP via `claude-agent-acp`, as tidewave does. Loses the native provider, which is the point of trying the harness.
