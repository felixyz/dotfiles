# 0018. Run a project's devenv stack beside bridged host ports

## Context

decisions/0015 bridges the port behind each allowed `.localhost` name into the sandbox, because Tidewave Web points the agents it launches at `http://localhost:<local_port>/tidewave/mcp`, the dev server's socket port. Inside the sandbox that port is then taken. A devenv project with `strict_ports: true` checks every process port before starting anything, so even a recipe that starts only Postgres fails with `Port 4004 is already in use`. Agents launched from the Tidewave IDE have to run tests, so the bridge and the sandbox's own stack must coexist.

## Decision

**The launcher overlays a `devenv.local.yaml` with `strict_ports: false`.** devenv merges `devenv.local.yaml` into `devenv.yaml`, and every devenv command reads it, however a recipe starts its processes. The sandbox's copy is the project's own `devenv.local.yaml` with any `strict_ports:` line replaced, mounted read-only over the original. devenv then gives the sandbox's processes the next free port, and the bridged port keeps reaching the host's dev server. Observed in myproto: the sandbox's Phoenix got 4005, and 873 tests passed while `localhost:4004` reached the host app.

**Each sandbox gets its own `.devenv`, not only `.devenv/state`.** `.devenv/nix-eval-cache.db` holds a single entry. With a shared cache, the host and a sandbox with a different `devenv.local.yaml` replace each other's entry, at 7 to 18 seconds of evaluation per switch, measured in myproto. The host's `.devenv/state/venv` is still bind-mounted in.

The overlay applies only when `devenv.yaml` sits at the sandbox root. A project whose `devenv.yaml` is in a subdirectory of the root keeps strict ports in the sandbox.

## Consequences

- Every sandbox launch in a devenv project pays one full Nix evaluation, about 7 to 18 seconds, on the first devenv command.
- When the project has no `devenv.local.yaml`, the launcher creates one on the host containing `{}`, because bwrap needs a file to mount over. Its first appearance is expected to cost the host one re-evaluation and one direnv reload. The global gitignore in `home.nix` lists it.
- A host edit to `devenv.local.yaml` reaches a sandbox at its next launch.
- In the sandbox, a devenv-allocated port can differ from the one in a project's own port files. Recipes that read the port from devenv follow it.

## Dead ends

- devenv's user config, through `DEVENV_USER_CONFIG`. Its schema allows only `version`, `tui`, and `shell`, with no other keys.
- An environment variable for strict ports. devenv 2.4 has none.
- A `devenv` wrapper adding `--no-strict-ports`. Only `devenv up` and `devenv processes up` accept the flag. myproto starts services with `devenv processes start`, and `devenv test` does not take it either.
- Bridging route ports only into Tidewave-launched sessions. Those are the sessions that most need to run tests.
