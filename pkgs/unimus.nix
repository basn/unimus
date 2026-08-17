{
  callPackage,
  fetchurl,
}:

callPackage ./mk-unimus-package.nix {
  pname = "unimus";
  version = "2.9.1";
  jar = fetchurl {
    url = "https://download.unimus.net/unimus/2.9.1/Unimus.jar";
    hash = "sha256-j8o5Sw/GDpnd3HVOjSZ5Fwc6S8pLasSNBdvMAYVjhZE=";
  };
  jarName = "Unimus.jar";
}
