{
  description = "Pretix ticketing software";

  inputs = {
    # Some utility functions to make the flake less boilerplaty
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs.url = "nixpkgs/nixos-20.09";

    pretixSrc = {
      url = "github:pretix/pretix";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, pretixSrc, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlay ];
          };
        in
        {
          defaultPackage = pkgs.pretix;
          packages = { inherit (pkgs) pretix update-pretix; };
        }) // {

      overlay = final: prev: {
        update-pretix = prev.writeScriptBin "update-pretix" ''
          #!/usr/bin/env bash

          set -euo pipefail
          set -x

          export PATH=${
            prev.lib.concatMapStringsSep ":" (x: "${x}/bin")
            (prev.stdenv.initialPath ++ [ final.poetry prev.stdenv.cc ])
          }:$PATH

          POETRY=${final.poetry}/bin/poetry

          workdir=$(mktemp -d)
          trap "rm -rf \"$workdir\"" EXIT

          pushd "$workdir"
          cp ${./pyproject.toml.template} pyproject.toml
          chmod +w pyproject.toml
          cat ${pretixSrc}/src/requirements/production.txt | \
            sed -e 's/#.*//' -e 's/\([=<>]\)/@&/' | \
            xargs "$POETRY" add

          poetry add gunicorn

          popd
          cp "$workdir"/{pyproject.toml,poetry.lock} ./
        '';
        pretix = (prev.poetry2nix.mkPoetryApplication {
          projectDir = pretixSrc;
          pyproject = ./pyproject.toml;
          poetrylock = ./poetry.lock;
          src = pretixSrc + "/src";
          overrides = prev.poetry2nix.overrides.withDefaults (pself: psuper: {
            # The tlds package is an ugly beast which fetches its content
            # at build-time. So instead replace it by a fixed hardcoded
            # version.
            tlds = psuper.tlds.overrideAttrs (a: {
              src = prev.fetchFromGitHub {
                owner = "regnat";
                repo = "tlds";
                rev = "3c1c0ce416e153a975d7bc753694cfb83242071e";
                sha256 =
                  "sha256-u6ZbjgIVozaqgyVonBZBDMrIxIKOM58GDRcqvyaYY+8=";
              };
            });
            # For some reason, tqdm is missing a dependency on toml
            tqdm = psuper.tqdm.overrideAttrs (a: {
              buildInputs = (a.buildInputs or [ ])
              ++ [ prev.python3Packages.toml ];
            });
            django-scopes = psuper.django-scopes.overrideAttrs (a: {
              # Django-scopes does something fishy to determine its version,
              # which breaks with Nix
              prePatch = (a.prePatch or "") + ''
                sed -i "s/version = '?'/version = '${a.version}'/" setup.py
              '';
            });
          });
        }).dependencyEnv;
      };

      nixosModules.pretix = {
        imports = [ ./nixos-module.nix ];
        nixpkgs.overlays = [ self.overlay ];
      };

      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.pretix
          ({ config, lib, pkgs, ... }:
            let
              # XXX: Should be passed out-of-band so as to not end-up in the
              # Nix store
              pretix_secret_cfg = pkgs.writeText "pretix-secrets"
                (lib.generators.toKeyValue { } {
                  PRETIX_DATABASE_PASSWORD = "foobar";
                });
            in
            {
              system.configurationRevision = self.rev or "dirty";

              services.pretix = {
                enable = true;
                config = {
                  database = {
                    backend = "postgresql";
                    name = "pretix";
                    host = "localhost";
                    user = "pretix";
                  };
                };
                secretConfig = pretix_secret_cfg;
                host = "0.0.0.0";
                port = 8000;
              };

              # Ad-hoc initialisation of the database password.
              # Ideally the postgres host is on another machine and handled
              # separately
              systemd.services.pretix-setup = {
                script = ''
                  # Setup the db
                  set -eu

                  ${pkgs.utillinux}/bin/runuser -u ${config.services.postgresql.superUser} -- \
                    ${config.services.postgresql.package}/bin/psql -c \
                    "ALTER ROLE ${config.services.pretix.config.database.user} WITH PASSWORD '$PRETIX_DATABASE_PASSWORD'"
                '';

                after = [ "postgresql.service" ];
                requires = [ "postgresql.service" ];
                before = [ "pretix.service" ];
                requiredBy = [ "pretix.service" ];
                serviceConfig.EnvironmentFile = pretix_secret_cfg;
              };

              networking.firewall.allowedTCPPorts =
                [ config.services.pretix.port ];

              networking.hostName = "pretix";
              services.mingetty.autologinUser = "root";
            })
        ];
      };
    };
}
