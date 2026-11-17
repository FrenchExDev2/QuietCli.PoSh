#Objective: Returns checksum-pinned diagnostic and script test packages and prepares them in an isolated verified cache.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunEncoding.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-RunProfilerPackages {
    <#
    .SYNOPSIS
    Returns the two checksum-pinned diagnostic packages and their required entrypoints.
    .PARAMETER Module
    Selects profiler and/or dottrace, once each in catalogue order. Defaults to both.
    #>
    param([ValidateNotNullOrEmpty()][ValidateCount(1,2)][ValidateSet('profiler','dottrace')][string[]]$Module=@('profiler','dottrace'))
    $catalogue=@(
        @{ Name = 'Profiler'; Version = '4.3.0'; Url = 'https://www.powershellgallery.com/api/v2/package/Profiler/4.3.0'; SHA256 = '4BB44C89117EABAAFDA17B3DFFA622CFDFC770ED05EB6084469203C66DB43E0F'; Entrypoint = 'Profiler.psd1' }
        @{ Name = 'dotnet-trace'; Version = '10.0.750501'; Url = 'https://api.nuget.org/v3-flatcontainer/dotnet-trace/10.0.750501/dotnet-trace.10.0.750501.nupkg'; SHA256 = 'EF17F25724A55F9685BFAF8506A778EA87C2B62783ECA2CA73263226128B0D4E'; Entrypoint = 'tools/net8.0/any/dotnet-trace.dll' }
    )
    foreach($package in $catalogue){
        $key=if($package.Name -ceq 'Profiler'){'profiler'}else{'dottrace'}
        if($Module -contains $key){$package}
    }
}

function Get-RunTestToolPackages {
    <#
    .SYNOPSIS
    Returns the checksum-pinned script test tools (Pester 6.2.0, PSScriptAnalyzer 1.25.0) and their entrypoints.
    .PARAMETER Tool
    Selects pester and/or scriptanalyzer, once each in catalogue order. Defaults to both.
    #>
    param([ValidateNotNullOrEmpty()][ValidateCount(1,2)][ValidateSet('pester','scriptanalyzer')][string[]]$Tool=@('pester','scriptanalyzer'))
    $catalogue=@(
        @{ Name = 'Pester'; Version = '6.2.0'; Url = 'https://www.powershellgallery.com/api/v2/package/Pester/6.2.0'; SHA256 = 'E6AC7418D4F12500269AACA58AE56CF1CAAFBBF1AFA2CEC334E289D1CF50A239'; Entrypoint = 'Pester.psd1' }
        @{ Name = 'PSScriptAnalyzer'; Version = '1.25.0'; Url = 'https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.25.0'; SHA256 = '14E634C828EB98EFB9F40B2918BA90F139ED5ECCDF663A2A747736D996995D60'; Entrypoint = 'PSScriptAnalyzer.psd1' }
    )
    foreach($package in $catalogue){
        $key=if($package.Name -ceq 'Pester'){'pester'}else{'scriptanalyzer'}
        if($Tool -contains $key){$package}
    }
}

function Get-QuietTestToolDirectory {
    <#
    .SYNOPSIS
    Returns the default isolated test tool cache, <workspace>/.cache/test-tools (ignored by Git).
    .PARAMETER WorkspaceRoot
    Repository root.
    #>
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkspaceRoot)
    [IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot,'.cache','test-tools'))
}

function Initialize-QuietTestTools {
    <#
    .SYNOPSIS
    Prepares the pinned script test tools in an isolated cache and returns their module manifest paths.
    .PARAMETER WorkspaceRoot
    Repository root; the default cache is <workspace>/.cache/test-tools.
    .PARAMETER OutputDirectory
    Optional explicit cache directory.
    .PARAMETER Tool
    pester and/or scriptanalyzer; defaults to both.
    .PARAMETER Offline
    Fails on a cache miss instead of downloading.
    .PARAMETER DownloadBytes
    Optional byte provider (tests); checksum verification is always applied.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkspaceRoot,[string]$OutputDirectory,[ValidateNotNullOrEmpty()][ValidateCount(1,2)][ValidateSet('pester','scriptanalyzer')][string[]]$Tool=@('pester','scriptanalyzer'),[switch]$Offline,[scriptblock]$DownloadBytes)
    if([string]::IsNullOrWhiteSpace($OutputDirectory)){$OutputDirectory=Get-QuietTestToolDirectory -WorkspaceRoot $WorkspaceRoot}
    $cache=Initialize-RunToolCache -OutputDirectory $OutputDirectory -Packages @(Get-RunTestToolPackages -Tool $Tool) -Offline:$Offline -DownloadBytes $DownloadBytes
    [pscustomobject][ordered]@{ PesterModulePath = $cache.Paths['Pester']; ScriptAnalyzerModulePath = $cache.Paths['PSScriptAnalyzer']; Receipt = $cache.Receipt; Directory = $cache.Directory }
}

function Initialize-RunToolCache {
    <#
    .SYNOPSIS
    Verifies cached or downloaded packages before extraction, then publishes a local tool receipt.
    .PARAMETER OutputDirectory
    Isolated tool cache; no global installation is performed.
    .PARAMETER Packages
    Explicit package specifications; production callers supply Get-RunProfilerPackages or Get-RunTestToolPackages.
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
            $directory = [IO.Path]::Combine($OutputDirectory,$package.Name)
            [void][IO.Directory]::CreateDirectory($directory)
            $archive = [IO.Path]::Combine($directory,($package.Name + '.' + $package.Version + '.nupkg'))
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
            $entrypoint = [IO.Path]::Combine($directory,$package.Entrypoint)
            if (-not [IO.File]::Exists($entrypoint)) { [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive, $directory, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() }
            if (-not [IO.File]::Exists($entrypoint)) { throw 'ProfilerPackageLayoutMismatch' }
            $paths[$package.Name] = [IO.Path]::GetFullPath($entrypoint)
        }
    }
    finally { if ($null -ne $client) { $client.Dispose() } }
    $receipt = [IO.Path]::Combine($OutputDirectory,'tool-receipt.json')
    $result = [ordered]@{ ProfilerModulePath = $paths['Profiler']; ClrProfilerPath = $paths['dotnet-trace']; Paths = $paths; Receipt = $receipt; Directory = $OutputDirectory }
    Write-RunTextFile -Path $receipt -Text ((ConvertTo-Json -InputObject @{ Packages = $Packages; ProfilerModulePath = $result.ProfilerModulePath; ClrProfilerPath = $result.ClrProfilerPath; Paths = $paths; GlobalInstallation = $false } -Depth 8) + "`n")
    return [pscustomobject]$result
}
Export-ModuleMember -Function Get-RunProfilerPackages, Get-RunTestToolPackages, Get-QuietTestToolDirectory, Initialize-QuietTestTools, Initialize-RunToolCache
