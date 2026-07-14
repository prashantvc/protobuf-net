#!/usr/bin/env bash
# Download all NuGet dependencies for protobuf-net into ./offline-packages
# Run this on a machine WITH network access, then copy offline-packages/ to the air-gapped host.
#
# Important: restore graphs pull *host* packs for the CURRENT machine RID (e.g. osx-arm64).
# Air-gapped Linux needs Microsoft.NETCore.App.Host.linux-x64 and matching *.App.Ref packs,
# so this script also downloads those explicitly for common RIDs and patch versions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OFFLINE_DIR="${OFFLINE_DIR:-$ROOT/offline-packages}"
TEMP_PACKAGES="${TEMP_PACKAGES:-$(mktemp -d "${TMPDIR:-/tmp}/pbn-packages.XXXXXX")}"
ONLINE_CONFIG="${TEMP_PACKAGES}/NuGet.Online.Config"

cleanup() { rm -rf "$TEMP_PACKAGES" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$OFFLINE_DIR" "$TEMP_PACKAGES"

download_nupkg() {
  # download_nupkg <packageId> <version>
  local id_lower version url dest
  id_lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  version="$2"
  dest="$OFFLINE_DIR/${id_lower}.${version}.nupkg"
  if [[ -f "$dest" ]]; then
    return 0
  fi
  url="https://api.nuget.org/v3-flatcontainer/${id_lower}/${version}/${id_lower}.${version}.nupkg"
  echo "    + ${1} ${version}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

cat > "$ONLINE_CONFIG" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="NuGet" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
XML

echo "==> Restoring Build.csproj (current RID) into temporary packages folder..."
dotnet restore Build.csproj \
  --force \
  --packages "$TEMP_PACKAGES/packages" \
  --configfile "$ONLINE_CONFIG" \
  --verbosity minimal

# Pull host packs for air-gapped Linux/Windows targets (restore alone only gets the prepare-machine RID).
RIDS=(linux-x64 linux-arm64 osx-x64 osx-arm64 win-x64 win-arm64)
echo "==> Restoring with additional RuntimeIdentifiers for host packs..."
for rid in "${RIDS[@]}"; do
  echo "    RID=$rid"
  # Not all projects produce RID-specific assets; continue on failure.
  dotnet restore Build.csproj \
    --force \
    -r "$rid" \
    --packages "$TEMP_PACKAGES/packages" \
    --configfile "$ONLINE_CONFIG" \
    --verbosity minimal || true
done

echo "==> Collecting nupkg files into $OFFLINE_DIR ..."
find "$TEMP_PACKAGES/packages" -name '*.nupkg' -exec cp -n {} "$OFFLINE_DIR/" \;

# MSBuild SDK used by Build.csproj
echo "==> Ensuring Microsoft.Build.Traversal SDK packages..."
for ver in 2.0.19 4.1.0; do
  download_nupkg "Microsoft.Build.Traversal" "$ver" || true
done

# Framework / targeting packs: version is tied to the *consumer* SDK patch, not the prepare machine.
# Download a band of stable 8.0.x packs + NETStandard so Ubuntu/other SDKs can resolve.
echo "==> Downloading NETStandard and net8/net10 targeting + host packs for offline Linux/Windows..."
download_nupkg "NETStandard.Library.Ref" "2.1.0" || true

# Recent net8 patch train (includes 8.0.27 and 8.0.28 seen in the wild)
NET8_PATCHES=(8.0.19 8.0.20 8.0.21 8.0.22 8.0.23 8.0.24 8.0.25 8.0.26 8.0.27 8.0.28)
# net10 patches commonly requested by SDK 10.0.x
NET10_PATCHES=(10.0.0 10.0.1 10.0.2 10.0.3 10.0.4 10.0.5 10.0.6 10.0.7 10.0.8 10.0.9)

for ver in "${NET8_PATCHES[@]}" "${NET10_PATCHES[@]}"; do
  download_nupkg "Microsoft.NETCore.App.Ref" "$ver" || true
  download_nupkg "Microsoft.AspNetCore.App.Ref" "$ver" || true
  for rid in linux-x64 linux-arm64 osx-x64 osx-arm64 win-x64 win-arm64; do
    download_nupkg "Microsoft.NETCore.App.Host.${rid}" "$ver" || true
  done
done

# Also copy any packs already in the global cache
if [[ -d "${NUGET_PACKAGES:-$HOME/.nuget/packages}" ]]; then
  find "${NUGET_PACKAGES:-$HOME/.nuget/packages}" -name '*.nupkg' \( \
      -path '*/microsoft.netcore.app.ref/*' -o \
      -path '*/microsoft.aspnetcore.app.ref/*' -o \
      -path '*/microsoft.netcore.app.host.*/*' -o \
      -path '*/netstandard.library.ref/*' -o \
      -path '*/microsoft.build.traversal/*' \
    \) -exec cp -n {} "$OFFLINE_DIR/" \; 2>/dev/null || true
fi

# Inventory
(cd "$OFFLINE_DIR" && ls -1 *.nupkg 2>/dev/null | sort > PACKAGE-LIST.txt || true)
count=$(find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' | wc -l | tr -d ' ')
size=$(du -sh "$OFFLINE_DIR" | awk '{print $1}')
echo "==> Done. $count packages in $OFFLINE_DIR ($size)"
echo "    Copy offline-packages/ (or offline-packages.tar.gz) to the air-gapped machine."
echo "    Then:  dotnet restore Build.csproj && dotnet build Build.csproj -c Release"
