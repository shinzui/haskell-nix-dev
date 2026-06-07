---
id: 3
slug: integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template
title: "Integrate the base flake into the nix-haskell-flake seihou template"
kind: exec-plan
created_at: 2026-06-03T15:41:55Z
intention: "intention_01kt71x4veegvsc87z3qmsbab7"
master_plan: "docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md"
---

# Integrate the base flake into the nix-haskell-flake seihou template

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This plan belongs to the MasterPlan at
`docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md`. It **hard-depends** on
`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md` (it calls that flake's
consumer API) and **soft-depends** on
`docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md` (it copies the
Cachix substituter and key that plan publishes). You can implement everything except the
final substituter values without EP-2; fill those in once EP-2 records the cache name and key
in the MasterPlan's Surprises & Discoveries.


## Purpose / Big Picture

`seihou` is a project-bootstrapping tool: it reads a *module* (a directory with a
`module.dhall` definition and a `files/` folder of templates) and writes generated files into
a new project. The module this plan changes is `nix-haskell-flake`, at
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake`. Running
`seihou run nix-haskell-flake` in a project produces a `flake.nix`, a pinned `flake.lock`, an
`.envrc` for direnv, and optional `treefmt.nix` / `process-compose.yaml` files.

Today the generated `flake.nix` inlines a single GHC toolchain
(`pkgs.haskell.packages."ghc9124"`) and builds HLS into a GHC wrapper, so a bootstrapped
project supports exactly one GHC version and rebuilds HLS from source. After this plan, a
bootstrapped project's `flake.nix` will instead **consume the base flake**
(`github:shinzui/haskell-nix-dev`, produced by EP-1). The result, visible to anyone who
bootstraps a project:

- The project gets a development shell for the default GHC (9.12.4) **and** a named shell for
  each additional configured GHC (initially the latest 9.14), so `nix develop` gives the
  default toolchain and `nix develop .#<ghc914>` gives the second — enabling cross-version
  testing with no extra setup.
- The project inherits the base flake's pinned `nixpkgs` (via `inputs.nixpkgs.follows`), so
  there is a **single shared lock**: upgrading GHC across projects is "bump the base flake and
  run `nix flake update haskell-nix-dev`," not editing every project's pin.
- The generated flake advertises the Cachix cache, so the first `nix develop` downloads HLS
  instead of compiling it.

The existing toggles (process-compose, PostgreSQL, treefmt, pre-commit) and the exported
`ghc.version` variable continue to work unchanged.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Confirm the seihou template engine's list-iteration capability; choose multi-version emission strategy. (2026-06-03 — no `{{#each}}`; chose Strategy B, single optional `ghc.secondary`)
- [x] M1: Update `module.dhall` — keep `ghc.version` (default), add `ghc.secondary` (text, Strategy B), bump to 0.10.0, constrain prompt choices; `ghc.version` export preserved. (2026-06-03 — both modules type-check)
- [x] M2: Rewrite `files/flake.nix.tpl` to consume the base flake, follow its nixpkgs, and emit default + optional secondary devShell with toggles preserved. (2026-06-03 — render-checked, no leftover tokens)
- [x] M2: Add the `nixConfig` cache block to the template (empty placeholder until EP-2). (2026-06-03)
- [x] Follow-up (EP-2 soft dep, now resolved): fill the template's `nixConfig` with the `shinzui.cachix.org` substituter + public key EP-2 published. (2026-06-07 — `seihou-modules` `aacda72`, module+registry bumped to 0.11.1, `seihou upgrade` applied, scratch `seihou run` renders the cache block with no leftover tokens; coordinates `https://shinzui.cachix.org` / `shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=`.)
- [x] M3: Regenerate `files/flake.lock` so `haskell-nix-dev` is pinned. (2026-06-03 — base flake pushed `66ea98b`; lock has `haskell-nix-dev` node, `nixpkgs`/`treefmt-nix` follow it)
- [x] M3: Commit the seihou-modules changes; reinstall the module; update `README.md`; sync registry to 0.10.0. (2026-06-03 — seihou-modules `95d9c3e`, `e56dbb0`; installed module = 0.10.0)
- [x] M3: End-to-end smoke test — `seihou run` into a scratch project, then `nix develop` and build the project. (2026-06-03 — default shell: GHC 9.12.4 + cabal 3.16.1.0 + HLS 2.13.0.0 [same store path as base flake]; `nix build .#default` built the sample via callCabal2nix)
- [ ] Follow-up: once EP-1 adds `ghc9141` to the base flake, set/document `ghc.secondary=ghc9141` and verify the second shell *evaluates* (only render-tested so far, since the base flake has no ghc9141 yet). Re-lock and bump the module if needed.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

