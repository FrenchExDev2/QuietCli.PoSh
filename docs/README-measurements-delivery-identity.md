# Delivery identity and token measurements

[Measurements and privacy](../readmes/README-measurements.md) · [Allocation and delivery metrics](README-allocation-and-delivery-metrics.md) · [SQLite schema and queries](README-sqlite-schema-and-queries.md)

## Representation and token counts

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

## SQLite storage and gain reports

SQLite keeps one `quiet2_events` delivery row, preserving its initial tokenizer fields and timestamp. `quiet2_delivery_tokens` stores one numeric measurement per `(delivery_id, token_profile, token_version)`. Additional tokenizers enrich the same delivery without increasing delivery or byte totals. Repeated measurements are cached locally; persistence is idempotent and transactional. Storage failures preserve the local identity and are reported through `Measurement.StorageError`, permitting a later conversion to retry with the same identity.

`Get-QuietCliGain` reports `DeliveredTokensByProfile`: measured tokens, measured/unmeasured deliveries and completeness for each encoding/version. These totals never mix encodings or treat missing measurements as zero. `NativeTokens` remains unknown: this feature does not tokenize native streams. The gain report's own JSON/YAML representations remain excluded from delivery tracking.

Existing databases remain readable without rewriting their events. With telemetry enabled, a successfully started native invocation queues background preparation of the writer connection, schema and reusable statements. The token table is created during that preparation or the first write, never by an ordinary read. Import, engine inspection and telemetry-disabled calls do not prepare a database. Historical deliveries are neither retokenized nor retroactively deduplicated; their missing measurements remain explicit coverage gaps. Conversion records a unique produced representation, not proof that a person or model received it.

See the [configuration reference](README-configuration.md#schema-version-1) for tokenizer and telemetry settings, and [focused validation](README-configuration.md#focused-development-validation) for the shared test suite.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
