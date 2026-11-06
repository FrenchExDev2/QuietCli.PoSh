<#
.SYNOPSIS
Explicitly downloads checksum-pinned diagnostic tools to an isolated cache, without global installation.
.PARAMETER OutputDirectory
Dedicated cache for the two exact packages and their extraction receipts.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$packages=@(
    @{Name='Profiler';Version='4.3.0';Url='https://www.powershellgallery.com/api/v2/package/Profiler/4.3.0';SHA256='4BB44C89117EABAAFDA17B3DFFA622CFDFC770ED05EB6084469203C66DB43E0F'},
    @{Name='dotnet-trace';Version='10.0.750501';Url='https://api.nuget.org/v3-flatcontainer/dotnet-trace/10.0.750501/dotnet-trace.10.0.750501.nupkg';SHA256='EF17F25724A55F9685BFAF8506A778EA87C2B62783ECA2CA73263226128B0D4E'}
)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$client=[Net.Http.HttpClient]::new()
try{
    foreach($package in $packages){
        $directory=Join-Path $OutputDirectory $package.Name
        [void][IO.Directory]::CreateDirectory($directory)
        $archive=Join-Path $directory ($package.Name+'.'+$package.Version+'.nupkg')
        if(!(Test-Path -LiteralPath $archive)){
            $bytes=$client.GetByteArrayAsync($package.Url).GetAwaiter().GetResult()
            if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $package.SHA256){throw 'ProfilerDownloadDigestMismatch'}
            [void][IO.File]::WriteAllBytesAsync($archive,$bytes).GetAwaiter().GetResult()
        }
        if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $package.SHA256){throw 'ProfilerCacheDigestMismatch'}
        $entrypoint=if($package.Name -eq 'Profiler'){Join-Path $directory 'Profiler.psd1'}else{Join-Path $directory 'tools/net8.0/any/dotnet-trace.dll'}
        if(!(Test-Path $entrypoint)){[IO.Compression.ZipFile]::ExtractToDirectory($archive,$directory,$true)}
    }
}finally{$client.Dispose()}
$module=Join-Path $OutputDirectory 'Profiler/Profiler.psd1'
$trace=Join-Path $OutputDirectory 'dotnet-trace/tools/net8.0/any/dotnet-trace.dll'
if(!(Test-Path $module) -or !(Test-Path $trace)){throw 'ProfilerPackageLayoutMismatch'}
Write-WorkspaceJson (Join-Path $OutputDirectory 'tool-receipt.json') @{Packages=$packages;ProfilerModulePath=$module;ClrProfilerPath=$trace;GlobalInstallation=$false}
[pscustomobject]@{ProfilerModulePath=[IO.Path]::GetFullPath($module);ClrProfilerPath=[IO.Path]::GetFullPath($trace);Receipt=(Join-Path $OutputDirectory 'tool-receipt.json');Directory=[IO.Path]::GetFullPath($OutputDirectory)}
