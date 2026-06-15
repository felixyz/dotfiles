# 0010. claude-code via buildFHSEnv, not patchelf

## Context

From v2.1.113, `@anthropic-ai/claude-code` dropped `cli.js` and ships only a per-platform `bun build --compile` native binary. Bun detects the embedded app via a magic footer at the end of the file. `autoPatchelfHook` (or any `patchelf --set-interpreter`) shifts that footer, after which the binary silently downgrades to plain bun CLI mode — `claude --version` prints bun's version, subcommands fail as "Script not found". No error indicates the embedded app didn't activate.

## Decision

Fetch the linux-x64 native tarball with `dontStrip = true; dontFixup = true; dontPatchELF = true;` to keep the ELF byte-identical, then wrap in `pkgs.buildFHSEnv` with `glibc` in `targetPkgs` so bwrap provides `/lib64/ld-linux-x86-64.so.2` at runtime. Bumping the version requires only a new SRI hash.
