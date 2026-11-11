# Module-specific CI containers

This is the technical reference for native-tool image declarations and their build/identity contract.
For the complete product/test onboarding path, YAML suite registration and integration suites, use
[Add a QuietCli companion](../README-add-companion.md).

Core's own Linux CI images (see [Linux CI images](ci/linux-images.md)) stay independent of every
Core-consumer module: Core's base image declaration never reads consumer locks or scripts. A module that needs
native CI tooling beyond Core's base image (for example, a compiled `git`) builds its own derived image,
layered over a verified parent starting with Core, through a small, generic, reusable contract. `Git` is the
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

- `Get-QuietModuleContainerfile -Platform -Objective -Stages` renders Containerfile text from a module's own ordered
  `Stages`, on top of Core's only shared boilerplate (`ARG CORE_IMAGE`), using the right `apt`/`apk`
  cache-mount and install syntax for `Fragment.Platform`. A module declares as many stages as it needs,
  each `FROM ${CORE_IMAGE}` or `FROM` an earlier stage's own `Name` — not a fixed `tools`/`ci` pair — so a
  module can install packages or copy build output into any stage it declares, including its own final
  stage (for example, runtime shared libraries a self-compiled binary links against).
- `Get-QuietCiModuleImagePlan -WorkspaceRoot -RuntimeIdentifier -Module -ContainerfileFragment -ModuleArguments -ModuleInputPaths [-ParentPlan]`
  uses the supplied preceding layer or resolves Core's own plan, renders the Containerfile, and composes the fingerprint
  from three parts:
  1. the hashes of the module's own `InputPaths` (locks, fetch script, the `ci/Get-CiImageArguments.ps1`
     contract script itself);
  2. `'CONTAINERFILE '` + the SHA-256 of the *rendered* Containerfile text — so a change to the declared
     fragment alone (no file touched) still invalidates the module's cache;
  3. `'CORE_FINGERPRINT '` + the parent's verified fingerprint. The label retains its existing name,
     but the parent can be the preceding overlay. A changed intermediate layer invalidates every
     descendant, as does a change to Core's base.
  The registry path carries the module suffix: `frenchexdev2/quietcli2-ci-{platform}-{architecture}-{module}`.
- `Invoke-QuietCiImageBuild` is the shared Podman build/pull/push/verify/receipt orchestration, reused by
  both Core's own `New-CiImage.ps1` and every module's build — not duplicated per module.

## `scripts/New-CiModuleImage.ps1`

The single, generic entrypoint for every module, parameterized by `-Module`:

1. Resolves the preceding `-ParentPlan`, or Core's plan when no parent is supplied.
2. Invokes the module's `ci/Get-CiImageArguments.ps1` by its fixed path, then resolves the fragment
   and fingerprint. A missing declaration fails with `CiModuleContractMissing: <path>`.
   `-PlanOnly` returns here, without native execution or registry access.
3. For preparation, uses `-ParentImage` when a parent plan is supplied; otherwise it prepares Core via
   `New-CiImage.ps1`. A supplied parent image is checked for ID, native architecture, input fingerprint
   and source label before use. Metadata reads are bounded.
4. Tags the prepared parent locally as
   `localhost/quietcli2-ci-core-<platform>-<arch>:<parent-fingerprint>`. The prefix is retained for
   compatibility; the identity belongs to the actual preceding layer. A bare image ID cannot be a
   Containerfile `FROM` target.
5. Injects the local parent tag into the plan as the
   `CORE_IMAGE` build ARG.
6. Builds the image with `Invoke-QuietCiImageBuild`, using the module's own
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

Image selection delegates to `New-CiSuiteImage.ps1` and `scripts/lib/CiCompanions.psm1`; the same final
plan is used for registry lookup and Docker fallback. Suite registration, generic entry triggers
and cross-product integration belong to [the onboarding guide's CI section](../README-add-companion.md#5-ci).
This reference does not define a second registration procedure or a per-module workflow.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
