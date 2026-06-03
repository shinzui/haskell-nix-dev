---
id: 1
slug: base-flake-providing-multi-version-ghc-hls-and-cabal
title: "Base flake providing multi-version GHC, HLS, and cabal"
kind: exec-plan
created_at: 2026-06-03T15:41:55Z
intention: "intention_01kt71x4veegvsc87z3qmsbab7"
master_plan: "docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md"
---

# Base flake providing multi-version GHC, HLS, and cabal

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This plan is the foundation of the MasterPlan at
`docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md`. Two sibling plans depend on
the artifacts produced here: `docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md`
builds and caches the toolchain outputs defined here, and
`docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md`
calls the consumer API defined here. You do not need to read those plans to implement this
one, but if you change any public name described under "Interfaces and Dependencies" you must
update the MasterPlan's Integration Points section so the other plans stay consistent.


## Purpose / Big Picture

A **flake** is a directory containing a `flake.nix` file that declares pinned `inputs`
(other git repositories at exact revisions, recorded in a generated `flake.lock`) and
produces `outputs` (packages, development shells, and reusable functions) that other flakes
can import. **GHC** is the Haskell compiler; **HLS** (Haskell Language Server) is the
editor backend that powers go-to-definition and type-on-hover; **cabal** is the Haskell
build tool. A **development shell** (`devShell`) is an environment you enter with
`nix develop` that puts a chosen set of tools on your `PATH` without installing them
globally.

After this plan, the repository `haskell-nix-dev` (the one you are working in) will contain a
`flake.nix` that provides complete Haskell toolchains — GHC, HLS, and cabal — for **two GHC
versions at once**: GHC 9.12.4 and the latest GHC 9.14 available in the pinned nixpkgs. You
will be able to run, on a machine with Nix and flakes enabled:

```bash
nix develop .#ghc9124 --command ghc --version
# -> The Glorious Glasgow Haskell Compilation System, version 9.12.4

nix develop .#<latest-9.14-attr> --command ghc --version
# -> The Glorious Glasgow Haskell Compilation System, version 9.14.x
```

and in each shell `cabal --version` and `haskell-language-server --version` will both work.
`nix develop` with no attribute (the default shell) will give the GHC 9.12.4 toolchain. The
flake will also expose a small reusable library so other flakes can build their own shells
on top of these toolchains, and it will expose buildable package outputs so a CI job (a
sibling plan) can build the toolchains once and cache them.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Confirm flakes are usable; resolve the exact nixpkgs attribute for the latest 9.14. (2026-06-03 — Determinate Nix 3.17.0 / 2.33.3, flakes enabled; latest 9.14 attr is `ghc9141` = 9.14.1)
- [x] M1: Pin nixpkgs to a revision that contains both `haskell.packages.ghc9124` and the latest 9.14; record findings. (2026-06-03 — single unstable rev `4df1b885d76a54e1aa1a318f8d16fd6005b6401f` has ghc9124=9.12.4 and ghc9141=9.14.1)
- [x] M1: Measure which toolchain components for each GHC are already in `cache.nixos.org` vs build-from-source. (2026-06-03 — ghc9141 HLS = 345 derivations from source; ghc9124 HLS = 4; both compilers + cabal cached)
- [ ] M2: Write a minimal `flake.nix` exposing `devShells.<system>.ghc9124` and `.<latest-9.14>` with ghc + cabal + HLS.
- [ ] M2: Verify `ghc`, `cabal`, and `haskell-language-server` all run inside each shell.
- [ ] M3: Add `ghcVersions`, `defaultGhc`, and `lib.<system>.mkDevShell`; make `default` the 9.12.4 shell.
- [ ] M3: Add a `formatter` output via treefmt-nix (nixpkgs-fmt) so `nix fmt` works.
- [ ] M4: Expose buildable toolchain outputs (`packages.<system>.*`) and a `checks` set; `nix flake check` passes.
- [ ] M4: Add a `nixConfig` placeholder block (substituters filled in by the Cachix plan) and a README.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

