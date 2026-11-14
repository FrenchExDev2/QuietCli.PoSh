#requires -Version 7.6
<#
.SYNOPSIS
Creates a bounded, credential-redacted failure bundle from an allowlist of CI report filenames.
.PARAMETER WorkspaceRoot
Checkout containing the artifacts tree. Symlinks and staged workspaces are excluded.
.PARAMETER OutputDirectory
New dedicated bundle directory, defaults to artifacts/failure-diagnostics.
.PARAMETER MaxFileBytes
Maximum source-file size accepted before parsing and redaction.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$OutputDirectory,
    [ValidateRange(1024,2097152)][int]$MaxFileBytes=1048576)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
if(!$OutputDirectory){$OutputDirectory=[IO.Path]::Combine($WorkspaceRoot,'artifacts/failure-diagnostics')}
$source=[IO.Path]::GetFullPath(([IO.Path]::Combine($WorkspaceRoot,'artifacts')))
$destination=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if((Test-Path -LiteralPath $source) -and ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FailureDiagnosticSourceLinkRejected'}
if(Test-Path -LiteralPath $destination){throw 'FailureDiagnosticDestinationExists'}
if(!$PSCmdlet.ShouldProcess($destination,'Write bounded redacted failure diagnostics')){return}
[void][IO.Directory]::CreateDirectory($destination)
$utf8=[Text.UTF8Encoding]::new($false,$true)
$secrets=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($variable in Get-ChildItem Env:){
    if($variable.Name -notmatch '(?i)TOKEN|PASSWORD|SECRET|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTHORIZATION' -or !$variable.Value){continue}
    [void]$secrets.Add($variable.Value)
    [void]$secrets.Add([Convert]::ToBase64String($utf8.GetBytes($variable.Value)))
    if($env:GITHUB_ACTOR){[void]$secrets.Add([Convert]::ToBase64String($utf8.GetBytes($env:GITHUB_ACTOR+':'+$variable.Value)))}
}
$secretValues=@($secrets|Sort-Object Length -Descending)
$allowed=@('worker.stdout.log','worker.stderr.log','worker-failure.json','status.json','summary.json',
    'core-suite.json','git-suite.json','vagrant-suite.json','guest-diagnostics.json','gallery-install-diagnostics.json',
    'ci-process-encoding-diagnostics.json','live-diagnostics.json','registry-login.json','image.json','podman.log')
$records=[Collections.Generic.List[object]]::new()
$pending=[Collections.Generic.Stack[string]]::new()
if(Test-Path -LiteralPath $source){$pending.Push($source)}
while($pending.Count -and $records.Count -lt 64){
    foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
        if($records.Count -ge 64){break}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        if($item.PSIsContainer){
            if($item.Name -notin @('workspace','.git','lib','bin','obj','.profilers','failure-diagnostics') -and $item.FullName -ne $destination){$pending.Push($item.FullName)}
            continue
        }
        if($item.Name -notin $allowed){continue}
        $relative=[IO.Path]::GetRelativePath($source,$item.FullName).Replace('\','/')
        if($item.Length -gt $MaxFileBytes){$records.Add(@{Source=$relative;State='ExcludedOversized';Bytes=$item.Length});continue}
        try{$text=[IO.File]::ReadAllTextAsync($item.FullName,$utf8).GetAwaiter().GetResult()}catch{$records.Add(@{Source=$relative;State='Unreadable'});continue}
        if($item.Name -in @('core-suite.json','git-suite.json','vagrant-suite.json','summary.json')){
            try{
                $report=$text|ConvertFrom-Json
                $cases=if($report.PSObject.Properties['Cases']){@($report.Cases)}elseif($report.PSObject.Properties['Suites']){@($report.Suites|ForEach-Object {$_.Cases})}else{@()}
                $state=if($report.PSObject.Properties['State']){$report.State|Select-Object Project,Platform,State,Passed,Failed,Error}else{$null}
                $text=@{State=$state;FailedCases=@($cases|Where-Object State -NE Passed|Select-Object -First 8 Name,State,Error)}|ConvertTo-Json -Depth 6
            }catch{
                # Incomplete JSON remains redacted diagnostic text, never accepted as qualification evidence.
            }
        }
        foreach($secret in $secretValues){$text=$text.Replace($secret,'[REDACTED]')}
        $text=[regex]::Replace($text,'(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----','[REDACTED PRIVATE KEY]')
        $text=[regex]::Replace($text,'(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)','[REDACTED]')
        $text=[regex]::Replace($text,'(?i)(authorization\s*[:=]\s*["'']?(?:Bearer|Basic)\s+)[^\s"'']+','$1[REDACTED]')
        $text=[regex]::Replace($text,'(?i)((?:password|token|secret|api[_-]?key)\s*["'']?\s*[:=]\s*["'']?)[^\s,"'']+','$1[REDACTED]')
        $text=[regex]::Replace($text,'\x1B\[[0-?]*[ -/]*[@-~]','').Replace("`r`n","`n").Replace("`r","`n")
        $lines=@($text -split "`n")
        $truncated=$lines.Count -gt 120 -or $text.Length -gt 32768 -or @($lines|Where-Object Length -GT 2048).Count -gt 0
        $tail=@($lines|Select-Object -Last 120|ForEach-Object {if($_.Length -gt 2048){$_.Substring(0,2048)+'…'}else{$_}}) -join "`n"
        if($tail.Length -gt 32768){$tail=$tail.Substring($tail.Length-32768)}
        $target=[IO.Path]::Combine($destination,($relative+'.redacted.log'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [void][IO.File]::WriteAllTextAsync($target,$tail+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $records.Add(@{Source=$relative;State='Redacted';SourceBytes=$item.Length;RetainedBytes=(Get-Item -LiteralPath $target).Length;Truncated=$truncated})
        if($records.Count -ge 64){break}
    }
}
Write-WorkspaceJson ([IO.Path]::Combine($destination,'manifest.json')) @{SchemaVersion=1;Records=$records.ToArray();LimitFiles=64;LimitLines=120;LimitCharacters=32768;TraversalIncomplete=($pending.Count -gt 0 -or $records.Count -ge 64);RawFilesCopied=$false;CredentialFilesIncluded=$false;Redaction='Known credential environment values and Base64 forms, GitHub token patterns, Authorization/password assignments and PEM private keys.'}
[pscustomobject]@{Directory=$destination;Files=$records.Count;RawFilesCopied=$false}
