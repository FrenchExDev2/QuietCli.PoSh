#requires -Version 7.6
<#
.SYNOPSIS
Accepts the script mutation campaign only when the downloaded shard reports cover every configured target, each above its break.
.PARAMETER ReportRoot
Downloaded shard artifacts; every report.json below it is read.
.PARAMETER OutputPath
New completion receipt destination; an existing file is rejected.
.PARAMETER WorkspaceRoot
Checkout supplying the authoritative targets file.
.PARAMETER TargetsPath
Targets file; defaults to <workspace>/test/scripts/mutation.targets.psd1.
.PARAMETER Target
Selected target names; only their shards are required. Omitted, every configured target is required.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ReportRoot,[Parameter(Mandatory)][string]$OutputPath,[string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[string]$TargetsPath,[string[]]$Target)
if(!$PSCmdlet.ShouldProcess($OutputPath,'Verify every script mutation shard and save a completion receipt')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptMutation.psm1')) -DisableNameChecking -ErrorAction Stop
$testsRoot=[IO.Path]::Combine($WorkspaceRoot,'test','scripts')
if([string]::IsNullOrWhiteSpace($TargetsPath)){$TargetsPath=[IO.Path]::Combine($testsRoot,'mutation.targets.psd1')}
$targets=@(Read-QuietScriptMutationTargets -Path $TargetsPath -ScriptsRoot ([IO.Path]::Combine($WorkspaceRoot,'scripts')) -TestsRoot $testsRoot)
if($PSBoundParameters.ContainsKey('Target')){
    # A selective run qualifies only the targets its changes reach; each one must still be complete.
    if(!@($Target).Count){throw 'ScriptMutationTargetSelectionEmpty'}
    foreach($name in $Target){if($name -cnotin @($targets.Name)){throw ('ScriptMutationTargetUnknown: '+$name)}}
    $targets=@($targets|Where-Object {$_.Name -cin $Target})
}
$reports=@(if([IO.Directory]::Exists($ReportRoot)){
    Get-ChildItem -LiteralPath $ReportRoot -Recurse -File -Filter report.json|Sort-Object FullName|ForEach-Object {
        if($_.Length -gt 4194304 -or $_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ScriptMutationShardReportInvalid'}
        [IO.File]::ReadAllText($_.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json
    }
})
$receipt=Assert-QuietScriptMutationShards -Targets $targets -Reports $reports
$destination=[IO.Path]::GetFullPath($OutputPath,$PWD.Path)
if([IO.File]::Exists($destination)){throw 'ScriptMutationCompletionReceiptExists'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
[IO.File]::WriteAllText($destination,($receipt|ConvertTo-Json -Depth 4)+"`n",[Text.UTF8Encoding]::new($false))
$receipt
