# 0016. OpenChamber on a separate OpenCode v2, in its own sandbox persona

## Context

OpenChamber (https://github.com/openchamber/openchamber) is a web UI over an OpenCode server. It requires OpenCode 2.0.20 or newer and refuses 1.x. OpenCode v2 is a separate release line, published as `@opencode/cli`, while nixpkgs and `jean-luc` follow the 1.x line published as `opencode-ai`.

v2 converts the existing `opencode.json` and agents without changes, and Tensorix works. The `opencode-claude-auth` plugin does not. v2 lists it but exposes no Anthropic models, and upstream tracks v2 support as open issues #245 and #290. An agent pinned to an Anthropic model runs on the default model instead, with no error.

v1 and v2 both keep sessions and auth in `~/.local/share/opencode`. OpenChamber ships code that imports v1 sessions into v2's tables.

## Decision

**Package v2 next to v1, not instead of it.** `pkgs/opencode2.nix` fetches `@opencode/cli-linux-x64` byte-identical, as decisions/0010 does for claude-code. It is not on PATH. The `openchamber` FHS env is its only user, through `OPENCODE_BINARY`.

**OpenChamber is built from the npm tarball** with a lockfile generated from its `package.json` minus devDependencies, kept in `pkgs/openchamber/`. Install scripts are skipped, so node-pty uses the prebuilt binary it ships instead of compiling. The FHS env supplies the loader and libstdc++ the prebuilt native modules need.

**A fourth sandbox persona, `openchamber`.** The sandbox boundary is the OpenChamber server, as for juggler in decisions/0014, since it spawns OpenCode and the terminal. The persona binds `~/.config/openchamber-opencode`, `~/.local/share/openchamber-opencode`, `~/.local/state/openchamber-opencode`, and `~/.cache/openchamber-opencode` at the paths opencode uses, so v2 inside the sandbox never sees v1's config, sessions, or auth. `~/.config/openchamber` holds OpenChamber's own state.

**The v2 config holds only `opencode.json`**, the same file v1 uses. The claude-auth plugin and the yolo agent are left out, because neither works on v2.

**Relay and self-update are off by default.** The wrapper sets `OPENCHAMBER_RELAY_HOST=off` and `OPENCODE_DISABLE_AUTOUPDATE=1`, both overridable.

## Consequences

- Only Tensorix and other API-key providers are available in OpenChamber until `opencode-claude-auth` supports v2.
- `jean-chamber` serves the UI at `http://127.0.0.1:3940`. Juggler keeps 3939.
- The v2 config, data, and cache dirs are writable inside the persona. v2 writes `service.json` and `cli.json` into its config dir, and its cache dir has a `bin` subdirectory. A compromised agent could plant a plugin there that later OpenChamber sessions load. v1 sessions are unaffected.
- `opencode.json` in the v2 config dir is a store symlink, so editing the global config from OpenChamber's settings fails. Change it in `opencode/config.json`.
- Running `openchamber` outside `jean-chamber` uses the real `~/.config/opencode` and `~/.local/share/opencode`, shared with v1.
- Bumping OpenChamber means regenerating the lockfile and `npmDepsHash`. See the update-agents skill.

## Dead ends

- `XDG_DATA_HOME` and friends on the OpenCode wrapper, to separate v1 and v2 data. They are inherited by every command the agent runs, so git and other tools would read the wrong config.