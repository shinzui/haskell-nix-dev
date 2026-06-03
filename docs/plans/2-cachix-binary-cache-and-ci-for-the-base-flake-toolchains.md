---
id: 2
slug: cachix-binary-cache-and-ci-for-the-base-flake-toolchains
title: "Cachix binary cache and CI for the base flake toolchains"
kind: exec-plan
created_at: 2026-06-03T15:41:55Z
intention: "intention_01kt71x4veegvsc87z3qmsbab7"
master_plan: "docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md"
---

# Cachix binary cache and CI for the base flake toolchains

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This plan belongs to the MasterPlan at
`docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md`. It **hard-depends** on
`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md`: that plan creates the
`flake.nix` and the buildable toolchain outputs this plan builds and caches. Do not start
until EP-1's Milestone 4 is complete (i.e. `nix flake check` passes and
`nix build .#toolchain-ghc9124` produces a store path in the repository
`/Users/shinzui/Keikaku/bokuno/haskell-nix-dev`).


## Purpose / Big Picture

A **binary cache** (also called a **substituter**) is a remote store of already-built Nix
artifacts. When a developer's machine needs a build that a trusted substituter already has,
Nix downloads the finished result instead of compiling it. **Cachix** is a hosted service
that runs such a cache for you; you push builds to it from CI and consumers pull from it.

Today, building the Haskell Language Server (HLS) for a GHC version that is not nixpkgs'
default compiler is done from source on every machine, which can take an hour or more. After
this plan, a GitHub Actions workflow will build the base flake's toolchains — GHC, HLS, and
cabal — for every supported GHC version across the target platforms **once**, push them to a
Cachix cache, and the flake will advertise that cache so any developer (or downstream
project) downloads the prebuilt binaries in seconds.

You will be able to demonstrate the win concretely: on a machine that has never built these
toolchains, after configuring the cache, `nix develop .#<ghc914>` will fetch HLS from Cachix
rather than compiling it, and the `nix build --dry-run` output will say the paths "will be
fetched" instead of "will be built". (`<ghc914>` is the latest-9.14 attribute resolved by
EP-1 and recorded in the MasterPlan's Surprises & Discoveries, e.g. `ghc9141`.)


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Create the Cachix cache; record its name and public key; store the auth/signing secret in the repo's GitHub secrets.
- [ ] M2: Add `.github/workflows/build.yml` that builds every toolchain across systems and pushes to Cachix.
- [ ] M2: Confirm CI is green and that a second CI run reports cache hits (paths fetched, not built).
- [ ] M3: Fill the base flake's `nixConfig` substituter/key placeholders with the real cache values.
- [ ] M3: Verify on a clean store that the toolchains are fetched from Cachix, not built.
- [ ] M3: Record the final cache name and public key in the MasterPlan's Surprises & Discoveries.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet. Record the final cache name, the public key, which runners were used for each
system, and the measured before/after fetch-vs-build for HLS here.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Use Cachix (hosted) for the binary cache, populated by GitHub Actions.
  Rationale: Inherited from the MasterPlan Decision Log (2026-06-03).
  Date: 2026-06-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

