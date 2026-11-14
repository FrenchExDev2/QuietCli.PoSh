#requires -Version 7.6
<#
.SYNOPSIS
Extracts a checksum-pinned PowerShell ZIP or tar/gzip archive without installing or changing profiles.
.PARAMETER Channel
Locked stable or preview release channel.
.PARAMETER RuntimeIdentifier
Native Windows or Linux glibc architecture selected by the CI matrix.
.PARAMETER OutputDirectory
New private extraction directory; existing destinations are rejected.
.PARAMETER WorkspaceRoot
Workspace containing the reviewed host lock.
.PARAMETER ArchiveCacheDirectory
Optional checksum-addressed archive cache; defaults to the checkout's .cache/powershell-hosts.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [Parameter(Mandatory)][ValidateSet('stable','preview')][string]$Channel,
    [Parameter(Mandatory)][ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$ArchiveCacheDirectory
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Initialize-PowerShellHost')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$lock=Get-Content ([IO.Path]::Combine($WorkspaceRoot,'build/powershell-hosts.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
if($Channel -ceq 'preview' -and $lock.PSObject.Properties['Preview'] -and !$lock.Preview.Available){throw ('PowerShellPreviewNotPublished: '+$lock.Preview.Version)}
$selected=@($lock.Hosts|Where-Object {$_.Channel -ceq $Channel -and $_.Rid -ceq $RuntimeIdentifier})
if($lock.SchemaVersion -ne 1 -or $selected.Count -ne 1){throw 'PowerShellHostLockInvalid'}
$hostSpec=$selected[0]
if($hostSpec.Version -notmatch '\A7\.\d+\.\d+(-(preview|rc)\.\d+)?\z' -or $hostSpec.SHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'PowerShellHostIdentityInvalid'}
$directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if(Test-Path -LiteralPath $directory){throw 'PowerShellHostDirectoryExists'}
[void][IO.Directory]::CreateDirectory($directory)
$windowsHost=$RuntimeIdentifier.StartsWith('win-')
$extension=if($windowsHost){'zip'}else{'tar.gz'}
$archive=[IO.Path]::Combine($directory,('host.'+$extension))
$asset=if($windowsHost){"PowerShell-$($hostSpec.Version)-$RuntimeIdentifier.zip"}else{"powershell-$($hostSpec.Version)-$RuntimeIdentifier.tar.gz"}
$url="https://github.com/PowerShell/PowerShell/releases/download/v$($hostSpec.Version)/$asset"
if(!$ArchiveCacheDirectory){$ArchiveCacheDirectory=[IO.Path]::Combine($WorkspaceRoot,'.cache/powershell-hosts')}
$cached=[IO.Path]::Combine($ArchiveCacheDirectory,($hostSpec.SHA256+'.'+$extension))
$cacheHit=Test-Path -LiteralPath $cached
if($cacheHit){
    if((Get-Item -LiteralPath $cached -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'PowerShellHostCacheChecksumMismatch'}
    Copy-Item -LiteralPath $cached -Destination $archive
}else{
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
}
if((Get-FileHash $archive -Algorithm SHA256).Hash -cne $hostSpec.SHA256){throw $(if($cacheHit){'PowerShellHostCacheChecksumMismatch'}else{'PowerShellHostChecksumMismatch'})}
if(!$cacheHit){
    [void][IO.Directory]::CreateDirectory($ArchiveCacheDirectory)
    if(!(Test-Path -LiteralPath $cached)){[IO.File]::Copy($archive,$cached,$false)}
}
$extracted=[IO.Path]::Combine($directory,'host')
if($windowsHost){[void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive,$extracted,[Threading.CancellationToken]::None).GetAwaiter().GetResult()}
else{
    [void][IO.Directory]::CreateDirectory($extracted)
    $input=[IO.File]::OpenRead($archive);$gzip=[IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
    try{[void][System.Formats.Tar.TarFile]::ExtractToDirectoryAsync($gzip,$extracted,$false,[Threading.CancellationToken]::None).GetAwaiter().GetResult()}finally{$gzip.Dispose();$input.Dispose()}
}
$executable=[IO.Path]::Combine($extracted,$(if($windowsHost){'pwsh.exe'}else{'pwsh'}))
if(!(Test-Path -LiteralPath $executable)){throw 'PowerShellHostExecutableMissing'}
if(!$windowsHost -and !$IsWindows){[IO.File]::SetUnixFileMode($executable,([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute -bor [IO.UnixFileMode]::GroupRead -bor [IO.UnixFileMode]::GroupExecute -bor [IO.UnixFileMode]::OtherRead -bor [IO.UnixFileMode]::OtherExecute))}
$receipt=@{Channel=$Channel;Version=$hostSpec.Version;RuntimeMajor=$hostSpec.RuntimeMajor;RuntimeIdentifier=$RuntimeIdentifier;ArchiveSHA256=$hostSpec.SHA256;Source=$url;Directory=$extracted;Executable=$executable}
Write-WorkspaceJson ([IO.Path]::Combine($directory,'host-receipt.json')) $receipt
[pscustomobject]$receipt
