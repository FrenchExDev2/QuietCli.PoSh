<#
.SYNOPSIS
Copies bounded report types into a CI evidence artifact with revision/run identity and SHA-256 checksums.
.PARAMETER ReportRoot
Owned test or container report tree. Staged workspaces, tool caches and Git internals are excluded.
.PARAMETER OutputDirectory
Separate artifact directory, outside ReportRoot.
.PARAMETER Revision
Exact workflow revision.
.PARAMETER RequireProfiling
Records missing successful profiling as an explicit evidence gap.
#>
[CmdletBinding()]
param([string]$ReportRoot,[string]$OutputDirectory,[string]$Revision,[switch]$RequireProfiling)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$source=[IO.Path]::GetFullPath($ReportRoot,$PWD.Path)
$destination=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
$relativeDestination=[IO.Path]::GetRelativePath($source,$destination)
if(![IO.Path]::IsPathRooted($relativeDestination) -and $relativeDestination -notmatch '^\.\.([\\/]|$)'){throw 'EvidenceDestinationMustBeOutsideReports'}
[void][IO.Directory]::CreateDirectory($destination)
$files=[Collections.Generic.List[object]]::new();$gaps=[Collections.Generic.List[string]]::new();$profileSuccess=0
$profileReports=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $source){
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($source)
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'EvidenceSourceLinkRejected'}
            if($item.PSIsContainer){if($item.Name -notin @('workspace','.git','.profilers','bin','obj','lib')){$pending.Push($item.FullName)};continue}
            if($item.Extension -notin @('.json','.nettrace','.log','.txt','.xml','.csv')){continue}
            $relative=[IO.Path]::GetRelativePath($source,$item.FullName)
            $target=Join-Path $destination $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $evidenceInputStream=[IO.FileStream]::new($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $evidenceOutputStream=[IO.FileStream]::new($target,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{[void]$evidenceInputStream.CopyToAsync($evidenceOutputStream).GetAwaiter().GetResult()}finally{$evidenceInputStream.Dispose();$evidenceOutputStream.Dispose()}
            $files.Add(@{Path=$relative.Replace('\','/');Bytes=(Get-Item $target).Length;SHA256=(Get-FileHash $target -Algorithm SHA256).Hash})
            if($relative.Replace('\','/') -match '^(?:[^/]+/)?(?:guest/)?profiling/summary\.json$'){
                $profileReports.Add($target)
            }
        }
    }
}else{$gaps.Add('No report directory was produced; inspect preceding failed CI steps.')}
foreach($path in $profileReports){
    $profileEvidence=Get-Content $path -Raw -Encoding utf8|ConvertFrom-Json
    if($profileEvidence.State -ne 'Success'){continue}
    $base=Split-Path $path -Parent
    $valid=$profileEvidence.ProfilerVersion -eq '4.3.0' -and $profileEvidence.ClrProfilerVersion -eq '10.0.750501'
    $valid=$valid -and (Test-Path (Join-Path $base 'powershell-lines.json')) -and (Test-Path (Join-Path $base 'powershell.speedscope.json'))
    foreach($collector in $profileEvidence.Collectors){
        $trace=Join-Path $base $collector.Trace
        if(!(Test-Path $trace) -or !(Test-Path (Join-Path $base $collector.Speedscope))){$valid=$false;continue}
        if((Get-FileHash $trace -Algorithm SHA256).Hash -cne $collector.SHA256){$valid=$false}
    }
    $expected=if($profileEvidence.TargetIdentity.EngineMode -eq 'Process'){2}else{1}
    if($profileEvidence.Collectors.Count -ne $expected){$valid=$false}
    if($valid){$profileSuccess++}else{$gaps.Add('Incomplete or modified profiling artifacts: '+[IO.Path]::GetRelativePath($destination,$path))}
}
if($RequireProfiling -and !$profileSuccess){$gaps.Add('No successful mandatory PowerShell/CLR profiling report.')}
Write-WorkspaceJson (Join-Path $destination 'evidence-manifest.json') @{
    SchemaVersion=1;Revision=$Revision;Repository=$env:GITHUB_REPOSITORY;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT
    CreatedUtc=[DateTimeOffset]::UtcNow.ToString('o');RunnerOS=$env:RUNNER_OS;RunnerArchitecture=$env:RUNNER_ARCH
    SuccessfulProfilingReports=$profileSuccess;EvidenceGaps=$gaps.ToArray();Files=@($files|Sort-Object Path)
    Integrity='SHA-256 detects content changes; this manifest alone does not authenticate its author. GitHub artifact/run identity remains separate.'
}
[pscustomobject]@{Directory=$destination;Files=$files.Count;Gaps=$gaps.Count}
if($RequireProfiling -and $gaps.Count){throw 'MandatoryProfilingEvidenceMissing'}
