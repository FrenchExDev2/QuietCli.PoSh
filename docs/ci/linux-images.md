# Linux CI images

No local ARM machine is required. GitHub runs x64 on `ubuntu-latest` and ARM64 on `ubuntu-24.04-arm`. Each runner builds and runs containers of the same architecture, without QEMU. The two multi-stage recipes are `.github/containers/Dockerfile.ci.debian` and `Dockerfile.ci.alpine`.

## First run and GHCR cache

1. `New-CiImage.ps1` computes a SHA-256 fingerprint of the recipes, their shared script, the image scripts, `global.json` and the SDK/Git lock files.
2. It looks for this fingerprint in `ghcr.io/frenchexdev2/quietcli2-ci-{debian|alpine}-{x64|arm64}`.
3. If it exists and is accessible, it resolves the tag to a digest, pulls that digest, then verifies the architecture, source and fingerprint declared in the labels.
4. Otherwise, it builds a new image natively. On a push or manual dispatch in the upstream repository on `main`, it publishes the image to GHCR with the fingerprint as its tag. An input change produces a new tag; old images are neither intentionally overwritten nor automatically deleted.
5. The suites run in a private container without network access, using the verified local image ID. Reports retain the actual ID, registry digest and host/guest/engine identities.

A change confined to a handler does not rebuild the image. A pull request reuses an accessible cache or builds locally; it does not publish to the trusted `main` cache. Registry network/server errors remain errors, without automatic retries. A missing or inaccessible cache can be rebuilt.

## Tools and stages

The `tools` stage downloads the exact .NET SDK and verifies its SHA-512 hash. It compiles Git 2.56.0 from the SHA-256-pinned archive. Compilers and Git sources are not copied into the final stage. The SDK remains in the final image because the suites verify the tools and test assemblies.

Debian uses the official PowerShell 7.6.7 x64/ARM64 archives, verified with SHA-256. Alpine uses its signed `powershell=7.6.9-r0` package, available for x86_64 and aarch64, with its .NET 10 dependency. The pinned .NET 11 SDK/runtime is installed alongside it for the isolated engine. A recipe never silently replaces ARM64 PowerShell with an x64 executable.

The Debian/Alpine base images are pinned by multi-architecture index digest in the recipes and `build/ci-images.lock.json`. Transitive apt/apk dependencies are resolved from their signed repositories during a build: the result is not presented as a bit-for-bit reproducible build. A withdrawn package version causes the build to fail and requires a reviewed lock-file update.

This fast test environment uses Git without Rust or the Tcl/Tk interface. It does not replace exhaustive qualification of Git helpers, variants and versions; the older `Containerfile.debian` remains dedicated to that separate preparation.

## Permissions and privacy

The image job uses only its ephemeral `GITHUB_TOKEN`, with `contents: read` and `packages: write`. It is absent from pull request runs. Linux test jobs have only `packages: read` and wait for the image jobs on `main`. Concurrency control per RID prevents simultaneous publications from the Core and Git workflows. Podman login receives the token through stdin and stores authentication in a private temporary file deleted on exit. No token enters build arguments, the Docker context, layers or reports. The PSGallery key is independent.

GHCR initially creates private packages and links them to the repository through the workflow token and the OCI label `org.opencontainers.image.source`. Repository jobs can reuse this cache. To allow anonymous pulls, make these four packages public in the GitHub Packages settings. A fork PR that cannot read a private cache builds its image; it remains testable without registry write access.

Receipts are stored in `artifacts/ci-images/*/image.json`. The old `QUIETCLI_*_IMAGE` variables are no longer required. PSGallery publication remains manual and waits for all six Windows/Linux jobs to succeed; publishing a test image does not publish any module.

References: [GitHub ARM64 runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [GHCR authentication and visibility](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [Alpine ARM64 package](https://pkgs.alpinelinux.org/package/v3.24/community/aarch64/powershell).

## Native PTY compiler

The final Debian image includes gcc and libc6-dev; the final Alpine image includes gcc and musl-dev. The pty-mutation matrix compiles and runs its baseline and all 23 targeted mutants inside these same native x64/ARM64 images without guest network access. Invoke-ContainerCi.ps1 -Suite Mutation retains reports and rejects a mismatched runtime identifier. Dockerfile changes alter the content fingerprint, so old images without the compiler are not accepted as the new image plan.

Native qualification also requires all 35 baseline assertions (including process properties) and 20,000 coverage-guided decoder executions under ASan/UBSan. CI images contain GCC, G++, Clang and compiler-rt (Debian: libclang-rt-dev; Alpine: compiler-rt). The ordinary CI process runner has no product-engine dependency. A successful native matrix is required before the .NET matrix starts and before any Gallery publication can be authorized.

Native mutation containers have a 1 GiB cgroup memory limit. On musl the fuzzer requires that external limit before disabling its defective internal RSS-monitor thread; ASan, UBSan and LeakSanitizer remain enabled. The delivery guard requires at least 20,000 executed fuzz inputs, all process properties and all 23 targeted mutants. Runtime-leak reproducers are retained for the separate future libFuzzer patch.
