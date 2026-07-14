#!/usr/bin/env bash
# Verify restore using only configured NuGet sources (local offline-packages by default).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d offline-packages ]] || [[ -z "$(ls -A offline-packages/*.nupkg 2>/dev/null || true)" ]]; then
  echo "ERROR: offline-packages/ is empty."
  echo "  Ubuntu platform packs only:  ./scripts/prepare-ubuntu-packs.sh"
  echo "  Full self-contained feed:    ./scripts/prepare-offline-packages.sh"
  exit 1
fi

count=$(find offline-packages -maxdepth 1 -name '*.nupkg' | wc -l | tr -d ' ')
echo "==> offline-packages contains $count nupkg(s)"

# Heuristic: platform-packs-only feeds are small and cannot restore the full graph alone
if [[ "$count" -lt 100 ]]; then
  echo "NOTE: This looks like an Ubuntu platform-packs-only feed."
  echo "      Ordinary libraries (xunit, BenchmarkDotNet, etc.) must come from nuget.org"
  echo "      or a complete offline feed. For full air-gap run prepare-offline-packages.sh."
fi

VERIFY_PACKAGES="$(mktemp -d "${TMPDIR:-/tmp}/pbn-verify-packages.XXXXXX")"
cleanup() { rm -rf "$VERIFY_PACKAGES"; }
trap cleanup EXIT

echo "==> Offline restore (packages -> $VERIFY_PACKAGES)..."
dotnet restore Build.csproj \
  --force \
  --packages "$VERIFY_PACKAGES" \
  --source "$ROOT/offline-packages" \
  --verbosity minimal \
  /p:RestoreIgnoreFailedSources=false

echo "==> Offline restore succeeded."