**M1 — Feasibility and version resolution (2026-06-03, system `aarch64-darwin`).**

- Environment: Determinate Nix 3.17.0 (Nix 2.33.3), `nix-command` + `flakes` enabled by
  default — no extra experimental-features flags were needed.
- GHC 9.14 attributes present in current unstable nixpkgs `haskell.compiler`: `ghc914`
  (series alias) and `ghc9141` (concrete). **Resolved latest-9.14 attribute = `ghc9141`**,
  version `9.14.1`. We pick the concrete attribute (mirrors how `ghc9124` pins an exact patch
  level), not the `ghc914` alias.
- `ghc9124` still exists in the same unstable nixpkgs, version `9.12.4`. A single nixpkgs
  revision therefore contains both compilers; no second nixpkgs input is needed.
- **Pinned nixpkgs revision: `4df1b885d76a54e1aa1a318f8d16fd6005b6401f`** (the
  `nixpkgs-unstable` branch as resolved on 2026-06-03). We pin the explicit revision so the
  lock is stable.
- Upstream cache coverage (`nix build --dry-run` against `cache.nixos.org`):
  - `ghc9124` compiler: fully cached (nothing to build). `cabal-install` (shared): fully
    cached. `ghc9124` `haskell-language-server`: only 4 derivations build from source
    (`lsp-test`, `ghcide`, `hls-test-utils`, `haskell-language-server` 2.13.0.0) — the rest
    substitute.
  - `ghc9141` compiler: cached (fetched, 306 MiB download). `ghc9141`
    `haskell-language-server`: **345 derivations build from source** — essentially the entire
    9.14 Haskell package set is *not* in the upstream binary cache.
- Implication for EP-2 (Cachix): the bulk of the caching value is on the **9.14 toolchain**
  (HLS + its 345-package closure). The 9.12.4 toolchain is nearly free from upstream already.
  Recorded in the MasterPlan's Surprises & Discoveries for the sibling plans.

**M2 — HLS profiling panic on aarch64-darwin (2026-06-03).** The first `nix develop .#ghc9124`
attempt failed because `haskell-language-server` for `ghc9124` is not in `cache.nixos.org`
(confirmed: narinfo 404 on both aarch64-darwin and x86_64-linux output paths) and its
from-source build **panics**:

```text
> [75 of 79] Compiling Text.Fuzzy.Levenshtein ( ... dist/build/.../*.p_o )
> ghc: panic! ... pprPanic, called at compiler/GHC/Core/Subst.hs:196:17 in ghc-9.12.4
> Please report this as a GHC bug
```

The `.p_o` extension shows it panics compiling **profiling** objects of `ghcide`. Findings:

- Building `ghcide` with `disableLibraryProfiling` succeeds (exit 0) — the panic is
  profiling-specific.
- Disabling profiling on `ghcide` alone then fails its profiled consumers with
  `GHC-88719: ... haven't installed the profiling libraries for package 'ghcide'`
  (e.g. `hls-test-utils`). `dontCheck` on HLS does **not** drop `hls-test-utils` from the
  closure.
- Disabling profiling **globally** on the package set builds 341 derivations from source
  (the cached profiled leaf deps all become non-profiled).
- Disabling profiling on the **`ghcide` + `hls-*` upper tree** (plus HLS itself) is
  consistent and rebuilds only **5 derivations** (`hls-graph`, `hls-plugin-api`, `ghcide`,
  `hls-test-utils`, `haskell-language-server`); leaf deps stay profiled+cached. **This is the
  chosen fix** (see Decision Log). Verified: produced
  `/nix/store/5zh48s6rsfzlqzdhrykf6376ydp0gbcy-haskell-language-server-2.13.0.0`.
- Local build time for the 5-derivation HLS fix on this machine (with other CPU-heavy work
  running): ~10–13 minutes. EP-2/Cachix will eliminate this for consumers.
- This panic and the same fix are expected to recur for `ghc9141` when it is added (deferred
  per Decision Log); 9.14 additionally builds its whole HLS closure (~345) from source.


