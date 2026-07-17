#!/usr/bin/env bash
# Download ONLY the Ubuntu/Linux-specific NuGet packages that a cross-platform
# (e.g. macOS-prepared) feed or a nuget.org library restore typically misses:
#   - NETStandard.Library.Ref
#   - Microsoft.NETCore.App.Ref / Microsoft.AspNetCore.App.Ref (patch versions)
#   - Microsoft.NETCore.App.Host.linux-x64
#   - Microsoft.Build.Traversal (MSBuild SDK used by Build.csproj)
#
# All of these are still published on nuget.org — there are no private/MyGet
# dependencies. This script only packages the OS/SDK-specific delta needed on Ubuntu.
#
# Usage (networked machine):
#   ./scripts/prepare-ubuntu-packs.sh
# Then copy offline-packages/ to the air-gapped Ubuntu host.
#
# On air-gapped Ubuntu, NuGet.Config should list:
#   1) ./offline-packages  (this delta)
#   2) your nuget.org mirror OR a full library package cache
# If you have NO nuget.org mirror at all, use prepare-offline-packages.sh instead
# for a complete feed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OFFLINE_DIR="${OFFLINE_DIR:-$ROOT/offline-packages}"
mkdir -p "$OFFLINE_DIR"

download_nupkg() {
  local id="$1" version="$2"
  local id_lower
  id_lower="$(echo "$id" | tr '[:upper:]' '[:lower:]')"
  local dest="$OFFLINE_DIR/${id_lower}.${version}.nupkg"
  if [[ -f "$dest" ]]; then
    echo "    = ${id} ${version} (exists)"
    return 0
  fi
  local url="https://api.nuget.org/v3-flatcontainer/${id_lower}/${version}/${id_lower}.${version}.nupkg"
  echo "    + ${id} ${version}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

echo "==> Clearing previous offline-packages (ubuntu packs only)..."
# Remove any existing nupkgs so we don't ship a multi-GB mixed feed by accident
find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' -delete 2>/dev/null || true

echo "==> Downloading Ubuntu/Linux platform + targeting packs from nuget.org..."

# MSBuild SDK for Build.csproj
download_nupkg "Microsoft.Build.Traversal" "2.0.19"
download_nupkg "Microsoft.Build.Traversal" "4.1.0"

# netstandard TFMs (protobuf-net multi-targets netstandard2.0/2.1)
download_nupkg "NETStandard.Library.Ref" "2.1.0"

# net8 is the primary TFM across this repo; Ubuntu SDK 10 resolves a specific patch
# (errors seen: wanted 8.0.29 when feed only had up to 8.0.28). Keep a short recent band.
NET8_PATCHES=(8.0.24 8.0.25 8.0.26 8.0.27 8.0.28 8.0.29)
# net10 packs for SDK 10.0.x / projects that may pull framework refs at 10.x
NET10_PATCHES=(10.0.5 10.0.6 10.0.7 10.0.8 10.0.9 10.0.10)

for ver in "${NET8_PATCHES[@]}" "${NET10_PATCHES[@]}"; do
  download_nupkg "Microsoft.NETCore.App.Ref" "$ver"
  download_nupkg "Microsoft.AspNetCore.App.Ref" "$ver"
  # Host pack MUST be linux-x64 for Ubuntu x86_64 (this is what macOS prepare misses)
  download_nupkg "Microsoft.NETCore.App.Host.linux-x64" "$ver"
done

(cd "$OFFLINE_DIR" && ls -1 *.nupkg 2>/dev/null | sort > PACKAGE-LIST.txt)
count=$(find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' | wc -l | tr -d ' ')
size=$(du -sh "$OFFLINE_DIR" | awk '{print $1}')
echo "==> Done. $count Ubuntu platform packages in $OFFLINE_DIR ($size)"
echo
echo "These are the ONLY packages packaged here — all are from nuget.org, selected because"
echo "Ubuntu air-gapped restore needs them as OS/SDK-specific packs."
echo
echo "Transfer offline-packages/ to Ubuntu, then restore with a nuget.org mirror for libraries,"
echo "or use prepare-offline-packages.sh if you need a fully self-contained feed."
