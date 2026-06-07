---
id: 1
slug: reusable-multi-ghc-haskell-base-flake
title: "Reusable multi-GHC Haskell base flake"
kind: master-plan
created_at: 2026-06-03T15:41:45Z
intention: "intention_01kt71x4veegvsc87z3qmsbab7"
---

# Reusable multi-GHC Haskell base flake

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

Today every Haskell project bootstrapped from the `seihou` template module
`nix-haskell-flake` (located at
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake`) gets a
`flake.nix` that inlines a single GHC toolchain: `pkgs.haskell.packages."ghc9124"` taken
from `nixpkgs-unstable`, plus a Haskell Language Server (HLS) built into a GHC wrapper via
`ghcWithPackages`. Two problems follow from this. First, only one GHC version is supported
per project, so a library author cannot easily test against multiple compilers. Second,
upgrading GHC is painful: each project owns its own `flake.lock`, there is no shared source
of truth for "which nixpkgs revision and which GHC we standardize on," and because the
chosen GHC is usually not the nixpkgs *default* compiler, HLS and much of the package set
are not present in the public binary cache (`cache.nixos.org`) and get rebuilt from source —
an operation that can take an hour or more per machine.

After this initiative is complete, there will be a single reusable Nix **flake** living in
this repository (`haskell-nix-dev`, consumed by other projects as the flake input
`github:shinzui/haskell-nix-dev`). A flake is a directory with a `flake.nix` file that
declares pinned `inputs` (other repositories at exact git revisions, recorded in a
`flake.lock`) and produces `outputs` (packages, development shells, and reusable library
functions) that other flakes can import. This base flake will:

- Provide complete Haskell toolchains — the GHC compiler, HLS (the editor language server),
  and `cabal` (the build tool) — for **two GHC versions concurrently**: GHC 9.12.4 and the
  latest GHC 9.14 available in the pinned nixpkgs. It will be structured so adding or
  removing a version is a one-line change.
- Default to a single version (GHC 9.12.4) so the common case stays simple, while exposing
  the other version under a named development shell for cross-version testing.
- Own the canonical `flake.lock`. Consumers inherit the exact nixpkgs revision (and thus the
  exact GHC builds) transitively through this flake. Upgrading GHC across all projects
  becomes "bump this flake's lock once; consumers run `nix flake update haskell-nix-dev`."
- Be backed by a **Cachix** binary cache populated by GitHub Actions, so the expensive HLS
  and toolchain builds happen once in CI and every developer machine downloads prebuilt
  binaries instead of compiling. A binary cache is a remote store of already-built Nix
  artifacts; Cachix is a hosted service for such caches.
- Expose a small, documented library interface (`lib.<system>.mkDevShell` and a set of
  prebuilt `devShells`) so the `seihou` template can generate a thin `flake.nix` that simply
  references this base flake rather than re-deriving toolchains itself.

In scope: the base flake and its consumer API; the Cachix cache and CI that populate it; and
the rewrite of the `nix-haskell-flake` template module to consume the base flake while
preserving its existing toggles (process-compose, PostgreSQL, treefmt, pre-commit) and its
exported `ghc.version` variable (relied on by the sibling module `haskell-library`).

Explicitly out of scope: migrating to `haskell.nix` (IOG) — the decision (see Decision Log)
is to use plain nixpkgs; per-project package overrides or pinned Hackage dependency sets
(the base flake provides the compiler and tooling, not a project's library dependency set);
and changing unrelated `seihou` modules beyond what is required to keep `ghc.version`
working.


## Decomposition Strategy

The initiative was split by functional concern into three child ExecPlans, each producing an
independently verifiable behavior.

The first concern is **producing the toolchains**: a flake that, given a pinned nixpkgs,
yields working GHC + HLS + cabal for two versions and a clean consumer API. This is the
foundation everything else builds on, so it is ExecPlan 1 and has no dependencies. It
includes an early feasibility milestone that discovers the exact nixpkgs attribute for "the
latest 9.14" and measures what is and is not already cached upstream, because that fact
shapes the rest of the work.

The second concern is **making the toolchains cheap to obtain**: a Cachix cache plus GitHub
Actions that build the toolchains for every supported GHC across the target systems and push
them to the cache, plus the `nixConfig` substituter advertisement that lets consumers pull
from it. This directly answers the user's "expensive nix rebuilds" pain. It is ExecPlan 2
and hard-depends on ExecPlan 1 because there is nothing to build or cache until the flake
exposes buildable toolchain outputs.

The third concern is **delivery to projects**: rewriting the `nix-haskell-flake` template so
generated projects consume the base flake, get both GHC shells, inherit the shared lock, and
advertise the cache. It is ExecPlan 3. It shares an interface with ExecPlan 1 (the consumer
API it calls) and benefits from ExecPlan 2 (the cache substituters it advertises), so it is
modeled with an integration dependency on ExecPlan 1 and a soft dependency on ExecPlan 2.

Alternatives considered. A single combined plan was rejected because the work touches two
separate repositories (this one and `seihou-modules`) and three independently testable
behaviors, exceeding the "single ExecPlan" threshold. A separate up-front design-spike plan
was considered but folded into ExecPlan 1 as its first milestone, because the two big forks
(plain nixpkgs vs `haskell.nix`, and Cachix vs upstream-only) were already resolved by the
user before planning (see Decision Log), leaving only concrete discovery work that belongs
inside the foundation plan rather than a standalone plan.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Base flake providing multi-version GHC, HLS, and cabal | docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md | None | None | In Progress |
| 2 | Cachix binary cache and CI for the base flake toolchains | docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md | EP-1 | None | Not Started |
| 3 | Integrate the base flake into the nix-haskell-flake seihou template | docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md | EP-1 | EP-2 | Complete* |

Status values: Not Started, In Progress, Complete, Cancelled.
\* EP-1's `ghc9141` landed 2026-06-07 (`c541332`) as a **compiler+cabal shell, no HLS** — GHC
9.14 HLS is unbuildable in nixpkgs (see Surprises & Discoveries); enabling 9.14 HLS later is a
one-line `hlsGhcs` change. EP-1 remains In Progress only for that deferred HLS follow-up; its
shipped scope (both GHCs, consumer API, packages/checks, `nix flake check` green) is complete.
EP-3 is Complete for the shipped scope (default `ghc9124` shell, shared lock, verified
end-to-end); because the `ghc.secondary` shell needs no HLS, its `ghc.secondary=ghc9141` path
can now be set/verified without waiting on 9.14 HLS. The Cachix `nixConfig` in both the base
flake and the template stays an empty placeholder until EP-2.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).
EP-3 additionally has an *integration dependency* on EP-1 (shared consumer API), described
in Integration Points below; integration dependencies are not blocking and so are not listed
in the Hard Deps column.


## Dependency Graph

ExecPlan 1 (base flake) has no dependencies and must be implemented first. It produces two
things every other plan relies on: buildable toolchain outputs (so there is something for CI
to build and cache) and the consumer API surface (so the template has something to call).

ExecPlan 2 (Cachix + CI) hard-depends on ExecPlan 1. The CI workflow builds the flake's
toolchain/`checks` outputs and pushes the results to Cachix; those outputs do not exist until
ExecPlan 1 defines them. ExecPlan 2 can begin as soon as ExecPlan 1's toolchain outputs are
buildable, even before ExecPlan 1's consumer API is fully polished.

ExecPlan 3 (template integration) hard-depends on ExecPlan 1 because the generated `flake.nix`
calls the base flake's consumer API (`lib.<system>.mkDevShell` / the prebuilt `devShells`),
which cannot be referenced until it exists and is stable. ExecPlan 3 soft-depends on
ExecPlan 2: the generated flake should advertise the Cachix substituter and public key so
developers pull prebuilt toolchains, but ExecPlan 3 can be implemented and tested without the
cache (developers simply build locally the first time) and the substituter lines can be filled
in once ExecPlan 2 publishes the cache name and key.

Parallelism: once ExecPlan 1's toolchain outputs are buildable, ExecPlan 2 and the
non-cache portions of ExecPlan 3 can proceed in parallel. The only true serialization is
ExecPlan 1 before either follower.


## Integration Points

**Consumer API of the base flake** (defined by EP-1; consumed by EP-3). The base flake's
`flake.nix` exposes, per system, a library function and a set of prebuilt development shells
that the generated project flake calls. The agreed shape is:

- `ghcVersions` — an attribute set mapping a GHC attribute name (the nixpkgs attribute under
  `pkgs.haskell.packages`, e.g. `"ghc9124"`) to its toolchain `{ ghc; compiler; hls; cabal; }`.
  EP-1 owns the canonical list; it must contain at least `ghc9124` and the resolved latest-9.14
  attribute. **Refinement (2026-06-07):** `hls` is `null` for GHCs not in the new `hlsGhcs`
  list (the subset of `supportedGhcs` that ship HLS); currently `hlsGhcs = [ "ghc9124" ]`
  because GHC 9.14 HLS is unbuildable in nixpkgs (see Surprises & Discoveries).
- `defaultGhc` — a string naming the default GHC attribute (`"ghc9124"`).
- `lib.${system}.mkDevShell { ghc ? defaultGhc, extraNativeBuildInputs ? [],
  withHls ? <hls shipped for ghc>, shellHook ? "" }` — returns a `pkgs.mkShell` derivation
  containing that GHC, `cabal`, and (where the GHC ships HLS) HLS, plus any extra packages and
  shell hook the caller supplies. **Refinement (2026-06-07):** `withHls` now defaults to
  whether the GHC is in `hlsGhcs` rather than literal `true`; a GHC without HLS (currently
  `ghc9141`) yields a compiler+cabal shell, and `withHls = true` for it is a harmless no-op.
  EP-3's generated flake passes `extraNativeBuildInputs` (e.g. `postgresql`, `process-compose`,
  `just`, `zlib`, `pkg-config`) and a `shellHook` (e.g. the PostgreSQL setup) into this
  function.
- `devShells.${system}.<ghcName>` and `devShells.${system}.default` — prebuilt shells for
  direct `nix develop`, where `default` is the `defaultGhc` shell.

EP-1 must document the exact final signature in its Interfaces and Dependencies section. If
EP-1 changes any name here, it must update this section of the MasterPlan and EP-3 in the
same change. EP-3 must reference these names by reading this section and EP-1, never by
assuming an older shape.

**Cachix substituter coordinates** (defined by EP-2; consumed by EP-3 and by EP-1's own
flake). EP-2 creates the cache and publishes two facts: the cache substituter URL
(`https://<cache-name>.cachix.org`) and the public trusted key
(`<cache-name>.cachix.org-1:<base64>`). Both EP-1's `flake.nix` and EP-3's generated
`flake.nix` advertise these via a `nixConfig` block (`extra-substituters` and
`extra-trusted-public-keys`). EP-2 must record the final cache name and key in the
MasterPlan's Surprises & Discoveries section so EP-3 can copy them verbatim.

**Canonical GHC version set and pinned nixpkgs** (owned by EP-1; mirrored by EP-2 and EP-3).
The list of supported GHC attribute names and the nixpkgs revision live in EP-1's `flake.nix`
and `flake.lock`. EP-2's CI build matrix derives its GHC dimension from this same list (it
must not hard-code a divergent list). EP-3's template default GHC (`ghc.version`) and extra
versions (`ghc.extra-versions`) must name versions that exist in EP-1's set. When EP-1 adds,
removes, or renames a version, EP-2's matrix and EP-3's template defaults must be updated to
match; record the change in the Decision Log.

