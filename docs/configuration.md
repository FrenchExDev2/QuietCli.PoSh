# Configuration and unique tokenized deliveries

QuietCli lazily reads `~/.quietcli/config.yaml` on first relevant use and keeps a validated snapshot for the session. Importing the module does not read configuration, start an engine or create a file. An absent file uses built-in defaults. An invalid existing file fails explicitly before execution.

`QUIETCLI_CONFIG_DIRECTORY` is the only product configuration environment variable. It selects the directory containing `config.yaml`; it does not contain the file name. No `QUIETCLI2_*` aliases are recognized. Old database, hosting, tracking, IPC-timeout and Recall-root environment settings no longer configure the product. Test-runner control variables are separate from product configuration.

Explicit command parameters override YAML values, which override built-in defaults. Configuration-management cmdlets accept an explicit `-Path` to inspect, create or load another file. The automatic path otherwise comes from `QUIETCLI_CONFIG_DIRECTORY`, then `~/.quietcli`.

```powershell
New-QuietCliConfiguration
$validation = Test-QuietCliConfiguration
$validation.IsValid
$validation.Errors
$effective = Get-QuietCliConfiguration
$effective.Configuration
$effective.Origins

# Apply edits explicitly; an invalid reload preserves the previous snapshot.
Import-QuietCliConfiguration
```

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

## Tokens and delivery identity

`quiet -AsJson` / `-AsYaml`, `Out-QuietResult`, `ConvertTo-QuietJson` and `ConvertTo-QuietYaml` share one delivery path. Tokenization defaults to `o200k_base` and counts the exact final representation, including whitespace and any truncation envelope. `-Tokenizer cl100k_base` or `-Tokenizer off` overrides the configured default. Counts identify the encoding and actual tokenizer library version, rather than claiming model-independent tokens.

```powershell
$json = ConvertTo-QuietJson $result
$result.AlreadyDelivered               # False on the first representation
$result.Deliveries[0].TokenProfile     # o200k_base by default
$same = ConvertTo-QuietJson $result
$result.AlreadyDelivered               # True; same DeliveryId
$otherCount = ConvertTo-QuietJson $result -Tokenizer cl100k_base
$yaml = ConvertTo-QuietYaml $result
```

Within the originating result, format plus the SHA-256 of exact UTF-8 text identifies a representation. Identical conversions reuse their `DeliveryId`; a different format or text creates a new delivery. Returning to a previous representation reuses its receipt. The tokenizer is a measurement choice, not a new delivery identity. The latest delivery and its `AlreadyDelivered`, tokenizer and token count are available through `Deliveries[0]` and `Measurement`; the result also exposes `DeliveryId` and `AlreadyDelivered`.

Only hashes, numeric measurements and metadata receipts accumulate locally, bounded by `maxTrackedRepresentations`. Only the latest delivery text is retained. Exceeding the capacity fails explicitly before a new representation is delivered or counted. `-AsObject` never enumerates or serializes business data to measure tokens. Offline conversion and disabled tracking retain only local receipts.

SQLite keeps one `quiet2_events` delivery row, preserving its initial tokenizer fields and timestamp. `quiet2_delivery_tokens` stores one numeric measurement per `(delivery_id, token_profile, token_version)`. Additional tokenizers enrich the same delivery without increasing delivery or byte totals. Repeated measurements are cached locally; persistence is idempotent and transactional. Storage failures preserve the local identity and are reported through `Measurement.StorageError`, permitting a later conversion to retry with the same identity.

`Get-QuietCliGain` reports `DeliveredTokensByProfile`: measured tokens, measured/unmeasured deliveries and completeness for each encoding/version. These totals never mix encodings or treat missing measurements as zero. `NativeTokens` remains unknown: this feature does not tokenize native streams. The gain report's own JSON/YAML representations remain excluded from delivery tracking.

Existing databases remain readable without rewriting their events. The token table is created transactionally on a delivery write, not a read. Historical deliveries are neither retokenized nor retroactively deduplicated; their missing measurements remain explicit coverage gaps. Conversion records a unique produced representation, not proof that a person or model received it.

## Focused development validation

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild
```

The focused suite uses owned temporary configuration/database files, both hosting modes, generated Unicode/scalar properties, malformed YAML/UTF-8 inputs, historical SQLite fixtures, transaction conflicts and targeted PowerShell/C# source mutants. The shared launcher owns the visible monitor and saves diagnostics outside the checkout. This development scope does not qualify unexecuted platform/release matrix entries.
