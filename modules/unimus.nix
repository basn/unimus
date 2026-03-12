{ config, lib, pkgs, ... }:
let
  inherit (lib)
    concatStringsSep
    escapeShellArgs
    filterAttrs
    generators
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    optionalAttrs
    types;

  cfg = config.services.unimus;

  proxyModule = types.submodule {
    options = {
      enable = mkEnableOption "an nginx reverse proxy for Unimus";

      hostName = mkOption {
        type = types.str;
        default = "";
        example = "unimus.example.com";
        description = "Virtual host name served by nginx.";
      };

      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Backend address nginx proxies to.";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Public nginx listen port when TLS is not enabled.";
      };

      forceSSL = mkOption {
        type = types.bool;
        default = false;
        description = "Redirect HTTP to HTTPS.";
      };

      enableACME = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ACME for this virtual host.";
      };

      useACMEHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Reuse certificates from another ACME host.";
      };

      sslCertificate = mkOption {
        type = types.nullOr (types.oneOf [ types.path types.str ]);
        default = null;
        description = "Manual certificate path for nginx.";
      };

      sslCertificateKey = mkOption {
        type = types.nullOr (types.oneOf [ types.path types.str ]);
        default = null;
        description = "Manual private key path for nginx.";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra nginx virtual host configuration.";
      };
    };
  };

  serviceModule = kind: defaults: {
    enable = mkEnableOption "the ${kind} service";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = literalExpression ''
        pkgs.callPackage (unimus + "/pkgs/mk-unimus-package.nix") {
          pname = "${kind}";
          jar = /var/lib/secrets/${defaults.jarName};
        }
      '';
      description = "Native package built from the vendor distribution.";
    };

    binary = mkOption {
      type = types.str;
      default = defaults.binary;
      description = "Binary inside the package used by the systemd service.";
    };

    user = mkOption {
      type = types.str;
      default = defaults.user;
      description = "System user used to run the service.";
    };

    group = mkOption {
      type = types.str;
      default = defaults.group;
      description = "System group used to run the service.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the configured listen ports in the firewall.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = defaults.listenAddress;
      description = "Bind address for the service.";
    };

    port = mkOption {
      type = types.port;
      default = defaults.port;
      description = "Main listen port.";
    };

    extraPorts = mkOption {
      type = types.listOf types.port;
      default = defaults.extraPorts;
      description = "Additional listen ports to open in the firewall.";
    };

    stateDir = mkOption {
      type = types.str;
      default = defaults.stateDir;
      description = "Writable state directory.";
    };

    logDir = mkOption {
      type = types.str;
      default = defaults.logDir;
      description = "Writable log directory.";
    };

    configDir = mkOption {
      type = types.str;
      default = defaults.configDir;
      description = "Configuration directory.";
    };

    propertiesFileName = mkOption {
      type = types.str;
      default = defaults.propertiesFileName;
      description = "Properties file generated in `configDir`.";
    };

    properties = mkOption {
      type = types.attrsOf (types.oneOf [ types.str types.int types.bool types.path ]);
      default = { };
      example = literalExpression ''
        {
          "database.type" = "POSTGRESQL";
          "database.host" = "127.0.0.1";
          "database.port" = 5432;
        }
      '';
      description = "Application properties written to the generated properties file.";
    };

    propertiesFromFiles = mkOption {
      type = types.attrsOf (types.oneOf [ types.path types.str ]);
      default = { };
      example = literalExpression ''
        {
          "database.password" = config.sops.secrets."unimus/database-password".path;
          "license.key" = config.sops.secrets."unimus/license-key".path;
        }
      '';
      description = ''
        Property values loaded from files at service start.
        Useful for secrets managed by tools such as sops-nix.
      '';
    };

    javaProperties = mkOption {
      type = types.attrsOf (types.oneOf [ types.str types.int types.bool types.path ]);
      default = { };
      description = "Properties exposed as `-Dkey=value` in `JAVA_OPTS`.";
    };

    javaOpts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional JVM options passed through `JAVA_OPTS`.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables for the systemd service.";
    };

    args = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra command-line arguments passed to the launcher.";
    };

    certificateFile = mkOption {
      type = types.nullOr (types.oneOf [ types.path types.str ]);
      default = null;
      description = "Convenience path exposed as a Java property when set.";
    };

    certificateKeyFile = mkOption {
      type = types.nullOr (types.oneOf [ types.path types.str ]);
      default = null;
      description = "Convenience path exposed as a Java property when set.";
    };

    listenAddressProperty = mkOption {
      type = types.nullOr types.str;
      default = defaults.listenAddressProperty or null;
      description = "Java property name used for `listenAddress`.";
    };

    portProperty = mkOption {
      type = types.nullOr types.str;
      default = defaults.portProperty or null;
      description = "Java property name used for `port`.";
    };
  };

  mkJavaPropertyArgs = attrs:
    mapAttrsToList (name: value: "-D${name}=${toString value}") attrs;

  mkPropertiesFile = serviceCfg:
    pkgs.writeText "${serviceCfg.propertiesFileName}" (
      generators.toKeyValue { } serviceCfg.properties
    );

  mkService = name: serviceCfg:
    let
      propertiesFile = mkPropertiesFile serviceCfg;
      javaPropertyArgs =
        mkJavaPropertyArgs serviceCfg.javaProperties
        ++ optional (serviceCfg.listenAddressProperty != null) "-D${serviceCfg.listenAddressProperty}=${serviceCfg.listenAddress}"
        ++ optional (serviceCfg.portProperty != null && serviceCfg.port > 0) "-D${serviceCfg.portProperty}=${toString serviceCfg.port}"
        ++ optional (serviceCfg.certificateFile != null) "-Dunimus.certificate.file=${toString serviceCfg.certificateFile}"
        ++ optional (serviceCfg.certificateKeyFile != null) "-Dunimus.certificate.key-file=${toString serviceCfg.certificateKeyFile}";
      javaOpts = concatStringsSep " " (serviceCfg.javaOpts ++ javaPropertyArgs);
    in
    {
      description = "Unimus ${name}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = serviceCfg.user;
        Group = serviceCfg.group;
        PermissionsStartOnly = true;
        WorkingDirectory = serviceCfg.stateDir;
        RuntimeDirectory = "unimus-${name}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      environment =
        {
          JAVA_OPTS = javaOpts;
          UNIMUS_STATE_DIR = serviceCfg.stateDir;
          UNIMUS_LOG_DIR = serviceCfg.logDir;
          UNIMUS_CONFIG_DIR = serviceCfg.configDir;
        }
        // serviceCfg.environment;

      preStart = ''
        install -d -m0750 -o ${serviceCfg.user} -g ${serviceCfg.group} ${serviceCfg.stateDir}
        install -d -m0750 -o ${serviceCfg.user} -g ${serviceCfg.group} ${serviceCfg.logDir}
        install -d -m0750 -o ${serviceCfg.user} -g ${serviceCfg.group} ${serviceCfg.configDir}
        install -m0640 -o ${serviceCfg.user} -g ${serviceCfg.group} ${propertiesFile} ${serviceCfg.configDir}/${serviceCfg.propertiesFileName}
      '' + lib.concatStringsSep "" (
        mapAttrsToList
          (name: path: ''
            printf '%s=%s\n' '${name}' "$(${pkgs.coreutils}/bin/tr -d '\r\n' < ${lib.escapeShellArg (toString path)})" >> ${serviceCfg.configDir}/${serviceCfg.propertiesFileName}
            chown ${serviceCfg.user}:${serviceCfg.group} ${serviceCfg.configDir}/${serviceCfg.propertiesFileName}
            chmod 0640 ${serviceCfg.configDir}/${serviceCfg.propertiesFileName}
          '')
          serviceCfg.propertiesFromFiles
      ) + ''
      '';

      script = ''
        exec ${serviceCfg.package}/bin/${serviceCfg.binary} ${escapeShellArgs serviceCfg.args}
      '';
    };

  enabledServices = filterAttrs (_: serviceCfg: serviceCfg.enable) {
    server = cfg.server;
    core = cfg.core;
  };

  mkNginxVirtualHost = serviceCfg: {
    ${serviceCfg.reverseProxy.hostName} = {
      enableACME = serviceCfg.reverseProxy.enableACME;
      useACMEHost = serviceCfg.reverseProxy.useACMEHost;
      forceSSL = serviceCfg.reverseProxy.forceSSL;
      sslCertificate = serviceCfg.reverseProxy.sslCertificate;
      sslCertificateKey = serviceCfg.reverseProxy.sslCertificateKey;

      locations."/" = {
        proxyPass = "http://${serviceCfg.reverseProxy.listenAddress}:${toString serviceCfg.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Real-IP $remote_addr;
        '';
      };

      extraConfig = serviceCfg.reverseProxy.extraConfig;
      listen = [
        {
          addr = "0.0.0.0";
          port = serviceCfg.reverseProxy.port;
          ssl = serviceCfg.reverseProxy.forceSSL
            || serviceCfg.reverseProxy.enableACME
            || serviceCfg.reverseProxy.useACMEHost != null
            || serviceCfg.reverseProxy.sslCertificate != null;
        }
      ];
    };
  };