You are working in the git repository `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev`. By the
time this plan runs, EP-1
(`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md`) has created a
`flake.nix` there that exposes, per system, buildable package outputs named
`packages.<system>.toolchain-<ghcName>` (one per supported GHC) and a
`checks.<system>.toolchain-<ghcName>` set, plus a top-level `nixConfig` block with empty
`extra-substituters` and `extra-trusted-public-keys` placeholders. The supported GHC
attribute names live in a `supportedGhcs` list inside `flake.nix` (e.g. `ghc9124` and the
resolved latest-9.14 attribute, recorded in the MasterPlan's Surprises & Discoveries). This
plan does not change the toolchain logic; it only adds CI and fills the substituter
placeholders.

Definitions used below:

- **GitHub Actions**: GitHub's CI system. A *workflow* is a YAML file under
  `.github/workflows/` describing jobs that run on GitHub-hosted *runners* (virtual machines).
  A *matrix* runs the same job once per combination of parameters (here: per system).
- **Runner / system mapping**: GitHub-hosted runners map to Nix systems as follows —
  `ubuntu-latest` → `x86_64-linux`; `macos-14` (Apple Silicon) → `aarch64-darwin`;
  `macos-13` (Intel) → `x86_64-darwin`. Choose runners to cover the systems you actually use
  for development; at minimum cover your daily-driver system. The repo author develops on
  macOS (Darwin), so `aarch64-darwin` coverage is important; add `x86_64-linux` because it is
  the cheapest runner and is what most downstream CI will use.
- **`cachix/install-nix-action`** and **`cachix/cachix-action`**: official GitHub Actions that
  install Nix and configure pushing/pulling to a Cachix cache, respectively.
- **Auth token vs signing key**: Cachix caches authenticate writes either with an
  *auth token* (`CACHIX_AUTH_TOKEN`, for caches that use Cachix-managed signing) or a
  *signing key* (`CACHIX_SIGNING_KEY`, for self-signed caches). A modern Cachix cache uses an
  auth token; this plan assumes the auth-token model and notes the signing-key alternative.
- **Public key / trusted-public-keys**: every Cachix cache has a public key of the form
  `<cache-name>.cachix.org-1:<base64>`. Consumers must list it under
  `extra-trusted-public-keys` (and the URL under `extra-substituters`) before Nix will trust
  downloads from it. This pair is the integration point EP-3 also consumes.

There is no existing CI in this repository at the start of this plan (no `.github/` directory).


## Plan of Work

Three milestones: create the cache, wire CI to build and push, then advertise the cache and
prove the speedup.

### Milestone 1 — Create the Cachix cache and store credentials

Scope: a Cachix cache exists, you know its name and public key, and the credential needed to
push to it from CI is stored as a GitHub Actions secret. No files change in this milestone
except possibly notes.

These steps require accounts and secrets, so they are performed by you (the human operator);
the agent should prompt the operator to perform them and paste back the resulting public key.
In this Claude Code session you can run a command yourself by typing it with a leading `!`.

1. Create a Cachix account at https://app.cachix.org and create a cache. A reasonable name is
   `haskell-nix-dev` (the cache URL becomes `https://haskell-nix-dev.cachix.org`). If that
   name is taken, pick another and use it consistently everywhere below.
2. From the cache's settings, copy its **public key** (looks like
   `haskell-nix-dev.cachix.org-1:AAAA...`). Record it in Surprises & Discoveries and in the
   MasterPlan's Surprises & Discoveries.
3. Generate a push credential: in the cache settings create an **auth token** with write
   access (or, for a self-signed cache, a signing key).
4. Add it to the GitHub repository that hosts `haskell-nix-dev` as an Actions secret named
   `CACHIX_AUTH_TOKEN` (Settings → Secrets and variables → Actions → New repository secret).
   If you used a signing key instead, name the secret `CACHIX_SIGNING_KEY` and adjust the
   workflow accordingly in M2.

Acceptance for M1: the cache exists and is reachable
(`curl -sI https://<cache-name>.cachix.org/nix-cache-info` returns HTTP 200), the public key
is recorded, and the push secret is present in the repo's GitHub Actions secrets.

### Milestone 2 — CI workflow that builds and pushes every toolchain

Scope: add a GitHub Actions workflow that, on every push and pull request, builds all of the
flake's toolchain outputs for each target system and pushes them to Cachix. At the end, a
green CI run has populated the cache.

Create `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev/.github/workflows/build.yml`. Replace
`haskell-nix-dev` with your actual cache name if different. The workflow builds the flake's
`checks` (which EP-1 defined as the per-GHC toolchain bundles), so it automatically covers
every supported GHC without hard-coding the version list — this honours the MasterPlan
integration point that CI must not diverge from the flake's canonical `supportedGhcs`.

```yaml
name: build

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: ubuntu-latest    # x86_64-linux
          - runner: macos-14         # aarch64-darwin
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4

      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
            accept-flake-config = true

      - uses: cachix/cachix-action@v15
        with:
          name: haskell-nix-dev
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      # Build every toolchain for this runner's system. `nix flake check` builds the
      # `checks` outputs (the per-GHC toolchain bundles EP-1 defined). cachix-action
      # automatically pushes newly built paths to the cache after the build.
      - name: Build all toolchains
        run: nix flake check --print-build-logs

      # Build the named package outputs explicitly too, so toolchain-<ghc> packages are cached.
      - name: Build toolchain packages
        run: |
          system=$(nix eval --impure --raw --expr builtins.currentSystem)
          for attr in $(nix flake show --json | nix run nixpkgs#jq -- -r \
            ".packages[\"$system\"] | keys[]"); do
            echo "building .#$attr"
            nix build ".#$attr" --print-build-logs --no-link
          done
```

