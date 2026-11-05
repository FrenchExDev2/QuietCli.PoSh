# Principal Git command handlers — 5 November 2026

The module now registers 29 specialized command families. This change adds common workflows for switch, restore, reset, rm, mv, clean, merge, rebase, cherry-pick, revert, tag, remote, config, init and clone to the earlier 14 families. Specialization is not a claim that every option, Git release or platform is qualified.

## Responsibilities and runtime costs

GitConfigRecords parses NUL config entries without losing duplicate keys, multiline/empty/valueless settings or invalid UTF-8 bytes. GitRemoteRecords preserves configured remote names, URL boundaries and fetch/push direction. GitOperationOutcome retains native failure while annotating observed conflicts. These are separate caller-local C# responsibilities, built for net10.0 and net11.0; there is no GitDaily command or type.

RepositoryCommands.ps1 owns native execution and observations. File operations use one business process and two porcelain-v2 status observations; operations that can move refs add two local ref observations. Status carries HEAD/branch/index/worktree state so separate HEAD/branch probes are unnecessary. Initial observation failure blocks these worktree operations before mutation. Observations remain non-atomic and cannot prove file contents, remote state or hook effects.

A failed merge remains failed with visible unmerged entries. Abort/continue are separate explicit requests; there is no retry or automatic resolution. The clean dry-run plan and explicitly requested patch/format records are retained. Init/clone repository identity is verified for known explicit destinations; implicit clone destination discovery, recursive submodule state and bare worktree-operation variants remain unqualified.

## Validation

The stable integrated run at artifacts/tests/git-main-stable-recovered passed 89/89 scenarios with zero failures, including 26 Core C# cases and 22 Git C# cases. The isolated Preview/.NET 11 run also passed 89/89 scenarios. After LF normalization, Git retained its passing 43 scenarios and the focused Core rerun passed 44/44, including 64 generated JSON-value/LF round trips (seed 72055), source scanning and Gallery packaging. Retained final receipts are under artifacts/tests/git-principal-final. All local runs use the dedicated visible monitor and saved terminal reports. The snapshot descriptor is artifacts/tests/git-main-final-snapshot.json.

The Git additions include nine PowerShell workflows, generated interaction properties (240 vectors, seed 72054), two isolated in-memory PowerShell guard mutants, 2,000 generated C# config/remote cases (seeds 72051/72052), and 20,000 bounded malformed remote records (seed 72053). Existing push cases retain their own generated/fuzz checks. These deterministic campaigns do not claim coverage-guided fuzzing.

The explicitly selected C# catalogues each require their baseline first, then eight detected source-checked mutants. Reports distinguish survivors, invalid builds, timeouts and infrastructure errors. The reusable CI enables both compiler-based catalogues in Windows Preview x64 qualification, while ordinary development can select only the relevant campaign. This catalogue is not exhaustive mutation coverage. Linux/ARM64 execution of this new command pass and the complete 2.40–2.56 release matrix remain unexecuted locally. Unchanged native PTY source/resources retain their separate existing receipts; C# parser mutations do not qualify native C.

## Test isolation correction and recovery

An earlier non-repository test incorrectly created its empty directory beneath this checkout. Git discovered the enclosing repository, and that test's reset --hard unintentionally reset tracked workspace files. The test was responsible; no concurrent task is needed to explain the reset.

Seventy-one changed files were recovered from the earlier validated frozen checkout at C:/Users/serard/AppData/Local/Temp/quietcli-git-migration-d8b43b04 after checking rewrite timestamps and content digests. Original reset contents and the recovery plan remain under artifacts/tests/unintended-reset-20261105. New files were preserved and current handler/test/policy changes were reapplied. Binary/source identity checks then passed for all four projects.

The regression now uses an external temporary directory, explicitly sets GIT_CEILING_DIRECTORIES to prevent parent discovery and invokes rm on a unique nonexistent path instead of a destructive reset. It requires zero business executions when the initial state cannot be observed, and a separate native-failure case requires exactly one execution without retry. No test may reset/clean/discard the actual workspace; this rule and coherent commit checkpoints are recorded in AGENTS.md.

Official format references: [Git status porcelain v2](https://git-scm.com/docs/git-status), [config](https://git-scm.com/docs/git-config), [tag](https://git-scm.com/docs/git-tag), [remote](https://git-scm.com/docs/git-remote), [clone](https://git-scm.com/docs/git-clone). No push or publication is performed by this work.

## Filesystem line endings

All repository text is UTF-8 with LF on disk, enforced by .gitattributes, .editorconfig and the source assertion. The JSON generator and dependency notice importer produce LF. Thirty-two existing source/evidence files were normalized; changed evidence hashes retain OriginalSHA256 provenance. Binary resources and immutable run evidence were preserved. The workspace and repository AGENTS.md also record the LF requirement. Compiler-based mutations were already qualified before the formatting-only pass; unrelated campaigns were not repeated solely for line-ending changes.