in
{
  options.services.unimus = {
    server = mkOption {
      type = types.submodule ({ ... }: {
        options =
          serviceModule "server" {
            jarName = "unimus.jar";
            binary = "unimus";
            user = "unimus";
            group = "unimus";
            listenAddress = "127.0.0.1";
            port = 8085;
            extraPorts = [ 5509 ];
            stateDir = "/var/lib/unimus";
            logDir = "/var/log/unimus";
            configDir = "/etc/unimus";
            propertiesFileName = "unimus.properties";
            listenAddressProperty = "server.address";
            portProperty = "server.port";
          }
          // {
            reverseProxy = mkOption {
              type = proxyModule;
              default = { };
              description = "Optional nginx reverse proxy configuration for the web UI.";
            };
          };
      });
      default = { };
      description = "Native Unimus server service.";
    };

    core = mkOption {
      type = types.submodule {
        options = serviceModule "core" {
          jarName = "unimus-core.jar";
          binary = "unimus-core";
          user = "unimus-core";
          group = "unimus-core";
          listenAddress = "0.0.0.0";
          port = 0;
          extraPorts = [ ];
          stateDir = "/var/lib/unimus-core";
          logDir = "/var/log/unimus-core";
          configDir = "/etc/unimus-core";
          propertiesFileName = "unimus-core.properties";
        };
      };
      default = { };
      description = "Native Unimus Core service.";
    };
  };

  config = mkIf (enabledServices != { }) (mkMerge [
    {
      assertions =
        mapAttrsToList (name: serviceCfg: {
          assertion = serviceCfg.package != null;
          message = "services.unimus.${name}.package must be set when the service is enabled.";
        }) enabledServices
        ++ optional (cfg.server.enable && cfg.server.reverseProxy.enable) {
          assertion = cfg.server.reverseProxy.hostName != "";
          message = "services.unimus.server.reverseProxy.hostName must be set when nginx reverse proxying is enabled.";
        };
    }

    {
      users.groups =
        optionalAttrs (cfg.server.enable && cfg.server.group == "unimus") { unimus = { }; }
        // optionalAttrs (cfg.core.enable && cfg.core.group == "unimus-core") { "unimus-core" = { }; };

      users.users =
        optionalAttrs (cfg.server.enable && cfg.server.user == "unimus") {
          unimus = {
            isSystemUser = true;
            group = cfg.server.group;
            home = cfg.server.stateDir;
            createHome = true;
          };
        }
        // optionalAttrs (cfg.core.enable && cfg.core.user == "unimus-core") {
          "unimus-core" = {
            isSystemUser = true;
            group = cfg.core.group;
            home = cfg.core.stateDir;
            createHome = true;
          };
        };

      systemd.services =
        optionalAttrs cfg.server.enable { unimus = mkService "server" cfg.server; }
        // optionalAttrs cfg.core.enable { unimus-core = mkService "core" cfg.core; };
    }

    (mkIf (cfg.server.enable && cfg.server.openFirewall) {
      networking.firewall.allowedTCPPorts = [ cfg.server.port ] ++ cfg.server.extraPorts;
    })

    (mkIf (cfg.core.enable && cfg.core.openFirewall) {
      networking.firewall.allowedTCPPorts = optional (cfg.core.port > 0) cfg.core.port ++ cfg.core.extraPorts;
    })

    (mkIf (cfg.server.enable && cfg.server.reverseProxy.enable) {
      services.nginx.enable = true;
      services.nginx.recommendedProxySettings = true;
      services.nginx.virtualHosts = mkNginxVirtualHost cfg.server;
    })
  ]);
}
