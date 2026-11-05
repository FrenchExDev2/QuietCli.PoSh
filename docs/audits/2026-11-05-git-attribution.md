# Reflog, blame and annotate — 5 November 2026

This checkpoint adds three handlers, bringing the catalogue to 44 specialized entries of 183. These are scoped command forms, not full version/platform certification. Parsing is caller-local C#; PowerShell retains invocation/format selection.

GitBlameRecords consumes line-porcelain headers, metadata and exact content; it checks positive line/group counts, continuity and incomplete EOF. GitQuotedPath independently decodes C-style byte paths, retaining invalid UTF-8 explicitly. GitReflogRecords maps five NUL-delimited reflog fields. There is no direct .git-file parsing, captured native document, additional Git process or engine IPC per record.

Evidence: artifacts/tests/git-attribution-stable-2 passed 53/53 under Windows stable/.NET 10; artifacts/tests/git-attribution-preview-1 passed 56/56 under Preview/.NET 11. Native Git was 2.56.0.windows.3. Both include 33 independent compiled cases. Stable selected the eight new attribution mutants; Preview selected all four catalogues after the runner refactor, detecting 32/32 with zero survivors, invalid mutants, timeouts or infrastructure errors.

Generated path/group tests retain seeds 74051/74052; 20,000 bounded malformed inputs per compiled execution use seed 74053. This is deterministic fuzzing, not coverage-guided fuzzing. Native tests use supported 1 KiB reads, and cover Unicode quoted names, content CR, uncommitted lines, selected annotate ranges, explicit incremental records, reflog selectors/messages and missing predicates. Linux/ARM64 and all Git versions/options remain unqualified locally. Existing Core/native PTY code was unchanged.

Sources: [blame porcelain](https://git-scm.com/docs/git-blame#_the_porcelain_format), [reflog](https://git-scm.com/docs/git-reflog), [Git path quoting](https://github.com/git/git/blob/v2.56.0/quote.c). No push or publication was performed.
