#!/usr/bin/env bash
#
# update-haskell-toolchain.sh — bump the `haskell-nix-dev` pin across every
# consumer flake in lockstep, so they all keep resolving to ONE shared toolchain
# (GHC / cabal / HLS) derivation and share the binary cache.
#
# Why lockstep: each consumer has its own flake.lock; they share the toolchain
# only while they pin the SAME haskell-nix-dev revision (nixpkgs follows it).
# Update one alone and it drifts off the shared cache until the rest catch up.
#
# Usage:
#   update-haskell-toolchain.sh [--root DIR] [--rev REV] [--apply]
#
#   --root DIR   Workspace to scan for consumers (default: parent of this repo).
#   --rev REV    Pin to a specific haskell-nix-dev revision (default: latest).
#   --apply      Actually write the locks. Without it, this is a dry run.
#
# It never commits — review and commit each repo's flake.lock yourself.
set -euo pipefail

INPUT="haskell-nix-dev"
FLAKE_REF="github:shinzui/haskell-nix-dev"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # default: the workspace containing this repo
REV=""
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --rev)  REV="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Extract the locked haskell-nix-dev rev (and the nixpkgs rev it pulls in) from a
# flake.lock — these two together decide whether two projects share the toolchain.
lock_revs() { # $1 = flake.lock -> "<hnd-rev> <nixpkgs-rev>"
  python3 - "$1" <<'PY'
import json, sys
try:
    n = json.load(open(sys.argv[1])).get("nodes", {})
    hnd = (n.get("haskell-nix-dev", {}).get("locked", {}).get("rev") or "-")[:12]
    nxp = n.get("haskell-nix-dev", {}).get("inputs", {}).get("nixpkgs")
    nxp = (n.get(nxp, {}).get("locked", {}).get("rev") or "-")[:12] if isinstance(nxp, str) else "-"
    print(hnd, nxp)
except Exception:
    print("- -")
PY
}

if [ -z "$REV" ]; then
  REV="$(nix flake metadata "$FLAKE_REF" --json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')"
fi
TARGET="${REV:0:12}"

echo "haskell-nix-dev lockstep updater"
echo "  workspace : $ROOT"
echo "  target    : $TARGET"
echo "  mode      : $([ "$APPLY" = 1 ] && echo APPLY || echo 'dry-run (pass --apply to write locks)')"
echo

# Discover consumers: directories whose flake.nix references the base flake.
consumers=()
while IFS= read -r dir; do consumers+=("$dir"); done < <(
  find "$ROOT" \
       \( -name .git -o -name result -o -name '.direnv' -o -name node_modules \) -prune -o \
       -type f -name flake.nix -print 2>/dev/null \
  | while IFS= read -r f; do grep -ql "shinzui/haskell-nix-dev" "$f" && dirname "$f"; done \
  | sort -u
)

if [ "${#consumers[@]}" -eq 0 ]; then
  echo "No consumer flakes found under $ROOT" >&2
  exit 0
fi

printf "%-45s  %-14s  %-14s\n" "project (relative to workspace)" "hnd rev" "nixpkgs rev"
printf "%-45s  %-14s  %-14s\n" "-------------------------------" "--------------" "--------------"

fail=0
declare -a seen_hnd=()
for dir in "${consumers[@]}"; do
  if [ "$APPLY" = 1 ]; then
    if ! ( cd "$dir" && nix flake update "$INPUT" \
             --override-input "$INPUT" "$FLAKE_REF/$REV" >/dev/null 2>&1 ); then
      printf "%-45s  %s\n" "${dir#"$ROOT"/}" "UPDATE FAILED"
      fail=1
      continue
    fi
  fi
  read -r hnd nxp <<<"$(lock_revs "$dir/flake.lock")"
  seen_hnd+=("$hnd")
  printf "%-45s  %-14s  %-14s\n" "${dir#"$ROOT"/}" "$hnd" "$nxp"
done

echo
# Lockstep check: every consumer must pin the same haskell-nix-dev rev.
uniq_count="$(printf '%s\n' "${seen_hnd[@]}" | sort -u | wc -l | tr -d ' ')"
if [ "$uniq_count" = "1" ] && [ "${seen_hnd[0]}" = "$TARGET" ]; then
  echo "✓ lockstep: all ${#consumers[@]} consumers pin $TARGET — shared toolchain & cache."
elif [ "$uniq_count" = "1" ]; then
  echo "✓ lockstep: all consumers pin ${seen_hnd[0]} (target is $TARGET)."
  [ "$APPLY" = 1 ] || echo "  run with --apply to move them to $TARGET."
else
  echo "✗ DRIFT: consumers pin $uniq_count different revs — they do NOT share the toolchain."
  [ "$APPLY" = 1 ] || echo "  run with --apply to bring them all to $TARGET."
  fail=1
fi

[ "$APPLY" = 1 ] && echo && echo "Locks written. Review and commit each repo's flake.lock."
exit $fail
