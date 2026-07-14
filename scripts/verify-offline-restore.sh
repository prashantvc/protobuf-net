#!/usr/bin/env bash
# Verify that restore succeeds using ONLY the local offline-packages feed (no network).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d offline-packages ]] || [[ -z "$(ls -A offline-packages/*.nupkg 2>/dev/null || true)" ]]; then
  echo "ERROR: offline-packages/ is empty. Run scripts/prepare-offline-packages.sh first."
  exit 1
fi

# Use a throwaway global packages folder so we don't rely on a warm machine cache
VERIFY_PACKAGES="$(mktemp -d -t pbn-verify-packages.XXXXXX)"
cleanup() { rm -rf "$VERIFY_PACKAGES"; }
trap cleanup EXIT

echo "==> Offline restore (packages -> $VERIFY_PACKAGES)..."
# NUGET_CERT_REVOCATION_MODE=offline helps some air-gapped TLS stacks; --force ensures we hit the feed
DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=1 \
  dotnet restore Build.csproj \
    --force \
    --packages "$VERIFY_PACKAGES" \
    --source "$ROOT/offline-packages" \
    --verbosity minimal \
    /p:RestoreIgnoreFailedSources=false

echo "==> Offline restore succeeded."