Notes and adjustments:

- If you created a self-signed cache (signing key) instead of an auth token, replace the
  `cachix-action` `with:` block with `signingKey: ${{ secrets.CACHIX_SIGNING_KEY }}`.
- `cachix-action` pushes paths built during the job automatically; you do not need an explicit
  `cachix push` step. If you prefer an explicit push, add
  `nix build ... && cachix push <cache-name> ./result*`.
- `checks` and `packages` share the same underlying derivations, so the explicit package loop
  is belt-and-suspenders to guarantee the named `toolchain-<ghc>` packages are realized and
  pushed. If `nix flake check` already builds everything, you may drop the loop — record the
  choice in the Decision Log.

Commit and push so CI runs:

```bash
cd /Users/shinzui/Keikaku/bokuno/haskell-nix-dev
git add .github/workflows/build.yml
git commit -m "$(cat <<'EOF'
ci: build all GHC toolchains and push to Cachix

Add GitHub Actions matrix (x86_64-linux, aarch64-darwin) that builds the
flake checks/packages and pushes results to the haskell-nix-dev Cachix cache.

MasterPlan: docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md
ExecPlan: docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md
Intention: intention_01kt71x4veegvsc87z3qmsbab7
EOF
)"
git push
```

Watch the run with `gh run watch` or in the GitHub UI. Acceptance for M2: the workflow
succeeds on every matrix entry, and the Cachix cache web UI shows newly pushed store paths
for HLS and the compilers. Re-running the workflow (via `workflow_dispatch`) should be much
faster and the logs should show paths being fetched from the cache rather than rebuilt —
record before/after timings in Surprises & Discoveries.

### Milestone 3 — Advertise the cache and prove the speedup

Scope: fill the base flake's `nixConfig` placeholders so consumers automatically use the
cache, then demonstrate that a clean machine fetches rather than builds. At the end the flake
itself advertises the cache and you have evidence of the fetch.

Edit `/Users/shinzui/Keikaku/bokuno/haskell-nix-dev/flake.nix` and replace the empty
placeholder lists EP-1 left in `nixConfig` with the real values (use your cache name and the
public key from M1):

```nix
  nixConfig = {
    extra-substituters = [ "https://haskell-nix-dev.cachix.org" ];
    extra-trusted-public-keys = [ "haskell-nix-dev.cachix.org-1:REPLACE_WITH_PUBLIC_KEY" ];
  };
```

A flake's `nixConfig` is only honored when the user has opted into trusting it. For the most
reliable consumer experience, also document (in the README EP-1 created) that developers
should either add the substituter and key to their `~/.config/nix/nix.conf`, or run
`cachix use haskell-nix-dev` once. Add a short "Binary cache" section to the README spelling
this out, including the exact two lines for `nix.conf`:

```text
extra-substituters = https://haskell-nix-dev.cachix.org
extra-trusted-public-keys = haskell-nix-dev.cachix.org-1:REPLACE_WITH_PUBLIC_KEY
```

Prove the speedup on a store that does not already have the builds. The cleanest proof is a
`--dry-run` build that consults the substituters: after configuring the cache, a fresh
machine should report the HLS path as "will be fetched":

```bash
cd /Users/shinzui/Keikaku/bokuno/haskell-nix-dev
# With the cache configured (via `cachix use` / nix.conf), ask what realizing the 9.14 HLS does:
nix build .#toolchain-<ghc914> --dry-run 2>&1 | sed -n '1,40p'
# Expect a "these paths will be fetched" section listing HLS/ghc, and NO large
# "these derivations will be built" list for HLS.
```

If you have access to a second machine or a CI job that has never built these toolchains, run
the same `--dry-run` there for the strongest evidence and capture the output in Surprises &
Discoveries.

Commit and record the final cache coordinates in the MasterPlan:

