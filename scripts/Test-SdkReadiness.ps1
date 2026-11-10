#requires -Version 7.6
<#
.SYNOPSIS
Reports whether the pinned .NET SDK is current and whether ReadyToRun (Crossgen2) is actually publishable for
every RID that -ReadyToRun on Build-Workspace.ps1 would target, without building, installing or publishing
anything.
.DESCRIPTION
Three independent checks, each best-effort and individually reported as Unknown on failure instead of failing
the whole run:
  1. Pinned SDK (global.json) versus the SDK dotnet actually resolves here (respects rollForward) and versus the
     latest SDK published for that channel.
  2. Installed Microsoft.NETCore.App runtimes, used to find the local runtime version per target framework.
  3. Whether Microsoft.NETCore.App.Crossgen2.<Rid> has a published NuGet version matching that runtime version,
     for net10.0/<LocalRuntimeIdentifier> (the lib/inprocess publication) and net11.0/<RuntimeIdentifier> (every
     lib/engine/<rid> publication).
This never installs an SDK or calls dotnet publish; -Update only prints the commands that would close a gap.
.PARAMETER WorkspaceRoot
QuietCli2 workspace containing global.json and runtime-targets.json.
.PARAMETER RuntimeIdentifier
RIDs to check for the net11.0 lib/engine/<rid> publications. Defaults to Build-Workspace.ps1's own default set.
.PARAMETER LocalRuntimeIdentifier
RID checked for the net10.0 lib/inprocess publication. Defaults to the local Windows architecture, matching
Build-Workspace.ps1's own default; override on Linux (for example linux-x64).
.PARAMETER Offline
Skips every network call (channel lookup, NuGet Crossgen2 listings) and reports those fields as Unknown instead
of failing.
.PARAMETER Update
Performs no install or publish. When set, also prints the exact command for each gap found (SDK behind channel,
Crossgen2 not published for a RID) so the user can run it themselves.
.OUTPUTS
One [pscustomobject] (SchemaVersion 1): Sdk, ReadyToRun (one row per framework/RID pair) and Gaps (string list).
Callers branch on this object instead of re-parsing text; it is also written to the pipeline in every mode.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),
    [string]$LocalRuntimeIdentifier=('win-'+([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant())),
    [switch]$Offline,
    [switch]$Update
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Test-SdkReadiness')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-QuietPinnedSdk {
    <#
    .SYNOPSIS
    Reads the pinned SDK version and rollForward policy straight from global.json.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace.
    #>
    param([string]$WorkspaceRoot)
    $path=Join-Path $WorkspaceRoot 'global.json'
    if(!(Test-Path -LiteralPath $path)){throw 'GlobalJsonMissing'}
    $doc=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json
    [pscustomobject]@{Path=$path;Version=[string]$doc.sdk.version;RollForward=[string]$doc.sdk.rollForward;AllowPrerelease=[bool]$doc.sdk.allowPrerelease;Channel=(($doc.sdk.version -split '\.')[0..1] -join '.')}
}
function Invoke-QuietDotnetQuery {
    <#
    .SYNOPSIS
    Runs one read-only dotnet query and returns its trimmed stdout lines, or an empty list on failure.
    .PARAMETER WorkspaceRoot
    Directory dotnet is invoked from, so global.json governs SDK resolution.
    .PARAMETER Arguments
    Read-only dotnet argument vector.
    #>
    param([string]$WorkspaceRoot,[string[]]$Arguments)
    $state=@{Lines=[Collections.Generic.List[string]]::new()}
    $result=Invoke-CiProcess -FilePath dotnet -ArgumentList $Arguments -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout' -and $e.Text.Trim()){$s.Lines.Add($e.Text.Trim())}}
    if($result.Outcome -ne 'Success'){return @()}
    return @($state.Lines)
}
function Get-QuietInstalledSdks {
    <#
    .SYNOPSIS
    Parses `dotnet --list-sdks` into version/path pairs; empty when dotnet is missing or the call fails.
    .PARAMETER WorkspaceRoot
    Directory dotnet is invoked from.
    #>
    param([string]$WorkspaceRoot)
    @(Invoke-QuietDotnetQuery $WorkspaceRoot @('--list-sdks')|ForEach-Object{if($_ -match '^(?<version>\S+)\s+\[(?<path>.+)\]$'){[pscustomobject]@{Version=$Matches.version;Path=$Matches.path}}})
}
function Get-QuietInstalledRuntimes {
    <#
    .SYNOPSIS
    Parses `dotnet --list-runtimes` into name/version/path triples; empty when the call fails.
    .PARAMETER WorkspaceRoot
    Directory dotnet is invoked from.
    #>
    param([string]$WorkspaceRoot)
    @(Invoke-QuietDotnetQuery $WorkspaceRoot @('--list-runtimes')|ForEach-Object{if($_ -match '^(?<name>\S+)\s+(?<version>\S+)\s+\[(?<path>.+)\]$'){[pscustomobject]@{Name=$Matches.name;Version=$Matches.version;Path=$Matches.path}}})
}
function Get-QuietLocalRuntimeVersion {
    <#
    .SYNOPSIS
    Picks the highest installed Microsoft.NETCore.App runtime whose major matches one target framework.
    .PARAMETER Runtimes
    Result of Get-QuietInstalledRuntimes.
    .PARAMETER Framework
    Target framework moniker, for example net11.0.
    #>
    param([object[]]$Runtimes,[string]$Framework)
    $major=[int]($Framework -replace '^net','' -replace '\..*$','')
    $candidates=@($Runtimes|Where-Object{$_.Name -eq 'Microsoft.NETCore.App'}|ForEach-Object{try{[pscustomobject]@{Text=$_.Version;Parsed=[version]($_.Version -replace '-.*$','')}}catch{$null}}|Where-Object{$_ -and $_.Parsed.Major -eq $major})
    if(!$candidates){return $null}
    ($candidates|Sort-Object Parsed -Descending|Select-Object -First 1).Text
}
function Get-QuietChannelLatestSdk {
    <#
    .SYNOPSIS
    Reads the latest SDK published for one release channel from the official releases index.
    .PARAMETER Channel
    Channel version, for example 11.0.
    #>
    param([string]$Channel)
    try{
        $index=Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json' -TimeoutSec 15
        $entry=$index.'releases-index'|Where-Object{$_.'channel-version' -eq $Channel}
        if(!$entry){return [pscustomobject]@{Channel=$Channel;LatestSdk=$null;SupportPhase=$null;Queried=$true}}
        [pscustomobject]@{Channel=$Channel;LatestSdk=[string]$entry.'latest-sdk';SupportPhase=[string]$entry.'support-phase';Queried=$true}
    }catch{[pscustomobject]@{Channel=$Channel;LatestSdk=$null;SupportPhase=$null;Queried=$false}}
}
function Get-QuietCrossgen2Versions {
    <#
    .SYNOPSIS
    Lists published versions of Microsoft.NETCore.App.Crossgen2.<Rid> from the NuGet flat container index.
    .PARAMETER Rid
    Runtime identifier, for example linux-musl-arm64.
    #>
    param([string]$Rid)
    try{
        $id='microsoft.netcore.app.crossgen2.'+$Rid
        $index=Invoke-RestMethod -Uri ('https://api.nuget.org/v3-flatcontainer/'+$id+'/index.json') -TimeoutSec 15
        [pscustomobject]@{Rid=$Rid;Versions=@($index.versions);Queried=$true}
    }catch{[pscustomobject]@{Rid=$Rid;Versions=@();Queried=$false}}
}
function Test-QuietCrossgen2Match {
    <#
    .SYNOPSIS
    Checks whether a Crossgen2 version list contains the exact local runtime version.
    .PARAMETER Versions
    Published version strings for one RID.
    .PARAMETER RuntimeVersion
    Locally installed Microsoft.NETCore.App version to match, or null when unknown.
    #>
    param([string[]]$Versions,[string]$RuntimeVersion)
    if(!$RuntimeVersion){return $false}
    $RuntimeVersion -cin $Versions
}

