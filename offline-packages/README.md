# Offline NuGet package feed

This directory is a **flat local NuGet feed** of every package required to restore and build
`Build.csproj` without access to nuget.org (or any other network feed).

## Populate (machine with network)

From the repository root:

```bash
./scripts/prepare-offline-packages.sh
```

Then copy the entire `offline-packages/` folder to the air-gapped host alongside the repo.

## Restore / build (air-gapped)

`NuGet.Config` at the repo root is configured to use **only** this folder:

```bash
dotnet restore Build.csproj
dotnet build Build.csproj -c Release
dotnet test Build.csproj -c Release
```

Verify offline restore (clears reliance on the machine global cache):

```bash
./scripts/verify-offline-restore.sh
```

## What is included

- All direct and transitive NuGet packages referenced by the solution (`Directory.Packages.props` + restore graph)
- `Microsoft.Build.Traversal` (MSBuild SDK used by root `Build.csproj`)

## What is **not** a NuGet package (must be installed separately offline)

| Dependency | Why | How to provide offline |
|---|---|---|
| **.NET SDK 10.x** (see `global.json`) | Compiler / MSBuild host | Install offline SDK installer / copy `/usr/share/dotnet` or Windows installers |
| **.NET 8.x targeting packs** (optional for multi-TFM) | Some projects still multi-target older TFMs | Install matching SDK / targeting packs offline |
| **Git repository history** | `Nerdbank.GitVersioning` stamps versions from git | Clone with history (`fetch-depth: 0` in CI) |
| **GitHub network** | `Microsoft.SourceLink.GitHub` embeds source links when packing Release | Not required for build/test; only affects SourceLink metadata on packed packages |

## Historical / inactive sources

The original `NuGet.Config` had **MyGet** feeds commented out (`protobuf-net`, `dotnet-coreclr`). They are **not** used by the current restore graph — everything resolves from nuget.org when online.

## BuildTools smoke tests

`src/BuildToolsSmokeTests/nuget.config` points at a **project-local** package output folder for a just-built `protobuf-net.BuildTools` package. That path is not nuget.org; it is produced by building this repo first. Smoke tests are excluded from `Build.csproj` packing/default traversal restore of that project path.

## Size

Expect on the order of **~350 packages / ~350–400 MB** of `.nupkg` files (flat feed). Expanded global packages folders are much larger (~2 GB).
