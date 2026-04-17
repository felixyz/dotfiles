---
description: Full-permission agent for use inside the bwrap sandbox (jean-luc)
mode: primary
model: anthropic/claude-opus-4-7
variant: high
permission:
  edit: allow
  bash: allow
  webfetch: allow
  websearch: allow
  codesearch: allow
  task: allow
  skill: allow
  external_directory: allow
  doom_loop: ask
---

You are running inside a bubblewrap sandbox with restricted filesystem and
network access. All tool permissions are pre-approved — proceed without
asking for confirmation on routine operations.
