# 0007. Hardening the opencode sandbox (jean-luc)

## Context

The first working version of `jean-luc` had real holes surfaced by a review. The most serious was a **host-escape vector via the shared cache**: `~/.cache/opencode/` was bind-mounted writable, and that same path is used by host-side opencode. A compromised sandbox could poison `node_modules/` or drop shims in `bin/`; the next unsandboxed `opencode` run would execute them as felix.

Smaller issues compounded: `~/.claude/*` was bound wholesale for both personas (claude creds exposed to opencode); `~/.local/share/opencode/` was fully writable (snapshot/storage could be poisoned to inject into future sessions); `~/.config/opencode/` had no parent ro-bind (agent could drop sibling config files at runtime).

## Decision

### Per-persona scoping of `~/.claude`

Each persona gets only what it actually needs from `~/.claude`:

- **claude**: full access (Claude CLI's own home).
- **opencode**: only `.credentials.json` (ro, for the plugin) and `skills/` (ro, for skill discovery). No `~/.claude.json`.

Persona is auto-detected from the command basename; unknown basenames error out (fail-closed).

The plugin's `writeBackCredentials()` EROFSes on the ro credentials file, catches silently, and opencode persists refreshed tokens to its own `auth.json`. The stale-but-valid refresh token on disk keeps working across cold starts until it expires upstream. Accepting that failure mode was cheaper than widening write access.

### Opencode dirs: ro-bind parent + narrow writable carve-outs

Pattern: `--ro-bind` the parent directory (blocks sibling-creation attacks where the agent drops a config file opencode would trust), then `--bind` specific children for writes.

- `~/.config/opencode/`: fully ro. All contents are nix-managed symlinks.
- `~/.local/share/opencode/`: writable only for `auth.json`, the sessions DB files, and `log/`. `snapshot/` and `storage/` are per-session tmpfs overlays, so opencode's undo works within a session but can't poison future ones. `tool-output/` stays ro.
- `~/.cache/opencode/`: fully ro. Stale `models.json` is cheap; host-escape via `node_modules`/`bin` poisoning is not.

### PATH inheritance

Prepend the launching shell's `$PATH` to the hardcoded sandbox base so direnv, `nix develop`, and `devenv shell`-activated toolchains work inside. Bwrap only binds `/nix/store`, `~/.nix-profile`, `/run/current-system`, and `PROJECT_DIR`, so paths that don't exist under those fail with ENOENT regardless of what's on `$PATH`. The one net-new vector is `PROJECT_DIR/.bin` via direnv, equivalent to "I trust this project's `.envrc`", already a host-level concern.

## Consequences

- Host-escape via cache poisoning, cross-persona token exposure, cross-session snapshot/storage poisoning, sibling-config injection: all closed.
- LSPs inside `jean-luc` come only from `home.packages` or an activated flake/devenv in the launching shell. No auto-fetching into a writable cache. Intentional.
- The stale refresh token on `~/.claude/.credentials.json` will eventually expire. When that happens, re-auth from the host. Rare enough to not be worth engineering around.

## Dead ends

- `~/.cache/opencode/` with a writable tmpfs overlay populated with the host's contents: would restore the undo/history feature at the cost of the cache being reseeded from a potentially poisoned host state. Ro-binding is simpler and strictly safer.
- Carving out `~/.cache/opencode/packages/` as writable (so LSPs can auto-install): gives up the closed-loop fail-safe for LSP/plugin fetches. Pre-installing LSPs via nix is better.
