{
  pkgs ? import <nixpkgs> { },
}:
let
  unimusPackage = pkgs.callPackage ../pkgs/mk-unimus-package.nix {
    pname = "unimus";
    jar = pkgs.fetchurl {
      url = "https://download.unimus.net/unimus/2.9.1/Unimus.jar";
      hash = "sha256-j8o5Sw/GDpnd3HVOjSZ5Fwc6S8pLasSNBdvMAYVjhZE=";
    };
  };

  unimusCorePackage = pkgs.callPackage ../pkgs/mk-unimus-package.nix {
    pname = "unimus-core";
    jar = pkgs.fetchurl {
      url = "https://download.unimus.net/unimus-core/2.9.1/Unimus-Core.jar";
      hash = "sha256-QJlj0MaOaDiorNdw8rri7CgNpz6magXPAR9FbZFIn+4=";
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "unimus-jars-vm";

  nodes.machine = { ... }: {
    environment.systemPackages = [
      unimusPackage
      unimusCorePackage
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("install -d /var/lib/unimus /var/log/unimus /etc/unimus")
    machine.succeed("timeout 15s env JAVA_OPTS='-Dserver.address=127.0.0.1 -Dserver.port=18085' unimus >/tmp/unimus.out 2>&1 || test $? -eq 124")
    machine.succeed("grep -q 'version 2.9.1' /tmp/unimus.out")

    machine.succeed("install -d /var/lib/unimus-core /var/log/unimus-core /etc/unimus-core")
    machine.succeed("timeout 15s unimus-core >/tmp/unimus-core.out 2>&1 || true")
    machine.succeed("grep -q 'version 2.9.1' /tmp/unimus-core.out")
  '';
}
