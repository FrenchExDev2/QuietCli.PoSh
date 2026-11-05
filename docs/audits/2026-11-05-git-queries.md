# Git object, ref and file queries — 5 November 2026

This checkpoint adds twelve dedicated query handlers to the existing 29. The catalogue has 41 specialized entries; 142 inventory entries still lack one. This count does not qualify every form or every installed Git command. Remaining helper/legacy commands are not exposed through an invented generic parser.

Parsing runs in GitObjectRecords, GitReferenceRecords, GitIndexRecords, GitObjectCounts and GitVersionRecords in the caller-local net10.0/net11.0 companion. Queries.ps1 coordinates native requests. NUL fields are used where the format supports them. Literal separators, operands and explicit output formats retain their native meaning. Each business query executes once; no extra engine IPC or hidden native/network probe was introduced.

Version/platform receipts:
- artifacts/tests/git-query-stable-1: Windows x64, stable PowerShell/.NET 10, 49/49 passed.
- artifacts/tests/git-query-preview-1: Windows x64, Preview PowerShell/.NET 11, 49/49 passed.
- Both use native Git 2.56.0.windows.3. This does not qualify every 2.40–2.56 release or Linux/ARM64.
- Each run includes 28 nested compiled cases and eight detected targeted query mutants, with zero survivors, invalid builds, timeouts or infrastructure errors.
- Twenty thousand bounded malformed inputs per compiled execution exercise rejection without partial business rows; seeds and generated workloads are in QueryCases.cs. This is deterministic fuzzing, not coverage-guided fuzzing.

Exact local receipts and source/binary identities are retained in those run directories. mutation/catalogues.json separates independent targeted catalogues from the reusable runner; existing Push/Repository selectors are preserved. No native PTY change requires a new C campaign for this query-only checkpoint.

The native assertions cover tracked paths/stages/requested formats; local refs and explicitly requested local advertisements; SHA-1 blob hashing against an independently calculated object header; revision parents; ancestry/non-ancestry/native errors; counters; version; ref validation; detached symbolic refs. Advanced output shapes use RequestedFormat or fail explicitly; they are not silently filtered into misleading object lists. Qualification remains Pending in Get-QuietGitCoverage, which now exposes HandlerLanguage and ParserTypes.

Official sources: [ls-files](https://git-scm.com/docs/git-ls-files), [for-each-ref](https://git-scm.com/docs/git-for-each-ref), [show-ref](https://git-scm.com/docs/git-show-ref), [ls-remote](https://git-scm.com/docs/git-ls-remote), [rev-list](https://git-scm.com/docs/git-rev-list), [count-objects](https://git-scm.com/docs/git-count-objects). No push or publication was performed.
