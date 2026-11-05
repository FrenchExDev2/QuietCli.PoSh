# Git push extraction and apphost staging fix — 5 November 2026

Push porcelain record parsing now belongs to GitPush in the caller-local Git companion, built for net10.0 and net11.0. PowerShell still owns stdout filtering, execution and finalization. No per-line IPC or business-object serialization was added. The Git format reference is [git-push OUTPUT](https://git-scm.com/docs/git-push#_output).

The independent compiled runner contains 18 cases, including authored push deletion/rejection fixtures, 1,200 generated flag/field/isolation checks (seed 71051) and 20,000 bounded malformed-input fuzz cases (seed 71052). This deterministic campaign is not coverage-guided fuzzing. Eight source-checked mutations exercise remote matching/value boundaries, CR handling, flag recognition, acceptance, source/target boundaries and summary preservation.

## Windows apphost fix

The first mutation campaign failed to copy the baseline apphost from its deeply nested workspace artifact build directory. No mutant result was accepted from that attempt. Compilation now uses an owned short directory under %TEMP%/qgpm-<id>, with the repository's pinned global.json copied to its root. Source/test copies and apphosts remain there for inspection; build/test logs and summary.json remain under artifacts/git-push-mutation/<id>. Product source files are never edited in place. No Windows registry or global long-path setting was changed.

## Verified results

- Windows stable, integrated .NET 10: artifacts/tests/git-push-csharp-2, 35/35 scenarios, zero failures.
- Windows Preview, integrated .NET 11: artifacts/tests/git-push-preview-1, 35/35 scenarios, zero failures.
- Both include a successful 18-case baseline followed by 8/8 detected targeted mutants. The final campaign reports zero survivors, invalid mutants, timeouts or infrastructure errors. The initial failed run remains retained under git-push-csharp-1.
- The shared launcher provided a visible monitor for each run and saved terminal results before closure. Source identity checks passed at the end of both runs.

The mutation campaign is explicitly requested with QUIETCLI2_GIT_PUSH_MUTATION=1 when the push implementation or its tests/tooling changes; reproduction is documented in the companion README. Its catalogue does not establish exhaustive coverage. These targeted Git-only checks do not replace release qualification, the Git version compatibility matrix or unexecuted Linux/ARM64 checks for this revision. No commit, push or publication was performed.
