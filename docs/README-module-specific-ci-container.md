# Module-specific CI containers

Core's own Linux CI images (see [Linux CI images](ci/linux-images.md)) stay independent of every
Core-consumer module: Core never reads a module's locks, scripts or Containerfiles. A module that needs
native CI tooling beyond Core's base image (for example, a compiled `git`) builds its own derived image,
layered on top of Core's already-verified one, through a small, generic, reusable contract. `Git` is the
first module to use it; the same shape is intended for any future Core-consumer module.

Core declares its own image the exact same way: `FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1`
is Core's own contract script, in the same shape as every module's, returning its own `Stages` (including
the explicit, visible decision to install a plain distro `git` -- needed only because Core's own
`Status.ControlledProbe.ps1` resolves `git` from PATH independent of the Git module). Core has no parent
image, so its stages name an explicit base (the pinned debian/alpine digest) instead of `${CORE_IMAGE}`.
There is no longer a checked-in `Dockerfile.ci.debian`/`Dockerfile.ci.alpine` text file: both are rendered
by the same `Get-QuietModuleContainerfile` generator a module's image goes through.

Core's own final stage also conditionally adds the native mutation/ASan/UBSan toolchain (`gcc`/`clang`/etc.)
only when `MUTATION_TESTING` is set in the environment that resolves the plan -- the ordinary CI matrix
never sets it, so that toolchain is excluded from the image by default.

## The contract a module provides

A Core-consumer module `FrenchExDev2.QuietCli.<Module>.PoSh` owns, under its own directory:

- `.github/containers/fetch-<module>-tools.sh` (or equivalent): the fetch/build script for whatever the
  module compiles or downloads, run inside the generated image's `tools` stage.
- `metadata/locks/*.json`: the module's own pinned versions and hashes (never Core's).
- `ci/Get-CiImageArguments.ps1`: a single PowerShell **script** (not a function file to dot-source) at
  this exact relative path, for every module. It is invoked directly:

  ```powershell
  & "FrenchExDev2.QuietCli.<Module>.PoSh/ci/Get-CiImageArguments.ps1" -WorkspaceRoot $root -Platform $platform
  ```

  `-Platform` is `'debian'` or `'alpine'`, already resolved from Core's own plan for the requested RID.
  The script validates the module's own locks, then returns one object:

  | Property | Shape | Meaning |
  |---|---|---|
  | `Arguments` | ordered hashtable | Podman build ARGs specific to the module (for example `GIT_URL`, `GIT_SHA256`). |
  | `InputPaths` | string array | The module's own files that participate in the module's cache fingerprint. Never a Core-owned path. |
  | `Containerfile` | object (a *fragment*, not a path) | `Platform`, `Objective`, `Stages` — an ordered list of stage declarations, described below. |

  Each entry in `Stages` is an object with:

  | Property | Shape | Meaning |
  |---|---|---|
  | `Name` | string | The stage's own name (required). |
  | `From` | string, optional | Another declared stage's own `Name`. Omitted (or unrecognized) means `FROM ${CORE_IMAGE}`. |
  | `Args` | string array, optional | `ARG` names declared in this stage, after any `Packages` install and before `FetchScript` runs. |
  | `Packages` | string, optional | Space-separated package list installed in this stage, in the target platform's own syntax, under a cache-mounted `RUN`. Any stage may declare its own — not only one fixed "tools" stage. |
  | `FetchScript` | string, optional | File name of a script copied from the build context into `/tmp` and run under a separate `ci-tools` cache mount. |
  | `Copy` | array of `{Stage;Spec}`, optional | Rendered as `COPY --from=<Stage> <Spec>`; `Spec` is a literal `"<source> <destination>"` pair. |
  | `PathPrefix` | string, optional | Directory prepended to `PATH` in this stage. |

A module never commits a static `Dockerfile.ci.*` text file. It declares the fragment; Core renders the
actual Containerfile text.

## What stays generic in Core

`scripts/CiImages.ps1` provides the reusable, module-agnostic side of the contract:

