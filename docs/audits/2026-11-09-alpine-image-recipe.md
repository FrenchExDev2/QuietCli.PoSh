# Alpine image recipe correction and execution — 9 November 2026

Follow-up to the [runtime diagnosis](2026-11-09-container-runtime-diagnosis.md).
The recipe is now corrected in source, rebuilt locally and checked through actual host/native/SDK execution.
[Curated JSON evidence](2026-11-09-alpine-image-recipe.json) preserves the results and input identities.

## Source changes

`FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1` now:

- Installs `powershell=$POWERSHELL_PACKAGE` in Alpine's final stage, using the locked version argument.
- Selects `/usr/lib/dotnet` for the distribution's framework-dependent stable PowerShell host.
- Keeps `/usr/share/dotnet` first on `PATH` for the separately pinned SDK and its own CLR.
- Rejects a terminal newline in the package version using exact-string regex anchors.

Debian's runtime-root policy is unchanged. The existing image fingerprint includes the module declaration,
so the corrected recipe produces a different image identity instead of depending on an old cached tag.

## Real build and smoke

Run: `%TEMP%/QuietCli2/874a99c9b658/alpine-image/968059536e6141a78d0f897bcb309301`.
The dedicated build/smoke window and nested runtime monitor stayed visible and closed after saving terminal reports.

**9 passed, 0 failed**, native Linux `amd64` Podman backend:

- The image was built from the declared recipe, with no registry-cache shortcut or publication.
- Its unchanged default starts PowerShell **7.6.9** on **.NET 10.0.14** from
  `/usr/lib/dotnet/shared/Microsoft.NETCore.App/10.0.14/`.
- The installed PowerShell version matches locked package `7.6.9-r0`.
- The expected musl SQLite library passes its staged hash check, loads, and returns **3.53.3**.
- The diagnosis reports **BootstrapConfigurationProblem = false**.
- Under the same image defaults, `dotnet --version` succeeds and returns **11.0.100-rc.3.26522.148**,
  matching `global.json`. Correcting stable PowerShell's root did not hide the pinned SDK.
- Runtime diagnostic removal is confirmed and the SDK probe container is independently confirmed absent.

Image ID: `14226520251bfa04fc2a45b36b758474eff0e2b08d1d2b96bbcd33cfa9eb2f49`.
Input fingerprint: `e4c8171c44d8e6b99b05d51e0c9eeb3ec0512ab3706ca360aef296f54bdf5c4e`.
Builder receipt and complete build log:
`artifacts/ci-images/linux-musl-x64-313e72cf20ee49b9bf384193e191ec06/`.
The local `ghcr.io/...` tag is a local name; `Published = false`.

The explicit `/usr/lib/dotnet` control also succeeds. Explicitly changing the stable host back to
`/usr/share/dotnet` fails, as expected for a root containing only CLR 11. This negative control is not
a failure of the corrected unchanged default.

An initial smoke-harness preflight used Podman's nonexistent Go-template field `.Host.Os`. Its failure
is retained in `alpine-image/e55cd82553394dada24a353ee5ded84d`. The harness now uses `.Host.OS`, saves
the backend observation, and passed on the same backend. That initial failure was infrastructure syntax,
not an image architecture failure.

## Recipe properties, malformed inputs and mutations

`tests/20261109-093326-cf7d1b` under the shared temporary report root finished **1 passed, 0 failed**
for `*Alpine image recipe*`. It is a filtered development run, **Partial = true**, with 65 cases skipped.

Its independent recipe contracts cover all four Linux target declarations, **200 generated plans**
(100 locked package versions across x64/ARM64 Alpine declarations), **9 malformed inputs**, and
**5/5 killed mutants**. Seed: `20261109`. Tests check final-stage installation rather than merely
the existence of an argument or entry point, exact lock propagation, host/SDK separation and rendered ordering.
The package's terminal-newline rejection has a deterministic regression and a corresponding killed mutant.

Recipe SHA-256: `AA51D47D1D89E9D1983690640F0A914E3911A5502818EABA974162D5C7B13CEE`.
No engine C# or native C behavior was changed, so their previously recorded campaigns were not rerun
for this recipe-only correction. The native image smoke exercises the actual changed package/environment path.

Reproduce from the monorepo root with a native matching Podman backend:

```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -Case '*Alpine image recipe*' -SkipBuild
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-AlpineImageSmoke.ps1 -RuntimeIdentifier linux-musl-x64
```

## Remaining boundary

The raw RID remains **`alpine.3.24-x64`**. The new diagnostic decision is **`AssetSelection`**, rather
than `BootstrapAndAssetSelection`: raw-RID resource directories are absent while portable musl assets load.
No RID was spoofed, no CI identity guard was relaxed and module resource resolution was not changed.
The image bootstrap correction is verified; full module/platform qualification remains separate work.

ARM64 was checked as a generated declaration, not executed natively. No remote workflow, full release
matrix, commit, push or image/module publication was performed. The prepared local image and build
caches remain available; only owned probe containers were removed. The documentation and lock refresh
followed the executed code checks and do not represent a second image build.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