## Decision Log

Record every decision made while working on the plan.

- Decision: Use plain nixpkgs (`pkgs.haskell.packages.<ghc>`) rather than haskell.nix.
  Rationale: Inherited from the MasterPlan Decision Log (2026-06-03); the user targets
  "the latest 9.14 available in nixpkgs."
  Date: 2026-06-03

- Decision: Default GHC is `ghc9124`; the second supported version is the latest 9.14.
  Rationale: Inherited from the MasterPlan; keeps the common `nix develop` path on the stable
  primary version.
  Date: 2026-06-03

- Decision: Resolve the latest 9.14 to the concrete attribute `ghc9141` (9.14.1) and pin a
  single nixpkgs revision `4df1b885d76a54e1aa1a318f8d16fd6005b6401f` (option (a) from the
  plan) that contains both `ghc9124` and `ghc9141`.
  Rationale: M1 discovery confirmed both compilers exist in the same current-unstable
  revision, so a single lock and single cache domain suffice; no need for the heavier
  two-nixpkgs-input fallback. The concrete `ghc9141` pins an exact patch level the way
  `ghc9124` does.
  Date: 2026-06-03

- Decision: Build HLS with **library profiling disabled on `ghcide` and the `hls-*`
  packages** (and on `haskell-language-server` itself), rather than the nixpkgs default
  (profiling enabled) or a global profiling-disable across the whole package set.
  Rationale: On aarch64-darwin, building `ghcide` 2.13.0.0 with library profiling triggers a
  GHC 9.12.4 compiler **panic** (`GHC.Core.Subst` pprPanic compiling profiling `.p_o`
  objects); the package is also absent from `cache.nixos.org`, so it always builds from
  source and always panics. Disabling profiling only on `ghcide` then breaks every *profiled*
  consumer of it (`hls-test-utils`, the `hls-*` plugins) with GHC-88719 "haven't installed
  the profiling libraries for package ghcide". Disabling profiling globally fixes consistency
  but un-caches the ~337 leaf dependencies (4→341 from-source builds), discarding the upstream
  cache benefit. Disabling profiling on just the `ghcide`+`hls-*` upper tree is consistent
  (no profiled consumer of `ghcide` remains), leaves the leaf deps profiled+cached, and
  reduces the rebuild to **5 derivations** (`hls-graph`, `hls-plugin-api`, `ghcide`,
  `hls-test-utils`, `haskell-language-server`). Profiling libraries are useless for an editor
  backend, so dropping them costs nothing. Verified: full HLS built successfully this way for
  `ghc9124`.
  Date: 2026-06-03

- Decision: Land `ghc9124` end-to-end first (devShells, consumer API, packages/checks,
  formatter, README, `nix flake check` green, committed and consumable from other projects),
  then add `ghc9141` to `supportedGhcs` as a follow-up. The flake's `supportedGhcs` list makes
  adding 9.14 a one-line change.
  Rationale: User requested (2026-06-03) to finish a working single-version deliverable before
  paying the expensive 9.14 build (345 from-source derivations for its HLS) and to start
  consuming the flake in other projects immediately. Sequencing this way delivers usable value
  first and isolates the heavy 9.14 build/cache work.
  Date: 2026-06-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

You are working in the git repository at `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev`. At
the start of this plan it contains only planning and tooling scaffolding: `agents/skills/`
and `.claude/skills/` (the planning skills), `.seihou/` (template-tool state), `docs/plans/`
and `docs/masterplans/` (this plan and its MasterPlan), and a `.gitignore`. There is **no**
`flake.nix` yet; you are creating it.

This flake will be published and consumed by other projects as the flake input
`github:shinzui/haskell-nix-dev`. Keep its public output names stable once defined (see
Interfaces and Dependencies).

Key Nix concepts used below, defined in plain terms:

- **nixpkgs**: the large repository of Nix package definitions. We pin it to one exact git
  revision so builds are reproducible. `pkgs = import nixpkgs { inherit system; }` gives the
  package set for one platform.
