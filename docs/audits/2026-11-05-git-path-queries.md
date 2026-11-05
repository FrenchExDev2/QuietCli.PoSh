# Search, path checks and raw plumbing diffs — 5 November 2026

Seven added handlers bring specialization to 51/183 inventory entries; 132 remain partial or missing. These counts describe routed forms, not full option/version/platform qualification.

GitRawDiffRecords parses full raw headers, scores, commit prefixes and single/rename/copy NUL paths. It does not force patch recursion. GitPathCheckRecords implements the distinct three/four-field protocols, including an empty first nonmatching field that history-style grouping must not skip. GitMailmapRecords splits the native canonical identity. Grep's requested file lists reuse GitIndexRecords; quiet mode is a native predicate and content/context/binary output remains exact requested records. No hidden fetch, .git metadata reader or engine IPC was introduced.

Evidence: artifacts/tests/git-pathquery-stable-2 and git-pathquery-preview-1 each passed 60/60 scenarios with Git 2.56.0.windows.3 on Windows x64 (integrated .NET 10/.NET 11). Each includes 39 compiled cases, eight detected targeted PathQuery mutants, zero survivors/invalid/timeouts/infrastructure errors, and the PowerShell mode/guard assertions. The generated C# campaigns retain seeds 75051–75054, with 20,000 bounded malformed inputs per compiled execution; the PowerShell grep-mode properties use 500 cases at seed 75055 and detect two isolated mutants. This is deterministic fuzzing, not coverage-guided fuzzing.

An initial native attribute test omitted the outer PowerShell separator and consumed Git's --. The corrected native vectors retain both attribute names and the exact path, including Unicode. Product argument binding was unchanged. The interaction regression fixes a real routing ambiguity: -p/--patch requires input only for actual patch selectors, while diff/log/blame display modes remain noninteractive.

Full Git release, Linux/ARM64 and unimplemented formats remain explicitly unqualified. Existing Core/native PTY implementations were unchanged. No push or publication was performed.

References: [raw diff](https://git-scm.com/docs/git-diff-index#_raw_output_format), [attributes](https://git-scm.com/docs/git-check-attr), [ignore](https://git-scm.com/docs/git-check-ignore), [mailmap](https://git-scm.com/docs/git-check-mailmap), [grep](https://git-scm.com/docs/git-grep).
