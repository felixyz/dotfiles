{
  lib,
  buildGoModule,
  go_1_26,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  webkitgtk_6_0,
  libsoup_3,
  glib-networking,
  nodejs_22,
  git,
  xdg-utils,
}:
# Bump: set version, set both hashes to lib.fakeHash, build, paste the "got:"
# hash for src, build again, paste the one for vendorHash.
(buildGoModule.override {go = go_1_26;}) rec {
  pname = "juggler";
  version = "0.6.4";

  src = fetchFromGitHub {
    owner = "juggler-ai";
    repo = "juggler";
    rev = "v${version}";
    # go.mod replaces github.com/wailsapp/wails/v3 with the 3rdparty/wails
    # submodule, so the vendor step fails without it.
    fetchSubmodules = true;
    hash = "sha256-jPg1z8PAXUvvLNEzHpl5NyK5rwEFtTr2JLJXelYtos8=";
  };

  vendorHash = "sha256-RjcQjEUo/2exaLWAol50+L1rnh+vDDpxX+PGd7PWmNc=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];
  buildInputs = [
    gtk4
    webkitgtk_6_0
    libsoup_3
    glib-networking
  ];

  subPackages = [
    "cmd/juggler"
    "cmd/juggler-app"
  ];

  # Same as upstream's `make release-build`. Drops the test-only handlers.
  tags = ["production"];

  ldflags = [
    "-s"
    "-w"
    "-X juggler/cmd/juggler/core.stampedVersion=${version}-nix"
  ];

  # icon.png is gitignored and copied in by the Makefile,
  # which buildGoModule does not run. Without it `//go:embed icon.png` fails.
  preBuild = ''
    cp assets/icons/juggler-icon.png cmd/juggler/app/icon.png
  '';

  # The test suite spawns a WebKitGTK webview and needs a display.
  doCheck = false;

  # With Node 22 or newer on PATH the server runs its engine in a Node child
  # process instead of a hidden webview, so it works without a display.
  # The PATH entry goes into the GApps wrapper so the binaries are not wrapped twice.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        nodejs_22
        git
        xdg-utils
      ]
    })
  '';

  meta = {
    description = "Visual AI coding agent, headless server plus GTK desktop client";
    homepage = "https://juggler.studio";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "juggler";
  };
}
