# 0002. ZFS pool on Crucial T500 for /nix and data

## Context

A mostly-empty 2TB T500 and a 512GB Samsung holding root + Windows. Wanted compression on `/nix`, snapshots for data dirs (Dropbox, general), and headroom on the fast disk. Root on ext4 stays: Windows lives on the Samsung, and root is easily reinstalled, so the complexity of a ZFS root wasn't worth it.

## Decision

ZFS pool `tank` on the T500 for `/nix` and `/data/*`. Root stays ext4.

A `tank/reserved` dataset with ~10% `refreservation` guarantees the pool never fills completely. That state is recoverable only by destroying data, so the buffer is cheap insurance.

## Consequences

- Compression hit 2.38x on the nix store.
- `tank/nix` snapshots are a trap: rolling back loses store paths newer NixOS generations depend on. Treat NixOS generations as the rollback mechanism for `/nix` and use ZFS snapshots only on the data datasets.
- Migrating `/nix` needed the order `rsync, nixos-rebuild boot, rsync delta, reboot`. `nixos-rebuild boot` writes new store paths *after* the initial rsync, so a naive `rsync then reboot` leaves the new generation's init script missing and the system unbootable.
- The Samsung's original 100MB EFI partition was too small for multiple NixOS generations' kernels and ran out of space during rebuilds. Moved `/boot` to a new 1GB EFI partition on the Crucial and repointed the firmware boot entry with `efibootmgr`. If this machine is ever rebuilt, size EFI for ~1GB from the start.

## Follow-ups

- Sanoid snapshot policy for `tank/dropbox` and `tank/general`.