**`seihou` exported variable `ghc.version`** (owned by EP-3; consumed by the existing sibling
module `haskell-library`). The module
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`
depends on `nix-haskell-flake` and shares its exported `ghc.version`. EP-3 must keep
`ghc.version` as the exported default-GHC variable (adding new variables alongside it rather
than renaming it) so `haskell-library` keeps working without modification.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and
the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-1 M1: Feasibility — resolve the latest-9.14 nixpkgs attribute and measure cache coverage for both GHCs. (2026-06-03 — `ghc9141`/9.14.1; rev `4df1b885…`; 9.14 HLS = 345 from-source builds)
- [x] EP-1 M2: Minimal flake — `nix develop .#ghc9124` gives working ghc/cabal/HLS. (2026-06-03 — committed `26aa846`; `.#ghc9141` deferred to follow-up)
- [x] EP-1 M3: Consumer API — `lib.<system>.mkDevShell`, `ghcVersions`, `defaultGhc`, prebuilt `devShells`, treefmt formatter. (2026-06-03)
- [x] EP-1 M4: Buildable toolchain outputs for CI (`packages`/`checks`) and `nix flake check` passing. (2026-06-03)
- [x] EP-1 follow-up: Add `ghc9141` (9.14.1) to `supportedGhcs`. (2026-06-07 — committed `c541332`; shipped as **compiler+cabal, no HLS** — GHC 9.14 HLS is unbuildable in nixpkgs; `nix develop .#ghc9141` + `runghc` verified; pin kept at `4df1b885`.)
- [ ] EP-1 follow-up (deferred): Enable HLS for `ghc9141` (add it to `hlsGhcs`, one line) once nixpkgs ships a buildable GHC 9.14 HLS. See Surprises & Discoveries.
- [ ] EP-2 M1: Cachix cache created; auth secret wired into the repo.
- [ ] EP-2 M2: GitHub Actions builds all GHC toolchains across target systems and pushes to Cachix.
- [ ] EP-2 M3: `nixConfig` substituters added to the base flake; cache hit verified on a clean machine/CI.
- [x] EP-3 M1: `module.dhall` updated — `ghc.version` default + `ghc.secondary` (Strategy B; engine has no list iteration) + constrained prompt; `ghc.version` export preserved. (2026-06-03 — v0.10.0; both modules type-check)
- [x] EP-3 M2: `flake.nix.tpl` rewritten to consume the base flake and emit default + optional secondary devShell with toggles preserved. (2026-06-03 — render-checked, no leftover tokens)
- [x] EP-3 M3: Regenerated `flake.lock`, updated README + registry, and an end-to-end `seihou run` smoke test producing a buildable project. (2026-06-03 — pushed; `nix develop` + `nix build .#default` verified)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

