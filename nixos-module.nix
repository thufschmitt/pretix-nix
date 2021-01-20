{ config, pkgs, lib, ... }:
let
  cfg = config.services.pretix;
  # XXX: This will likely contain secrets and will be world-readable
  # in the store
  configFile = pkgs.writeText "pretix.cfg" (lib.generators.toINI {} cfg.config);

  hasLocalPostgres =
    cfg.config.database.backend or null == "postgresql" &&
    (! (cfg.config.database ? host)
    || builtins.substring  0 1 cfg.config.database.host == "/" # Unix socket
    || cfg.config.database.host == "localhost");
in
{
  options.services.pretix = {
    enable = lib.mkEnableOption "pretix";
    url = lib.mkOption {
      type = lib.types.str;
      example = "pretix.de";
    };
    config = lib.mkOption rec {
      type = lib.types.attrs;
      default = {
        pretix = {
          instance_name = config.networking.hostName;
          url = cfg.url;
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = lib.mkDefault "podman";
    virtualisation.oci-containers.containers.pretix = {
      volumes = [
        "pretix-data:/data"
        "/var/run/redis:/var/run/redis"
        "${configFile}:/etc/pretix/pretix.cfg"
      ] ++ lib.optional hasLocalPostgres "/run/postgresql:/run/postgresql"
      ;
      image = "pretix/standalone:stable";
      cmd = ["all"];
      extraOptions = ["--network=host"];
    };

    services.redis = {
      enable = true;
      unixSocket = "/var/run/redis/redis.sock";
    };

    services.postgresql = lib.mkIf hasLocalPostgres {
      enable = true;
      ensureDatabases = [ "pretix" ];
      ensureUsers = [
        {
          name = "pretix";
          ensurePermissions = {
            "DATABASE pretix" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    systemd.services.pretix-setup = lib.mkIf (hasLocalPostgres && (cfg.config.database.password ? null) != null) {
      script = ''
        # Setup the db
        ${pkgs.utillinux}/bin/runuser -u ${config.services.postgresql.superUser} -- ${config.services.postgresql.package}/bin/psql -c "ALTER ROLE ${cfg.config.database.user} WITH PASSWORD '${cfg.config.database.password}'"
      '';

      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      before = [ "${config.virtualisation.oci-containers.backend}-pretix.service" ];
      requiredBy = [ "${config.virtualisation.oci-containers.backend}-pretix.service" ];
    };

    warnings =
      (if cfg.config ? mail then [] else [
        ''
          You didn't configure a mail server for pretix.
          This is likely to render it unusable.
        ''
      ]);
  };
}
