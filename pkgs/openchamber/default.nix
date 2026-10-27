{
  lib,
  buildNpmPackage,
  buildFHSEnv,
  fetchzip,
  writeShellScript,
  jq,
  nodejs_22,
  opencode2,
}: let
  version = "2.1.1";

  openchamber-web = buildNpmPackage {
    pname = "openchamber-web";
    inherit version;

    src = fetchzip {
      url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
      hash = "sha256-yOmjwEBPENwI/8AphBfknhDpmbnLQzwp692mIAIWa30=";
    };

    nodejs = nodejs_22;
    npmDepsHash = "sha256-vyVna/FM6n6dN8D2Pqvv83D0Eqm6ybwPDyU3yFBvVpk=";

    # package-lock.json was generated from package.json without its devDependencies,
    # and npm refuses a lockfile that does not match.
    postPatch = ''
      ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./package-lock.json} package-lock.json
    '';

    # node-pty's install script falls back to compiling with node-gyp.
    # Its prebuilt binary ships in the package and loads without the script.
    npmFlags = ["--ignore-scripts"];
    npmRebuildFlags = ["--ignore-scripts"];
    dontNpmBuild = true;
    dontStrip = true;
  };
in
  buildFHSEnv {
    name = "openchamber";
    targetPkgs = pkgs: [
      pkgs.glibc
      pkgs.stdenv.cc.cc.lib
      pkgs.git
      nodejs_22
    ];
    runScript = writeShellScript "openchamber" ''
      export OPENCODE_BINARY="''${OPENCODE_BINARY:-${opencode2}/bin/opencode}"
      export OPENCODE_DISABLE_AUTOUPDATE="''${OPENCODE_DISABLE_AUTOUPDATE:-1}"
      export OPENCHAMBER_RELAY_HOST="''${OPENCHAMBER_RELAY_HOST:-off}"
      exec ${openchamber-web}/bin/openchamber "$@"
    '';
    extraBwrapArgs = [
      "--symlink"
      "/.host-etc/containers"
      "/etc/containers"
    ];
    passthru = {inherit openchamber-web;};
  }