- `Get-QuietModuleContainerfile($Fragment)` renders Containerfile text from a module's own ordered
  `Stages`, on top of Core's only shared boilerplate (`ARG CORE_IMAGE`), using the right `apt`/`apk`
  cache-mount and install syntax for `Fragment.Platform`. A module declares as many stages as it needs,
  each `FROM ${CORE_IMAGE}` or `FROM` an earlier stage's own `Name` — not a fixed `tools`/`ci` pair — so a
  module can install packages or copy build output into any stage it declares, including its own final
  stage (for example, runtime shared libraries a self-compiled binary links against).
- `Get-QuietCiModuleImagePlan($WorkspaceRoot,$RuntimeIdentifier,$Module,$ContainerfileFragment,$ModuleArguments,$ModuleInputPaths)`
  resolves Core's own plan first, renders the Containerfile text, and composes the module's fingerprint
  from three parts:
  1. the hashes of the module's own `InputPaths` (locks, fetch script, the `ci/Get-CiImageArguments.ps1`
     contract script itself);
  2. `'CONTAINERFILE '` + the SHA-256 of the *rendered* Containerfile text — so a change to the declared
     fragment alone (no file touched) still invalidates the module's cache;
  3. `'CORE_FINGERPRINT '` + Core's own already-verified fingerprint — so a Core change also invalidates
     every module built on top of it.
  The registry path carries the module suffix: `frenchexdev2/quietcli2-ci-{platform}-{architecture}-{module}`.
- `Invoke-QuietCiImageBuild` is the shared Podman build/pull/push/verify/receipt orchestration, reused by
  both Core's own `New-CiImage.ps1` and every module's build — not duplicated per module.

## `scripts/New-CiModuleImage.ps1`

The single, generic entrypoint for every module, parameterized by `-Module`:

1. Resolves (or builds) Core's own image via `New-CiImage.ps1`.
2. Tags it locally as `localhost/quietcli2-ci-core-<platform>-<arch>:<core-fingerprint>` — a bare image ID
   cannot be a Containerfile `FROM` target, so this tag, keyed by Core's own verified fingerprint, is the
   stable reference whether Core's image just arrived by a GHCR pull or a fresh local build.
3. Resolves the module's `ci/Get-CiImageArguments.ps1` by the fixed path convention above and invokes it
   as a script. If it is missing, the build fails fast with `CiModuleContractMissing: <path>` rather than
   a confusing downstream error.
4. Builds the module's plan with `Get-QuietCiModuleImagePlan`, injects the local Core tag as the
   `CORE_IMAGE` build ARG.
5. With `-PlanOnly`, returns the plan without touching Podman further (useful to inspect the fingerprint
   and rendered Containerfile offline).
6. Otherwise, builds the module's image with `Invoke-QuietCiImageBuild`, using the module's own
   `.github/containers/` as the build context — never Core's.

```powershell
./scripts/New-CiModuleImage.ps1 -Module Git -RuntimeIdentifier linux-x64 -RegistryCache -PublishCache
```

## Why a script, not a dot-sourced function

Earlier revisions of this contract dot-sourced `ci/<Module>CiImages.ps1` and then called a function whose
name was built by string interpolation from `-Module` (`Get-Quiet${Module}CiImageArguments`). That tied a
module's declaration to guessing a function name from its module name. The contract now fixes the path
(`ci/Get-CiImageArguments.ps1`, identical for every module) and invokes it directly as a script — the path
itself identifies the module, so there is nothing to interpolate or guess, and a missing contract is
caught before any function lookup would have silently failed.

## Workflow wiring

`.github/workflows/ci.yml` adds one job per module, after the `linux-images` job that publishes Core's own
cache: for example, `linux-git-images` calls `New-CiModuleImage.ps1 -Module Git` and is gated the same way
Core's job is, plus the module's own suite selection (`suite ∈ {Git, All}`). The `linux` job that actually
runs the suites resolves the image through `New-CiImage.ps1` for `suite=Core`, or `New-CiModuleImage.ps1
-Module Git` otherwise. Core's own cache publication stays the exclusive responsibility of `linux-images`;
a module job never publishes Core's cache.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
