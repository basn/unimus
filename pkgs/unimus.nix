{ callPackage
, fetchurl
}:

callPackage ./mk-unimus-package.nix {
  pname = "unimus";
  version = "2.8.0";
  jar = fetchurl {
    url = "https://download.unimus.net/unimus/2.8.0/Unimus.jar";
    hash = "sha256-fMpxC45zUGTTqUXlqEUUNIMkZsh5YhsKCMWDOLMwYfU=";
  };
  jarName = "Unimus.jar";
}
