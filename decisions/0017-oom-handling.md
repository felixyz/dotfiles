# 0017. OOM handling

## Context

When memory ran low, the desktop stalled and often froze until a hard reset. Nothing killed a process before that happened. systemd-oomd was enabled but watched no cgroup, because no slice set `ManagedOOMMemoryPressure=kill`. The ZFS ARC could grow to nearly all of RAM, and the kernel swapped out applications before the ARC shrank.

## Decision

**Cap the ZFS ARC at 6 GiB**, with `zfs_arc_shrinker_limit=0` so it shrinks as fast as the kernel asks.

**Set MGLRU `min_ttl_ms` to 1000.** The kernel OOM-kills once it can no longer keep the memory used in the last second, instead of thrashing. This is the main guard against the freeze.

**Use earlyoom instead of systemd-oomd, as a backstop.** It kills the process with the highest `oom_score` when available memory is under 5% and swap is more than half full. It is simpler than oomd and does not depend on cgroup settings. gnome-shell, Xwayland, journald, dbus, pipewire, and sshd are protected with `--avoid`.

## Consequences

A runaway process gets killed rather than freezing the machine. earlyoom shows a desktop notification when it kills something, and `journalctl -k | grep -i oom` shows kernel kills.
