#Objective: Returns the two checksum-pinned diagnostic packages and their required entrypoints.
#requires -Version 7.6
Import-Module (Join-Path $PSScriptRoot 'RunEncoding.psm1')

function Get-RunProfilerPackages {
    <#
    .SYNOPSIS
    Returns the two checksum-pinned diagnostic packages and their required entrypoints.
    #>
    @(
        @{ Name = 'Profiler'; Version = '4.3.0'; Url = 'https://www.powershellgallery.com/api/v2/package/Profiler/4.3.0'; SHA256 = '4BB44C89117EABAAFDA17B3DFFA622CFDFC770ED05EB6084469203C66DB43E0F'; Entrypoint = 'Profiler.psd1' }
        @{ Name = 'dotnet-trace'; Version = '10.0.750501'; Url = 'https://api.nuget.org/v3-flatcontainer/dotnet-trace/10.0.750501/dotnet-trace.10.0.750501.nupkg'; SHA256 = 'EF17F25724A55F9685BFAF8506A778EA87C2B62783ECA2CA73263226128B0D4E'; Entrypoint = 'tools/net8.0/any/dotnet-trace.dll' }
    )
}

function Initialize-RunToolCache {
    <#
    .SYNOPSIS
    Verifies cached or downloaded packages before extraction, then publishes a local tool receipt.
    .PARAMETER OutputDirectory
    Isolated tool cache; no global installation is performed.
    .PARAMETER Packages
    Explicit package specifications; production callers supply Get-RunProfilerPackages.
    .PARAMETER Offline
    Rejects a cache miss before constructing an HTTP client.
    .PARAMETER DownloadBytes
    Optional byte provider for an explicit package URL; checksum verification is always applied.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][hashtable[]]$Packages, [switch]$Offline, [scriptblock]$DownloadBytes)
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $paths = @{}
    $client = $null
    try {
        foreach ($package in $Packages) {
            $directory = Join-Path $OutputDirectory $package.Name
            [void][IO.Directory]::CreateDirectory($directory)
            $archive = Join-Path $directory ($package.Name + '.' + $package.Version + '.nupkg')
            if (-not [IO.File]::Exists($archive)) {
                if ($Offline) { throw 'ProfilerOfflineCacheMiss' }
                if ($DownloadBytes) { $bytes = [byte[]](& $DownloadBytes $package.Url) }
                else {
                    if ($null -eq $client) { $client = [Net.Http.HttpClient]::new() }
                    $bytes = $client.GetByteArrayAsync($package.Url).GetAwaiter().GetResult()
                }
                if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $package.SHA256) { throw 'ProfilerDownloadDigestMismatch' }
                [void][IO.File]::WriteAllBytesAsync($archive, $bytes).GetAwaiter().GetResult()
            }
            $cached = [IO.File]::ReadAllBytesAsync($archive).GetAwaiter().GetResult()
            if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($cached)) -cne $package.SHA256) { throw 'ProfilerCacheDigestMismatch' }
            $entrypoint = Join-Path $directory $package.Entrypoint
            if (-not [IO.File]::Exists($entrypoint)) { [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive, $directory, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() }
            if (-not [IO.File]::Exists($entrypoint)) { throw 'ProfilerPackageLayoutMismatch' }
            $paths[$package.Name] = [IO.Path]::GetFullPath($entrypoint)
        }
    }
    finally { if ($null -ne $client) { $client.Dispose() } }
    $receipt = Join-Path $OutputDirectory 'tool-receipt.json'
    $result = [ordered]@{ ProfilerModulePath = $paths['Profiler']; ClrProfilerPath = $paths['dotnet-trace']; Receipt = $receipt; Directory = $OutputDirectory }
    Write-RunTextFile -Path $receipt -Text ((ConvertTo-Json -InputObject @{ Packages = $Packages; ProfilerModulePath = $result.ProfilerModulePath; ClrProfilerPath = $result.ClrProfilerPath; GlobalInstallation = $false } -Depth 8) + "`n")
    return [pscustomobject]$result
}
Export-ModuleMember -Function Get-RunProfilerPackages, Initialize-RunToolCache