$pinned=Get-QuietPinnedSdk $WorkspaceRoot
$installedSdks=@(Get-QuietInstalledSdks $WorkspaceRoot)
$effectiveVersion=(Invoke-QuietDotnetQuery $WorkspaceRoot @('--version')|Select-Object -Last 1)
$runtimes=@(Get-QuietInstalledRuntimes $WorkspaceRoot)
$channel=if($Offline){[pscustomobject]@{Channel=$pinned.Channel;LatestSdk=$null;SupportPhase=$null;Queried=$false}}else{Get-QuietChannelLatestSdk $pinned.Channel}

$frameworkRids=@(@{Framework='net10.0';Rid=$LocalRuntimeIdentifier})+@($RuntimeIdentifier|ForEach-Object{@{Framework='net11.0';Rid=$_}})
$gaps=[Collections.Generic.List[string]]::new()
if(!(@($installedSdks.Version) -ccontains $pinned.Version)){$gaps.Add('PinnedSdkNotInstalled: '+$pinned.Version)}
if($effectiveVersion -cne $pinned.Version){$gaps.Add('EffectiveSdkMismatch: resolved '+([string]$effectiveVersion)+' vs pinned '+$pinned.Version)}
if($channel.Queried -and $channel.LatestSdk -and $channel.LatestSdk -cne $pinned.Version){$gaps.Add('ChannelAheadOfPin: latest '+$channel.LatestSdk+' vs pinned '+$pinned.Version)}

