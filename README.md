# Pretix-nix

Nix packaging for https://pretix.eu

This repo contains a set of .nix files for packaging pretix.
The (probably) only interesting entrypoint is the NixOS module.
As an example of use, see the config defined in `nixosConfigurations.vm` in the flake.

## Running the test vm

```shell
nixos-rebuild build-vm --flake .#vm
QEMU_NET_OPTS='hostfwd=tcp::8000-:8000' QEMU_OPTS='-nographic -m 2G' ./result/bin/run-pretix-vm
firefox http://localhost:8000
```

## Updating pretix

To update pretix to a new version:

```shell
# Update the source to a newer version
nix flake update --update-input pretixSrc
# Update the pyproject.toml and poetry.lock to match the new package requirements
nix run .#update-pretix # And go take a coffee
```

## Caveats

1. The update process is a bit wonky and I can't really guaranty that it'll stay reliable in the long term
2. The NixOS module only had a shallow testing and there's many moving parts (a celery worker, a cron job, …), it's possible that one of these misbehaves and I didn't notice it
3. A few things are hardcoded in the NixOS module (like using a local celery&rabbitmq)
