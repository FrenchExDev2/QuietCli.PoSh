# Configuration

[QuietCli overview](../README.md) · [Configuration reference](../docs/README-configuration.md) · [Measurements and privacy](README-measurements.md)

QuietCli looks for `~/.quietcli/config.yaml` and uses built-in defaults when the file is absent. To select another automatic location, set `QUIETCLI_CONFIG_DIRECTORY` to the directory containing `config.yaml` before first use. Explicit invocation parameters override the loaded settings.

## Create a configuration file

In PowerShell with the installed Core module, choose the automatic path and create a template if the file is absent.

```powershell
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$configDirectory = $env:QUIETCLI_CONFIG_DIRECTORY
if ([string]::IsNullOrEmpty($configDirectory)) {
    $configDirectory = [IO.Path]::Combine($HOME, '.quietcli')
}
$configPath = [IO.Path]::Combine($configDirectory, 'config.yaml')
if (-not (Test-Path -LiteralPath $configPath)) {
    New-QuietCliConfiguration -Path $configPath
}
```

For a new configuration, save this minimal `config.yaml` as UTF-8. It sets the default JSON/YAML delivery budget to 2,048 bytes. Other settings use their built-in values. In an existing configuration, edit the `delivery.maxOutputBytes` key directly to preserve your other settings.

```yaml
schemaVersion: 1
delivery:
  maxOutputBytes: 2048
```

## Validate, reload and inspect

```powershell
$validation = Test-QuietCliConfiguration -Path $configPath
if (-not $validation.IsValid) {
    $validation.Errors
    throw 'Fix the configuration errors before reloading.'
}
Import-QuietCliConfiguration -Path $configPath -ErrorAction Stop
$effective = Get-QuietCliConfiguration
$effective.Configuration
$effective.Origins
```

QuietCli uses a session snapshot. Repeat validation and reload after saving changes. A rejected reload preserves the current settings. If you change the database path or hosting mode while an engine is active, finish active work, run `Stop-QuietEngine`, then reload. The [configuration reference](../docs/README-configuration.md) lists every key, range and precedence rule.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