$rows=@(foreach($pair in $frameworkRids){
    $runtimeVersion=Get-QuietLocalRuntimeVersion $runtimes $pair.Framework
    $crossgen=if($Offline){[pscustomobject]@{Rid=$pair.Rid;Versions=@();Queried=$false}}else{Get-QuietCrossgen2Versions $pair.Rid}
    $matched=Test-QuietCrossgen2Match $crossgen.Versions $runtimeVersion
    $status=if($Offline -or !$crossgen.Queried){'Unknown'}elseif(!$runtimeVersion){'RuntimeNotInstalled'}elseif($matched){'Published'}else{'NotPublished'}
    if($status -eq 'NotPublished'){$gaps.Add('Crossgen2NotPublished: '+$pair.Framework+'/'+$pair.Rid+' runtime '+$runtimeVersion)}
    if($status -eq 'RuntimeNotInstalled'){$gaps.Add('RuntimeNotInstalled: '+$pair.Framework+' needed for '+$pair.Rid)}
    [pscustomobject]@{Framework=$pair.Framework;Rid=$pair.Rid;LocalRuntimeVersion=$runtimeVersion;Crossgen2PackageId=('microsoft.netcore.app.crossgen2.'+$pair.Rid);Status=$status}
})

$report=[pscustomobject]@{
    SchemaVersion=1
    GeneratedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    WorkspaceRoot=$WorkspaceRoot
    Offline=[bool]$Offline
    Sdk=[pscustomobject]@{
        Pinned=$pinned
        InstalledSdks=$installedSdks
        EffectiveVersion=$effectiveVersion
        EffectiveMatchesPinned=($effectiveVersion -ceq $pinned.Version)
        Channel=$channel
        IsPinnedLatestInChannel=($channel.Queried -and $channel.LatestSdk -ceq $pinned.Version)
    }
    ReadyToRun=$rows
    Gaps=@($gaps)
    ReadyToRunFeasible=(!(@($rows|Where-Object Status -eq 'NotPublished')) -and !(@($rows|Where-Object Status -eq 'RuntimeNotInstalled')))
}

