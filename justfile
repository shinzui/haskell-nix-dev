# haskell-nix-dev — toolchain maintenance recipes.
# Run from this directory (the base-flake repo).

# Default: show which consumer flakes pin which haskell-nix-dev rev (no writes).
default: check-toolchain

# Dry run: report every consumer's pinned rev and whether they're in lockstep.
check-toolchain:
    ./scripts/update-haskell-toolchain.sh

# Bump every consumer flake to the latest haskell-nix-dev, in lockstep.
update-toolchain:
    ./scripts/update-haskell-toolchain.sh --apply

# Pin every consumer flake to a specific haskell-nix-dev revision, in lockstep.
update-toolchain-rev rev:
    ./scripts/update-haskell-toolchain.sh --rev {{rev}} --apply

# As above but scan a different workspace root for consumers.
update-toolchain-root root:
    ./scripts/update-haskell-toolchain.sh --root {{root}} --apply
