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
    config = lib.mkOption rec {
      type = lib.types.attrs;
      default = {
        pretix = {
          instance_name = config.networking.hostName;
          url = "${cfg.host}:${toString cfg.port}";
        };
        redis = {
          location = "redis://127.0.0.1/0";
          sessions = true;
        };
        celery = {
          backend = "redis://127.0.0.1/1";
          broker = "redis://127.0.0.1/2";
        };
      };
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
    };

    secretConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      description = ''
        Path to a file containing a set of environment variables to override
        the configuration file. Use this to store secrets (passwords, etc..)
        that shouldn't end-up in the store.

        The format is the one described in a note in
        <https://docs.pretix.eu/en/latest/admin/config.html>
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # virtualisation.oci-containers.backend = lib.mkDefault "podman";
    # virtualisation.oci-containers.containers.pretix = {
    #   volumes = [
    #     "pretix-data:/data"
    #     "/var/run/redis:/var/run/redis"
    #     "${configFile}:/etc/pretix/pretix.cfg"
    #   ] ++ lib.optional hasLocalPostgres "/run/postgresql:/run/postgresql"
    #   ;
    #   image = "pretix/standalone:stable";
    #   cmd = ["all"];
    #   extraOptions = ["--network=host"] ++
    #     lib.optionals (cfg.secretConfig != null) ["--env-file" "${cfg.secretConfig}" ];
    # };

    users.users.pretix = {
      group = "pretix";
      isSystemUser = true;
    };
    users.groups.pretix = {};

    systemd.services.pretix-worker = {
      serviceConfig = {
        WorkingDirectory="/var/lib/pretix";
        ExecStart = ''
          ${pkgs.pretix}/bin/celery -A pretix.celery_app worker -l info
        '';
        EnvironmentFile="${cfg.secretConfig}";
        StateDirectory="pretix";
        PrivateTmp = true;
        User = "pretix";
        Group = "pretix";
      };
      environment.PRETIX_CONFIG_FILE="${configFile}";

      wantedBy = ["multi-user.target"];
    };

    systemd.services.pretix = {
      path = [ pkgs.gettext ];
      preStart = ''
        ${pkgs.pretix}/bin/python -m pretix migrate
      '';
      serviceConfig = {
        WorkingDirectory="/var/lib/pretix";
        ExecStart = ''
          ${pkgs.pretix}/bin/gunicorn \
            --pythonpath ${pkgs.pretix}/lib/python3.8/site-packages pretix.wsgi \
            --name pretix \
            -b ${cfg.host}:${toString cfg.port}
          '';
        EnvironmentFile="${cfg.secretConfig}";
        StateDirectory="pretix";
        User = "pretix";
        Group = "pretix";
        PrivateTmp = true;
        Restart = "on-failure";
        TimeoutStartSec = 300; # For some reason the first migration is pretty long
      };
      environment.PRETIX_CONFIG_FILE="${configFile}";

      wantedBy = ["multi-user.target"];
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
    services.rabbitmq.enable = true;

    warnings =
      (if cfg.config ? mail then [] else [
        ''
          You didn't configure a mail server for pretix.
          This is likely to render it unusable.
        ''
      ]);
  };
}
