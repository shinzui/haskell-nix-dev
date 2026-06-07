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

- [x] M1: Cache exists and key recorded — **reusing the existing `shinzui` cache** (not a new `haskell-nix-dev` one): URL `https://shinzui.cachix.org`, key `shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=`, reachable (HTTP 200). (2026-06-07)
- [ ] M1 (remaining): Add `CACHIX_AUTH_TOKEN` push secret to `shinzui/haskell-nix-dev` GitHub repo (repo currently has zero secrets). **Operator-gated** — see Surprises & Discoveries.
- [x] M2: Add `.github/workflows/build.yml` that builds every toolchain across systems and pushes to Cachix. (2026-06-07 — authored; matrix `macos-14` [aarch64-darwin, primary] + `ubuntu-latest`; `fail-fast: false`; not yet committed/pushed — held until M1 secret exists so the first CI run is green.)
- [x] M2: Confirm CI is green and that a second CI run reports cache hits (paths fetched, not built). (2026-06-07 — run `27107180663` green on both runners; cache-warm times **macOS 2h16m→9m28s, Linux 1h39m→1m19s** — the speedup is the fetch-vs-build proof.)
- [x] M3: Fill the base flake's `nixConfig` substituter/key placeholders with the real cache values. (2026-06-07 — `https://shinzui.cachix.org` + key in `flake.nix`.)
- [x] M3: Verify the toolchains are fetched from Cachix, not built. (2026-06-07 — `toolchain-ghc9124` bundle and `haskell-language-server-2.13.0.0` [`5zh48s6…`] both return HTTP 200 on `shinzui.cachix.org`; CI run 2 fetched them, cutting macOS build to 9m. Local `--dry-run` is a no-op only because this dev machine already has the paths in-store.)
- [x] M3: Record the final cache name and public key in the MasterPlan's Surprises & Discoveries. (2026-06-07)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

**Reusing the existing `shinzui` Cachix cache (2026-06-07).** Rather than creating a new
`haskell-nix-dev` cache, this plan reuses the user's existing `shinzui.cachix.org`, already
wired into `/Users/shinzui/Keikaku/dotfiles.nix`:

- `darwin/bootstrap.nix` lists `https://shinzui.cachix.org` under `substituters` and
  `shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=` under
  `trusted-public-keys` — so the cache is **already trusted on the user's machines** (no
  `cachix use` needed locally; a fresh consumer machine without this config still needs the
  flake `nixConfig` / `cachix use shinzui`).
- `home/cachix.nix` writes `~/.config/cachix/cachix.dhall` with an `authToken` sourced from
  agenix (`secrets/cachix_auth_token.dhall.age`) — the local CLI push credential.
- Cache reachable: `curl -sI https://shinzui.cachix.org/nix-cache-info` → HTTP 200.

**M1 remaining (operator-gated).** GitHub-hosted runners do not have the local agenix token, so
CI still needs a repo secret. The `shinzui/haskell-nix-dev` repo currently has **zero secrets**
(`gh secret list` empty). The operator must add `CACHIX_AUTH_TOKEN` (reuse the existing `shinzui`
auth token or mint a new write token at app.cachix.org). Repo/tooling facts: remote
`https://github.com/shinzui/haskell-nix-dev.git`; `gh` authed as `shinzui`; `cachix` CLI at
`/Users/shinzui/.nix-profile/bin/cachix`. The agent is holding the workflow commit/push until
this secret exists so the first CI run is green.

**First CI run (27103918872, 2026-06-07): builds passed, macOS push step failed on a daemon
drain timeout.** Both runners' `nix flake check` succeeded (Linux 1h39m, macOS 2h16m). The
macOS `ghc9124` HLS closure built and was pushed (logs show `Pushed … haskell-language-server-2.13.0.0`,
`ghcide-2.13.0.0`, `haskell-toolchain-ghc9124`). But the streaming Cachix **daemon** only gets a
60s drain grace at shutdown; with ~20 paths still in flight it logged `Push manager drain timed
out` / `Failed 9 stuck jobs` and exited code 3, marking the job red even though the build and
most pushes succeeded. Linux pushed fully (faster runner, fewer in-flight paths at drain).
Fix: set `useDaemon: false` on `cachix-action` (verified the only push knobs in v15 are
`skipPush`/`pathsToPush`/`pushFilter`/`cachixArgs`/`useDaemon`; no drain-timeout input exists),
which pushes all new paths in one synchronous post-step with no drain timeout.

Non-blocking: GHA warns `actions/checkout@v4` and `cachix/cachix-action@v15` run on Node 20
(deprecated June 16 2026). Cosmetic for now; bump later.

**Green run + cache-hit proof (run 27107180663, 2026-06-07).** Runners: `macos-14`
(aarch64-darwin), `ubuntu-latest` (x86_64-linux). With the cache populated by the prior run,
the `useDaemon: false` run was green on both legs and dramatically faster because the build now
*fetches* from `shinzui` instead of compiling:

| System | Run 1 (cold) | Run 2 (warm) |
|--------|--------------|--------------|
| aarch64-darwin (macOS) | 2h16m52s | **9m28s** |
| x86_64-linux | 1h39m18s | **1m19s** |

The dominant saving is the `ghc9124` HLS, which builds from source cold. Direct cache check:
`curl -sI https://shinzui.cachix.org/<hash>.narinfo` returns **HTTP 200** for both
`haskell-toolchain-ghc9124` and `haskell-language-server-2.13.0.0`
(`/nix/store/5zh48s6rsfzlqzdhrykf6376ydp0gbcy-…`, the same path the run-1 push logged).