**EP-1 M1 — resolved versions and upstream cache coverage (2026-06-03, `aarch64-darwin`).**

- Resolved latest-9.14 attribute = **`ghc9141`** (version `9.14.1`). Default stays `ghc9124`
  (version `9.12.4`). The canonical `supportedGhcs` list is therefore `[ "ghc9124" "ghc9141" ]`.
  EP-2's CI matrix and EP-3's template defaults must mirror these two attribute names.
- Pinned nixpkgs revision = **`4df1b885d76a54e1aa1a318f8d16fd6005b6401f`** (single
  `nixpkgs-unstable` revision containing both compilers; no second nixpkgs input needed).
- Upstream cache coverage measured with `nix build --dry-run`:
  - `ghc9124`: compiler + `cabal-install` fully cached upstream; HLS needs only 4 derivations
    built from source.
  - `ghc9141`: compiler fetched (cached); **HLS pulls in 345 derivations built from source** —
    the 9.14 package set is essentially absent from `cache.nixos.org`.
- **Guidance for EP-2:** the high-value caching target is the **9.14 (`ghc9141`) toolchain**,
  whose HLS closure (~345 packages) currently builds from source on every machine. The 9.12.4
  toolchain is nearly free from the upstream cache already, so EP-2 still builds it (cheap) but
  the dominant CI cost and cache payoff is 9.14.

