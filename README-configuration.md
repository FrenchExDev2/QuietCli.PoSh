# Configuration

[Back to the QuietCli overview](README.md)

Related: [Measurements and privacy](README-measurements.md).

See [configuration and unique tokenized deliveries](docs/configuration.md). The sole product environment override, `QUIETCLI_CONFIG_DIRECTORY`, selects the directory containing `config.yaml`. Explicit parameters override the session's YAML snapshot, then built-in defaults. Use `New-QuietCliConfiguration`, `Test-QuietCliConfiguration`, `Get-QuietCliConfiguration` and `Import-QuietCliConfiguration` to manage it explicitly.
