{
  callPackage,
  fetchurl,
}:

callPackage ./mk-unimus-package.nix {
  pname = "unimus-core";
  version = "2.9.1";
  jar = fetchurl {
    url = "https://download.unimus.net/unimus-core/2.9.1/Unimus-Core.jar";
    hash = "sha256-QJlj0MaOaDiorNdw8rri7CgNpz6magXPAR9FbZFIn+4=";
  };
  jarName = "Unimus-Core.jar";
}