**EP-1 M2 — HLS library-profiling panic; toolchain builds HLS with profiling disabled
(2026-06-03).** On aarch64-darwin, `haskell-language-server` for `ghc9124` is uncached
upstream and its from-source build **panics** (a GHC 9.12.4 compiler bug compiling `ghcide`'s
profiling objects, `GHC.Core.Subst`). The base flake therefore builds HLS with **library
profiling disabled on the `ghcide` + `hls-*` upper tree** (5 from-source derivations; leaf
deps stay cached). Cross-plan impact:

- **EP-2 (Cachix):** the toolchain derivations it builds/caches use this profiling-disabled
  HLS — they differ from stock nixpkgs `haskell.packages.<ghc>.haskell-language-server`. EP-2
  must build the base flake's actual `packages.toolchain-<ghc>` outputs (it already plans to),
  not the stock attribute, so the cached artifacts match what consumers request. The same
  panic is expected for `ghc9141`, which also builds its full ~345-package HLS closure from
  source — that is the dominant CI cost.
- **EP-3 (template):** no interface change; it consumes `mkDevShell`/`devShells` which already
  embed the fixed HLS.

**Scope sequencing (EP-1):** per the user (2026-06-03), `ghc9124` is delivered end-to-end and
made consumable from other projects **first**; `ghc9141` is added afterward (a one-line
`supportedGhcs` change plus a long first build). This does not change the decomposition or any
interface — `supportedGhcs`/`defaultGhc` remain the single source of truth; the set is simply
`[ "ghc9124" ]` until 9.14 is appended.

**EP-3 M1–M3 — template integration delivered for ghc9124 (2026-06-03).**

