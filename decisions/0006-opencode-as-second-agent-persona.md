# 0006. Opencode as a second agent persona (jean-luc)

## Context

Opencode alongside (not replacing) Claude Code. Two things needed thought:

1. Opencode's TUI doesn't accept `--dangerously-skip-permissions`; that flag exists only on `opencode run`. The sandboxed workflow needs unsupervised operation.
2. The `opencode-claude-auth` plugin is what routes opencode through the Claude Code billing path. Without it, requests show the "third-party app / $200 credit" notice and draw from pay-as-you-go usage instead of my plan.

## Decision

### Supervised-but-permissive via a `yolo` agent

Instead of a CLI flag, define a yolo agent in markdown with every permission set to `allow` except `doom_loop: ask` (so runaway loops can still be broken with Esc). Launch it via the alias.

### Plugin as a local-plugin re-export, not an npm fetch

The nixpkgs derivation lags upstream, and old plugin versions still emit the third-party notice. Override the plugin's `src` to fetch the prebuilt tarball directly from the npm registry, not from the GitHub source, which switched to pnpm and can't be driven by `buildNpmPackage`.

To avoid opencode's runtime npm fetch entirely, `opencode.json` has no `"plugin"` field. Instead, a tiny local-plugin file in `~/.config/opencode/plugins/` re-exports from the nix store path:

```js
export { ClaudeAuthPlugin, default } from "/nix/store/.../opencode-claude-auth/dist/index.js";
```

Version bumps are a `home.nix` edit. Prefetch the new tarball with `nix-prefetch-url --unpack https://registry.npmjs.org/opencode-claude-auth/-/opencode-claude-auth-<ver>.tgz` and convert the hash with `nix-hash --to-sri`.

### Nix-managed opencode config

Everything under `~/.config/opencode/` is a nix-store symlink (sourced from `dotfiles/opencode/`): yolo agent, TUI keybinds, the plugin re-export, and opencode's own config file. Manual edits to those paths fail. The config file itself is minimal, only the `alejandra` formatter override, because opencode's built-in formatter for `.nix` is `nixfmt` which I don't use.

### OPENCODE_DISABLE_LSP_DOWNLOAD

Set to `true` in the sandbox. LSPs that opencode would otherwise auto-install land in `~/.cache/opencode/packages/`, which is ro inside the sandbox anyway (see 0007). Fail-closed. Project LSPs come from `home.packages` or a project flake/devenv activated in the launching shell.

## Consequences

- `variant: high` in the agent is applied on API calls from the first request, but opencode 1.4.3's TUI doesn't render the variant label in the status bar until you cycle with ctrl+t once. Cosmetic only; the API behavior is already correct.
- Opencode's built-in formatter discovery means `mix format`, `prettier`, `shfmt`, `ruff` etc. work automatically as long as the tool is on PATH. Only `alejandra` needs an explicit override because I prefer it to nixfmt.
- Skills come from `~/.claude/skills/` (Claude-format, auto-discovered). That directory is ro-bound in `jean-luc`; skills are trusted code (model instructions with bash access) and shouldn't be writable from inside the sandbox.
- `display_thinking` keybind (`ctrl+o`) toggles thinking-block visibility in the TUI but does **not** enable thinking on the API side; that's the variant's job.

## Dead ends

- Bumping `opencode-claude-auth` via `overrideAttrs` plus `buildNpmPackage`: upstream dropped `package-lock.json` in favor of `pnpm-lock.yaml`, and `buildNpmPackage` requires an npm lockfile. Building from source would need a full pnpm toolchain plus handling the `@opencode-ai/plugin` peer dep.
- Leaving opencode to fetch the plugin from npm at startup: works, but means runtime state in `~/.cache/opencode/packages/` that's impossible to sandbox cleanly (see 0007) and gives up version pinning.
