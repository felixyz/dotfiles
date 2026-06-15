# 0011 — Host tooling for the Fly 6PN → on-prem Postgres workflow

## Context

To reach the dvc on-prem Postgres from this laptop we join the Fly 6PN
WireGuard mesh as a peer (see the dvc project's `fly.md`), replacing the older
VPN. That needs `wg`/`wg-quick` (bring the tunnel up) and `dig` (resolve
`*._peer.internal` peers via Fly's `fdaa::3` DNS). `flyctl` was already present.

## Decision

### Tooling split

Global, in `home.nix`: `wireguard-tools` and `dnsutils` (dig). These are
generic host-level networking CLIs, used across any project that needs the mesh,
and `wg-quick` needs host root + a real net namespace — it can't do anything
useful from inside a project `devShell` anyway.

`psql` and Postgres tooling stay in **project flakes**, not global: projects pin
different Postgres versions and the client should match the server. (`pgcli`
remains globally for ad-hoc interactive use; the version-matched `psql`/`pg_dump`
come from the project's flake.)

### Where the WireGuard `.conf` lives

`/etc/wireguard/felix-laptop.conf`, owned `root:root`, mode `0600`, created
out-of-band (`fly wireguard create … > …`) — **not** in the nix store, **not**
git-tracked, **not** declared in `configuration.nix`. Bring the tunnel up on
demand with `wg-quick up felix-laptop` and down with `wg-quick down felix-laptop`.

Why this is the natural NixOS home for it:

- The file is both a **secret** (it carries the peer private key) and
  **regenerable** (Fly re-mints a fresh keypair anytime). Both properties argue
  against declarative management: secrets must not land in the world-readable
  nix store or in git-tracked `configuration.nix`, and "regenerable" means we
  don't need reproducibility for it.
- `/etc/wireguard/` is `wg-quick`'s own default search path, so the bare
  `wg-quick up felix-laptop` just works — we follow the tool's convention
  instead of fighting it.
- NixOS does not manage `/etc/wireguard/` unless an interface is declared there,
  so a hand-placed file persists across `nixos-rebuild` and reboots, untouched.
- `root:root 0600` puts it out of reach of every non-root process — including an
  unsandboxed agent running as `felix` without sudo — and it sits outside the
  `bwrap-sandbox` `PROJECT_DIR` roots (`~/code`, `~/dotfiles`, `/code`; see
  0003), so sandboxed agents never see it either.

Caveat: if this host ever moves to an impermanence/tmpfs-root setup, `/etc`
isn't persistent — add the path to the persistence list, or accept re-creating
the peer each boot.

Alternative considered: declarative `networking.wg-quick.interfaces.<name>` with
the key fed from a runtime secret (agenix/sops-nix). Heavier, and implies a
managed/always-on interface — overkill for a tunnel we raise only when we need
the DB. Reach for it only if we later want the mesh up at boot.

## Consequences (security)

- **Sandboxed agents cannot reach the mesh.** The sandbox is `--unshare-net`
  (0004): no interfaces, no usable `CAP_NET_ADMIN`, no `sudo`. `wg-quick up`
  fails, and the only egress is the squid HTTP-CONNECT proxy. Putting `wg`/`dig`
  on the host PATH makes them visible inside the sandbox but inert for network
  escape.
- **The new exposure is on the host.** Raising the tunnel turns "prod DB
  reachable only from Fly" into "reachable from this laptop," gated thereafter
  only by DB credentials — so keep it down except when in use, and don't leave
  prod creds where a host process (or unsandboxed agent) running as `felix` can
  read them. The `.conf` location above keeps the private key itself off-limits.

## Deferred

Giving agents scoped (read-only) DB access — a server-side read-only role plus a
per-session port bridge into the sandbox — is out of scope here and left for
later.
