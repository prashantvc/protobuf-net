#!/usr/bin/env bash
# Build a COMPLETE offline NuGet feed for restoring/building on Ubuntu (linux-x64).
# Includes the full dependency graph + Ubuntu platform packs only (no win/osx hosts).
#
# Prefer scripts/prepare-ubuntu-packs.sh if you already have nuget.org (or a mirror)
# for ordinary library packages and only need the Linux platform delta.
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
  local id="$1" version="$2"
  local id_lower
  id_lower="$(echo "$id" | tr '[:upper:]' '[:lower:]')"
  local dest="$OFFLINE_DIR/${id_lower}.${version}.nupkg"
  [[ -f "$dest" ]] && return 0
  local url="https://api.nuget.org/v3-flatcontainer/${id_lower}/${version}/${id_lower}.${version}.nupkg"
  echo "    + ${id} ${version}"
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

echo "==> Restoring Build.csproj for linux-x64 into temporary packages folder..."
dotnet restore Build.csproj \
  --force \
  -r linux-x64 \
  --packages "$TEMP_PACKAGES/packages" \
  --configfile "$ONLINE_CONFIG" \
  --verbosity minimal

# Also restore without RID for non-RID assets
dotnet restore Build.csproj \
  --force \
  --packages "$TEMP_PACKAGES/packages" \
  --configfile "$ONLINE_CONFIG" \
  --verbosity minimal

echo "==> Collecting nupkg files into $OFFLINE_DIR ..."
find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' -delete 2>/dev/null || true
find "$TEMP_PACKAGES/packages" -name '*.nupkg' -exec cp {} "$OFFLINE_DIR/" \;

# Drop host packs for other OSes — keep only linux-x64 (Ubuntu)
echo "==> Removing non-linux host packs to keep feed Ubuntu-focused..."
find "$OFFLINE_DIR" -maxdepth 1 -name 'microsoft.netcore.app.host.*.nupkg' ! -name 'microsoft.netcore.app.host.linux-x64.*.nupkg' -delete

echo "==> Ensuring Ubuntu platform / targeting packs..."
download_nupkg "Microsoft.Build.Traversal" "2.0.19"
download_nupkg "Microsoft.Build.Traversal" "4.1.0"
download_nupkg "NETStandard.Library.Ref" "2.1.0"

for ver in 8.0.24 8.0.25 8.0.26 8.0.27 8.0.28 10.0.5 10.0.6 10.0.7 10.0.8 10.0.9; do
  download_nupkg "Microsoft.NETCore.App.Ref" "$ver"
  download_nupkg "Microsoft.AspNetCore.App.Ref" "$ver"
  download_nupkg "Microsoft.NETCore.App.Host.linux-x64" "$ver"
done

(cd "$OFFLINE_DIR" && ls -1 *.nupkg 2>/dev/null | sort > PACKAGE-LIST.txt)
count=$(find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' | wc -l | tr -d ' ')
size=$(du -sh "$OFFLINE_DIR" | awk '{print $1}')
echo "==> Done. $count packages in $OFFLINE_DIR ($size) [Ubuntu linux-x64 complete feed]"
