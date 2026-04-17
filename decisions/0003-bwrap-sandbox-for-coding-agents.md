# 0003 — bwrap-sandbox wrapper for coding agents

## Context

Coding agents need the project directory, their auth files, and outbound HTTPS to a known set of hosts. Everything else (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/gh`, `~/.npm`, `~/.cargo`, browser profiles) should be invisible.

Claude Code's own `/sandbox` only gates bash; its other tools (WebFetch, Read) bypass it, and `--dangerously-skip-permissions` disables it entirely. Not sufficient.

## Decision

Generic `bwrap-sandbox <command>` wrapper. Per-persona scoping via a small `case` branching on `BWRAP_PERSONA` (which auto-detects from the command basename). Aliases `jean-claude` and `jean-luc` invoke it.

PROJECT_DIR is an allowlist: `~/code`, `~/dotfiles`, `/code` by default; `BWRAP_ALLOW_ANY_DIR=1` overrides. Pointing the sandbox at `~/.ssh` would bind-mount keys writable for the agent. The principle is fail-closed, not enumerate-dangers.

Tool-state dirs (`~/.mix`, `~/.npm`, `~/.cargo`, `~/.config/gh`) are never mounted. `MIX_HOME` and `HEX_HOME` redirect to the project so first-run installs don't touch `~/.mix` where hex tokens live.

`PATH` inside the sandbox is the launching shell's `$PATH` prepended to a hardcoded base. This lets direnv, `nix develop`, and `devenv shell`-activated toolchains reach inside. Worst-case analysis: bwrap only binds `/nix/store`, `~/.nix-profile`, `/run/current-system`, and `PROJECT_DIR`, so a poisoned path on host `$PATH` that doesn't live in one of those fails with ENOENT. The one residual vector is `PROJECT_DIR/.bin` via direnv, equivalent to "I trust this project's `.envrc`", already a host-level concern.

## Consequences

- This is defense in depth for accidents and prompt-injection, not a barrier against a sophisticated attacker with model control.
- Wayland socket is ro-bound so image paste works. Tradeoff: any Wayland client in the sandbox can read and write the clipboard (passwords if copied, injectable paste content). Wayland's own isolation blocks keylogging and screenshots. Acceptable on a single-user dev machine.
- Claude Code has hardcoded Datadog telemetry (`http-intake.logs.us5.datadoghq.com`). Not on the allowlist, silently blocked. Incidental win.

## Dead ends

- Relying on `HTTP_PROXY` env vars alone for network filtering: honoring them is up to each process. `curl --noproxy '*'`, raw sockets, anything that doesn't read the env var bypasses the filter entirely. Needs `--unshare-net` to be real enforcement (see 0004).
- `exec bwrap`: replaces the shell, cleanup trap never fires. Must run as a child.
- `--new-session`: disconnects from the controlling terminal, breaks interactive TUIs.
- Per-domain socat port forwarding (no proxy): TLS SNI conflicts, port collisions, more complex than squid for equivalent effect.