- **system**: a platform string like `x86_64-linux`, `aarch64-darwin` (Apple Silicon macOS),
  or `x86_64-darwin`. Flake outputs are produced per system.
- **flake-utils**: a small helper whose `eachDefaultSystem` function builds the per-system
  outputs for the common systems without repeating yourself. The existing `seihou` templates
  already use it, so we match that idiom.
- **`pkgs.haskell.packages.<attr>`**: a complete Haskell package set built with a specific
  GHC. `<attr>` is a name like `ghc9124`. Inside it you find `ghc` (the compiler),
  `haskell-language-server`, and other Haskell packages built with that compiler.
- **`pkgs.haskell.compiler.<attr>`**: the bare GHC compiler derivation for that version (no
  package set). Useful to confirm a version exists.
- **`ghcWithPackages`**: a function that builds a GHC wrapper bundling extra Haskell
  libraries. The current template uses it to add HLS; this plan does *not* bundle HLS into a
  GHC wrapper — it adds `haskell-language-server` as its own package on the shell `PATH`,
  which keeps the GHC closure smaller and caches more cleanly.
- **`pkgs.mkShell`**: builds a development shell. Its `nativeBuildInputs` list names the
  packages put on `PATH`; its `shellHook` is a bash snippet run on shell entry.
- **treefmt-nix**: a formatter aggregator. Its `evalModule` produces a wrapper that runs
  configured formatters; exposing it as the flake's `formatter` output makes `nix fmt` work.

The closest existing reference is the template this initiative will eventually feed:
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/files/flake.nix.tpl`.
That file shows the project's house style: `inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable"`,
`flake-utils.lib.eachDefaultSystem`, `pkgs.haskell.packages."ghc9124"`, and a `devShells.default`
built with `pkgs.mkShell`. We deliberately diverge from it in two ways: we support multiple
GHCs, and we add HLS as a standalone package rather than via `ghcWithPackages`.

Term of art — **binary cache / substituter**: a remote store of already-built Nix artifacts.
When a substituter has a build, Nix downloads it instead of compiling. `cache.nixos.org` is
the public one; a later sibling plan adds a Cachix cache. This plan only leaves a placeholder
for the substituter configuration.


## Plan of Work

The work proceeds in four milestones. Milestone 1 is pure investigation and de-risks the
rest by nailing down the one unknown fact (the exact 9.14 attribute and what nixpkgs already
caches). Milestones 2–4 build up the flake additively, each independently verifiable.

### Milestone 1 — Feasibility and version resolution

Scope: determine the exact nixpkgs attribute name for the latest GHC 9.14, choose a nixpkgs
revision that contains both it and `ghc9124`, and measure what is already cached upstream.
At the end you will have written concrete facts into Surprises & Discoveries and chosen a
nixpkgs pin; no `flake.nix` exists yet.

First confirm your environment has Nix with flakes enabled. Run:

```bash
nix --version
```

If `nix flake` subcommands error about experimental features, enable them for the session by
prefixing commands with
`--extra-experimental-features 'nix-command flakes'`, or add
`experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`.

Discover the available GHC compiler attributes in current unstable nixpkgs without cloning
it. The attribute set `haskell.compiler` lists every GHC; filter for 9.14:

```bash
nix eval --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let pkgs = import (builtins.getFlake "github:nixos/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; };
        names = builtins.attrNames pkgs.haskell.compiler;
        is914 = n: builtins.match "ghc914.*" n != null;
    in builtins.concatStringsSep " " (builtins.filter is914 names)
  '
```

Expected output is one or more attribute names such as `ghc9141` (and possibly `ghc914`
as an alias). Record the full list. The "latest 9.14" is the highest concrete version
(prefer a fully-specified attribute like `ghc9141` over a bare-series alias like `ghc914`,
because the concrete one pins an exact patch level the way `ghc9124` does). Confirm the
exact compiler version string:

```bash
nix eval --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let pkgs = import (builtins.getFlake "github:nixos/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; };
    in pkgs.haskell.compiler.<resolved-9.14-attr>.version
  '
# -> e.g. 9.14.1
```

