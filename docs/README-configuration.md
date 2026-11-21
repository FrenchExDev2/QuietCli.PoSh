# QuietCli configuration reference

[Configuration guide](../readmes/README-configuration.md) · [Delivery identity and token measurements](README-measurements-delivery-identity.md)

## Loading and precedence

QuietCli reads `~/.quietcli/config.yaml` on first relevant use and keeps a validated snapshot for the session. Importing the module leaves configuration unread. An absent file uses built-in defaults. An invalid existing file fails explicitly before native execution.

Explicit invocation parameters override YAML values, followed by built-in defaults. `QUIETCLI_CONFIG_DIRECTORY`, the only product configuration environment variable, selects the directory containing `config.yaml`. `New-QuietCliConfiguration`, `Test-QuietCliConfiguration` and `Import-QuietCliConfiguration` also accept `-Path` to select a specific file. `Get-QuietCliConfiguration` reports the active configuration and setting origins. The environment has no `QUIETCLI2_*` aliases. Test-runner variables are separate.

## Validation and reload

`New-QuietCliConfiguration -Force` explicitly permits replacing an existing file; `-WhatIf` is supported. Validation returns a `PSCustomObject` with `IsValid`, `Path`, `Exists`, `Errors`, `Warnings` and normalized `Configuration`. Errors identify their key, line and column where available. Validation never creates a configuration file, database or engine. The verified managed parser may be loaded to inspect an existing YAML file.

Changing the database or hosting setting while an engine is active rejects the reload and requests `Stop-QuietEngine`. It never stops a command or switches a database implicitly. Other settings take effect after explicit reload. Changing the environment directory alone does not replace an already loaded snapshot.

## Schema version 1

```yaml
schemaVersion: 1
tokenization:
  tokenizer: o200k_base
delivery:
  maxOutputBytes: 4096
  maxItems: 20
  maxTrackedRepresentations: 256
execution:
  timeoutSeconds: 600
  drainTimeoutSeconds: 30
telemetry:
  enabled: true
  database: ~/.quietcli2/gains.sqlite
engine:
  hosting: Auto
  ipcTimeoutSeconds: 30
streams:
  transport: Pipe
  stdoutMode: Text
  stderrMode: Text
  maxRecordBytes: 1048576
  readBlockBytes: 16384
recall:
  maxBytes: 16MiB
  policy: Head
  root: null
gain:
  maxEvents: 10000
```

Sections and values may be omitted. Keys and enum values are case sensitive. Unknown versions, unknown or duplicate keys, malformed types and out-of-range values are rejected. YAML input is strict UTF-8, at most 64 KiB, 256 parser events and eight nested mappings; aliases, anchors, tags, sequences and multiple documents are rejected. Only inert mapping/scalar data is parsed, never arbitrary objects or expressions.

`tokenizer` accepts `o200k_base`, `cl100k_base` or `off`. Hosting accepts `Auto`, `InProcess` or `Process`. Transport accepts `Pipe` or `Pty`; stream modes accept `Text` or `Bytes`. Recall policies are `Head`, `Tail` and `HeadAndTail`; its byte budget uses the existing integer/IEC-size/`All` contract. Recall settings never enable capture without explicit `-Recall` or `-SaveRecall`.

Output bytes must be at least 256; item count may be zero. Representation capacity is 1–65536 per result. Record bytes are 1–2147483647 and native blocks are 1024–16384 bytes. Execution timeout is 0.001–4294967.294 seconds; drain and IPC timeouts are 0.05–300 seconds. Gain event budget is 1–1000000.

Relative YAML paths resolve against the configuration file directory. Only a leading `~` expands to the user profile. No variable, wildcard or expression expansion occurs. Omitted database and Recall paths preserve the existing user-data locations; no historical database is moved.

## Focused development validation

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild
```

The suite uses owned temporary configuration and database files, both hosting modes, generated Unicode and scalar properties, malformed YAML/UTF-8 inputs, and targeted PowerShell/C# source mutants. It also exercises historical SQLite fixtures and transaction conflicts for the [delivery measurement contract](README-measurements-delivery-identity.md). See the [local test guide](../readmes/README-qualification-local.md) for the visible monitor and reports.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
