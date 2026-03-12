{ callPackage
, fetchurl
}:

callPackage ./mk-unimus-package.nix {
  pname = "unimus-core";
  version = "2.8.0";
  jar = fetchurl {
    url = "https://download.unimus.net/unimus-core/2.8.0/Unimus-Core.jar";
    hash = "sha256-74iiH12LmMZbxksiWqDH304fuT0wrex9bj9wLs7w22E=";
  };
  jarName = "Unimus-Core.jar";
}