Note on local `--dry-run`: on this dev machine `nix build .#toolchain-ghc9124 --dry-run` is a
no-op (nothing fetched/built) because the toolchain is already in-store from prior local work;
nixConfig also emits "ignoring untrusted flake configuration" warnings since flake `nixConfig`
is advisory unless trusted — the user's dotfiles already trust `shinzui`, and fresh consumers
run `cachix use shinzui` (documented in the README). The CI cold→warm drop is the authoritative
fetch-vs-build evidence.


## Decision Log

Record every decision made while working on the plan.

- Decision: Use Cachix (hosted) for the binary cache, populated by GitHub Actions.
  Rationale: Inherited from the MasterPlan Decision Log (2026-06-03).
  Date: 2026-06-03

- Decision: Reuse the user's existing **`shinzui`** Cachix cache rather than creating a new
  `haskell-nix-dev` cache.
  Rationale: The user (2026-06-07) pointed out `shinzui.cachix.org` is already configured in
  `/Users/shinzui/Keikaku/dotfiles.nix` — listed as a trusted substituter + key in
  `darwin/bootstrap.nix` and with its auth token managed via agenix
  (`home/cachix.nix` → `~/.config/cachix/cachix.dhall`). Reusing it means: (a) no new account
  setup, (b) the cache is already trusted on the user's machines (no `cachix use` needed
  locally), and (c) the public key is already known. The workflow's `cachix-action` `name:` is
  set to `shinzui`. Cache name `shinzui`, URL `https://shinzui.cachix.org`, public key
  `shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=`.
  Date: 2026-06-07

- Decision: Drop the belt-and-suspenders explicit `packages` build loop from the workflow;
  rely on `nix flake check` alone.
  Rationale: `checks.toolchain-<ghc>` and `packages.toolchain-<ghc>` are the *same*
  `toolchainPackage ghc` derivation (verified in `flake.nix` lines 104–137), so building the
  checks realizes the identical store paths. cachix-action pushes everything built during the
  job. The loop added no coverage and only risked `nix flake show --json` evaluation overhead.
  Date: 2026-06-07

- Decision: Order the CI matrix with `macos-14` (aarch64-darwin) first and keep
  `fail-fast: false`.
  Rationale: Per the user (2026-06-07), the macOS cache is the important one — aarch64-darwin
  is where the `ghc9124` HLS (profiling-fixed, 5 from-source derivations) actually builds from
  source; the Linux toolchain is largely cached upstream. `fail-fast: false` ensures a Linux
  failure never cancels the high-value macOS job.
  Date: 2026-06-07

- Decision: Set `useDaemon: false` on `cachix-action` instead of the default streaming daemon.
  Rationale: The default daemon streams pushes during the build but only gets a 60s drain grace
  at shutdown; the macOS runner left ~20 paths in flight and failed the job (exit 3) on a drain
  timeout even though the build and the high-value HLS pushes succeeded. v15 exposes no
  drain-timeout input, so `useDaemon: false` (one synchronous push at job end, no timeout) is
  the deterministic fix.
  Date: 2026-06-07

- Decision: Author `.github/workflows/build.yml` before M1, but hold the commit/push until the
  `CACHIX_AUTH_TOKEN` secret exists.
  Rationale: M1 (Cachix account, cache, auth token, GitHub secret) requires operator access I
  do not have. Pushing the workflow before the secret exists would make cachix-action's push
  step fail and produce a red first CI run. Holding the push keeps the first run green.
  Date: 2026-06-07


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original purpose.

Delivered (2026-06-07). The base flake's toolchains are now built in CI and cached on Cachix,
and the flake advertises the cache — meeting the plan's purpose (stop rebuilding HLS from
source on every machine).

- **Cache:** reused the user's existing `shinzui.cachix.org` (already trusted in
  `dotfiles.nix`) instead of creating a new one — no account setup, key already known.
- **CI:** `.github/workflows/build.yml` — matrix `macos-14` (aarch64-darwin, primary) +
  `ubuntu-latest`, `fail-fast: false`, driven by `nix flake check` so it tracks `supportedGhcs`
  with no hard-coded version list. Pushes with `cachix-action@v15`, `useDaemon: false`.
- **Advertised:** `flake.nix` `nixConfig` carries the `shinzui` substituter + key; README has a
  "Binary cache" section (`cachix use shinzui` / nix.conf lines).
- **Result:** cache-warm CI dropped macOS 2h16m→9m28s and Linux 1h39m→1m19s; HLS + toolchain
  paths confirmed present on the cache (HTTP 200).

Gaps / lessons:
- The streaming Cachix daemon's fixed 60s shutdown drain is too short for large macOS pushes
  and fails the job after a successful build; `useDaemon: false` is the reliable choice for
  big-closure Haskell toolchains.
- `actions/checkout@v4` and `cachix-action@v15` run on Node 20 (GHA-deprecated 2026-06-16) —
  non-blocking warning; bump when convenient.
- There is no `ghc9141` HLS to cache (GHC 9.14 HLS is unbuildable in nixpkgs); when it is
  eventually enabled in EP-1's `hlsGhcs`, CI needs no change — it builds the flake's `checks`,
  which will then include the 9.14 HLS automatically.


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
