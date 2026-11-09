# Container runtime diagnosis — 9 November 2026

Follow-up to the unresolved Alpine scope in the [provider/UI audit](2026-11-09-provider-ui-qualification.md).
The requested reusable scripts determine whether an image startup configuration or raw-RID resource
selection accounts for the observations. They do not change the image or fix qualification guards.

See the [usage guide](../README-container-runtime-diagnosis.md) and [curated JSON evidence](2026-11-09-container-runtime-diagnosis.json).

## Delivered scripts

- `scripts/Invoke-ContainerRuntimeDiagnosis.ps1`: visible monitored launcher and engine-independent
  Podman worker. Resolves the local image to an immutable ID, stages explicit inputs, runs default/root
  controls in one private networkless container and retains diagnostics before removing that container.
- `scripts/Probe-ContainerRuntime.ps1`: guest identity, ELF machine, mapped libc and verified SQLite load.
  It saves each phase before loading native code and never imports the product or creates a database.
- `scripts/lib/RuntimeDiagnosis.psm1`: reusable offline policy. Partial/malformed observations remain
  inconclusive; actual RID values are preserved, architecture guards are not weakened and no diagnostic
  result qualifies the entire product.

## Real observations

Alpine image ID: `43c31918a5a487938145c1c81ac45cfbcc171aa8f82f458d4d78d1dbdc4a435c`.
Final run: `%TEMP%/QuietCli2/874a99c9b658/runtime-diagnosis/12e098052d1f4a9193735bca0307d7c6`.

1. The unchanged default host fails before executing the guest script: the selected .NET root only
   contains .NET 11, while the framework-dependent PowerShell needs .NET 10.
2. Explicit `/usr/lib/dotnet` starts PowerShell 7.6.9 on .NET 10.0.14. Its runtime directory is
   `/usr/lib/dotnet/shared/Microsoft.NETCore.App/10.0.14/`.
3. Independent observations agree on x64: image `amd64`, process/OS `x64`, ELF machine 62. The process
   maps `/lib/ld-musl-x86_64.so.1`; OS release is Alpine 3.24.3. The raw CLR RID remains `alpine.3.24-x64`.
4. The staged module has no native SQLite directory named `alpine.3.24-x64`. The resource under
   `linux-musl-x64` passes its staged SHA-256 check, loads, and returns SQLite version `3.53.3`.
   Asset SHA-256: `647B7B5886526691AED58E0FCBB56DC1E6DEA8B1F9F5390782F0C95269250DB1`.
5. Explicit `/usr/share/dotnet` repeats the startup failure. No root or resource is installed or changed.

Conclusion: `BootstrapAndAssetSelection`. The image's default PowerShell runtime-root configuration
needs correction or an explicit launcher selection. Separately, native-resource paths and CI comparisons
currently use the raw RID; adopting a verified portable-target selection requires implementation and tests.
Recreating a container from unchanged inputs does not address these identified faults. Rebuilding an
unchanged recipe also leaves the defaults unchanged. A successful SQLite call does not prove all other
native dependencies or the full engine work with that mapping.

Debian control image ID: `deae35efba53bf08342132303a0624c14529b84c3710dada5a619cc185aa48cb`.
Final run: `%TEMP%/QuietCli2/874a99c9b658/runtime-diagnosis/f414aea4b37f428b98d82963b26b689e`.
All three controls complete with raw RID `linux-x64`; required SQLite loads return `3.53.3`.
Decision: `NoMismatchObserved`, within this diagnostic's scope only.

Both diagnostic workers finish `Success` and record `RemovedOwnedContainer`. Failed startup controls
remain explicitly failed inside the completed diagnostic; they are not counted as passing tests.
Source/asset hashes, runtime identities and relevant production source bindings are retained in JSON.

## Independent policy validation

`tests/20261109-085749-f9b588` under the same temporary report root finished **1 passed, 0 failed**.
This was the explicit filtered Core case `*container runtime diagnosis*`: **Partial = true**, 64 cases
skipped. It does not replace an unfiltered Core or release run.

The case contains **15 independent examples**, **200 generated RID/architecture cases**, **3,500 malformed
report inputs**, and **7/7 killed PowerShell policy mutants**. Seed: `20261109`.
Regressions include incomplete phases, unknown libc, wrong ELF machine, emulation-shaped OS/process
disagreement, missing raw assets, invalid hash evidence, and single-element arrays masquerading as scalars.
The policy module hash in each final diagnostic input snapshot matches the tested policy hash.

Mutants cover hidden bootstrap faults, ignored ELF/libc/hash checks, hidden asset-selection faults,
accepting incomplete probes and promoting a diagnostic to whole-product qualification. No new engine
C# or native C behavior was changed. The guest's C# declaration is solely an interop delegate; actual
native calls were exercised in both images. No new engine/native mutation campaign is claimed.

An initial Podman formatting error (`json .Id` inside a composite format) is retained under
`runtime-diagnosis/d68d0735c0134c6c824e2bc9965f7bad`. The launcher now reads only three separate allowlisted
fields and binds subsequent inspections and execution to the captured immutable ID. That first run is
infrastructure failure, not runtime incompatibility evidence.

## Boundaries

No image pull/build/publication, system installation, persistent environment/profile change, RID rewrite,
guard waiver, commit or push was performed. The current release qualification remains incomplete.
ARM64, other images/runtime packages, all native dependencies and the full host/platform matrix remain
outside this diagnostic. Curated evidence is retained beside this report; complete run diagnostics remain
in the temporary directories. Documentation and source-lock updates followed the executed code checks.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
