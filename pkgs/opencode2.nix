{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "opencode2";
  version = "2.0.24";

  src = fetchzip {
    url = "https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-${version}.tgz";
    hash = "sha256-ZvJTtrZvT5qwaYhdAi5L9MYwiE7Yy0aj9QyvPZeY7HM=";
  };

  # A bun standalone binary. Patching the ELF breaks it, see decisions/0010.
  dontStrip = true;
  dontFixup = true;
  dontPatchELF = true;

  installPhase = ''
    install -Dm755 bin/opencode $out/bin/opencode
  '';
}
