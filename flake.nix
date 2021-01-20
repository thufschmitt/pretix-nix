{
  description = "Pretix ticketing software";

  inputs = {
    # Some utility functions to make the flake less boilerplaty
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs.url = "nixpkgs/nixos-20.09";
  };

  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (
    system:
    let pkgs = import nixpkgs {
      inherit system;
      overlays = [ self.overlay ];
    }; in
    { # See later whether I want to actually package this
    }
    ) // {

      overlay = final: prev: {
      };

      nixosModules.pretix = {
        imports = [ ./nixos-module.nix ];
        nixpkgs.overlays = [ self.overlay ];
      };

      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            self.nixosModules.pretix
            ({ config, lib, pkgs, ... }:
            let
              # XXX: Should be passed out-of-band so as to not end-up in the
              # Nix store
              pretix_secret_cfg = pkgs.writeText "pretix-secrets" (
                lib.generators.toKeyValue {} {
                  PRETIX_DATABASE_PASSWORD = "foobar";
                }
              );
            in
            { system.configurationRevision = self.rev or "dirty";

            services.pretix = {
              enable = true;
              url = "localhost:8080";
              config = {
                database = {
                  backend = "postgresql";
                  name = "pretix";
                  host = "localhost";
                  user = "pretix";
                };
              };
              secretConfig = pretix_secret_cfg;
            };

            # Ad-hoc initialisation of the database password.
            # Ideally the postgres host is on another machine and handled
            # separately
            systemd.services.pretix-setup = {
              script = ''
                # Setup the db
                set -eu

                ${pkgs.utillinux}/bin/runuser -u ${config.services.postgresql.superUser} -- \
                  ${config.services.postgresql.package}/bin/psql -c "ALTER ROLE ${config.services.pretix.config.database.user} WITH PASSWORD '$PRETIX_DATABASE_PASSWORD'"
              '';

              after = [ "postgresql.service" ];
              requires = [ "postgresql.service" ];
              before = [ "${config.virtualisation.oci-containers.backend}-pretix.service" ];
              requiredBy = [ "${config.virtualisation.oci-containers.backend}-pretix.service" ];
              serviceConfig.EnvironmentFile = pretix_secret_cfg;
            };

            networking.firewall.allowedTCPPorts = [ 80 ];
            networking.hostName = "pretix";
            services.mingetty.autologinUser = "root";
          })
        ];
      };
    };
  }

