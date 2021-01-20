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
                  password = "foobar";
                };
              };
            };

            networking.firewall.allowedTCPPorts = [ 80 ];
            networking.hostName = "pretix";
            services.mingetty.autologinUser = "root";
          }
        ];
      };
    };
}

