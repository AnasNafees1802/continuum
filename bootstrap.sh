#!/usr/bin/env bash
# Continuum remote bootstrap (macOS / Linux).
#
# One-line install (global — once for every agent):
#   curl -fsSL https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.sh | bash
#
# Force all known agents (even undetected):
#   curl -fsSL https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.sh | CONTINUUM_ALL=1 bash
#
# Per-project install (ledger + committed adapters in the current directory):
#   curl -fsSL https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.sh | CONTINUUM_MODE=project bash
#
# Downloads the repo to a temp folder, runs the matching installer, then cleans up.
set -euo pipefail

REPO="AnasNafees1802/continuum"
BRANCH="main"
MODE="${CONTINUUM_MODE:-global}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Continuum ($BRANCH)..."
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$tmp"
src="$tmp/continuum-$BRANCH"

if [ "$MODE" = "project" ]; then
  bash "$src/install.sh" "${CONTINUUM_TARGET:-$PWD}"
else
  if [ "${CONTINUUM_ALL:-0}" = "1" ]; then
    ALL=1 bash "$src/install-global.sh"
  else
    bash "$src/install-global.sh"
  fi
fi
