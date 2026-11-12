#requires -Version 7.6
<#
.SYNOPSIS
Accepts only the complete run-profile mutation catalogue from matching isolated shards.
.PARAMETER ReportRoot
Downloaded shard artifacts; each must contain exactly one mutation report.
.PARAMETER Revision
Exact workflow revision to require in every report.
.PARAMETER WorkspaceRoot
Checkout supplying the authoritative catalogue and input hashes.
.PARAMETER OutputPath
New completion receipt destination.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ReportRoot,[Parameter(Mandatory)][string]$Revision,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($OutputPath,'Verify every mutation shard and save a complete-catalogue receipt')){return}
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/MutationShards.psm1') -ErrorAction Stop
$catalogue=@((Import-PowerShellDataFile -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.Catalogue.psd1')).Mutants)
$reports=@(Get-ChildItem -LiteralPath $ReportRoot -Recurse -File -Filter run-profiles-mutation.json | ForEach-Object {
    if($_.Length -gt 2097152 -or $_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'MutationShardReportInvalid'}
    [IO.File]::ReadAllText($_.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json
})
$receipt=Assert-QuietMutationShards -Reports $reports -Catalogue $catalogue -SourceSHA256 (Get-QuietRunProfileMutationIdentity $WorkspaceRoot) -Revision $Revision
if(Test-Path -LiteralPath $OutputPath){throw 'MutationCompletionReceiptExists'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath,$PWD.Path)))
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath,$PWD.Path),($receipt|ConvertTo-Json -Depth 4)+"`n",[Text.UTF8Encoding]::new($false))
$receipt
