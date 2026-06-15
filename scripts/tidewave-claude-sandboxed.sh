#!/usr/bin/env bash
# Wrapper that tidewave-cli's CLAUDE_CODE_EXECUTABLE points at, so the
# claude-agent-acp bridge spawns claude inside bwrap-sandbox instead of
# directly on the host. Same persona scoping as the `jean-claude` alias.
#
# Tidewave Web pins the session cwd at whatever path the user typed
# (often a subapp like /code/foo/ui). Walk up to the nearest ancestor
# containing a .sandbox/ dir so PROJECT_DIR anchors at the user-declared
# umbrella root — that's where allowed-hosts / allowed-ports live and
# where a writable mount is wanted.
set -euo pipefail
d="$PWD"
while [ "$d" != "/" ]; do
  if [ -d "$d/.sandbox" ]; then
    cd "$d"
    break
  fi
  d="$(dirname "$d")"
done
export BWRAP_PERSONA=claude
exec "$HOME/.nix-profile/bin/bwrap-sandbox" "$HOME/.nix-profile/bin/claude" "$@"