**M1 — seihou template engine has no list iteration (2026-06-03).** The engine
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Engine/Template.hs`)
implements only `{{#if <expr>}}...{{#else}}...{{/if}}`. The block scanner recognizes solely
`{{#if`, `{{/if}}`, `{{#else}}` — **no `{{#each}}`** and no `{{this}}`. Expression grammar
(`.../Seihou/Core/Expr.hs`): `IsSet <var>`, `Eq <var> <val>`, `&&`, `||`, `!`, parens,
`true`/`false`. A `list` variable interpolated as `{{var}}` renders comma-separated
(`valueToText (VList vs) = T.intercalate "," ...`). The docs direct list-iteration use cases
to the separate `dhall-text` step strategy. Consequence: Strategy A (`{{#each}}`) is
infeasible; using Strategy B (single optional `ghc.secondary`). Evidence corroborated by zero
`{{#each` matches across all `modules/**/*.tpl`.

**M1 — base flake currently ships one GHC (`ghc9124`).** EP-1 deferred `ghc9141`, so the base
flake's `supportedGhcs = [ "ghc9124" ]`. The template must not offer a `ghc.version` or
`ghc.secondary` outside that set, or the generated `mkDevShell <attr>` fails. Handled by
constraining the prompt to `ghc9124` and defaulting `ghc.secondary` unset until EP-1 adds
`ghc9141`.

**M2 — `seihou run` uses *installed* modules, not the source repo (2026-06-03).** Editing
`/Users/shinzui/Keikaku/bokuno/seihou-modules/.../nix-haskell-flake` does not affect
`seihou run`; the engine loads modules from `~/.config/seihou/installed/<name>/`, populated by
`seihou install <git-url> --module <name>` (which **clones committed git state**). So the
delivery loop is: edit source → commit (→ push) → `seihou install`/`upgrade`. For an
unblocked M2 render check I temporarily synced the edited `module.dhall` + `flake.nix.tpl`
into the installed copy, rendered, then restored it. Render results (both with no leftover
`{{...}}` tokens):

- Default (no `ghc.secondary`): generated `flake.nix` has `inputs.haskell-nix-dev.url =
  "github:shinzui/haskell-nix-dev"`, `nixpkgs`/`flake-utils`/`treefmt-nix` `follows` lines, the
  empty `nixConfig` block, `hsdev = haskell-nix-dev.lib.${system}`,
  `packages.default = haskellPackages.callCabal2nix "sample" ./. {}`, and `devShells` =
  `{ default; "ghc9124"; }`.
- With `--var ghc.secondary=ghc9141`: `devShells` additionally contains `"ghc9141" =
  mkProjectShell "ghc9141";` — the `{{#if IsSet ghc.secondary}}` guard works.

**Base-flake ref pinned in the template:** `github:shinzui/haskell-nix-dev`. This requires the
base flake (this repo) to be **pushed to GitHub** before the generated `flake.nix` can lock /
evaluate and before M3's bundled `files/flake.lock` can be regenerated.


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep `ghc.version` as the default-GHC variable and add `ghc.extra-versions`
  (a `list text`) for additional concurrent toolchains, rather than renaming `ghc.version`.
  Rationale: The sibling module `haskell-library`
  (`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`)
  depends on `nix-haskell-flake` and consumes its exported `ghc.version`; renaming would break
  it. Inherited from the MasterPlan Decision Log (2026-06-03).
  Date: 2026-06-03

- Decision: The generated flake follows the base flake's nixpkgs
  (`inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs"`) instead of declaring its own.
  Rationale: Guarantees a single shared lock and identical GHC builds, which is the whole
  point of the "same lock without expensive rebuilds" requirement.
  Date: 2026-06-03

- Decision: Use **Strategy B** (single optional `ghc.secondary` text variable, emitted via
  `{{#if IsSet ghc.secondary}}`) rather than Strategy A (`{{#each ghc.extra-versions}}`).
  Rationale: M1 investigation of the seihou template engine
  (`seihou-project/seihou/seihou-core/src/Seihou/Engine/Template.hs`) confirmed it implements
  **only** `{{#if <expr>}}...{{#else}}...{{/if}}` with the expression grammar
  `IsSet <var>` / `Eq <var> <val>` / `&&` / `||` / `!` — there is **no `{{#each}}`/list
  iteration** and no `{{this}}`. List variables render as comma-separated text; true iteration
  is only available via the separate `dhall-text` step strategy. Converting the whole
  `flake.nix.tpl` to `dhall-text` to support N versions is a large change unjustified now
  (the base flake currently provides one GHC; see below). Strategy B supports the immediate
  "default + one optional secondary" need with the engine's real capabilities. If >2 concurrent
  versions are ever needed, switch the step to `dhall-text`.
  Date: 2026-06-03

- Decision: `ghc.secondary` defaults to **unset** (no second shell emitted), and the
  `ghc.version` prompt offers only `ghc9124` for now.
  Rationale: EP-1 currently ships only `ghc9124` in the base flake's `supportedGhcs`
  (`ghc9141` deferred per the MasterPlan). `mkDevShell`/the prebuilt shells only accept
  versions in `supportedGhcs`, so offering `ghc9141`/`ghc984`/`ghc966` would generate a flake
  whose shell fails to evaluate. When EP-1 appends `ghc9141`, add it to the prompt choices and
  set `ghc.secondary`'s default (or document setting it) to `ghc9141`.
  Date: 2026-06-03

- Decision: The generated flake's `nixConfig` uses **empty** `extra-substituters` /
  `extra-trusted-public-keys` lists with a TODO, not a real-looking URL + placeholder key.
  Rationale: EP-2 (Cachix) is not yet implemented, so no cache name/key exists. Advertising a
  substituter with a wrong/placeholder trusted public key would cause signature-verification
  failures on consumers. Empty lists are inert (only a harmless warning) and mirror the base
  flake's own `nixConfig` placeholder. EP-2 fills both in the same change.
  Date: 2026-06-03
  Resolved 2026-06-07: EP-2 published the cache, so the template's `nixConfig` now lists
  `https://shinzui.cachix.org` + key `shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=`
  (the existing `shinzui` cache was reused rather than a new one). Module + registry bumped to
  0.11.1; `seihou-modules` `aacda72`.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original purpose.

**Delivered (2026-06-03).** The `nix-haskell-flake` seihou module (v0.10.0, pushed to
`github:shinzui/seihou-modules`) now generates Haskell projects that consume the
`haskell-nix-dev` base flake. A freshly bootstrapped project:

- follows the base flake's nixpkgs (`inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs"`) — a
  single shared lock; verified the regenerated `files/flake.lock` has a `haskell-nix-dev` node
  and `nixpkgs`/`treefmt-nix` resolve via `follows`;
- builds its devShell from `haskell-nix-dev.lib.${system}.mkDevShell` — `nix develop` gave GHC
  9.12.4, cabal 3.16.1.0, and HLS 2.13.0.0 at the **same store path** as the base flake (so
  consumers reuse the prebuilt HLS, no rebuild);
- builds its own package via `callCabal2nix` — `nix build .#default` produced
  `…-sample-0.1.0`;
- preserves the toggles (treefmt/pre-commit exercised; pre-commit hook installed via the
  shellHook) and the `ghc.version` export (`haskell-library` still type-checks).

**Gaps / deviations from the original plan.**

- The plan's **Strategy A (`{{#each}}` over `ghc.extra-versions`) is impossible** — the seihou
  engine has no list iteration. Implemented **Strategy B** (one optional `ghc.secondary`).
  Supporting >2 concurrent versions would require switching the step to the `dhall-text`
  strategy (noted for the future).
- The second devShell is **render-tested only**, not evaluated, because EP-1 currently ships
  only `ghc9124` (ghc9141 deferred). When the base flake adds `ghc9141`, set/document
  `ghc.secondary=ghc9141` and verify it evaluates (Progress follow-up).
- The `nixConfig` cache block is an **empty placeholder** pending EP-2 (Cachix); until then the
  first `nix develop` on a clean machine builds HLS from source (the ghc9124 HLS fix builds 5
  derivations).
- Discovered that `seihou run` uses **installed** modules, not the source tree, so delivery
  requires commit → push → `seihou install`. Also bumped the `seihou-registry.dhall` entry to
  0.10.0 (other modules' pre-existing version drift left untouched).

Against the original purpose: met — generated projects consume the base flake, share one lock,
and get a working GHC+cabal+HLS shell that reuses the base flake's prebuilt toolchain. The
multi-version dimension is structurally in place (default + optional secondary) and becomes
fully live once EP-1's `ghc9141` lands.


## Context and Orientation

The `seihou` module you are editing lives at
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake`. Its layout:

- `module.dhall` — the module definition: declared variables (`vars`), values exported to
  dependent modules (`exports`), interactive `prompts`, and generation `steps` (which template
  file produces which output). The schema is fetched from a pinned URL at the top of the file
  (`seihou-schema`); variable types are the strings `"text"`, `"bool"`, `"int"`, `"list text"`,
  `"list bool"`, `"list int"`, `"choice"`.
- `files/flake.nix.tpl` — the template for the generated `flake.nix`. The templating syntax is
  a Handlebars-like dialect: `{{project.name}}` interpolates a variable, and
  `{{#if Eq nix.treefmt true}} ... {{/if}}` conditionally includes a block. Whether it
  supports list iteration (`{{#each ...}}`) is unverified and is the first thing M1 resolves.
- `files/flake.lock` — a pre-resolved lock copied verbatim into generated projects (the
  `copy` step). It must be regenerated when `flake.nix.tpl`'s inputs change.
- Other `files/*.tpl` — `treefmt.nix.tpl`, `process-compose.yaml.tpl`, `envrc.tpl`, and the
  `gitignore-*.tpl` fragments. These are unaffected by this plan except where noted.
- `README.md` — human documentation of the module's variables and outputs; keep it in sync.

The current `files/flake.nix.tpl` (the thing being rewritten) reads, in essence:

```nix
{
  description = "{{project.description}}";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskell.packages."{{ghc.version}}";
      in {
        packages.default = haskellPackages.{{project.name}};
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.zlib pkgs.just pkgs.cabal-install pkgs.pkg-config
            (haskellPackages.ghcWithPackages (ps: [ ps.haskell-language-server ])) ];
          shellHook = ''...'';
        };
      });
}
```

The current `module.dhall` declares `ghc.version` (`text`, default `ghc9124`, validation
`ghc[0-9]+`), exports `project.name` and `ghc.version`, and has the toggles
`nix.process-compose`, `nix.postgresql`, `nix.treefmt`, `nix.pre-commit`.

The base flake you will consume (EP-1, in this repository `haskell-nix-dev`, published as
`github:shinzui/haskell-nix-dev`) exposes, per system, these names — copy them exactly (they
are the MasterPlan Integration Point "Consumer API of the base flake"):

- `lib.${system}.mkDevShell { ghc ? defaultGhc, extraNativeBuildInputs ? [], withHls ? true,
  shellHook ? "" }` → a `mkShell` with that GHC's compiler, cabal, optional HLS, plus extras.
- `lib.${system}.defaultGhc` → `"ghc9124"`.
- `lib.${system}.ghcVersions` → attrset of supported GHC attributes.
- `devShells.${system}.<ghcName>` / `.default`, `packages.${system}.toolchain-<ghcName>`.
- Inputs you can `follows`: `nixpkgs`, `flake-utils`, `treefmt-nix`.

The latest-9.14 GHC attribute (written `<ghc914>` throughout) and the Cachix cache name/public
key are recorded in the MasterPlan's Surprises & Discoveries by EP-1 and EP-2 respectively;
read them there before editing.

Term of art — **`callCabal2nix`**: a nixpkgs function `pkgs.haskell.packages.<ghc>.callCabal2nix
name src {}` that turns a project's `.cabal` file at `src` into a Nix-buildable Haskell package.
The generated flake uses it for `packages.default` so the project itself is buildable with the
chosen GHC, replacing the old `haskellPackages.{{project.name}}` (which assumed the project was
already in the nixpkgs Haskell set).


## Plan of Work

Three milestones. M1 settles the data model and the engine question; M2 rewrites the template;
M3 re-locks and proves a bootstrapped project works end to end. Throughout, replace `<ghc914>`
with the attribute EP-1 recorded (e.g. `ghc9141`) and the cache placeholders with EP-2's
values.

### Milestone 1 — Engine capability and module variables

Scope: determine how the template engine emits a list, then update `module.dhall` to model a
default GHC plus a list of extra GHC versions while preserving the `ghc.version` export.

First, settle whether the engine supports list iteration. Inspect the engine and existing
templates:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-modules
grep -rn '{{#each' modules/ || echo "no each usage in any module"
seihou --help 2>/dev/null | sed -n '1,40p' || true
# If seihou ships docs about template syntax:
mori registry search seihou 2>/dev/null || true
```

Decide between two emission strategies and record the choice in the Decision Log:

- **Strategy A (preferred), engine supports `{{#each ghc.extra-versions}}`**: model
  `ghc.extra-versions` as a `list text` and iterate it in the template (M2). This scales to any
  number of versions.
- **Strategy B (fallback), no list iteration**: the user needs exactly two versions, so add a
  single optional `ghc.secondary` (`text`) variable instead of a list, and emit one extra
  shell guarded by `{{#if ...}}`. Note the limitation (two versions max) in the README.

Edit `/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/module.dhall`:

1. Bump `version` from `Some "0.9.0"` to `Some "0.10.0"`.
2. Update the `description` to mention multi-version GHC via the base flake.
3. Keep the existing `ghc.version` VarDecl unchanged (default `ghc9124`, validation
   `ghc[0-9]+`) — it remains the default/primary GHC and the exported variable. Update its
   `description` to clarify it is "the default GHC; additional concurrent versions are listed
   in `ghc.extra-versions`."
4. Add a new VarDecl (Strategy A):

```dhall
, S.VarDecl::{
  , name = "ghc.extra-versions"
  , type = "list text"
  , default = Some "[\"<ghc914>\"]"
  , description = Some
      "Additional GHC versions (nixpkgs haskell.packages attributes) to expose as named devShells alongside the default ghc.version, for cross-version testing. Each becomes `nix develop .#<attr>`."
  , required = False
  }
```

   (For Strategy B, instead add `ghc.secondary` as `type = "text"`, `required = False`, default
   `Some "<ghc914>"`.) Confirm the exact default-encoding for a `list text` by checking how the
   seihou decoder parses defaults — if a Dhall list literal is required rather than a string,
   use `default = Some "..."` only if the schema's `default` field is `Optional Text`; the
   schema shows `default : Optional Text`, so the list default is a *string* the tool parses.
   Verify by running a dry-run in M3 and adjust if the tool rejects it.
5. Optionally add a prompt for the new variable. List prompts are awkward interactively, so it
   is acceptable to omit a prompt and rely on the default plus `--var` overrides; if you add
   one, use a plain `Prompt::{ var = "ghc.extra-versions", text = "..." }` without `choices`.
6. Leave `exports` unchanged — `project.name` and `ghc.version` must both remain, because
   `haskell-library`
   (`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`)
   consumes the `ghc.version` export.

Validate the Dhall is well-formed:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake
dhall type --file module.dhall >/dev/null && echo "module.dhall type-checks"
```

Acceptance for M1: `module.dhall` type-checks, declares `ghc.extra-versions` (or
`ghc.secondary`), still exports `ghc.version`, and the version is `0.10.0`. The engine
capability is recorded in the Decision Log.

### Milestone 2 — Rewrite the flake template

Scope: replace `files/flake.nix.tpl` so the generated flake consumes the base flake, follows
its nixpkgs, advertises the cache, and produces a default shell plus one named shell per extra
GHC. At the end, the template renders to valid Nix for a sample project.

Replace the entire contents of
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/files/flake.nix.tpl`
with the following (Strategy A shown; for Strategy B, swap the `{{#each}}` block for a single
`{{#if}}`-guarded shell using `ghc.secondary`). Replace the `nixConfig` placeholder values
with EP-2's real cache name and key once available.

```nix
{
  description = "{{project.description}}";

  inputs.haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
  inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs";
  inputs.flake-utils.follows = "haskell-nix-dev/flake-utils";
  {{#if Eq nix.treefmt true}}
  inputs.treefmt-nix.follows = "haskell-nix-dev/treefmt-nix";
  {{/if}}
  {{#if Eq nix.pre-commit true}}
  inputs.pre-commit-hooks.url = "github:cachix/git-hooks.nix";
  {{/if}}

  # Pull prebuilt GHC/HLS/cabal toolchains from the base flake's Cachix cache instead of
  # building HLS from source. Values published by the haskell-nix-dev base flake.
  nixConfig = {
    extra-substituters = [ "https://haskell-nix-dev.cachix.org" ];
    extra-trusted-public-keys = [ "haskell-nix-dev.cachix.org-1:REPLACE_WITH_PUBLIC_KEY" ];
  };

  outputs = { self, nixpkgs, haskell-nix-dev, flake-utils{{#if Eq nix.treefmt true}}, treefmt-nix{{/if}}{{#if Eq nix.pre-commit true}}, pre-commit-hooks{{/if}} }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        hsdev = haskell-nix-dev.lib.${system};
        haskellPackages = pkgs.haskell.packages."{{ghc.version}}";

        commonNativeBuildInputs = [
          pkgs.zlib
          pkgs.just
          pkgs.pkg-config
          {{#if Eq nix.postgresql true}}
          pkgs.postgresql
          {{/if}}
        ] ++ pkgs.lib.optional {{nix.process-compose}} pkgs.process-compose;

        commonShellHook = ''
          {{#if Eq nix.pre-commit true}}
          ${self.checks.${system}.pre-commit-check.shellHook}
          {{/if}}
          {{#if Eq nix.postgresql true}}

          export PGHOST="$PWD/db"
          export PGDATA="$PGHOST/db"
          export PGLOG=$PGHOST/postgres.log
          export PGDATABASE={{project.name}}
          export PG_CONNECTION_STRING=postgresql://$(jq -rn --arg x $PGHOST '$x|@uri')/$PGDATABASE

          mkdir -p $PGHOST
          mkdir -p .dev

          if [ ! -d $PGDATA ]; then
            initdb --auth=trust --no-locale --encoding=UTF8
          fi
          {{/if}}
        '';

        mkProjectShell = ghc: hsdev.mkDevShell {
          inherit ghc;
          extraNativeBuildInputs = commonNativeBuildInputs;
          withHls = true;
          shellHook = commonShellHook;
        };
        {{#if Eq nix.treefmt true}}
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        formatter = treefmtEval.config.build.wrapper;
        {{/if}}
      in
      {
        {{#if Eq nix.treefmt true}}
        formatter = formatter;

        {{/if}}
        packages = {
          default = haskellPackages.callCabal2nix "{{project.name}}" ./. { };
        };

        checks = {
          {{#if Eq nix.treefmt true}}
          formatting = treefmtEval.config.build.check self;
          {{/if}}
          {{#if Eq nix.pre-commit true}}
          pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              {{#if Eq nix.treefmt true}}
              treefmt.package = formatter;
              treefmt.enable = true;
              {{/if}}
            };
          };
          {{/if}}
        };

        devShells = {
          default = mkProjectShell "{{ghc.version}}";
          "{{ghc.version}}" = mkProjectShell "{{ghc.version}}";
          {{#each ghc.extra-versions}}
          "{{this}}" = mkProjectShell "{{this}}";
          {{/each}}
        };
      });
}
```

Notes:

- `inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs"` is what makes the project inherit the
  base flake's exact nixpkgs revision — the single shared lock.
- `haskellPackages` is still derived for `packages.default` via `callCabal2nix`; because it
  comes from the *followed* nixpkgs, it is the identical GHC build the base flake's shells use,
  so it is cached too.
- The PostgreSQL/process-compose/treefmt/pre-commit blocks are preserved exactly as in the old
  template; only the toolchain/devShell construction changed.
- If you chose Strategy B in M1, replace the `{{#each ghc.extra-versions}} ... {{/each}}` block
  with: `{{#if ghc.secondary}}"{{ghc.secondary}}" = mkProjectShell "{{ghc.secondary}}";{{/if}}`
  (use whatever truthiness/`Eq` form the engine supports for an optional text var).

Render-check the template against a sample variable set. Use seihou's dry-run to render
without writing into a real project:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake
seihou run nix-haskell-flake --dry-run \
  --var project.name=sample --var project.description="sample project" \
  --var nix.process-compose=false --var nix.postgresql=false \
  --var nix.treefmt=true --var nix.pre-commit=true 2>&1 | sed -n '1,80p'
```

Inspect the rendered `flake.nix` in the dry-run output: it must reference
`haskell-nix-dev.lib.${system}.mkDevShell`, contain `devShells.default`,
`devShells."ghc9124"`, and `devShells."<ghc914>"`, and have no leftover `{{ ... }}` tokens.

Acceptance for M2: the dry-run renders a `flake.nix` with the base-flake input, the `follows`
lines, the `nixConfig` block, and the expected set of devShells, with all template tokens
resolved.

### Milestone 3 — Re-lock, document, and end-to-end smoke test

Scope: regenerate the template's bundled `flake.lock` so it pins `haskell-nix-dev`, update the
README, and bootstrap a throwaway project to prove the generated flake builds and both GHC
shells work.

Regenerate `files/flake.lock`. The simplest reliable way is to bootstrap into a scratch
directory, let `nix flake lock` resolve the new inputs, then copy the resulting lock back into
the module:

```bash
scratch=$(mktemp -d); cd "$scratch"
git init -q
seihou run nix-haskell-flake \
  --var project.name=sample --var project.description="sample project" \
  --var nix.process-compose=false --var nix.postgresql=false \
  --var nix.treefmt=true --var nix.pre-commit=true
# create a minimal cabal file so callCabal2nix has something to read:
cat > sample.cabal <<'CABAL'
cabal-version: 2.4
name: sample
version: 0.1.0
library
  default-language: Haskell2010
  build-depends: base
CABAL
nix flake lock
cp flake.lock /Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/files/flake.lock
```

Then exercise the generated project to prove the behavior:

```bash
cd "$scratch"
nix develop --command bash -lc 'ghc --version'            # -> 9.12.4 (default == {{ghc.version}})
nix develop .#<ghc914> --command bash -lc 'ghc --version' # -> 9.14.x
nix develop --command bash -lc 'cabal --version && haskell-language-server --version'
nix build .#packages.$(nix eval --impure --raw --expr builtins.currentSystem).default --no-link
nix flake show
cd - >/dev/null; rm -rf "$scratch"
```

Update `/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/README.md`:
bump the version to `0.10.0`, document the new `ghc.extra-versions` (or `ghc.secondary`)
variable in the Variables table, explain that the flake now consumes the base flake
`github:shinzui/haskell-nix-dev` and inherits its nixpkgs (single shared lock; upgrade via
`nix flake update haskell-nix-dev`), describe the per-version devShells, and note the Cachix
binary cache and how to enable it.

Commit all the module changes (in the `seihou-modules` repository):

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-modules
git add modules/haskell/nix-haskell-flake/
git commit -m "$(cat <<'EOF'
feat(nix-haskell-flake): consume the haskell-nix-dev base flake for multi-GHC support

Generated projects now follow the base flake's nixpkgs (single shared lock),
expose a devShell per configured GHC (default ghc9124 + extras), advertise the
Cachix cache, and build the project via callCabal2nix. Bump module to 0.10.0.

MasterPlan: docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md
ExecPlan: docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md
Intention: intention_01kt71x4veegvsc87z3qmsbab7
EOF
)"
```

Note: the commit trailers reference plan paths under this repository
(`haskell-nix-dev`), but the change is committed in the `seihou-modules` repository; that is
intentional — the trailers point back to the governing plans regardless of which repo holds
the code.

Acceptance for M3: a freshly bootstrapped scratch project's default `nix develop` gives GHC
9.12.4, `nix develop .#<ghc914>` gives GHC 9.14.x, `cabal` and `haskell-language-server` run
in the shells, `nix build .#default` builds the sample package, the module's `flake.lock` pins
`haskell-nix-dev`, and the README documents the new behavior.


## Concrete Steps

All paths are absolute because this plan edits a second repository
(`/Users/shinzui/Keikaku/bokuno/seihou-modules`) distinct from the one the plan files live in.

1. M1: investigate engine list support; edit `module.dhall` (version 0.10.0, add
   `ghc.extra-versions`, keep `ghc.version` export); `dhall type --file module.dhall`.
2. M2: rewrite `files/flake.nix.tpl` (template above); `seihou run ... --dry-run` and inspect
   the rendered flake.
3. M3: regenerate `files/flake.lock` via a scratch bootstrap + `nix flake lock`; run the
   end-to-end shell/build checks; update `README.md`; commit in `seihou-modules` with the
   trailers shown.

Update this section with the resolved `<ghc914>` attribute, the chosen Strategy (A or B), and
the exact base-flake ref pinned, as you proceed.


## Validation and Acceptance

Complete when, after `seihou run nix-haskell-flake` into a fresh project:

- `nix develop --command ghc --version` prints GHC 9.12.4 (the `ghc.version` default).
- `nix develop .#<ghc914> --command ghc --version` prints GHC 9.14.x.
- In both shells `cabal --version` and `haskell-language-server --version` succeed.
- `nix build .#default` builds the project's package.
- The generated `flake.nix` contains `inputs.haskell-nix-dev`,
  `inputs.nixpkgs.follows = "haskell-nix-dev/nixpkgs"`, the `nixConfig` cache block, and one
  devShell per configured GHC.
- The module's bundled `files/flake.lock` has a `haskell-nix-dev` node.
- `module.dhall` still exports `ghc.version`; `dhall type --file module.dhall` succeeds and
  `haskell-library`'s module still type-checks
  (`dhall type --file /Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`).

The single-lock upgrade story is demonstrable: change the base flake's pin, run
`nix flake update haskell-nix-dev` in a project, and observe the project's GHC change without
editing the project's own `flake.nix`.


## Idempotence and Recovery

Editing `module.dhall`, `flake.nix.tpl`, and `README.md` is plain text work; re-running
`dhall type` and `seihou run --dry-run` is read-only. The scratch-project steps use a
`mktemp -d` directory that is removed at the end, so they never touch real projects and can be
repeated freely. Regenerating `files/flake.lock` is idempotent (`nix flake lock` produces the
same lock for the same inputs). If a generated flake fails to evaluate, fix `flake.nix.tpl`
and re-render; nothing is destructive. Keep the old single-version template content in git
history so it can be restored if the base flake is unavailable.


## Interfaces and Dependencies

Consumes (hard dependency, EP-1,
`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md`): the base flake's
per-system `lib.${system}.mkDevShell`, `lib.${system}.defaultGhc`, `lib.${system}.ghcVersions`,
and its `follows`-able inputs `nixpkgs`, `flake-utils`, `treefmt-nix`. These names are the
MasterPlan Integration Point "Consumer API of the base flake"; if EP-1 changed them, read the
MasterPlan's current Integration Points before editing.

Consumes (soft dependency, EP-2,
`docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md`): the Cachix cache
name and public key (recorded in the MasterPlan's Surprises & Discoveries) for the generated
flake's `nixConfig`. Until EP-2 publishes them, leave the placeholder values and a TODO.

Produces / preserves: the `seihou` module `nix-haskell-flake` at version `0.10.0`, still
exporting `ghc.version` (consumed by the sibling module `haskell-library` at
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/haskell-library/module.dhall`).
New variable `ghc.extra-versions` (`list text`, Strategy A) or `ghc.secondary` (`text`,
Strategy B). Generated outputs: `flake.nix` (now consuming the base flake), the bundled
`flake.lock` (pinning `haskell-nix-dev`), and the unchanged `.envrc`, `treefmt.nix`,
`process-compose.yaml`, and `.gitignore` fragments.
