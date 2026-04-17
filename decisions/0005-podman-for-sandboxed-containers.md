# 0005. Podman for sandboxed containers

## Context

Docker-compose workflows need to work inside the sandbox. Bind-mounting the host docker socket is root-equivalent: a container with socket access can `-v /:/host`, bypass the network filter via container networking, and persist backdoors. That defeats the sandbox entirely.

Running podman rootless directly inside bwrap is also not viable. Four independent blockers: `MS_NOSUID` on bwrap's mounts kills setuid `newuidmap` (needed for multi-UID mappings that containers like postgres/nginx/redis require); no writable cgroup; no `/dev/fuse`; and `--unshare-net` leaves a dead network namespace. A setuid bwrap wrapper doesn't help either; bwrap 0.11.0 adds `MS_NOSUID` to every mount unconditionally.

## Decision

Docker to Podman system-wide (`virtualisation.podman`, `dockerCompat = true`). Unrelated to the sandbox, just the better default.

For sandbox use, podman runs as a **separate system user** `bwrap-podman` behind a socket-activated systemd service. The sandbox connects via `DOCKER_HOST` and `CONTAINER_HOST` pointing at the unix socket.

Two independent isolation layers on the service:

1. **Unix permissions**: `bwrap-podman` is a different user, can't read felix-owned 700 dirs.
2. **systemd `ProtectHome=true`** on the service unit: `/home`, `/root`, `/run/user` are invisible regardless of directory modes. `BindPaths=["/code"]` re-exposes only the shared code tree.

Code lives at `/code` (separate ZFS dataset, setgid, shared `podman-dev` group). Because `/code` is outside `$HOME`, bwrap-podman never needs to traverse the home directory at all.

## Consequences

- A compromised container in the sandbox can see `/code` (fine, it's the code tree) but not `~/.ssh`, `~/.claude`, `~/.config/gh`, or anything else.
- Container network traffic bypasses bwrap's squid proxy; containers use `bwrap-podman`'s host networking. Acceptable: nothing sensitive is reachable from a container.
- Felix's podman store and bwrap-podman's store are separate. `jcd` and `sb-nuke` aliases wrap `podman --remote` pointing at the sandbox socket for inspection.
- Podman healthchecks in compose files need a systemd user session, which bwrap-podman doesn't have. Use `service_started` plus application-level readiness loops (`pg_isready`) instead.
- File ownership on `/code` gets mixed (container-created files have subuid ownership). setgid plus shared group covers most cases.

## Dead ends

- Host docker socket, felix's own podman socket: root-equivalent.
- Podman inside bwrap (various configurations): user-namespace constraints.
- Setuid bwrap wrapper: adds `MS_NOSUID` anyway.
- `homeMode = "711"` to let bwrap-podman traverse `/home/felix`: blocklist approach, would miss any permissive subdir (`~/.claude` is 755). Moving code out of `$HOME` is cleaner.
- Linger plus systemd healthcheck timers for bwrap-podman: no reliable D-Bus path when running as a system user. Removing healthchecks from compose files and relying on readiness loops worked around it.

## Non-obvious requirements

If this setup ever has to be rebuilt, these are the pieces the docs don't mention:

- The socket mode must be world-accessible (0666). bwrap drops supplementary groups via its user namespace, so felix loses the `podman-dev` group inside the sandbox. Security lives on `ProtectHome`, not socket permissions.
- Service PATH must include `/run/wrappers/bin`. Podman needs the NixOS setuid `newuidmap` and `newgidmap` wrappers.
- Service needs `cgroup_manager = "cgroupfs"` in containers.conf. Default is systemd, which requires a user-session D-Bus the system user doesn't have.
- Sandbox needs a `/run/user/$(id -u)` directory to exist, even though podman talks to the socket remotely. The CLI `lstat`s it unconditionally.
- Podman rejects symlinks leaving the build context. A `podman-build` wrapper that rsyncs with `--copy-links` first is needed for projects that symlink into shared dirs.
