function Initialize-QuietTestConfiguration {
    <#
    .SYNOPSIS
    Creates an owned YAML configuration for a test worker, independent of product imports.
    .PARAMETER DatabasePath
    Private database belonging to the worker.
    .PARAMETER Hosting
    Explicit test hosting mode; defaults to Auto.
    .PARAMETER Enabled
    Whether the worker persists telemetry.
    #>
    param([Parameter(Mandatory)][string]$DatabasePath,[string]$Hosting='Auto',[bool]$Enabled=$true)
    $directory=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($DatabasePath))) ('config-'+[IO.Path]::GetFileNameWithoutExtension($DatabasePath))
    [void][IO.Directory]::CreateDirectory($directory)
    $databaseLiteral=ConvertTo-Json -InputObject ([IO.Path]::GetFullPath($DatabasePath)) -Compress
    $boolean=if($Enabled){'true'}else{'false'}
    $text="schemaVersion: 1`ntelemetry:`n  database: $databaseLiteral`n  enabled: $boolean`nengine:`n  hosting: $Hosting`n"
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'config.yaml'),$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $env:QUIETCLI_CONFIG_DIRECTORY=$directory
}
. (Join-Path $PSScriptRoot '../FrenchExDev2.QuietCli.Core.Tests.PoSh/Configuration.TestSupport.ps1')
