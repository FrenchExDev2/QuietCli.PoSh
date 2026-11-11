#requires -Version 7.6
<#
.SYNOPSIS
Copies the shared .NET tooling into the repository's script/library/test layout.
.DESCRIPTION
This one-time import preserves existing destination files, which may contain
repository-specific integration. It never overwrites a maintained copy. Review
the mirrored documentation and run the repository checks after an initial import.
.PARAMETER SourceWorkspace
FrenchExDev_i2 workspace containing scripts and Doc/Net.
.PARAMETER DestinationRoot
QuietCli checkout receiving missing files; defaults to this checkout.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$SourceWorkspace,
    [string]$DestinationRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$source=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceWorkspace)
$destination=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
$mapping=[ordered]@{
    'scripts/Test-DotNetReadiness.ps1'='scripts/Test-DotNetReadiness.ps1'
    'scripts/Install-DotNet.ps1'='scripts/Install-DotNet.ps1'
    'scripts/Update-DotNetGlobalJson.ps1'='scripts/Update-DotNetGlobalJson.ps1'
    'scripts/DotNetReadiness.psm1'='scripts/lib/DotNetReadiness.psm1'
    'scripts/DotNetProvisioning.psm1'='scripts/lib/DotNetProvisioning.psm1'
    'scripts/tests/DotNetReadiness.Tests.ps1'='FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNetReadiness.Tests.ps1'
    'scripts/tests/DotNetProvisioning.Tests.ps1'='FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNetProvisioning.Tests.ps1'
    'scripts/tests/Invoke-DotNetReadinessTests.ps1'='scripts/Invoke-DotNetTests.ps1'
    'scripts/tests/Watch-DotNetReadinessTests.ps1'='scripts/Watch-DotNetTests.ps1'
    'Doc/Net/DotNetReadiness.md'='docs/README-dotnet-readiness.md'
    'Doc/Net/DotNetProvisioning.md'='docs/README-dotnet-provisioning.md'
}
foreach($entry in $mapping.GetEnumerator()) {
    if(!(Test-Path -LiteralPath (Join-Path $source $entry.Key) -PathType Leaf)){throw "Missing source: $($entry.Key)"}
}
foreach($entry in $mapping.GetEnumerator()) {
    $target=Join-Path $destination $entry.Value
    if(Test-Path -LiteralPath $target){[pscustomobject]@{Path=$target;Status='Preserved'};continue}
    if(!$PSCmdlet.ShouldProcess($target,'Copy initial .NET tooling source into its repository layout')){continue}
    $text=Get-Content -LiteralPath (Join-Path $source $entry.Key) -Raw -Encoding utf8
    if($entry.Value -like 'scripts/*.ps1' -and $entry.Value -notlike 'scripts/lib/*') {
        $text=$text.Replace("'DotNetReadiness.psm1'","'lib/DotNetReadiness.psm1'").Replace("'DotNetProvisioning.psm1'","'lib/DotNetProvisioning.psm1'")
    }
    if($entry.Value -like 'scripts/lib/*') {
        $text=$text.Replace("(Join-Path `$PSScriptRoot '../Net/FrenchExDev/global.json')","(Join-Path `$PSScriptRoot '../../global.json')")
        $text=$text.Replace("(Join-Path `$PSScriptRoot '../Net/FrenchExDev/.dotnet')","(Join-Path `$PSScriptRoot '../../.dotnet')")
        $text=$text.Replace("(Join-Path `$PSScriptRoot '../Net/FrenchExDev')","(Join-Path `$PSScriptRoot '../..')")
        $text=$text.Replace("(Join-Path `$PSScriptRoot '../PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh')","(Join-Path `$PSScriptRoot '../..')")
    }
    if($entry.Value -like 'FrenchExDev2.QuietCli.Core.Tests.PoSh/*') {
        $text=$text.Replace("'../DotNetReadiness.psm1'","'../scripts/lib/DotNetReadiness.psm1'").Replace("'../DotNetProvisioning.psm1'","'../scripts/lib/DotNetProvisioning.psm1'")
    }
    $null=[IO.Directory]::CreateDirectory((Split-Path $target -Parent))
    $null=[IO.File]::WriteAllTextAsync($target,$text.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [pscustomobject]@{Path=$target;Status='Copied'}
}
