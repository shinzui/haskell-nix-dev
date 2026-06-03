# haskell-nix-dev

A reusable Nix **flake** providing complete Haskell toolchains — the **GHC** compiler, the
**Haskell Language Server** (HLS, the editor backend), and **cabal** (the build tool) — as
ready-to-use development shells and as buildable, cacheable packages.

It exists so individual Haskell projects do not each re-derive their own toolchain. Projects
add this flake as a single input, inherit its pinned `nixpkgs` (and therefore the exact GHC
builds) through one shared lock, and get a consistent editor + compiler setup. Upgrading the
toolchain everywhere becomes "bump this flake, then `nix flake update haskell-nix-dev` in
consumers."

## Supported toolchains

| GHC attribute | Version | Status |
|---------------|---------|--------|
| `ghc9124`     | 9.12.4  | available — the default |
| `ghc9141`     | 9.14.1  | planned (see the MasterPlan; added by appending it to `supportedGhcs`) |

The canonical list lives in `flake.nix` as `supportedGhcs`, with `defaultGhc = "ghc9124"`.
Adding or removing a version is a one-line change to that list.

Each toolchain provides, on `PATH`: `ghc`, `cabal`, and `haskell-language-server`. HLS is
built with library profiling disabled on `ghcide` and the `hls-*` packages (profiling is
useless for an editor backend and triggers a GHC 9.12.4 compiler panic when enabled); see
`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md` for the full rationale.

## Using it directly in this repo

On a machine with Nix and flakes enabled:

```bash
# Enter the default toolchain (GHC 9.12.4):
nix develop

# Or name a specific GHC:
nix develop .#ghc9124

# Inside the shell:
ghc --version                     # 9.12.4
cabal --version                   # 3.16.1.0
haskell-language-server --version # 2.13.0.0 (GHC: 9.12.4)
```

Build the whole toolchain as one cacheable package (what CI builds and pushes to the binary
cache):

```bash
nix build .#toolchain-ghc9124   # -> result/bin/{ghc,cabal,haskell-language-server}
nix flake check                 # builds the toolchain check; exits 0
nix fmt                         # formats Nix files via treefmt (nixpkgs-fmt)
```

## Consuming it from another project

Add this flake as an input and build a dev shell from its library. A minimal consumer
`flake.nix`:

```nix
{
  inputs.haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
  # Reuse this flake's nixpkgs so you inherit the exact GHC builds and one lock:
  inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, haskell-nix-dev }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = haskell-nix-dev.lib.${system}.mkDevShell {
          # ghc = "ghc9124";                 # optional; defaults to defaultGhc
          extraNativeBuildInputs = [ pkgs.just pkgs.postgresql ];
          shellHook = ''
            echo "project shell ready"
          '';
        };
      });
}
```

Then `nix develop` in that project gives GHC + cabal + HLS plus your extra packages.

If you just want the prebuilt shell with no extras, reference it directly instead of calling
`mkDevShell`:

```nix
devShells.default = haskell-nix-dev.devShells.${system}.default;   # = the ghc9124 shell
```

### Before this flake is pushed to GitHub

`github:shinzui/haskell-nix-dev` resolves only once this repo is published. Until then,
consume it by local path:

```nix
inputs.haskell-nix-dev.url = "path:/Users/shinzui/Keikaku/bokuno/haskell-nix-dev";
```

## Consumer API

All outputs are namespaced per `system` (e.g. `aarch64-darwin`):

- `lib.${system}.defaultGhc : String` — the default GHC attribute (`"ghc9124"`).
- `lib.${system}.ghcVersions : AttrSet` — maps each supported GHC attribute to
  `{ ghc; compiler; hls; cabal; }`.
- `lib.${system}.mkDevShell { ghc ? defaultGhc, extraNativeBuildInputs ? [], withHls ? true, shellHook ? "" }`
  — returns a `pkgs.mkShell` with that GHC's compiler, `cabal`, optional HLS, plus the
  caller's extra packages and shell hook.
- `devShells.${system}.<ghcName>` and `devShells.${system}.default` — prebuilt shells; the
  `default` is the `defaultGhc` shell.
- `packages.${system}.toolchain-<ghcName>` and `packages.${system}.default` — buildable
  toolchain bundles (compiler + cabal + HLS).
- `checks.${system}.toolchain-<ghcName>` — same derivations, so `nix flake check` builds them.
- `formatter.${system}` — a treefmt wrapper enabling `nix fmt`.

## Binary cache

`flake.nix` contains a `nixConfig` placeholder for a Cachix substituter and public key. Once
populated (see `docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md`),
consumers download prebuilt toolchains — including HLS — instead of compiling from source.

## Keeping consumers in lockstep

Each consumer has its own `flake.lock`. They share one toolchain derivation (and therefore the
binary cache) only while they all pin the **same** `haskell-nix-dev` revision — `nixpkgs`
follows it, so the pin decides the GHC/cabal/HLS builds. Update one project alone and it drifts
off the shared cache until the rest catch up.

`scripts/update-haskell-toolchain.sh` bumps every consumer flake under a workspace in lockstep
and verifies they end up on one rev. It scans for `flake.nix` files that reference this base
flake, is **dry-run by default**, and never commits.

```bash
just check-toolchain                 # report each consumer's pinned rev (no writes)
just update-toolchain                # bump all consumers to the latest rev, in lockstep
just update-toolchain-rev <rev>      # pin all consumers to a specific rev
just update-toolchain-root <dir>     # scan a different workspace root

# or call the script directly:
./scripts/update-haskell-toolchain.sh [--root DIR] [--rev REV] [--apply]
```

After an update, review and commit each repo's `flake.lock` yourself.
