{ lib
, stdenvNoCC
, jre_headless
, pname
, jar
, version ? "unstable"
, jarName ? "${pname}.jar"
}:

stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/${pname} $out/bin
    install -m0644 ${jar} $out/share/${pname}/${jarName}

    cat > $out/bin/${pname} <<EOF
    #!${stdenvNoCC.shell}
    set -eu
    exec ${jre_headless}/bin/java ''${JAVA_OPTS-} -jar $out/share/${pname}/${jarName} "\$@"
    EOF
    chmod +x $out/bin/${pname}

    runHook postInstall
  '';

  meta = {
    description = "Java package wrapper for ${pname}";
    platforms = lib.platforms.linux;
  };
}