Also confirm `ghc9124` still exists in the same nixpkgs (the existing template uses it):

```bash
nix eval --extra-experimental-features 'nix-command flakes' \
  --impure --raw --expr '
    let pkgs = import (builtins.getFlake "github:nixos/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; };
    in pkgs.haskell.compiler.ghc9124.version
  '
# -> 9.12.4
```

If `ghc9124` is absent from current unstable (it may have aged out), you have two options;
choose the first that works and record the choice in the Decision Log: (a) pin nixpkgs to an
older revision that still has `ghc9124` but also has a 9.14 — check the existing template's
locked revision `f9d8b65950353691ab56561e7c73d2e1063d810b` first, since it was chosen to
have `ghc9124`; or (b) keep two nixpkgs inputs (one per GHC) — this is heavier and should be
a last resort. Strongly prefer (a): a single nixpkgs revision keeps one lock and one cache
domain.

Measure cache coverage. For each GHC attribute, ask Nix what it would do to realize the HLS
and cabal — whether it would substitute (download) or build. A `--dry-run` build reports
"these paths will be fetched" (cached) vs "these derivations will be built" (from source):

```bash
nix build --extra-experimental-features 'nix-command flakes' --dry-run --impure --expr '
  let pkgs = import (builtins.getFlake "github:nixos/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; };
  in pkgs.haskell.packages.<attr>.haskell-language-server
' 2>&1 | sed -n '1,40p'
```

Record, per GHC, whether HLS, cabal-install, and the compiler are fetched or built. This
tells the Cachix plan how much it must build. Write all findings (resolved 9.14 attribute,
chosen nixpkgs revision, version strings, and cache measurements) into Surprises &
Discoveries, and note the resolved 9.14 attribute in the MasterPlan's Surprises & Discoveries
so the sibling plans can use it.

Acceptance for M1: Surprises & Discoveries names the exact 9.14 attribute (e.g. `ghc9141`),
its version string, the nixpkgs revision you will pin, and a fetched/built breakdown for each
GHC's HLS and cabal.

### Milestone 2 — Minimal multi-GHC flake

Scope: create `flake.nix` and lock it, exposing two named development shells that each
contain a working GHC, cabal, and HLS. Throughout this plan, replace the placeholder
`<ghc914>` with the attribute you resolved in M1 (e.g. `ghc9141`).

Create `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev/flake.nix` with the following content.
It pins nixpkgs to the revision chosen in M1 (replace `REPLACE_WITH_REV` with that 40-char
git revision; using the explicit revision rather than the `nixpkgs-unstable` branch is what
makes the lock stable). It builds, for each GHC in a small list, a shell that puts the
compiler, cabal, and HLS on `PATH`.

```nix
{
  description = "Reusable multi-version GHC/HLS/cabal toolchains for Haskell projects";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/REPLACE_WITH_REV";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Canonical set of supported GHC attribute names. To add or drop a version,
      # edit this list (and keep defaultGhc pointing at a member).
      supportedGhcs = [ "ghc9124" "<ghc914>" ];
      defaultGhc = "ghc9124";
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # For one GHC attribute, gather the toolchain components.
        toolchainFor = ghc:
          let hp = pkgs.haskell.packages.${ghc};
          in {
            inherit ghc;
            compiler = hp.ghc;
            hls = hp.haskell-language-server;
            cabal = pkgs.cabal-install;
          };

        toolchains = pkgs.lib.genAttrs supportedGhcs toolchainFor;

        mkShellForGhc = ghc:
          let t = toolchains.${ghc};
          in pkgs.mkShell {
            nativeBuildInputs = [
              t.compiler
              t.cabal
              t.hls
              pkgs.pkg-config
              pkgs.zlib
            ];
            shellHook = ''
              export LANG=en_US.UTF-8
            '';
          };
      in
      {
        devShells =
          (pkgs.lib.genAttrs supportedGhcs mkShellForGhc)
          // { default = mkShellForGhc defaultGhc; };
      });
}
```

