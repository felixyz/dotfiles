---
name: update-agents
description: Update claude-code, opencode, and tidewave-cli to their latest releases in the dotfiles home.nix, and print a brief changelog summary for each. Use when the user asks to update/upgrade/bump claude-code, opencode, and/or tidewave (the coding agents), e.g. "update claude and opencode", "bump tidewave", "bump the agents".
---

Update the coding agents pinned in `~/dotfiles/home.nix` (claude-code, opencode, and
tidewave-cli), then print a short changelog summary for each.

Do the work in this order. If the user names only some of them, do just those.

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

## 3. tidewave-cli

Pinned as a direct GitHub release asset in the `tidewave-cli` derivation. Its version is
independent of the `:tidewave` hex package that Elixir projects depend on.

1. Latest version:
   ```sh
   curl -s https://api.github.com/repos/tidewave-ai/tidewave_app/releases/latest \
     | grep -m1 '"tag_name"'
   ```
2. SRI hash (**no** `--unpack`, the src is a plain `fetchurl` of a single binary):
   ```sh
   V=<version without the v>   # from step 1
   nix store prefetch-file --json \
     "https://github.com/tidewave-ai/tidewave_app/releases/download/v$V/tidewave-cli-x86_64-unknown-linux-musl" \
     | grep -o '"hash":"[^"]*"'
   ```
3. In `home.nix`, update `version =` and `hash =` in `tidewave-cli` (the `url` uses
   `${version}`).

If already on the latest version, say so and skip the edit.

## 4. Print a brief changelog summary (always do this)

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
  import json,sys,re
  rels=json.load(sys.stdin)
  key=lambda t: tuple(int(x) for x in t.lstrip("v").split("."))
  lo,hi=key("<old>"),key("<new>")   # old (exclusive) .. new (inclusive)
  out=[(key(r["tag_name"]),r["tag_name"],(r.get("body") or "").strip())
       for r in rels if re.fullmatch(r"v?\d+\.\d+\.\d+", r["tag_name"])   # the release list also holds tags like pr-38252-videos
       and lo<key(r["tag_name"])<=hi]
  for k,t,b in sorted(out,reverse=True):
      print("### "+t); print(b[:800]); print()
  '
  ```
- **tidewave-cli** (one changelog; the GitHub release notes are mostly empty). Entries
  are ordered by version, not date, so read every entry between old and new:
  ```sh
  curl -s https://raw.githubusercontent.com/tidewave-ai/tidewave_app/main/CHANGELOG.md | head -80
  ```

## 5. Hand off (do NOT commit, do NOT switch)

- **Stage** the `home.nix` diff (`git add home.nix`) but **never run `git commit` or
  `git push`** — ask the user to commit. (See the never-commit feedback in memory.)
- Do **not** run `home-manager switch` — the user applies it themselves. Tell them the
  edits are staged and ready to switch + commit.
- Note that the prefetch in steps 1–3 already hash-verifies the sources, so a
  successful prefetch means the new hashes are correct before switching.

## Gotchas

- claude-code and nixpkgs hashes use `--unpack` (unpacked tarballs); tidewave-cli's
  must not (single binary). Using the wrong mode gives a mismatched hash.
- `home.nix` shims tidewave's downloads under `~/.cache/tidewave/downloads/`, by
  filenames that carry the bundled opencode and bun versions (e.g.
  `bun-linux-x64-musl-1-3-10`). A tidewave bump can change those names. Tell the user
  that if tidewave reports "cannot execute" after switching, the new filename needs a
  matching `home.file` shim.
- Never patchelf the claude binary — it's a bun standalone with a magic footer; that's
  why it's wrapped in `buildFHSEnv`. See `~/dotfiles/decisions/0010`.
- opencode in nixpkgs may lag the newest npm release by a few patch versions — that's
  expected.
