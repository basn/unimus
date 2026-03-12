{
  description = "NixOS flake for native Unimus and Unimus Core services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      overlays.default = final: prev: {
        mkUnimusPackage = final.callPackage ./pkgs/mk-unimus-package.nix { };
      };

      checks = forAllSystems (pkgs: {
        nixos = import ./tests/nixos.nix { inherit pkgs; };
        jars-vm = import ./tests/jars-vm.nix { inherit pkgs; };
      });

      nixosTests = forAllSystems (pkgs: {
        unimus = import ./tests/nixos.nix { inherit pkgs; };
        unimus-jars = import ./tests/jars-vm.nix { inherit pkgs; };
      });

      nixosModules.default = import ./modules/unimus.nix;
    };
}