Generate the lock and enter each shell to verify the toolchains:

```bash
cd /Users/shinzui/Keikaku/bokuno/haskell-nix-dev
nix flake lock
git add flake.nix flake.lock
nix develop .#ghc9124 --command bash -lc 'ghc --version && cabal --version && haskell-language-server --version'
nix develop .#<ghc914> --command bash -lc 'ghc --version && cabal --version && haskell-language-server --version'
nix develop --command bash -lc 'ghc --version'   # default == ghc9124
```

Acceptance for M2: each of the three commands prints the expected compiler version (9.12.4
for `ghc9124` and the default shell; 9.14.x for the `<ghc914>` shell), and `cabal` and
`haskell-language-server` report versions without error. Note in Surprises & Discoveries how
long the first build took and whether HLS built from source (it likely will until the Cachix
plan lands).

### Milestone 3 — Consumer API and formatter

Scope: turn the minimal flake into a reusable one by exposing a library function and metadata
that the `seihou` template (a sibling plan) will call, and add a `formatter` so `nix fmt`
works in this repo. At the end, other flakes can build shells on top of these toolchains
without copying the shell-construction logic.

Edit `flake.nix` to add a `treefmt-nix` input and to expose, per system, a `lib` with a
`mkDevShell` function plus the `ghcVersions`/`defaultGhc` metadata, and a `formatter`. The
`mkDevShell` function is the contract EP-3 consumes (see Interfaces and Dependencies); keep
its parameter names exactly as written.

Add the input near the others:

```nix
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
```

Update the `outputs` function head to take `treefmt-nix`, and inside the per-system `let`
add the formatter and the `mkDevShell` function. The function accepts a GHC attribute name,
extra packages, an HLS toggle, and a shell hook, and returns a `mkShell`:

```nix
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
        };

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
```

Then rewrite `mkShellForGhc` to delegate to `mkDevShell` (so there is one shell builder), and
add the new per-system outputs:

```nix
        mkShellForGhc = ghc: mkDevShell { inherit ghc; };
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
      });
```

Note on flake-utils and `lib`: `eachDefaultSystem` namespaces every attribute you return
under the system, so the result is `lib.${system}.mkDevShell`, `lib.${system}.ghcVersions`,
and `lib.${system}.defaultGhc`. EP-3 calls them as `haskell-nix-dev.lib.${system}.mkDevShell`.
This is intentional and documented in Integration Points.

Verify the API and formatter:

```bash
cd /Users/shinzui/Keikaku/bokuno/haskell-nix-dev
nix flake lock
nix eval .#lib.$(nix eval --impure --raw --expr builtins.currentSystem).defaultGhc
# -> "ghc9124"
nix eval --json .#lib.$(nix eval --impure --raw --expr builtins.currentSystem).ghcVersions --apply builtins.attrNames
# -> ["<ghc914>","ghc9124"]   (order may vary)
nix fmt
git diff --stat   # nix fmt should leave flake.nix well-formed (no errors)
```

Also prove `mkDevShell` is usable from outside by building a shell with an extra package:

```bash
nix develop --impure --expr \
  'let f = builtins.getFlake (toString ./.); s = builtins.currentSystem;
   in f.lib.${s}.mkDevShell { extraNativeBuildInputs = [ (import f.inputs.nixpkgs { system = s; }).jq ]; }' \
  --command bash -lc 'ghc --version && jq --version'
```

Acceptance for M3: `defaultGhc` evaluates to `"ghc9124"`, `ghcVersions` lists both GHC
attributes, `nix fmt` runs without error, and a shell built via `mkDevShell` with an extra
package exposes both `ghc` and that extra package.

### Milestone 4 — Buildable outputs for CI and substituter placeholder

Scope: expose package outputs that a CI job can build and cache (the Cachix sibling plan
needs concrete derivations to `nix build`), make `nix flake check` pass, and add a
`nixConfig` placeholder block plus a README. At the end, `nix flake check` is green and there
are named `packages` that realize each toolchain.

