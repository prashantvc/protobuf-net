# Offline packages (Ubuntu)

## Important fact

**Every package this repo needs is on nuget.org.** There is no MyGet/private feed in use.
What failed on Ubuntu was not “non-nuget.org” packages — it was **OS/SDK-specific packs**
that a macOS-prepared feed does not include:

| Package | Why Ubuntu needs it |
|---------|---------------------|
| `Microsoft.NETCore.App.Host.linux-x64` | App host for Linux (macOS restore only pulls `osx-*`) |
| `Microsoft.NETCore.App.Ref` (e.g. 8.0.28) | net8 targeting pack; version follows the SDK patch on the machine |
| `Microsoft.AspNetCore.App.Ref` | same for ASP.NET |
| `NETStandard.Library.Ref` | netstandard2.0/2.1 multi-targeting |
| `Microsoft.Build.Traversal` | MSBuild SDK for root `Build.csproj` |

## What to package (recommended for your case)

### A) Ubuntu platform packs only (small)

On a **networked** machine:

```bash
./scripts/prepare-ubuntu-packs.sh
tar -czf offline-packages-ubuntu.tar.gz offline-packages
```

Copy `offline-packages/` to Ubuntu. Use this **together with** either:

- a nuget.org mirror for all other libraries, or  
- library packages you already restored into a local cache

### B) Full Ubuntu air-gapped feed (larger, self-contained)

```bash
./scripts/prepare-offline-packages.sh
```

This restores the full graph for **linux-x64 only** (no Windows/macOS host packs) plus the packs above.

## On air-gapped Ubuntu

```bash
cd /path/to/protobuf-net
# replace offline-packages/ with the tarball contents
tar -xzf offline-packages-ubuntu.tar.gz

# If offline-packages is packs-only and you have a nuget.org mirror, enable it in NuGet.Config.
# If offline-packages is a COMPLETE feed, keep NuGet.Config offline-only (default).

dotnet restore Build.csproj
dotnet build Build.csproj -c Release
```

## Verify packs present

```bash
ls offline-packages/microsoft.netcore.app.host.linux-x64.*.nupkg
ls offline-packages/microsoft.netcore.app.ref.8.0.28.nupkg
ls offline-packages/netstandard.library.ref.2.1.0.nupkg
```
