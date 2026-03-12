# Unimus NixOS Flake

This flake provides:

- a NixOS module for `services.unimus.server`
- a NixOS module for `services.unimus.core`
- an optional nginx reverse proxy for the server UI
- a helper for packaging the official upstream JARs
- package outputs for `unimus` and `unimus-core`

## Upstream JARs

- Unimus `2.8.0`: `https://download.unimus.net/unimus/2.8.0/Unimus.jar`
- Unimus Core `2.8.0`: `https://download.unimus.net/unimus-core/2.8.0/Unimus-Core.jar`

Pinned hashes:

- `Unimus.jar`: `sha256-fMpxC45zUGTTqUXlqEUUNIMkZsh5YhsKCMWDOLMwYfU=`
- `Unimus-Core.jar`: `sha256-74iiH12LmMZbxksiWqDH304fuT0wrex9bj9wLs7w22E=`

## Flake Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    unimus.url = "path:/home/basn/git/unimus";
  };

  outputs = { nixpkgs, unimus, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        unimus.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Package Helper

The flake also exposes:

- `packages.<system>.unimus`
- `packages.<system>.unimus-core`
- overlay `overlays.unimus`

So if you apply the overlay you can use `pkgs.unimus` and `pkgs.unimus-core` directly, in the same style as your `wazuh.nix` repo.

The helper in [pkgs/mk-unimus-package.nix](/home/basn/git/unimus/pkgs/mk-unimus-package.nix) wraps a JAR and creates a launcher equivalent to:

```sh
java $JAVA_OPTS -jar <packaged-jar>
```

Example:

```nix
{
  nixpkgs.overlays = [ unimus.overlays.default ];

  services.unimus.server.package = pkgs.unimus;
}
```

## Main Options

Shared options on both `services.unimus.server` and `services.unimus.core`:

- `enable`: start the service
- `package`: packaged JAR wrapper, required when enabled
- `user`, `group`: system user/group for the unit
- `listenAddress`, `port`, `extraPorts`: bind and firewall-related settings
- `stateDir`, `logDir`, `configDir`: runtime directories
- `properties`: literal key/value entries written into the generated properties file
- `propertiesFromFiles`: property values loaded from files at service start
- `javaProperties`: converted to `-Dkey=value` inside `JAVA_OPTS`
- `javaOpts`: extra JVM flags
- `environment`: extra service environment variables
- `args`: extra command-line args passed to the launcher
- `certificateFile`, `certificateKeyFile`: convenience Java-property file paths

Server-only options:

- `openFirewall`
- `listenAddressProperty`
- `portProperty`
- `reverseProxy.*`

Core-specific defaults differ mainly in paths and port handling:

- service name: `unimus-core`
- state dir: `/var/lib/unimus-core`
- log dir: `/var/log/unimus-core`
- config dir: `/etc/unimus-core`

## Secrets From Files

`propertiesFromFiles` is intended for secrets managed by `sops-nix` or any other mechanism that exposes decrypted values as files.

Example with `sops-nix`:

```nix
{
  sops.secrets."unimus/database-password" = { };
  sops.secrets."unimus/license-key" = { };

  services.unimus.server = {
    enable = true;
    package = pkgs.unimus;

    properties = {
      "database.type" = "POSTGRESQL";
      "database.host" = "127.0.0.1";
      "database.port" = 5432;
      "database.name" = "unimus";
      "database.user" = "unimus";
    };

    propertiesFromFiles = {
      "database.password" = config.sops.secrets."unimus/database-password".path;
      "license.key" = config.sops.secrets."unimus/license-key".path;
    };
  };
}
```

The file contents are read during `preStart` and appended into the generated properties file.

## Examples

### Server

```nix
{
  services.unimus.server = {
    enable = true;
    package = pkgs.unimus;

    port = 8085;
    openFirewall = true;

    properties = {
      "database.type" = "POSTGRESQL";
      "database.host" = "127.0.0.1";
      "database.port" = 5432;
      "database.name" = "unimus";
      "database.user" = "unimus";
    };

    javaOpts = [
      "-Xms256m"
      "-Xmx1024m"
    ];
  };
}
```

### Core

```nix
{
  services.unimus.core = {
    enable = true;
    package = pkgs.unimus-core;

    properties = {
      "unimus.address" = "10.10.10.10";
      "unimus.port" = 5509;
      "unimus.access.key" = "replace-with-core-key";
    };
  };
}
```

### Server With Nginx

```nix
{
  services.unimus.server = {
    enable = true;
    package = pkgs.unimus;

    listenAddress = "127.0.0.1";
    port = 8085;

    reverseProxy = {
      enable = true;
      hostName = "unimus.example.com";
      forceSSL = true;

      # Choose one certificate source:

      # ACME managed on this host
      enableACME = true;

      # Or reuse another ACME host
      # useACMEHost = "example.com";

      # Or use your own certificate files
      # sslCertificate = "/var/lib/acme/unimus.example.com/fullchain.pem";
      # sslCertificateKey = "/var/lib/acme/unimus.example.com/key.pem";

      # Optional extra nginx config
      # extraConfig = ''
      #   client_max_body_size 64m;
      # '';
    };
  };
}
```

## Tests

Available test coverage:

- [tests/nixos.nix](/home/basn/git/unimus/tests/nixos.nix)
  Covers the NixOS module with fake server/core services and nginx, including `propertiesFromFiles`.
- [tests/jars-vm.nix](/home/basn/git/unimus/tests/jars-vm.nix)
  Boots a VM and verifies the real upstream `2.8.0` JAR packages start and print their version banners.
