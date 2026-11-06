# QuietCli usage instructions

Read these production usage rules and the relevant workflow in [SKILL.md](SKILL.md).

1. Define the question, selected project, required business data and smallest useful delivery before executing. Keep unknown measurements unknown.
2. Use PowerShell Core 7.6+ with its normal profile and UTF-8 initialization. Import `FrenchExDev2.QuietCli.Core.PoSh` once per process. Load business companions only when using their registered handlers. Do not mix legacy QuietCli/OPumper modules into this process.
3. Read installed command help or official executable documentation before writing executable-specific analysis. Inventory membership is not semantic or platform qualification.
4. Run native commands through `quiet`, using a compatible registered handler or explicit `-Output` and `-Complete` analysis callbacks. CI/build orchestration and read-only streaming monitors retain their host application's documented exceptions.
5. Set `-WorkingDirectory` explicitly. QuietCli options precede the executable; native arguments follow it verbatim. Use `-FilePath` and `-ArgumentList` for exact argument vectors.
6. Keep `-AsObject` results in named variables. Check `Outcome`, `Execution`, `Completeness.Source`, `Completeness.Analysis`, `Error` and business scope before making a decision. A successful native exit alone does not prove complete analysis.
7. Callbacks retain only required business data in `runtime.Data`. `-Output` emits no incidental pipeline output; `-Complete` returns at most one business value. Use the unary comma to return an array as one value. Honor cancellation and keep synchronous callback work bounded.
8. Deliver bounded views with `FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult` or `ConvertTo-QuietJson`. Do not dump `Internal`, callback objects or retained native evidence. `-AsObject` alone does not serialize data or establish delivery savings.
9. Prefer a persistent PowerShell process for sequential agent work when the client's tools support it. Keep its process identity, tool session handle and result names. Verify command completion before submitting dependent work. A conversation is not a PowerShell process; lost processes lose ordinary result objects.
10. `QUIETCLI_CONFIG_DIRECTORY` selects the directory containing `config.yaml`. Use `New-QuietCliConfiguration` to create the default template and `Import-QuietCliConfiguration` for explicit reloads. Isolate telemetry and Recall paths in disposable work. Keep hosting at `Auto` unless a different mode is explicitly needed.
11. Native output is streamed once through bounded buffers by default. Explicit `-Recall -AsObject` retains bounded in-memory evidence; `-SaveRecall -AsObject` writes a durable journal. Use the Recall APIs and `RecallId` for offline reanalysis. These features are distinct from shell persistence and legacy RECORD APIs.
12. Preserve failures and incomplete evidence. Never retry automatically or repeat a mutation whose effect is unknown. Inspect bounded diagnostics; suggestions are not authorization.
13. `Get-QuietCliGain` reports measured volumes and available overhead. Native tokens and unmeasured delivery sizes remain unknown. Compare matching scopes and units; output savings do not measure API billing.
14. No wrapper grants permission for installations, profile changes, hooks, network access, pushes or publication. Use the host project's test strategy and visible monitoring rules. Production usage instructions are separate from repository maintenance rules.
