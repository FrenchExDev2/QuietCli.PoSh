# Invoke-DotNetMigrationBuild.ps1

Internal worker of [the .NET migration build facade](../Test-DotNetMigrationBuild.md). WorkspaceRoot supplies the independent shared process helper; RunDirectory owns request/status/logs/build-results/summary JSON. Direct worker execution is not the supported selection entry point. ShouldProcess guards execution before writes.

For each selected entry, recheck target hash, resolve SDK with dotnet --version from the target directory, then execute the literal Release argument vector. SDK probe time counts against the per-target deadline. Continue after ordinary build failures, recording independent state/exit/duration/logs; do not retry or infer success from a localized console message. Successful SDK resolution without an observed version is a failure. Policy changes, stale target files, crash and timeout remain explicit.

Only the child process receives DOTNET_CLI_UI_LANGUAGE=en and DOTNET_CLI_FORCE_UTF8_ENCODING=1. This avoids the observed non-UTF-8 localized help output on the developer host; it changes no user profile. Workload update notifications are disabled in this child. [Official .NET environment variables](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables).

Each UTF-8/LF target log is bounded to 8 MiB; truncation is reported while output continues to drain. The JSON retains the last twelve bounded diagnostic records, actual SDK, arguments and target hash. The visible monitor shows the selected project/task/root, current full target, elapsed duration and owned PowerShell worker identity. Child dotnet PIDs are not inferred. Summary counters are build counters, not test counts.

Critical review: [worker](../../../scripts/workers/Invoke-DotNetMigrationBuild.ps1) keeps full native execution independent of QuietCli and saves terminal evidence on every owned completion path. The outer supervisor handles hard crashes/timeouts. Source/configuration snapshots beyond the selected target remain separate migration requirements; Release build success does not satisfy them. Verdict: explicit compilation witness, including failures, not automatic migration approval.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
