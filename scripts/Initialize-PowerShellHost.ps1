# Objective: Download a pinned, checksum-verified side-by-side PowerShell host for integrated CI.
#requires -Version 7.6
<#
.SYNOPSIS
Extracts an official PowerShell ZIP into a new directory without installing or changing profiles.
.PARAMETER Channel
Locked stable or preview release channel.
.PARAMETER RuntimeIdentifier
Native Windows architecture selected by the CI matrix.
.PARAMETER OutputDirectory
New private extraction directory; existing destinations are rejected.
.PARAMETER WorkspaceRoot
Workspace containing the reviewed host lock.
#>
[CmdletBinding()]param(
    [Parameter(Mandatory)][ValidateSet('stable','preview')][string]$Channel,
    [Parameter(Mandatory)][ValidateSet('win-x64','win-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$lock=Get-Content (Join-Path $WorkspaceRoot 'build/powershell-hosts.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
$selected=@($lock.Hosts|Where-Object {$_.Channel -ceq $Channel -and $_.Rid -ceq $RuntimeIdentifier})
if($lock.SchemaVersion -ne 1 -or $selected.Count -ne 1){throw 'PowerShellHostLockInvalid'}
$hostSpec=$selected[0]
if($hostSpec.Version -notmatch '^7\.\d+\.\d+(-preview\.\d+)?$' -or $hostSpec.SHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'PowerShellHostIdentityInvalid'}
$directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if(Test-Path -LiteralPath $directory){throw 'PowerShellHostDirectoryExists'}
[void][IO.Directory]::CreateDirectory($directory)
$archive=Join-Path $directory 'host.zip'
$url="https://github.com/PowerShell/PowerShell/releases/download/v$($hostSpec.Version)/PowerShell-$($hostSpec.Version)-$RuntimeIdentifier.zip"
$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromMinutes(5)
$deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(5))
try{
    $response=$client.GetAsync($url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$deadline.Token).GetAwaiter().GetResult()
    try{
        [void]$response.EnsureSuccessStatusCode()
        $input=$response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
        $output=[IO.FileStream]::new($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,$true)
        try{[void]$input.CopyToAsync($output,$deadline.Token).WaitAsync($deadline.Token).GetAwaiter().GetResult()}finally{$output.Dispose();$input.Dispose()}
    }finally{$response.Dispose()}
}finally{$deadline.Dispose();$client.Dispose()}
if((Get-FileHash $archive -Algorithm SHA256).Hash -cne $hostSpec.SHA256){throw 'PowerShellHostChecksumMismatch'}
$extracted=Join-Path $directory 'host'
[void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive,$extracted,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
$executable=Join-Path $extracted 'pwsh.exe'
if(!(Test-Path -LiteralPath $executable)){throw 'PowerShellHostExecutableMissing'}
$receipt=@{Channel=$Channel;Version=$hostSpec.Version;RuntimeMajor=$hostSpec.RuntimeMajor;RuntimeIdentifier=$RuntimeIdentifier;ArchiveSHA256=$hostSpec.SHA256;Source=$url;Directory=$extracted;Executable=$executable}
Write-WorkspaceJson (Join-Path $directory 'host-receipt.json') $receipt
[pscustomobject]$receipt
