# Offline NuGet package feed

This directory is a **flat local NuGet feed** of packages required to restore and build
`Build.csproj` without access to nuget.org.

## Populate (machine with network)

```bash
./scripts/prepare-offline-packages.sh
# optional archive for transfer:
tar -czf offline-packages.tar.gz offline-packages
```

Copy `offline-packages/` (or the tarball) **and** this repo to the air-gapped host.

> **Important:** Always re-run the prepare script after SDK updates. Framework packs
> (`Microsoft.NETCore.App.Ref`, `Microsoft.NETCore.App.Host.linux-x64`, etc.) are versioned
> to the **consumer** machine’s SDK/runtime patch (e.g. Ubuntu may need `8.0.28` even if
> the prepare machine only needed `8.0.27`). The prepare script downloads a band of
> net8/net10 pack versions and host packs for `linux-x64`, `linux-arm64`, Windows, and macOS.

## Restore / build (air-gapped)

Root `NuGet.Config` uses **only** this folder:

```bash
# if you transferred the tarball:
tar -xzf offline-packages.tar.gz

dotnet restore Build.csproj
dotnet build Build.csproj -c Release
dotnet test Build.csproj -c Release
```

Verify restore without relying on a warm global cache:

```bash
./scripts/verify-offline-restore.sh
```

## Ubuntu / Linux notes

If you see errors like:

| Error | Cause | Fix |
|-------|--------|-----|
| `Unable to find package Microsoft.NETCore.App.Host.linux-x64` | Feed prepared only on macOS/Windows | Re-run `prepare-offline-packages.sh` (downloads linux host packs) and recopy feed |
| `Microsoft.NETCore.App.Ref with version (= 8.0.28)` but only `8.0.27` found | SDK patch mismatch between machines | Same: updated prepare script pulls multiple 8.0.x patches |
| `Unable to find package NETStandard.Library.Ref` | netstandard TFMs need this targeting pack as a NuGet package when not installed with the SDK | Included by prepare script |
| `protogen.site` package errors on Linux only | Case-sensitive path exclude (`protogen.Site` vs `protogen.site`) | Fixed in `Build.csproj`; pull latest repo |

Also install a **.NET SDK 10.x** offline on the air-gapped host (`global.json`). The Ubuntu
`dotnet` packages under `/usr/lib/dotnet` may not ship full multi-targeting packs; the
offline feed is intended to supply those via NuGet.

## What is **not** a NuGet package

| Dependency | Offline handling |
|---|---|
| **.NET SDK 10.x** | Install offline SDK installer / mirror |
| **Git history** | Full clone (for `Nerdbank.GitVersioning`) |
| **GitHub (SourceLink)** | Optional; only affects packed package metadata |

## Size

Expect roughly **400–800+ MB** of `.nupkg` files once multi-RID host packs are included.
