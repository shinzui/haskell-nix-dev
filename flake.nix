{
  description = "Reusable multi-version GHC/HLS/cabal toolchains for Haskell projects";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/4df1b885d76a54e1aa1a318f8d16fd6005b6401f";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  # Filled in by docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md:
  # the Cachix substituter and its public key, so consumers pull prebuilt toolchains instead
  # of building HLS from source.
  nixConfig = {
    extra-substituters = [ ]; # e.g. "https://<cache-name>.cachix.org"
    extra-trusted-public-keys = [ ]; # e.g. "<cache-name>.cachix.org-1:<base64>"
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix }:
    let
      # Canonical set of supported GHC attribute names. To add or drop a version,
      # edit this list (and keep defaultGhc pointing at a member). ghc9141 (9.14.1) is
      # intentionally deferred — see the MasterPlan Decision Log — and is added by appending
      # "ghc9141" here.
      supportedGhcs = [ "ghc9124" ];
      defaultGhc = "ghc9124";
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # For one GHC attribute, gather the toolchain components.
        #
        # HLS note: GHC 9.12.4 panics compiling ghcide's *profiling* objects on
        # aarch64-darwin, and ghcide/HLS are absent from cache.nixos.org, so HLS always
        # builds from source and always panics. Profiling libraries are useless for an editor
        # backend, so we disable library profiling on ghcide and the hls-* packages (and on
        # HLS itself). This keeps the ~337 leaf dependencies profiled+cached while rebuilding
        # only ~5 derivations. See the ExecPlan Decision Log / Surprises & Discoveries.
        toolchainFor = ghc:
          let
            hl = pkgs.haskell.lib;
            hp = pkgs.haskell.packages.${ghc}.extend (hself: hsuper:
              let
                names = builtins.filter
                  (n: n == "ghcide" || pkgs.lib.hasPrefix "hls-" n)
                  (builtins.attrNames hsuper);
              in
              builtins.listToAttrs (map
                (n: {
                  name = n;
                  value = hl.disableLibraryProfiling hsuper.${n};
                })
                names));
          in
          {
            inherit ghc;
            compiler = hp.ghc;
            hls = hl.disableLibraryProfiling hp.haskell-language-server;
            cabal = pkgs.cabal-install;
          };

        toolchains = pkgs.lib.genAttrs supportedGhcs toolchainFor;

        # The contract EP-3 (the seihou template) consumes. Keep these parameter names exactly.
        mkDevShell =
          { ghc ? defaultGhc
          , extraNativeBuildInputs ? [ ]
          , withHls ? true
          , shellHook ? ""
          }:
          let t = toolchains.${ghc};
          in pkgs.mkShell {
            nativeBuildInputs =
              [ t.compiler t.cabal pkgs.pkg-config pkgs.zlib ]
              ++ pkgs.lib.optional withHls t.hls
              ++ extraNativeBuildInputs;
            shellHook = ''
              export LANG=en_US.UTF-8
            '' + shellHook;
          };

        mkShellForGhc = ghc: mkDevShell { inherit ghc; };

        # A single buildable derivation per GHC bundling compiler + cabal + HLS, so a CI job
        # (EP-2) can `nix build` one target to realize and cache the whole toolchain.
        toolchainPackage = ghc:
          let t = toolchains.${ghc};
          in pkgs.buildEnv {
            name = "haskell-toolchain-${ghc}";
            paths = [ t.compiler t.cabal t.hls ];
          };

        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
        };
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        lib = {
          inherit mkDevShell;
          ghcVersions = toolchains;
          inherit defaultGhc;
        };

        devShells =
          (pkgs.lib.genAttrs supportedGhcs mkShellForGhc)
          // { default = mkShellForGhc defaultGhc; };

        packages =
          (pkgs.lib.mapAttrs'
            (ghc: _: pkgs.lib.nameValuePair "toolchain-${ghc}" (toolchainPackage ghc))
            toolchains)
          // { default = toolchainPackage defaultGhc; };

        checks = pkgs.lib.mapAttrs'
          (ghc: _: pkgs.lib.nameValuePair "toolchain-${ghc}" (toolchainPackage ghc))
          toolchains;
      });
}
