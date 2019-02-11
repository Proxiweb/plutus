{ system ? builtins.currentSystem
, config ? {}
, localPackages ? import ./. { inherit config system; }
, pkgs ? localPackages.pkgs
}:

let
  localLib = import ./lib.nix { inherit config system; };
  forceDontCheck = false;
  enableProfiling = false;
  enableSplitCheck = true;
  enableDebugging = false;
  enableBenchmarks = true;
  enablePhaseMetrics = true;
  enableHaddockHydra = true;
  fasterBuild = false;
  forceError = true;
  # This is the stackage LTS plus overrides, plus the plutus
  # packages.
  haskellPackages = let
    errorOverlay = import ./nix/overlays/force-error.nix {
      pkgs = localLib.pkgs;
      filter = localLib.isPlutus;
    };
  customOverlays = with localLib.pkgs.lib; optional forceError errorOverlay;
  pkgsGenerated = import ./pkgs { inherit pkgs; };
  in localLib.pkgs.callPackage localLib.iohkNix.haskellPackages {
    inherit forceDontCheck enableProfiling enablePhaseMetrics
    enableHaddockHydra enableBenchmarks fasterBuild enableDebugging
    enableSplitCheck customOverlays pkgsGenerated;
    inherit (pkgsGenerated) ghc;
    filter = localLib.isPlutus;
    filterOverrides = {
      splitCheck = let
        dontSplit = [
          # Broken for things with test tool dependencies
          "wallet-api"
          "plutus-tx"
          # Broken for things which pick up other files at test runtime
          "plutus-playground-server"
        ];
        # Split only local packages not in the don't split list
        doSplit = builtins.filter (name: !(builtins.elem name dontSplit)) localLib.plutusPkgList;
        in name: builtins.elem name doSplit;
    };
    requiredOverlay = ./nix/overlays/required.nix;
  };
  selected = localLib.pkgs.lib.attrValues (localLib.pkgs.lib.filterAttrs (n: v: localLib.isPlutus n) haskellPackages);
  packageInputs = map localLib.pkgs.haskell.lib.getBuildInputs selected;
  haskellInputs = localLib.pkgs.lib.filter
    (input: localLib.pkgs.lib.all (p: input.outPath != p.outPath) selected)
    (localLib.pkgs.lib.concatMap (p: p.haskellBuildInputs) packageInputs);
  # These are tools that will be used by bazel
  ghc = haskellPackages.ghcWithPackages (ps: haskellInputs);
  happy = haskellPackages.happy;
  alex = haskellPackages.alex;
  hlint = haskellPackages.hlint;
  stylishHaskell = haskellPackages.stylish-haskell;
  # We need a specific version of bazel
  bazelNixpkgs = import (localLib.iohkNix.fetchNixpkgs ./nixpkgs-bazel-src.json) {};
  nodejs = bazelNixpkgs.nodejs;
  yarn = bazelNixpkgs.yarn;
  purescript = if pkgs.stdenv.isDarwin
    then pkgs.writeTextFile {name = "purescript"; text = ""; destination = "/bin/purs"; }
    else (import (localLib.iohkNix.fetchNixpkgs ./plutus-playground/plutus-playground-client/nixpkgs-src.json) {}).purescript;
  mkBazelScript = {name, script}: pkgs.stdenv.mkDerivation {
          name = name;
          unpackPhase = "true";
          buildInputs = [];
          buildPhase = "";
          installPhase = ''
            mkdir -p $out/bin
            cp ${script} $out/bin/run.sh
          '';
        };
  hlintScript = mkBazelScript { name = "hlintScript";
                                script = import ./test-scripts/hlint-script.nix {inherit pkgs haskellPackages;};
                                };
  stylishHaskellScript = mkBazelScript { name = "stylishHaskellScript";
                                         script = import ./test-scripts/stylish-haskell-script.nix {inherit pkgs haskellPackages;};
                                         };
  shellcheckScript = mkBazelScript { name = "shellcheckScript";
                                     script = import ./test-scripts/shellcheck-script.nix {inherit pkgs;};
                                     };
in
pkgs.mkShell {
  # XXX: hack for macosX, this flag disables bazel usage of xcode
  # Note: this is set even for linux so any regression introduced by this flag
  # will be caught earlier
  # See: https://github.com/bazelbuild/bazel/issues/4231
  BAZEL_USE_CPP_ONLY_TOOLCHAIN=1;

  buildInputs = [
    ghc
    pkgs.git
    pkgs.cacert
    bazelNixpkgs.bazel
  ];

  shellHook = ''
    # Add nix config flags to .bazelrc.local.
    #
    BAZELRC_LOCAL=".bazelrc.local"
    if [ ! -e "$BAZELRC_LOCAL" ]
    then
      ARCH=""
      if [ "$(uname)" == "Darwin" ]; then
        ARCH="darwin"
      elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        ARCH="linux"
      fi
      echo "To get started try running"
      echo ""
      echo 'bazel test --test_env BUILD_WORKSPACE_DIRECTORY=$(pwd) //...'
      echo ""
      echo "[!] It looks like you are using a ''${ARCH} nix-based system. In order to build this project, you probably need to add the two following host_platform entries to your .bazelrc.local file."
      echo ""
      echo "common --host_platform=@io_tweag_rules_purescript//purescript/platforms:''${ARCH}_x86_64_nixpkgs"
      echo "common --platforms=@io_tweag_rules_purescript//purescript/platforms:''${ARCH}_x86_64_nixpkgs"

    fi

    # source bazel bash completion
    source ${pkgs.bazel}/share/bash-completion/completions/bazel

    # link the tools bazel will import to predictable locations
    mkdir -p tools
    ln -nfs ${ghc} ./tools/ghc
    ln -nfs ${happy} ./tools/happy
    ln -nfs ${alex} ./tools/alex
    ln -nfs ${hlintScript} ./tools/hlint
    ln -nfs ${stylishHaskellScript} ./tools/stylish-haskell
    ln -nfs ${shellcheckScript} ./tools/shellcheck
    ln -nfs ${purescript} ./tools/purescript
    mkdir -p yarn-nix/bin
    ln -nfs ${nodejs} ./node-nix
    ln -nfs ${yarn}/bin/yarn ./yarn-nix/bin/yarn.js
  '';
}