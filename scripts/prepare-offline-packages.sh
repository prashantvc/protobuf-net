#!/usr/bin/env bash
# Download all NuGet dependencies for protobuf-net into ./offline-packages
# Run this on a machine WITH network access, then copy offline-packages/ to the air-gapped host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OFFLINE_DIR="${OFFLINE_DIR:-$ROOT/offline-packages}"
TEMP_PACKAGES="${TEMP_PACKAGES:-$(mktemp -d -t pbn-packages.XXXXXX)}"
ONLINE_CONFIG="${TEMP_PACKAGES}/NuGet.Online.Config"

cleanup() { rm -rf "$TEMP_PACKAGES" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$OFFLINE_DIR" "$TEMP_PACKAGES"

cat > "$ONLINE_CONFIG" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="NuGet" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
XML

echo "==> Restoring Build.csproj into temporary packages folder..."
dotnet restore Build.csproj \
  --force \
  --packages "$TEMP_PACKAGES/packages" \
  --configfile "$ONLINE_CONFIG" \
  --verbosity minimal

echo "==> Collecting nupkg files into $OFFLINE_DIR ..."
find "$TEMP_PACKAGES/packages" -name '*.nupkg' -exec cp -n {} "$OFFLINE_DIR/" \;

# MSBuild SDK used by Build.csproj (Sdk="Microsoft.Build.Traversal/2.0.19") is resolved via NuGet
# but may not land in the project packages folder. Fetch it explicitly.
echo "==> Ensuring Microsoft.Build.Traversal SDK packages..."
for ver in 2.0.19 4.1.0; do
  dest="$OFFLINE_DIR/microsoft.build.traversal.${ver}.nupkg"
  if [[ ! -f "$dest" ]]; then
    url="https://api.nuget.org/v3-flatcontainer/microsoft.build.traversal/${ver}/microsoft.build.traversal.${ver}.nupkg"
    echo "    downloading microsoft.build.traversal ${ver}"
    curl -fsSL "$url" -o "$dest" || \
      wget -q "$url" -O "$dest" || \
      echo "WARN: could not download microsoft.build.traversal ${ver}"
  fi
done

# Also pull from local global cache if present
if [[ -d "${NUGET_PACKAGES:-$HOME/.nuget/packages}/microsoft.build.traversal" ]]; then
  find "${NUGET_PACKAGES:-$HOME/.nuget/packages}/microsoft.build.traversal" -name '*.nupkg' -exec cp -n {} "$OFFLINE_DIR/" \;
fi

count=$(find "$OFFLINE_DIR" -maxdepth 1 -name '*.nupkg' | wc -l | tr -d ' ')
size=$(du -sh "$OFFLINE_DIR" | awk '{print $1}')
echo "==> Done. $count packages in $OFFLINE_DIR ($size)"
echo "    Copy the offline-packages/ directory (and this repo) to the air-gapped machine."
echo "    Then run: dotnet restore Build.csproj"
