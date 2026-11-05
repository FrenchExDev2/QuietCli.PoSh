# Revision query audit - 2026-11-05

Scope: rev-parse, describe, name-rev and shortlog. The catalogue grows from 51 to 55 specialized handlers among 183 inventoried entries. Business parsing runs caller-local in C# with no business-object IPC. PowerShell retains dispatch, native invocation and caller identity.

rev-parse parses a single recognized scalar selector or verified IDs; mixed output retains requested records. Scalar buffering is explicitly bounded and preserves raw invalid UTF-8 and embedded newlines. describe uses long output except custom suffix/contains/zero-abbreviation modes. Native abbreviated identities remain abbreviated. name-rev does not mislabel symbolic input expressions as full object IDs. shortlog summary labels are opaque and default subjects are preserved.

Windows x64 Git 2.56.0.windows.3 passed 64/64 scenarios on PowerShell 7.6.9/.NET 10 and 7.7.0-preview.5/.NET 11. Auto selected integrated hosting. Reports: artifacts/tests/git-revision-stable-1 and git-revision-preview-1. Both include 44 compiled cases, generated properties (76051,76052), 20,000 malformed inputs (76053), and eight killed targeted revision mutants; no survivors, invalid builds, timeouts or infrastructure failures. The test worker verifies the imported source module and quiet alias before product tests. Native PTY was unchanged, so its unrelated campaign was not repeated.

Limits: development evidence is Windows x64 on one native Git version. Other versions, architectures, Linux and full option combinations remain unqualified. Requested-format fallback is explicit, not a typed semantic guarantee. No publication or push occurred.

References: [rev-parse](https://git-scm.com/docs/git-rev-parse), [describe](https://git-scm.com/docs/git-describe), [name-rev](https://git-scm.com/docs/git-name-rev), [shortlog](https://git-scm.com/docs/git-shortlog). Native installed help is the immediate argument reference.
