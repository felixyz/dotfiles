# 0013. Vendor the devenv package until nixpkgs ships 2.3

Status: retired 2026-09-25. The `nixpkgs-latest` pin reached devenv 2.3.1, whose recipe builds `devenv-proxy`, and the override was removed.

## Context

devenv 2.3 (2026-09-07) adds the localhost process proxy, which honey_ops enables via `process.proxy.enable`. The `nixpkgs-latest` pin ships 2.2.2. The upstream bump, NixOS/nixpkgs#560896, is open but unmerged, and even that recipe builds only the `devenv` and `devenv-run-tests` crates. `devenv up` then fails with "devenv-proxy is missing from the devenv installation" whenever the proxy is enabled, because the CLI looks for `devenv-proxy` next to its own binary.

## Decision

Carry the PR's `package.nix` as `pkgs/devenv.nix`, built with `callPackage` from the `nixpkgs-latest` base and substituted for `devenv` in that set. Two deltas from the PR, both mirroring upstream's own `nix/workspace.nix` and `nix/crate-config.nix`:

- `-p devenv-proxy` in `cargoBuildFlags`, so the proxy lands in `$out/bin`.
- `OPENSSL_NO_VENDOR = "1"`, because pingora pulls in openssl-sys with its vendored feature, and building OpenSSL from source needs perl.

Removal condition: when the pin's `devenv.version` is 2.3 or later and the nixpkgs recipe ships `devenv-proxy`, delete `pkgs/devenv.nix` and the override in `home.nix`. The update-agents skill carries the reminder.

## Alternatives

- devenv's own flake, `github:cachix/devenv/v2.3#devenv`, with the devenv.cachix.org substituter. Prebuilt, so no hour-long local build of the nix 2.35 fork. Rejected for now because `home.nix` is not a flake yet (docs/flake-migration-plan.md phase 3 covers exactly this) and the substituter is not configured. Revisit when the flake migration lands.
- `overrideAttrs` on `nixpkgs-latest.devenv`. Cannot reach the version, the source hash, or the bundled nix fork revision, which live in a `let` inside the recipe.
