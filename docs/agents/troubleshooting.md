# Troubleshooting QuietCli results

Always read the envelope before the data: `Outcome`, `Execution`, `Completeness.Source`,
`Completeness.Analysis` and `Error`. Never retry automatically; a failed command may have had an
effect. Deliver diagnostics with `FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $result -MaxItems 8 -MaxOutputBytes 4096`.

The first three rows' codes (`HandlerNotFound`, non-zero `ExitCode`, `RecallRequiresExplicitAsObject`)
were reproduced on the repository's local Core module. The other rows follow the documented
contracts in `AGENTS.md`, `examples.md` and `docs/recall.md` and were not reproduced here.

## Symptoms

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Outcome` is `Unsupported`; `Error[0].Code` is `HandlerNotFound` (phase `Resolve`); nothing ran | No registered handler matches the command and no callbacks were given | Import the companion module that owns the command, or supply `-Output` and `-Complete` (see [non-git-example.md](non-git-example.md)) |
| `Outcome` is `Failed`, `Execution.Native.ExitCode` is non-zero, both `Completeness` flags true | The native command itself failed; the analysis ran on its output | Read the executable's documented exit codes. Declare `-SuccessExitCodes` only for codes it documents as success |
| `Outcome` is `Success` but `Completeness.Analysis` is false | The analyzer did not see all records, or `-Complete` did not run to the end | Treat the data as unusable. Fix the parser, then run a fresh observation |
| `Completeness.Source` is false | Native output was not fully drained (timeout, cancellation, buffer limit) | Do not present the data as complete. Rerun only when repeating is safe |
| Exception `RecallRequiresExplicitAsObject` | `-Recall` or `-SaveRecall` used without `-AsObject` | Add `-AsObject`; both are only valid with an object result |
| Parser throws (for example `InvalidGitCommitCount`, `InvalidDotnetSdkRecord`) | A record did not match the documented format | Read the executable's help or format documentation again; do not loosen the parser to skip records |
| `-Complete` result has the wrong shape | A callback returned more than one value, or an array was unrolled | Return one object; return an array with the unary comma (`,$array`) |
| Callback output appears in the pipeline | `-Output` emitted a value (a method return, for example) | Use `[void]` on calls whose result is discarded |
| `Invoke-QuietRecall` stops on missing ranges | The retention budget dropped bytes | Rerun with a larger `-RecallMaxBytes`, or pass `-AllowPartial` and report the result as partial |
| A saved Recall cannot be found | Wrong `-RecallRoot`, or `-RecallName` used as an identity | Use `RecallId` as the identity; a name is only a searchable label |
| `$result` is gone in a later tool call | Each completed shell call started a new PowerShell process | Keep one process alive ([persistent-shell.md](persistent-shell.md)) or use `-SaveRecall` |
| Telemetry or Recall files appear in the wrong place | `QUIETCLI_CONFIG_DIRECTORY` alone does not relocate default storage | Set the database and Recall root in `config.yaml` and reload with `Import-QuietCliConfiguration` |

## Loading problems

- **Wrong module version loaded.** Check `(Get-Module FrenchExDev2.QuietCli.Core.PoSh).Path`. Do not
  accept an older installed release silently; import the selected source module explicitly.
- **Legacy modules in the process.** Never load legacy QuietCli or archived OPumper modules in the
  same process; they share public command names. Start a new process.
- **Hosting.** Leave `engine.hosting` at `Auto`. A CLR 10 process selects the `net10.0` build;
  CLR 11+ selects `net11.0`. `Get-QuietEngine` reports the host actually used. Never load the
  .NET 11 assembly into CLR 10.
- **Binaries stale or missing.** Import does not compile C#. Rebuild with the repository's
  `scripts/Build-Workspace.ps1`, then start a fresh PowerShell process.

## What not to do

- Do not re-run a mutating command to see whether it worked.
- Do not enumerate or serialize `Internal`, callback objects or retained native evidence.
- Do not treat a zero exit code as proof of complete analysis.
- Do not enable retries, hooks, network access or profile changes to work around a failure; the
  engine grants none of them.
