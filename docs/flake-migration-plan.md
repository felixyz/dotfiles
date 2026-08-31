# Plan: migrate the dotfiles config to a flake

Goal: convert the current channels + manual-pin setup to a single flake, without a
big-bang rewrite. Each phase leaves the machine in a working, switch-able state and
is independently revertible.

## Facts this plan is built on (from the current config)

- Host: `felix-nixos`. Single machine, `x86_64-linux`.
- System: `configuration.nix` (428 lines), `system.stateVersion = "21.11"`, applied
  from **root channels** (`nixos`, `nixos-hardware`) via `sudo nixos-rebuild switch`.
- Home: `home.nix` (557 lines), **standalone home-manager**, `home.stateVersion =
  "23.11"`, applied from **felix's user channels** via `home-manager switch`.
- Flakes are **already enabled** (`configuration.nix:12-14` sets
  `experimental-features = nix-command flakes`). No bootstrap needed.
- `nixpkgs.config.allowUnfree = true` (system).
- Hardware import is `<nixos-hardware/lenovo/thinkpad/p52>` (channel, angle-bracket)
  plus `/etc/nixos/hardware-configuration.nix` (absolute path, outside the repo).
- Manual pins that flakes will subsume: the `nixpkgs-latest` `fetchTarball`+sha256
  (home.nix:8-11) feeding opencode/devenv/signal-desktop.
- Manual pins that stay as-is: the per-package tarball derivations (`claude-code-bin`,
  `opencode-claude-auth`, `dirge`, `tidewave-cli`) — plain Nix, flake-agnostic.
- Runtime symlink `mkOutOfStoreSymlink "~/dotfiles/nvim"` — unaffected by flakes.

## Key gotchas to design around

1. **Pure eval can't read files outside the flake.** `<nixos-hardware/...>` and
   `/etc/nixos/hardware-configuration.nix` both break under flake eval. Fix: nixos-
   hardware becomes an input; `hardware-configuration.nix` gets **copied into the
   repo** and `git add`ed.
2. **Flakes ignore untracked files.** Everything referenced (incl. the vendored
   hardware config and `flake.lock`) must be `git add`ed or eval silently can't see it.
3. **Two nixpkgs.** Keep the current "second nixpkgs for latest packages" idea, but
   as a second flake input (`nixpkgs-latest`) instead of a hashed `fetchTarball`.
   `allowUnfree` must be set when instantiating it, same as today.
4. **ZFS host needs `networking.hostId`.** It already exists (in the current hardware
   config / system config); vendoring hardware-configuration.nix preserves it. Verify
   it survives the copy.
5. **stateVersions never change.** System stays `21.11`, home stays `23.11`. These
   are migration-safety anchors, not things to "modernize."

## Safety rails (apply to every phase)

- Do the work on a git branch (e.g. `flake-migration`).
- Validate with `nixos-rebuild build --flake .#felix-nixos` (**build, not switch**)
  before any switch — produces `./result` with zero system change.
- Keep the channels installed and untouched until Phase 4. If the flake misbehaves,
  `sudo nixos-rebuild switch` the old channel way still works.
- `nixos-rebuild switch` supports `--rollback`; and the bootloader keeps prior
  generations regardless.

---

## Phase 0 — Prep (no behavior change)

1. Create branch `flake-migration`.
2. Copy the live hardware config into the repo:
   `cp /etc/nixos/hardware-configuration.nix ./hardware-configuration.nix`, then
   `git add` it. Eyeball it for `networking.hostId`, ZFS `boot.zfs`/`fileSystems`,
   and any machine-specific bits.
3. Confirm the flake experimental features are active for the *user* too (they're set
   in system `nix.extraOptions`, so `nix flake` should already work; if not, that's a
   one-line `~/.config/nix/nix.conf`).

## Phase 1 — Flake wrapping the SYSTEM only (home untouched)

Smallest change that gets the system reproducible. Home-manager stays on channels.

