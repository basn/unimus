{
  pkgs ? import <nixpkgs> { },
}:
let
  unimusModule = import ../modules/unimus.nix;

  fakeUnimusPackage = pkgs.writeShellScriptBin "unimus" ''
    set -eu

    addr="127.0.0.1"
    port="8085"

    for opt in $JAVA_OPTS; do
      case "$opt" in
        -Dserver.address=*)
          addr="''${opt#-Dserver.address=}"
          ;;
        -Dserver.port=*)
          port="''${opt#-Dserver.port=}"
          ;;
      esac
    done

    hostname > "$UNIMUS_STATE_DIR/hostname"

    cat > "$UNIMUS_STATE_DIR/index.html" <<EOF
    fake unimus
    EOF

    exec ${pkgs.python3}/bin/python -m http.server "$port" --bind "$addr" --directory "$UNIMUS_STATE_DIR"
  '';

  fakeUnimusCorePackage = pkgs.writeShellScriptBin "unimus-core" ''
    set -eu

    mkdir -p "$UNIMUS_STATE_DIR"
    printf 'core alive\n' > "$UNIMUS_STATE_DIR/core-status"

    exec ${pkgs.bash}/bin/bash -c 'trap "exit 0" TERM INT; while true; do sleep 3600; done'
  '';
in
(pkgs.testers.runNixOSTest {
  name = "unimus-services";

  nodes.machine = { ... }: {
    imports = [ unimusModule ];

    environment.systemPackages = [ pkgs.curl ];

    environment.etc."unimus-test-secret".text = "super-secret-password\n";

    services.unimus.server = {
      enable = true;
      package = fakeUnimusPackage;
      port = 18085;
      listenAddress = "127.0.0.1";
      reverseProxy = {
        enable = true;
        hostName = "unimus.test";
        port = 8080;
      };
      propertiesFromFiles = {
        "database.password" = "/etc/unimus-test-secret";
      };
    };

    services.unimus.core = {
      enable = true;
      package = fakeUnimusCorePackage;
      stateDir = "/var/lib/unimus-core";
      logDir = "/var/log/unimus-core";
      configDir = "/etc/unimus-core";
      properties = {
        "unimus.address" = "127.0.0.1";
        "unimus.port" = 18085;
      };
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("unimus.service")
    machine.wait_for_unit("unimus-core.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(18085)
    machine.wait_for_open_port(8080)

    machine.succeed("test -f /etc/unimus/unimus.properties")
    machine.succeed("test -f /etc/unimus-core/unimus-core.properties")
    machine.succeed("grep -q '^database.password=super-secret-password$' /etc/unimus/unimus.properties")
    machine.succeed("systemctl is-active unimus-core.service")
    machine.succeed("test -f /var/lib/unimus-core/core-status")
    machine.succeed("test -s /var/lib/unimus/hostname")
    machine.succeed("curl -H 'Host: unimus.test' -fsS http://127.0.0.1:8080 | grep -q 'fake unimus'")
  '';
})
