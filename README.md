% Pretix-nix

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

After having updated the source with `nix flake update --update-input pretixSrc`, run `nix run .#update-pretix` (and go take a coffee) to generate a new `pyproject.toml` and `poetry.lock` which will be transparently consumed by `poetry2nix`. Then commit these new files, and you're good (hopefully).