function Write-QuietReadinessTable {
    <#
    .SYNOPSIS
    Renders the readiness report as UTF-8 box-drawing tables on the console; never used for the returned object.
    .PARAMETER Report
    Result produced above.
    #>
    param($Report)
    Write-Host ('┌'+('─'*78)+'┐')
    Write-Host ('│ SDK pinné   : '+$Report.Sdk.Pinned.Version.PadRight(62)+'│')
    Write-Host ('│ RollForward : '+($Report.Sdk.Pinned.RollForward+' (allowPrerelease='+$Report.Sdk.Pinned.AllowPrerelease+')').PadRight(62)+'│')
    Write-Host ('│ Effectif    : '+([string]$Report.Sdk.EffectiveVersion).PadRight(62)+'│')
    $channelText=if($Report.Sdk.Channel.Queried){($Report.Sdk.Channel.LatestSdk+' ('+$Report.Sdk.Channel.SupportPhase+')')}else{'Unknown (offline or unreachable)'}
    Write-Host (('│ Dernier canal '+$Report.Sdk.Pinned.Channel+' : '+$channelText).PadRight(78)+'│')
    Write-Host ('└'+('─'*78)+'┘')
    Write-Host ('┌'+('─'*18)+'┬'+('─'*18)+'┬'+('─'*24)+'┬'+('─'*16)+'┐')
    Write-Host ('│ '+'Framework'.PadRight(16)+' │ '+'Rid'.PadRight(16)+' │ '+'RuntimeVersion'.PadRight(22)+' │ '+'Status'.PadRight(14)+' │')
    Write-Host ('├'+('─'*18)+'┼'+('─'*18)+'┼'+('─'*24)+'┼'+('─'*16)+'┤')
    foreach($row in $Report.ReadyToRun){
        Write-Host ('│ '+$row.Framework.PadRight(16)+' │ '+$row.Rid.PadRight(16)+' │ '+([string]($row.LocalRuntimeVersion ?? '-')).PadRight(22)+' │ '+$row.Status.PadRight(14)+' │')
    }
    Write-Host ('└'+('─'*18)+'┴'+('─'*18)+'┴'+('─'*24)+'┴'+('─'*16)+'┘')
    if($Report.Gaps.Count){
        Write-Host 'Écarts :'
        foreach($gap in $Report.Gaps){Write-Host ('  - '+$gap)}
    }else{
        Write-Host 'Aucun écart détecté.'
    }
}
function Write-QuietReadinessProposals {
    <#
    .SYNOPSIS
    Prints the exact command that would close each detected gap; never runs dotnet install or publish itself.
    .PARAMETER Report
    Result produced above.
    #>
    param($Report)
    if(!$Report.Gaps.Count){Write-Host 'Aucune action proposée : aucun écart détecté.';return}
    Write-Host 'Actions proposées (aucune exécution automatique) :'
    foreach($gap in $Report.Gaps){
        if($gap -like 'PinnedSdkNotInstalled:*' -or $gap -like 'EffectiveSdkMismatch:*'){
            Write-Host ('  - Installer le SDK épinglé '+$Report.Sdk.Pinned.Version+' : winget install Microsoft.DotNet.SDK.Preview --version '+$Report.Sdk.Pinned.Version)
        }elseif($gap -like 'ChannelAheadOfPin:*'){
            Write-Host ('  - Évaluer la mise à jour du pin vers '+$Report.Sdk.Channel.LatestSdk+' dans '+$Report.Sdk.Pinned.Path+' (vérifier le changelog avant de changer la version épinglée).')
        }elseif($gap -like 'Crossgen2NotPublished:*' -or $gap -like 'RuntimeNotInstalled:*'){
            Write-Host ('  - '+$gap+' : ne pas activer -ReadyToRun pour cette cible tant que ce paquet/runtime n''est pas disponible ; revalider avec ./scripts/Test-SdkReadiness.ps1 après mise à jour.')
        }else{
            Write-Host ('  - '+$gap)
        }
    }
}

$isInteractive=[Environment]::UserInteractive -and ![Console]::IsOutputRedirected
if($Update){Write-QuietReadinessTable $report;Write-QuietReadinessProposals $report}
elseif($isInteractive){Write-QuietReadinessTable $report}
$report