Add per-system `packages` that bundle each GHC's toolchain into one derivation (so building
one package pulls compiler + HLS + cabal into the store, which is exactly what we want to
cache). Use `pkgs.buildEnv` or `pkgs.symlinkJoin` to combine them:

```nix
        toolchainPackage = ghc:
          let t = toolchains.${ghc};
          in pkgs.buildEnv {
            name = "haskell-toolchain-${ghc}";
            paths = [ t.compiler t.cabal t.hls ];
          };
      in
      {
        # ... formatter, lib, devShells as before ...

        packages =
          (pkgs.lib.mapAttrs' (ghc: _:
            pkgs.lib.nameValuePair "toolchain-${ghc}" (toolchainPackage ghc)) toolchains)
          // { default = toolchainPackage defaultGhc; };

        checks = pkgs.lib.mapAttrs' (ghc: _:
          pkgs.lib.nameValuePair "toolchain-${ghc}" (toolchainPackage ghc)) toolchains;
      });
```

Add a `nixConfig` block at the top level of the flake (a sibling of `description`/`inputs`),
left as a clearly-marked placeholder that the Cachix plan
(`docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md`) will fill with
the real cache name and key:

```nix
  # Filled in by docs/plans/2-...: the Cachix substituter and its public key, so consumers
  # pull prebuilt toolchains instead of building HLS from source.
  nixConfig = {
    extra-substituters = [ ];          # e.g. "https://<cache-name>.cachix.org"
    extra-trusted-public-keys = [ ];   # e.g. "<cache-name>.cachix.org-1:<base64>"
  };
```

Write a `README.md` at the repository root describing: what the flake provides, the supported
GHC attributes and the default, how to enter each shell (`nix develop .#ghc9124`,
`nix develop .#<ghc914>`), and how another flake consumes it (add
`inputs.haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";` and call
`haskell-nix-dev.lib.${system}.mkDevShell { ... }`). Keep the consumer-API description in
sync with Interfaces and Dependencies below.

Verify:

```bash
cd /Users/shinzui/Keikaku/bokuno/haskell-nix-dev
nix flake check
nix build .#toolchain-ghc9124 --no-link --print-out-paths
nix build .#toolchain-<ghc914> --no-link --print-out-paths
nix flake show
```

Acceptance for M4: `nix flake check` exits 0; each `nix build .#toolchain-<ghc>` produces a
store path containing `bin/ghc`, `bin/cabal`, and `bin/haskell-language-server`; and
`nix flake show` lists `devShells`, `packages`, `checks`, `formatter`, and `lib` per system.


## Concrete Steps

Run everything from `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev`. Throughout, substitute
the M1-resolved 9.14 attribute for `<ghc914>` and the chosen revision for `REPLACE_WITH_REV`.

1. M1 discovery (no files written yet):

```bash
nix --version
# resolve the 9.14 attribute and versions:
nix eval --impure --raw --expr '
  let pkgs = import (builtins.getFlake "github:nixos/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; };
  in builtins.concatStringsSep " " (builtins.filter (n: builtins.match "ghc914.*" n != null) (builtins.attrNames pkgs.haskell.compiler))'
```

2. M2: write `flake.nix` (template above), then:

```bash
nix flake lock
nix develop .#ghc9124 --command bash -lc 'ghc --version && cabal --version && haskell-language-server --version'
nix develop .#<ghc914> --command bash -lc 'ghc --version && cabal --version && haskell-language-server --version'
git add flake.nix flake.lock
git commit -m "$(cat <<'EOF'
feat: add minimal multi-GHC base flake (ghc9124 + latest 9.14)

Provide devShells for two GHC versions with ghc, cabal, and HLS on PATH.

MasterPlan: docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md
ExecPlan: docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md
Intention: intention_01kt71x4veegvsc87z3qmsbab7
EOF
)"
```

3. M3: edit `flake.nix` to add treefmt-nix, `mkDevShell`, `lib`, `formatter`; then verify per
the M3 commands and commit with the same trailers.

