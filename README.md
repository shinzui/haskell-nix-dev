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

| GHC attribute | Version | Tools on `PATH`        | Notes |
|---------------|---------|------------------------|-------|
| `ghc9124`     | 9.12.4  | `ghc`, `cabal`, `haskell-language-server` | the default |
| `ghc9141`     | 9.14.1  | `ghc`, `cabal`         | secondary, via `nix develop .#ghc9141`; **no HLS** (see below) |

The canonical list lives in `flake.nix` as `supportedGhcs`, with `defaultGhc = "ghc9124"`.
The subset that ships HLS lives in `hlsGhcs`. Adding or removing a version, or enabling HLS
for one, is a one-line change to those lists.

HLS is built with library profiling disabled on `ghcide` and the `hls-*` packages (profiling
is useless for an editor backend and triggers a GHC 9.12.4 compiler panic when enabled).

**Why `ghc9141` ships without HLS.** HLS for GHC 9.14 is not currently buildable from
nixpkgs: its dependency closure carries many stale upper bounds (`base < 4.22`,
`containers < 0.8`, `template-haskell < 2.24`, `time < 1.15`, `hedgehog < 1.6`) across ~19+
packages, and at least one (`Cabal-syntax`) resists `doJailbreak` because a Hackage cabal-file
revision re-imposes the bound. The GHC 9.14.1 *compiler* and `cabal` are fine and cached, so
`ghc9141` is provided as a compiler+cabal toolchain — enough to build and test libraries
against 9.14 — without HLS. Add `ghc9141` to `hlsGhcs` once nixpkgs ships a buildable 9.14
HLS. See `docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md` for the full
rationale.

## Using it directly in this repo

On a machine with Nix and flakes enabled:

```bash
# Enter the default toolchain (GHC 9.12.4):
nix develop

# Or name a specific GHC:
nix develop .#ghc9124
nix develop .#ghc9141   # the secondary toolchain (GHC 9.14.1, compiler + cabal, no HLS)

# Inside the default shell:
ghc --version                     # 9.12.4
cabal --version                   # 3.16.1.0
haskell-language-server --version # 2.13.0.0 (GHC: 9.12.4)
```

Build the whole toolchain as one cacheable package (what CI builds and pushes to the binary
cache):

```bash
nix build .#toolchain-ghc9124   # -> result/bin/{ghc,cabal,haskell-language-server}
nix build .#toolchain-ghc9141   # the 9.14.1 bundle (ghc + cabal; no HLS)
nix flake check                 # builds the toolchain checks; exits 0
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

## Consumer API

All outputs are namespaced per `system` (e.g. `aarch64-darwin`):

- `lib.${system}.defaultGhc : String` — the default GHC attribute (`"ghc9124"`).
- `lib.${system}.ghcVersions : AttrSet` — maps each supported GHC attribute to
  `{ ghc; compiler; hls; cabal; }`. `hls` is `null` for GHCs not in `hlsGhcs` (currently
  `ghc9141`).
- `lib.${system}.mkDevShell { ghc ? defaultGhc, extraNativeBuildInputs ? [], withHls ? <hls shipped for ghc>, shellHook ? "" }`
  — returns a `pkgs.mkShell` with that GHC's compiler, `cabal`, optional HLS, plus the
  caller's extra packages and shell hook. `withHls` defaults to whether that GHC ships HLS;
  for a GHC without HLS, passing `withHls = true` is a harmless no-op (there is no buildable
  HLS to add).
- `devShells.${system}.<ghcName>` and `devShells.${system}.default` — prebuilt shells; the
  `default` is the `defaultGhc` shell.
- `packages.${system}.toolchain-<ghcName>` and `packages.${system}.default` — buildable
  toolchain bundles (compiler + cabal, plus HLS for GHCs in `hlsGhcs`).
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