1. Write `flake.nix` with:
   - `inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"` (or the channel
     you're effectively on — pick to match current, verify no mass rebuild).
   - `inputs.nixos-hardware.url = "github:NixOS/nixos-hardware"`.
   - `outputs.nixosConfigurations.felix-nixos = nixpkgs.lib.nixosSystem { system;
     modules = [ ./configuration.nix ./hardware-configuration.nix
     nixos-hardware.nixosModules.lenovo-thinkpad-p52 ]; }`.
2. Edit `configuration.nix`:
   - Remove the `<nixos-hardware/...>` and `/etc/nixos/hardware-configuration.nix`
     entries from `imports` (now provided by the flake `modules` list).
   - Everything else stays.
3. `git add -A` (flake needs tracked files).
4. `sudo nixos-rebuild build --flake .#felix-nixos` → inspect `./result`, diff the
   closure against current system (`nvd diff /run/current-system ./result` if `nvd`
   is available) to confirm no surprise rebuilds.
5. When clean: `sudo nixos-rebuild switch --flake .#felix-nixos`.

**Exit state:** system is flake-driven; `flake.lock` pins nixpkgs + nixos-hardware.
Home-manager still on channels (unchanged).

## Phase 2 — Bring HOME into the flake

Recommended: keep home-manager **standalone** (preserves your two-command muscle
memory and the `home.nix`-is-the-source-of-truth model), but flake-driven.

1. Add inputs:
   - `inputs.home-manager.url = "github:nix-community/home-manager"` with
     `inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs"`.
   - `inputs.nixpkgs-latest.url = "github:NixOS/nixpkgs/nixpkgs-unstable"` (the
     replacement for the manual `fetchTarball` pin).
2. Add output `homeConfigurations.felix = home-manager.lib.homeManagerConfiguration {
   pkgs = <nixpkgs for felix>; extraSpecialArgs = { inherit nixpkgs-latest; ... };
   modules = [ ./home.nix ]; }`.
3. Edit `home.nix`:
   - Delete the `nixpkgs-latest-base = import (fetchTarball {…})` block (home.nix:6-11)
     and the `nixpkgs-latest` `let`-binding; instead receive `nixpkgs-latest` as a
     module argument (from `extraSpecialArgs`), and instantiate it once:
     `pkgs-latest = import nixpkgs-latest { inherit (pkgs) system; config.allowUnfree
     = true; };` — keeping the `opencode-claude-auth` override in the same `//` merge.
   - The tarball derivations (`claude-code-bin` etc.) stay exactly as they are.
4. Switch: `home-manager switch --flake .#felix`.
5. Verify: `claude --version`, `opencode --version`, `devenv version`, `signal-desktop`.

**Exit state:** both system and home are flake-driven and lock-pinned. Manual sha256
bumping for opencode/devenv/signal is gone — replaced by `nix flake update`.

## Phase 3 — Retire the manual pins & wire updates

1. `nix flake update` now bumps nixpkgs + nixpkgs-latest + home-manager reproducibly;
   `nix flake update nixpkgs-latest` bumps just the "latest" set (opencode/devenv/
   signal) — the exact selective bump you do by hand today.
2. **devenv-from-master** (the deferred question) becomes trivial here: add
   `inputs.devenv.url = "github:cachix/devenv"`, use
   `inputs.devenv.packages.${system}.default` in `home.nix`, and you get their cachix
   substitutes with no flake-compat shim. (Optional, do when you actually want it.)
3. Update `docs/updating-claude-code-and-opencode.md`: opencode section changes from
   "bump the nixpkgs-latest sha256" to "`nix flake update nixpkgs-latest`". claude-code
   section is unchanged (still a pinned tarball derivation — or optionally convert it
   to a flake input too).

## Phase 4 — Decommission channels (optional, final)

Only after a few days of the flake working:

1. `sudo nix-channel --remove nixos` / `nixos-hardware` (root); remove felix's
   home-manager/nixpkgs channels.
2. Confirm nothing else on the box relies on `<nixpkgs>` angle-bracket lookups
   (scripts, `nix-shell` one-liners). Set `nix.nixPath` / `nix.registry` from the
   flake inputs if you want `nix shell nixpkgs#foo` to resolve to the pinned nixpkgs.

**Exit state:** zero mutable channels; one `flake.lock` is the whole truth.

---

## Optional end-state variant: home-manager as a NixOS module

Instead of Phase 2's standalone `homeConfigurations`, fold home in as
`home-manager.nixosModules.home-manager` + `home-manager.users.felix = import
./home.nix`. Then a **single** `sudo nixos-rebuild switch --flake .#felix-nixos`
builds system + home together.

- Pro: one command, one generation, fully unified.
- Con: changes your workflow (no more separate `home-manager switch`), and home
  rebuilds require sudo. Contradicts the current "edit home.nix, `home-manager switch`"
  habit ([[feedback_homemanager]]).
- Recommendation: start with standalone (Phase 2 as written); switch to the module
  later only if you decide you want the single-command flow.

## Effort / risk

- Phase 1: ~1h, low risk (build-before-switch, easy rollback).
- Phase 2: ~1–2h, low-med risk (home changes are user-scope, trivially reverted).
- Phases 3–4: minutes, cleanup.
- Biggest single risk: an accidental nixpkgs channel-version jump causing a mass
  rebuild. Mitigated by picking the input branch to match the current channel and
  diffing the closure before switching.

## Rollback

- Per phase: `git checkout` the branch away + `nixos-rebuild switch`/`home-manager
  switch` from channels (still installed until Phase 4).
- System generations remain in the bootloader throughout.
