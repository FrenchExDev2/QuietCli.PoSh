# Run-profile tooling qualification — 8 November 2026

This closes the encoding, benchmark/profiler test and CI-wiring gaps listed in the
[earlier audit](2026-11-07-run-profiles.md). These are local development results, not public release qualification.

## Changes and independently checked contracts

- The benchmark rejects samples unless they contain exactly three invariant-culture, finite, nonnegative durations.
  It also rejects duplicate result markers. Generated duration properties and a malformed-input corpus cover these
  boundaries; the actual script runs against a deterministic native boundary to check pair identity, warm-up exclusion,
  failure budgets without retries, difference direction, separate profiling and paths containing spaces.
- Profiler tests cover explicit-path/environment precedence, pinned versions, generated trace-row projections and
  missing traces. The actual pinned profiler also runs in the full functional suite.
- The initializer delegates package caching to `RunToolCache.psm1`: verified downloaded bytes, verified cached archives,
  asynchronous ZIP extraction and a local receipt. Offline ZIP fixtures and an injected byte provider need no network.
  A separate live case executes the initializer against copies of both official cached archives with `-Offline`.
- The shared launcher exposes `RunProfiles` and `RunProfilesMutation`, with the existing visible, read-only monitor and
  external reports. Required skipped functional cases and every non-Killed mutation outcome fail the gate.
- `ci.yml` runs both scopes on Windows x64 stable integrated hosting for Core/All, uploads their reports with
  `if: always()` and blocks the existing Windows qualification dependency on failure. Git-only development keeps its
  narrower scope. Workflow YAML and the qualification dependency were checked locally; no GitHub run was dispatched.

## Results and provenance

Windows x64, PowerShell 7.6.9, .NET 10.0.14; SDK/build commands retain the repository's existing pins. Reports are
under `%TEMP%/QuietCli2/874a99c9b658/tests/`:

| Evidence | Result | Run directory |
| --- | --- | --- |
| Complete tooling suite, seed 61207, 300 generated inputs per property | 46 passed, 0 failed, 0 skipped | `20261108-064827-8817c4` |
| Full targeted catalogue, seed 61207, 120 generated inputs per property | 90 Killed, 0 Survived, 1 Crashed, 0 Timeout, 0 Invalid | `20261108-061256-67e0e2` |
| Affected cache/initializer catalogue after correction, same seed and iterations | 10 Killed, all other outcomes zero | `cache-reprise-20261108-064759` |
| Unfiltered Core/All regression gate after fixture corrections | Core 56/56, Git 67/67, 0 failures | `20261108-064827-3169aa` |

Combining outcomes by mutant name gives **91 distinct mutants, all Killed**. This is a full campaign plus a targeted
reprise, not one successful full-catalogue execution after the final correction. The ten cache/initializer mutants
were repeated because their code includes asynchronous extraction and because one exposed the assertion-output defect.
Unchanged catalogue entries retain the full campaign's evidence. The new assertion regression and complete functional
suite pass; the default CI gate still executes every mutant afresh for the revision being qualified.

The first failed cache-layout mutant returned an object when a failure was expected. `Assert-Throws` allowed that
object into PowerShell's formatting pipeline, which hid the textual summary. It was correctly classified as Crashed
and blocked the gate. The assertion now consumes incidental output; an independent regression verifies that an unmet
expectation throws without leaking an object. The failing sandbox is retained in the first campaign's JSON report.

The unfiltered regression also found two fixture defects: the invocation-link case constructed an incomplete native
request, and a logging fixture method lacked readable help. The invocation case now uses the facade argument reader's
complete request; its link-rejection assertion is unchanged. The method now has comment-based help. No production C#
behavior was changed to accommodate these fixtures.

The unfiltered run's repository source SHA-256 was
`F1312C772D3E68F7413550B6E61C0AE258C7F0B2483FC19C572D6F78E030F9F3`;
its net10.0 engine DLL SHA-256 was
`796CF3ABE66B94982EE822861AB3EF69A836F245C74ABB957DCFCEBAAD594D9E`.
The reports retain before/after source identities and actual host identities. Subsequent audit/help documentation and
workspace-lock refreshes do not change the validated executable logic. Reports in temporary storage need explicit
export for durable retention.

## Reproduction and remaining limits

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite RunProfiles -SkipBuild -TimeoutSeconds 600
./scripts/Invoke-WorkspaceCi.ps1 -Suite RunProfilesMutation -SkipBuild -TimeoutSeconds 3300
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
```

- The mutation score measures the committed targeted catalogue, not exhaustive fault coverage. Live profiler, console,
  actual-process and official-cache cases run separately from sandbox mutations.
- The three-pair live A/A test is a functional smoke test. False-positive calibration at 100/1000 pairs and the ReadyToRun
  A/B comparison remain unmeasured. Concurrent qualification timings are not controlled performance comparisons.
- Linux, ARM64 and the full release matrix were not executed by this tooling task. CI wiring is present; remote success,
  publication and qualification of a future committed revision are not established by these local results.