4. M4: add `packages`, `checks`, `nixConfig` placeholder, and `README.md`; run `nix flake
check`; commit with the same trailers.

Update this section with the real attribute name and any deviations as you proceed.


## Validation and Acceptance

The plan is complete when, from `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev`:

- `nix develop .#ghc9124 --command ghc --version` prints `... version 9.12.4`.
- `nix develop .#<ghc914> --command ghc --version` prints `... version 9.14.x`.
- In both shells, `cabal --version` and `haskell-language-server --version` succeed.
- `nix develop --command ghc --version` (default shell) prints `9.12.4`.
- `nix eval .#lib.<system>.defaultGhc` is `"ghc9124"` and `ghcVersions` lists both attributes.
- `nix fmt` runs without error.
- `nix build .#toolchain-ghc9124` and `nix build .#toolchain-<ghc914>` each yield a store path
  containing `bin/ghc`, `bin/cabal`, `bin/haskell-language-server`.
- `nix flake check` exits 0.

To prove the toolchain actually compiles Haskell (beyond version strings), do a tiny
end-to-end build inside a shell:

```bash
tmp=$(mktemp -d); cd "$tmp"
printf 'main :: IO ()\nmain = putStrLn "hello from GHC"\n' > Main.hs
nix develop /Users/shinzui/Keikaku/bokuno/haskell-nix-dev#ghc9124 --command bash -lc \
  'runghc Main.hs'
# -> hello from GHC
cd - >/dev/null; rm -rf "$tmp"
```


## Idempotence and Recovery

All steps are safe to repeat. `nix flake lock` is idempotent once the lock exists; to
re-pin nixpkgs after changing the `inputs.nixpkgs.url` revision, run
`nix flake lock --update-input nixpkgs`. `nix develop`, `nix build`, `nix eval`, and
`nix flake check` are read-only with respect to your source tree (they only populate the Nix
store). If a build fails midway you can simply re-run it; Nix resumes from cached
intermediate results. If you commit a broken `flake.nix`, fix it and recommit — nothing is
destructive. The only file you overwrite is `flake.nix`/`flake.lock`/`README.md`, all created
by this plan.


## Interfaces and Dependencies

External inputs (pinned in `flake.lock`): `github:nixos/nixpkgs` (at the M1-chosen revision),
`github:numtide/flake-utils`, `github:numtide/treefmt-nix`.

Public output surface produced by this flake, which the sibling template plan
(`docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md`)
depends on. These names are an integration point recorded in the MasterPlan; do not rename
them without updating the MasterPlan's Integration Points section.

- `lib.${system}.defaultGhc : String` — the default GHC attribute, `"ghc9124"`.
- `lib.${system}.ghcVersions : AttrSet` — maps each supported GHC attribute (e.g. `ghc9124`,
  `<ghc914>`) to `{ ghc; compiler; hls; cabal; }`.
- `lib.${system}.mkDevShell : { ghc ? defaultGhc, extraNativeBuildInputs ? [],
  withHls ? true, shellHook ? "" } -> derivation` — returns a `pkgs.mkShell` with that GHC's
  compiler, `cabal`, optional HLS, plus the caller's extra packages and shell hook.
- `devShells.${system}.<ghcName>` and `devShells.${system}.default` — prebuilt shells; the
  `default` is the `defaultGhc` shell.
- `packages.${system}.toolchain-<ghcName>` and `packages.${system}.default` — buildable
  toolchain bundles (compiler + cabal + HLS), the build targets the Cachix CI plan
  (`docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md`) will push to
  the cache.
- `checks.${system}.toolchain-<ghcName>` — same derivations, so `nix flake check` builds them.
- `formatter.${system}` — a treefmt wrapper enabling `nix fmt`.
- `nixConfig.extra-substituters` / `nixConfig.extra-trusted-public-keys` — placeholder lists,
  filled by the Cachix plan.

The canonical `supportedGhcs` list and `defaultGhc` are the single source of truth for which
versions exist; the CI matrix and the template defaults in the sibling plans must mirror them.
