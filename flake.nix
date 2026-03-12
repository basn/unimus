{
  description = "NixOS flake for native Unimus and Unimus Core services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    {
      overlays = {
        unimus = final: prev: {
          mkUnimusPackage = final.callPackage ./pkgs/mk-unimus-package.nix { };
          unimus = final.callPackage ./pkgs/unimus.nix { };
          unimus-core = final.callPackage ./pkgs/unimus-core.nix { };
        };

        default = self.overlays.unimus;
      };

      nixosModules = {
        unimus = import ./modules/unimus.nix;
        default = self.nixosModules.unimus;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        formatter = pkgs.alejandra;

        packages = {
          unimus = pkgs.callPackage ./pkgs/unimus.nix { };
          unimus-core = pkgs.callPackage ./pkgs/unimus-core.nix { };
          default = pkgs.callPackage ./pkgs/unimus.nix { };
        };

        checks = {
          nixos = import ./tests/nixos.nix { inherit pkgs; };
          jars-vm = import ./tests/jars-vm.nix { inherit pkgs; };
        };
      });
}
