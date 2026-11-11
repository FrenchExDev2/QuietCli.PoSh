# Linux CI images

No local ARM machine is required for the GitHub matrix. GitHub runs x64 on `ubuntu-latest` and ARM64 on `ubuntu-24.04-arm`. Each runner builds and runs containers of the same architecture, without QEMU. Core declares its multi-stage recipe in `FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1`; the shared renderer writes the generated Containerfile into each build's receipt directory. A Windows PowerShell client can also invoke a local build through its Linux Podman backend.

## First run and GHCR cache

1. `New-CiImage.ps1` computes a SHA-256 fingerprint of the recipes, their shared script, the image scripts, `global.json` and the SDK/Git lock files.
2. It looks for this fingerprint in `ghcr.io/frenchexdev2/quietcli2-ci-{debian|alpine}-{x64|arm64}`.
3. If it exists and is accessible, it resolves the tag to a digest, pulls that digest, then verifies the architecture, source and fingerprint declared in the labels.
4. Otherwise, it builds a new image natively. On a push or manual dispatch in the upstream repository on `main`, it publishes the image to GHCR with the fingerprint as its tag. An input change produces a new tag; old images are neither intentionally overwritten nor automatically deleted.
5. The suites run in a private container without network access, using the verified local image ID. Reports retain the actual ID, registry digest and host/guest/engine identities.

A change confined to a handler does not rebuild the image. A pull request reuses an accessible cache or builds locally; it does not publish to the trusted `main` cache. Registry network/server errors remain errors, without automatic retries. A missing or inaccessible cache can be rebuilt.

## Tools and stages

The `tools` stage downloads the exact .NET SDK and verifies its SHA-512 hash. The SDK remains in the final image because the suites verify the tools and test assemblies. Core's final stage explicitly installs the distribution Git package for its Core-only fixtures; companion modules declare their own additional requirements independently.

Debian uses the official PowerShell x64/ARM64 archives, verified with the lock's SHA-256. Alpine explicitly installs its signed `powershell=$POWERSHELL_PACKAGE` package using the locked version. A Microsoft .NET 10.0.14 musl runtime archive is verified with the lock's SHA-512 and copied to `/opt/pwsh-runtime`; `DOTNET_ROOT` selects this separate root for stable PowerShell. Unlike the distro runtime's `alpine.3.24-*` build RID, the Microsoft build reports the required portable `linux-musl-*` RID. `/usr/share/dotnet` remains first on `PATH` for the separately pinned .NET 11 SDK/runtime. Architecture and libc checks remain strict.

See [container runtime diagnosis](../README-container-runtime-diagnosis.md) for building an image from these inputs without a pre-existing cache. `FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-AlpineImageSmoke.ps1` builds the Alpine image and checks unchanged-default PowerShell startup, the pinned package/runtime, native SQLite and SDK execution with visible monitoring. Image bootstrap and module RID/resource selection remain separate conclusions.

The Debian/Alpine base images are pinned by multi-architecture index digest in the recipes and `build/ci-images.lock.json`. Transitive apt/apk dependencies are resolved from their signed repositories during a build: the result is not presented as a bit-for-bit reproducible build. A withdrawn package version causes the build to fail and requires a reviewed lock-file update.

This fast test environment uses Git without Rust or the Tcl/Tk interface. It does not replace exhaustive qualification of Git helpers, variants and versions.

## Permissions and privacy

The image job uses only its ephemeral `GITHUB_TOKEN`, with `contents: read` and `packages: write`. It is absent from pull request runs. Linux test jobs have only `packages: read` and wait for the image jobs on `main`. Concurrency control per RID prevents simultaneous publications from the Core and Git workflows. Podman login receives the token through stdin and stores authentication in a private temporary file deleted on exit. No token enters build arguments, the Docker context, layers or reports. The PSGallery key is independent.

GHCR initially creates private packages and links them to the repository through the workflow token and the OCI label `org.opencontainers.image.source`. Repository jobs can reuse this cache. To allow anonymous pulls, make these four packages public in the GitHub Packages settings. A fork PR that cannot read a private cache builds its image; it remains testable without registry write access.

Receipts are stored in `artifacts/ci-images/*/image.json`. The old `QUIETCLI_*_IMAGE` variables are no longer required. PSGallery publication remains manual and waits for all six Windows/Linux jobs to succeed; publishing a test image does not publish any module.

References: [GitHub ARM64 runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [GHCR authentication and visibility](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [Alpine ARM64 package](https://pkgs.alpinelinux.org/package/v3.24/community/aarch64/powershell).

## Native PTY compiler

Native campaign tools are opt-in when resolving the image plan through `MUTATION_TESTING`. That variant includes the GCC/Clang development packages declared for its distribution; the ordinary runtime/diagnostic image does not require them. The standalone local PTY campaign can then compile and run its baseline and targeted mutants without guest network access. GitHub workflows exclude this campaign and pass `-SkipTty` to ordinary test workers. Invoke-ContainerCi.ps1 -Suite Mutation retains reports and rejects a mismatched runtime identifier. The rendered package changes alter the content fingerprint, so a runtime-only image is not accepted as the compiler-enabled plan.

Native qualification also requires all 43 baseline assertions (including process properties) and 20,000 coverage-guided decoder executions under ASan/UBSan. Compiler-enabled images contain GCC, G++, Clang and compiler-rt (Debian: libclang-rt-dev; Alpine: compiler-rt). The ordinary CI process runner has no product-engine dependency. The native campaign remains a separate local qualification scope; it no longer precedes or blocks the GitHub .NET matrix or Gallery workflow. CI receipts explicitly exclude TTY qualification.

Native mutation containers have a 1 GiB cgroup memory limit. On musl the fuzzer requires that external limit before disabling its defective internal RSS-monitor thread; ASan, UBSan and LeakSanitizer remain enabled. The delivery guard requires at least 20,000 executed fuzz inputs, all process properties and all 31 targeted mutants. Runtime-leak reproducers are retained for the separate future libFuzzer patch.


## Alpine Gallery packaging dependency

Alpine keeps its native PowerShell executable and musl runtime. Its image additionally copies only Microsoft.PowerShell.PSResourceGet from the same-architecture Microsoft archive already pinned by the Debian lock entry. The tools stage verifies that archive SHA-256; no glibc PowerShell executable is copied to the final Alpine image. The build requires Compress-PSResource to resolve. The Alpine smoke probe creates a real nupkg with network disabled. This preparation changes the image fingerprint and leaves guest test execution offline. It neither publishes a package nor bypasses Gallery tests. Missing or malformed donor locks fail explicitly.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