- **seihou engine has no list iteration** (`{{#each}}`); only `{{#if Eq/IsSet ...}}`. The
  MasterPlan/EP-3 Integration Point that envisioned `ghc.extra-versions` as an iterated `list
  text` is infeasible as a template; implemented **Strategy B** — a single optional
  `ghc.secondary` text var (`{{#if IsSet ghc.secondary}}`). >2 versions would need the
  `dhall-text` step strategy. This refines the "Canonical GHC version set" integration point:
  the template exposes the default `ghc.version` plus one optional `ghc.secondary`, both
  constrained to the base flake's `supportedGhcs`.
- **`seihou run` uses installed modules**, not the source repo — delivery is commit → push →
  `seihou install`. Recorded so EP-2/future template work expects the same loop.
- The base flake was **pushed to `github:shinzui/haskell-nix-dev` (rev `66ea98b`)** so the
  template's `github:` input resolves; the generated project's `flake.lock` pins it and a
  bootstrapped project's `nix develop` reuses the base flake's exact prebuilt HLS store path.
- **Second-shell (`ghc.secondary`) is render-tested only**, gated on EP-1 adding `ghc9141`.
  When 9.14 lands in the base flake, both the EP-1 follow-up and the EP-3 follow-up
  (set/verify `ghc.secondary=ghc9141`) complete together.