```bash
git add flake.nix README.md
git commit -m "$(cat <<'EOF'
feat: advertise the haskell-nix-dev Cachix substituter in the flake

Fill nixConfig substituters/keys and document cache setup in the README so
consumers fetch prebuilt toolchains instead of building HLS from source.

MasterPlan: docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md
ExecPlan: docs/plans/2-cachix-binary-cache-and-ci-for-the-base-flake-toolchains.md
Intention: intention_01kt71x4veegvsc87z3qmsbab7
EOF
)"
```

Then edit `docs/masterplans/1-reusable-multi-ghc-haskell-base-flake.md`: in its Surprises &
Discoveries section, record the final cache name and public key verbatim, because EP-3
(`docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md`) copies
those exact strings into the generated project flake.

Acceptance for M3: `flake.nix` lists the real substituter URL and public key; the README has a
"Binary cache" section with the exact `nix.conf` lines; a `--dry-run` build of a toolchain on
a configured machine shows the toolchain being fetched rather than built; and the MasterPlan's
Surprises & Discoveries records the cache name and key.


## Concrete Steps

1. M1 (operator actions): create the Cachix cache, copy its public key, create an auth token,
   and add `CACHIX_AUTH_TOKEN` to the GitHub repo secrets. Verify reachability:

```bash
curl -sI https://haskell-nix-dev.cachix.org/nix-cache-info | head -1
# -> HTTP/2 200
```

2. M2: add `.github/workflows/build.yml` (template above), commit with the trailers shown,
   `git push`, and watch CI:

```bash
gh run watch || gh run list --limit 3
```

3. M3: fill `nixConfig` in `flake.nix`, add the README "Binary cache" section, prove the
   fetch with `nix build .#toolchain-<ghc914> --dry-run`, commit, and update the MasterPlan's
   Surprises & Discoveries with the cache name and key.

Keep this section updated with the real cache name, public key, and chosen runners.


## Validation and Acceptance

Complete when:

- CI (`.github/workflows/build.yml`) is green on every matrix entry on a push.
- The Cachix cache UI shows pushed paths for each supported GHC's HLS and compiler.
- `flake.nix`'s `nixConfig` lists the real substituter URL and public key.
- On a machine configured to use the cache, `nix build .#toolchain-<ghc914> --dry-run` shows
  the toolchain paths under "will be fetched", not "will be built".
- The MasterPlan's Surprises & Discoveries records the final cache name and public key.

Observable end-to-end win: on a clean checkout with the cache configured,
`time nix develop .#<ghc914> --command haskell-language-server --version` completes in seconds
(download) rather than the tens of minutes a source build of HLS would take. Capture both
numbers if you can.


## Idempotence and Recovery

Re-running CI is safe and idempotent: already-cached paths are skipped. Editing
`.github/workflows/build.yml` and pushing simply triggers a new run. Filling `nixConfig` is a
plain text edit; if the key is wrong, Nix fails closed — it refuses to trust downloads from
the cache and builds from source instead, so a typo degrades to the old slow behavior rather
than corrupting anything. If the auth token leaks, revoke it in the Cachix UI, create a new
one, and update the GitHub secret. Nothing in this plan deletes store paths or rewrites
history.


## Interfaces and Dependencies

Depends on: EP-1's `flake.nix` outputs `packages.<system>.toolchain-<ghcName>`,
`checks.<system>.toolchain-<ghcName>`, and the `nixConfig` placeholder
(`docs/plans/1-base-flake-providing-multi-version-ghc-hls-and-cabal.md`). The CI matrix
derives the GHC set from the flake (via `nix flake check` / `nix flake show`), so it stays in
sync with EP-1's canonical `supportedGhcs` list — do not hard-code a divergent version list.

Produces (integration point consumed by EP-3,
`docs/plans/3-integrate-the-base-flake-into-the-nix-haskell-flake-seihou-template.md`): the
Cachix **cache name** (URL `https://<cache-name>.cachix.org`) and its **public key**
(`<cache-name>.cachix.org-1:<base64>`), recorded in the MasterPlan's Surprises & Discoveries.
EP-3 copies these into the generated project flake's `nixConfig` so bootstrapped projects use
the cache from day one.

External Actions used: `actions/checkout@v4`, `cachix/install-nix-action@v30`,
`cachix/cachix-action@v15`. GitHub repository secret required: `CACHIX_AUTH_TOKEN` (or
`CACHIX_SIGNING_KEY` for a self-signed cache).
