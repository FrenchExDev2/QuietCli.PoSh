#Objective: Validates the three invariant-culture, finite, nonnegative durations returned by a measurement child.
#requires -Version 7.6
function ConvertFrom-RunColdSample {
    <#
    .SYNOPSIS
    Validates the three invariant-culture, finite, nonnegative durations returned by a measurement child.
    .PARAMETER Fields
    Import, first-call and second-call milliseconds, without the RESULT marker.
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$Fields)
    if ($null -eq $Fields -or $Fields.Count -ne 3) { throw 'ColdSampleInvalid' }
    $values = [double[]]::new(3)
    for ($index = 0; $index -lt 3; $index++) {
        $value = 0.0
        if (-not [double]::TryParse([string]$Fields[$index], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or -not [double]::IsFinite($value) -or $value -lt 0) { throw 'ColdSampleInvalid' }
        $values[$index] = $value
    }
    return [pscustomobject]@{ Import = $values[0]; First = $values[1]; Second = $values[2] }
}
function Get-RunModuleFootprintBytes {
    <#
    .SYNOPSIS
    Total on-disk size, in bytes, of every file under a module's root directory.
    .DESCRIPTION
    The module root is the manifest's containing directory, so this covers the manifest itself plus every
    assembly it loads (managed and native, IL or ReadyToRun). A ReadyToRun build embeds native code the IL build
    does not, so this number is expected to grow for a ReadyToRun candidate even when cold-start time improves.
    .PARAMETER ManifestPath
    Path to the module's .psd1 manifest.
    #>
    param([Parameter(Mandatory)][string]$ManifestPath)
    $root = Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))
    $files = [IO.Directory]::EnumerateFiles($root, '*', [IO.SearchOption]::AllDirectories)
    $total = 0L
    foreach ($file in $files) { $total += [IO.FileInfo]::new($file).Length }
    return $total
}

function Get-RunModuleHostedPathBytes {
    <#
    .SYNOPSIS
    On-disk size, in bytes, of only the engine files on the hosting path this process actually loads.
    .DESCRIPTION
    Get-RunModuleFootprintBytes sums the whole module directory, including every bundled RID whether or not it
    is used; this isolates the actual CLR/RID slot selected by Protocol.ps1, excluding unused RID directories.
    .PARAMETER ManifestPath
    Path to the module's .psd1 manifest.
    .PARAMETER RuntimeIdentifier
    RID used to select a matching ReadyToRun slot or the portable fallback for the actual CLR.
    Defaults to this process's own RID.
    #>
    param([Parameter(Mandatory)][string]$ManifestPath, [string]$RuntimeIdentifier = [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)
    $root = Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))
    $protocol=[IO.Path]::Combine($root,'src/Protocol.ps1')
    if(Test-Path -LiteralPath $protocol){
        . $protocol
        $target=Resolve-QuietManagedTarget -ModuleRoot $root -RuntimeIdentifier $RuntimeIdentifier
        $hosted=[IO.Path]::Combine($root,$target.Directory)
    }else{$hosted=[IO.Path]::Combine($root,$(if([Environment]::Version.Major -ge 11){'lib/engine'}else{'lib/inprocess'}))}
    if (-not (Test-Path -LiteralPath $hosted -PathType Container)) { throw "RunModuleHostedPathMissing: $hosted" }
    $total = 0L
    foreach ($file in [IO.Directory]::EnumerateFiles($hosted, '*', [IO.SearchOption]::AllDirectories)) {
        if([IO.Path]::GetRelativePath($hosted,$file) -cmatch '^(win|linux|linux-musl)-(x64|arm64)[\\/]'){continue}
        $total += [IO.FileInfo]::new($file).Length
    }
    return $total
}

function Get-RunModulePackageBytes {
    <#
    .SYNOPSIS
    Packages a module with Compress-PSResource and returns the resulting .nupkg size, in bytes.
    .DESCRIPTION
    Get-RunModuleFootprintBytes reports the raw on-disk sum; this reports what a PSGallery-style feed would
    actually serve, after nupkg (zip) compression. The two can diverge: native ReadyToRun code and already-compressed
    managed IL do not compress the same way, so a candidate's compressed size is not guaranteed to track its raw
    footprint. Packages into a throwaway temporary directory and removes it afterward; never writes into the
    module's own directory.
    .PARAMETER ManifestPath
    Path to the module's .psd1 manifest; its containing directory is packaged as-is.
    #>
    param([Parameter(Mandatory)][string]$ManifestPath)
    $root = Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))
    $scratch = [IO.Path]::Combine(([IO.Path]::GetTempPath()),('quietcli-coldstart-pkg-' + [guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($scratch)
    try {
        $compressed = Compress-PSResource -Path $root -DestinationPath $scratch -PassThru -ErrorAction Stop
        $path = if ($compressed -is [IO.FileInfo]) { $compressed.FullName } else { [string]$compressed }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RunModulePackageMissing: $path" }
        return [IO.FileInfo]::new($path).Length
    }
    finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Export-ModuleMember -Function ConvertFrom-RunColdSample, Get-RunModuleFootprintBytes, Get-RunModuleHostedPathBytes, Get-RunModulePackageBytes