**EP-1 follow-up — GHC 9.14 HLS is unbuildable in nixpkgs; `ghc9141` ships without HLS
(2026-06-07).** Adding `ghc9141` surfaced that HLS for GHC 9.14 cannot be built from nixpkgs
(at `4df1b885…` or current unstable): ≥19 packages in its dependency closure carry stale upper
bounds (`base < 4.22`, `containers < 0.8`, `template-haskell < 2.24`, `time < 1.15`,
`hedgehog < 1.6`), the set grows each `--keep-going` build, and `Cabal-syntax` resists
`doJailbreak` because a Hackage cabal-file revision re-imposes the bound. The GHC 9.14.1
*compiler* and `cabal` are fine and cached, and the user's goal is to **test libraries against
9.14** (no HLS needed), so `ghc9141` ships as a **compiler+cabal toolchain without HLS**.
Implementation: a new `hlsGhcs = [ "ghc9124" ]` list gates HLS; `ghcVersions.<ghc>.hls` is
`null` for GHCs outside it; `mkDevShell.withHls` defaults per-GHC; toolchain bundles omit the
null HLS. (Full evidence in EP-1's Surprises & Discoveries / Decision Log.) Cross-plan impact:

- **EP-2 (Cachix):** there is **no `ghc9141` HLS to cache** — `packages/checks.toolchain-ghc9141`
  is just the GHC 9.14.1 compiler + `cabal` (both already cached upstream), so the 9.14 caching
  burden the M1 finding anticipated (~345 HLS derivations) **does not exist** for now. The
  dominant cache value is again the `ghc9124` HLS (its 5-derivation profiling-fixed closure).
  When 9.14 HLS is eventually enabled (added to `hlsGhcs`), EP-2's matrix needs no change — it
  builds the flake's `checks`, which will then include the 9.14 HLS automatically.
- **EP-3 (template):** the `ghc.secondary` shell now resolves to a **compiler+cabal** shell
  (no HLS) when set to `ghc9141`. EP-3's generated flake calls `mkDevShell`/`devShells`, which
  already omit HLS for `ghc9141`, so **no template change is required**; the EP-3 follow-up
  (set/verify `ghc.secondary=ghc9141`) can proceed now rather than waiting on 9.14 HLS.
- **Pin unchanged:** the canonical lock stays at `4df1b885…` (a trial bump to `ffa10e26…` was
  reverted — it was based on a misread `--dry-run` count and gave no benefit once 9.14 HLS was
  abandoned), so consumers' shared lock and the already-shipped `ghc9124` toolchain are
  untouched.
- **Public-repo note:** an intermediate, non-building state (incomplete jailbreak, `ffa10e26`
  pin) was committed and pushed mid-session as `1db3eca`/`97f5425`; the fix `c541332` supersedes
  it and must be pushed to restore a buildable `github:shinzui/haskell-nix-dev`.

(EP-2 will record the final Cachix cache name and public key here for EP-3 to consume; both
the base flake's and the template's `nixConfig` remain empty placeholders until then.)


## Decision Log

- Decision: Build the base flake on plain nixpkgs (`pkgs.haskell.packages.<ghc>`) rather than
  `haskell.nix` (IOG).
  Rationale: The user's framing ("the latest 9.14 available in nixpkgs") and existing template
  both target nixpkgs; plain nixpkgs is the lighter, more familiar idiom. The expensive-rebuild
  problem is addressed by a dedicated binary cache (see next decision) rather than by adopting
  haskell.nix's cache.
  Date: 2026-06-03

- Decision: Solve expensive rebuilds with a Cachix cache populated by GitHub Actions, rather
  than relying solely on `cache.nixos.org`.
  Rationale: For non-default GHC versions, HLS and much of the package set are not in the
  upstream cache and would rebuild from source on every machine. Building once in CI and
  pushing to Cachix gives every consumer prebuilt binaries. EP-1 M1 will still measure upstream
  coverage; if a chosen version turns out to be fully cached upstream, EP-2's scope for that
  version shrinks accordingly.
  Date: 2026-06-03

- Decision: The base flake lives in this repository (`haskell-nix-dev`) and is consumed as
  `github:shinzui/haskell-nix-dev`.
  Rationale: The repository is otherwise empty and its name matches the purpose; a single
  published flake gives consumers one input to reference and one lock to inherit.
  Date: 2026-06-03

- Decision: Default to a single GHC (9.12.4) with the second version (latest 9.14) exposed as
  a named shell, supporting exactly two versions initially but structured for easy
  addition/removal.
  Rationale: Matches the user's "default to one, support two" requirement while keeping the
  common `nix develop` path simple.
  Date: 2026-06-03

- Decision: In the template, keep the existing exported variable `ghc.version` as the
  default-GHC selector and add a new `ghc.extra-versions` list variable for additional
  concurrent toolchains, rather than renaming `ghc.version` to a list.
  Rationale: The sibling module `haskell-library` depends on `nix-haskell-flake` and consumes
  the `ghc.version` export; preserving the name avoids a breaking cascade into that module.
  Date: 2026-06-03

- Decision: Sequence EP-1 delivery as `ghc9124`-first, end-to-end and consumable, then add
  `ghc9141`.
  Rationale: User asked (2026-06-03) to finish a working single-version deliverable and start
  using the flake in other projects before paying the expensive 9.14 build (345 from-source
  derivations for its HLS). The `supportedGhcs` list makes appending 9.14 a one-line change,
  so this changes only ordering, not the architecture or any integration interface.
  Date: 2026-06-03

- Decision: Ship `ghc9141` as a compiler+cabal toolchain **without HLS** (gated by a new
  `hlsGhcs` list), and keep the nixpkgs pin at `4df1b885…`.
  Rationale: GHC 9.14 HLS is unbuildable from nixpkgs — its closure has stale version bounds
  across ≥19 packages and `Cabal-syntax` resists `doJailbreak` (a Hackage cabal-file revision
  re-imposes the bound). The user (2026-06-07) wants to test libraries against 9.14, which needs
  only the (cached) compiler + `cabal`. This delivers that value now and makes re-enabling HLS a
  one-line `hlsGhcs` change later. A trial pin bump to `ffa10e26…` was reverted (it was based on
  a misread `--dry-run` count and had no benefit once 9.14 HLS was dropped). Refines the
  consumer API (`ghcVersions.<ghc>.hls` may be `null`; `mkDevShell.withHls` defaults per-GHC)
  and confirms EP-2 has no 9.14 HLS to cache and EP-3 needs no template change. See EP-1 and
  MasterPlan Surprises & Discoveries.
  Date: 2026-06-07

- Decision: The base flake builds HLS with library profiling disabled on the `ghcide`+`hls-*`
  upper tree (see EP-1 Decision Log and Surprises & Discoveries).
  Rationale: Works around a GHC 9.12.4 profiling-compilation panic on aarch64-darwin while
  preserving the upstream binary cache for the ~337 leaf dependencies. Affects what EP-2
  caches (the flake's own toolchain outputs, already its plan).
  Date: 2026-06-03

- Decision: Decompose into three child plans (base flake; Cachix + CI; template integration)
  with no separate design-spike plan.
  Rationale: The two major design forks were resolved before planning, leaving only concrete
  discovery work that fits as EP-1's first milestone. Three functional concerns across two
  repositories justify a MasterPlan over a single ExecPlan.
  Date: 2026-06-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original vision.

(To be filled during and after implementation.)
