---
name: update-agents
description: Update claude-code and opencode to their latest releases in the dotfiles home.nix, and print a brief changelog summary for each. Use when the user asks to update/upgrade/bump claude-code and/or opencode (the coding agents), e.g. "update claude and opencode", "bump the agents".
---

Update the two coding agents pinned in `~/dotfiles/home.nix`, then print a short
changelog summary for each. Full background lives in
`~/dotfiles/docs/updating-claude-code-and-opencode.md` — this skill is the executable
version of that recipe.

Do the work in this order. If the user names only one of the two, do just that one.

## 1. claude-code

Pinned as a direct npm linux-x64 tarball in the `claude-code-bin` derivation.

1. Latest version:
   ```sh
   curl -s https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/latest \
     | grep -o '"version":"[^"]*"' | head -1
   ```
2. SRI hash (note `--unpack`, the src is a `fetchzip`):
   ```sh
   V=<version>   # from step 1
   nix store prefetch-file --json --unpack \
     "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-$V.tgz" \
     | grep -o '"hash":"[^"]*"'
   ```
3. In `home.nix`, update **both** the `version =` line and the `url =` line (two
   `2.1.NNN` occurrences on adjacent lines in `claude-code-bin`) and the `hash =`.

If already on the latest version, say so and skip the edit.

## 2. opencode

opencode comes from the shared `nixpkgs-latest` pin, not a direct version. Bumping it
moves the whole pin (also `devenv`, `signal-desktop` — intended).

Note: `devenv` is overridden with a vendored `pkgs/devenv.nix` (decisions/0013) because
the pin lagged. After bumping the pin, check `nixpkgs-latest-base.devenv.version` and
whether its recipe builds `devenv-proxy`. If both hold (>= 2.3 and the proxy ships),
delete `pkgs/devenv.nix` and the `devenv-latest` override in `home.nix`.

1. Latest nixpkgs-unstable commit + tarball hash (base32, `--unpack`):
   ```sh
   rev=$(curl -s https://api.github.com/repos/NixOS/nixpkgs/commits/nixpkgs-unstable \
     | grep -m1 '"sha"' | cut -d'"' -f4)
   nix-prefetch-url --unpack "https://github.com/NixOS/nixpkgs/archive/$rev.tar.gz"
   ```
2. Confirm the opencode version that pin gives (note the old version first, for the
   changelog range):
   ```sh
   nix-instantiate --eval -E \
     "(import (fetchTarball { url = \"https://github.com/NixOS/nixpkgs/archive/$rev.tar.gz\"; }) {}).opencode.version"
   ```
3. In `home.nix`, replace the `sha256` on the `nixpkgs-latest-base` `fetchTarball`
   (the one commented "Update the sha256 to bump"). Leave `opencode-claude-auth`
   (pinned separately) unless the user asks.

Before editing, capture the **old** opencode version (evaluate the current pin's
`opencode.version`) so you know the changelog range.

## 3. Print a brief changelog summary (always do this)

After picking the new versions, print a **short summary — max ~10 brief points each**
— of the most important changes between the old and new versions, for each updated
agent. Prioritise user-facing features, notable fixes, and behaviour changes; skip
pure i18n / desktop-polish noise.

- **claude-code** (one changelog, newest first — read entries between old and new):
  ```sh
  curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | head -200
  ```
- **opencode** (per-release GitHub notes; repo redirects, so `-L`; filter the range):
  ```sh
  curl -sL "https://api.github.com/repositories/975734319/releases?per_page=80" \
    | python3 -c '
  import json,sys
  rels=json.load(sys.stdin)
  key=lambda t: tuple(int(x) for x in t.lstrip("v").split("."))
  lo,hi=key("<old>"),key("<new>")   # old (exclusive) .. new (inclusive)
  out=[(key(r["tag_name"]),r["tag_name"],(r.get("body") or "").strip())
       for r in rels if lo<key(r["tag_name"])<=hi]
  for k,t,b in sorted(out,reverse=True):
      print("### "+t); print(b[:800]); print()
  '
  ```

## 4. Hand off (do NOT commit, do NOT switch)

- **Stage** the `home.nix` diff (`git add home.nix`) but **never run `git commit` or
  `git push`** — ask the user to commit. (See the never-commit feedback in memory.)
- Do **not** run `home-manager switch` — the user applies it themselves. Tell them the
  edits are staged and ready to switch + commit.
- Note that the prefetch in steps 1–2 already hash-verifies the sources, so a
  successful prefetch means the new hashes are correct before switching.

## Gotchas

- All hashes use `--unpack` (both sources are unpacked tarballs); a plain hash
  mismatches.
- Never patchelf the claude binary — it's a bun standalone with a magic footer; that's
  why it's wrapped in `buildFHSEnv`. See `~/dotfiles/decisions/0010`.
- opencode in nixpkgs may lag the newest npm release by a few patch versions — that's
  expected.
