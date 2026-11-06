# Measurements and privacy

[Back to the QuietCli overview](README.md)

What QuietCli measures, what it stores and what it never stores. Related: [Configuration](README-configuration.md), [Streaming and callbacks](README-streaming.md).

The result counts stdin bytes actually written, stdout/stderr bytes actually read, and merged terminal bytes for PTY. `Business`, `Probe`, `Observation` and `Infrastructure` roles separate sources. Aggregates deduplicate sources; context subtotals are not necessarily additive. Probes and reanalysis do not inflate business gains.

With `-AsObject`, delivery size and reduction remain unknown. JSON/YAML bytes are measured only when their representation is produced, including the delivery envelope. The latest delivered text remains local under its `DeliveryId`; successive delivery strings do not accumulate in the result.

Use `ConvertTo-QuietJson` for JSON or `ConvertTo-QuietYaml` for YAML. `ConvertTo-QuietYaml` provides the symmetric YAML conversion; `Out-QuietResult -AsJson` also produces JSON.

```powershell
$json = ConvertTo-QuietJson $r -MaxOutputBytes 4096
$yaml = Out-QuietResult $r -AsYaml -MaxOutputBytes 4096
```

The first unique representation creates a `DeliveryId` and, when tracking is enabled and storage succeeds, adds one `kind='delivery'` row to SQLite's `quiet2_events` table. Identical conversions on the same result reuse that identity and expose `AlreadyDelivered=True`; different tokenizer measurements do not create new deliveries. These rows contain metadata and measurements such as format, output bytes and serialization duration, never the delivered JSON/YAML text or business data. Offline results and `telemetry.enabled: false` skip these writes. A storage failure is reported through `Measurement.StorageError` and `Measurement.Status='StorageUnavailable'` while the produced text is still returned.

Tokenization defaults to `o200k_base` and counts the exact final delivery text. `-Tokenizer cl100k_base` or `off` overrides that default. Native model-token counts remain unknown. Byte reduction alone establishes neither context-window use nor financial savings.

SQLite stores closed metadata, counters, relationships and structured error codes. It excludes native output, business objects, delivered text, Recall names and callback code. Explicit Recall storage is separate from telemetry and ordinary result serialization. YAML `telemetry.database` selects the database; `telemetry.enabled: false` disables measurement writes. Storage errors remain distinct from business outcomes.

See [allocation and delivery metrics](docs/allocation-and-delivery-metrics.md), [Core performance qualification](FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md) and the [RTK comparison](QUIET_VS_RTK_MEASURES.md) for definitions, measured scope and limitations.
