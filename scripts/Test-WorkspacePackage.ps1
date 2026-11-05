# Objectif : Contrôler toutes les entrées des quatre archives avant extraction et avant tout import explicitement demandé.
#requires -Version 7.6
<#
.SYNOPSIS
Verifies a complete package set without executing it; TestImport explicitly enables an import smoke check afterwards.
.PARAMETER PackageDirectory
Archives and manifests from a trusted source. Hashes alone do not authenticate their author.
.PARAMETER ExtractionDirectory
New destination owned by this verification.
.PARAMETER TestImport
Explicitly executes the verified Core and Git modules after every archive is verified.
.PARAMETER MaxFiles
Maximum file count across the distribution.
.PARAMETER MaxFileBytes
Maximum uncompressed size of one file.
.PARAMETER MaxTotalBytes
Maximum uncompressed distribution size.
#>
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ExtractionDirectory,
    [switch]$TestImport,
    [ValidateRange(1,100000)][int]$MaxFiles=10000,
    [ValidateRange(1,1073741824)][long]$MaxFileBytes=134217728,
    [ValidateRange(1,4294967296)][long]$MaxTotalBytes=536870912
)
$ErrorActionPreference='Stop'
$PackageDirectory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
$ExtractionDirectory=[IO.Path]::GetFullPath($ExtractionDirectory,$PWD.Path)
function Assert-PackageRelativePath {
    <#
    .SYNOPSIS
    Rejects ambiguous, rooted, platform-dependent and traversing archive paths.
    .PARAMETER Path
    Portable slash-separated relative file name.
    #>
    param([string]$Path)
    if([string]::IsNullOrEmpty($Path) -or $Path.Length -gt 512 -or $Path.Contains('\') -or $Path.Contains(':') -or $Path.StartsWith('/') -or $Path.Contains([char]0)){throw 'ArchiveUnsafePath'}
    foreach($part in $Path.Split('/')){
        if(!$part -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '[\x00-\x1f<>"|?*]' -or $part -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'){throw 'ArchiveUnsafePath'}
    }
}
function Assert-PackageDirectoryBounds {
    <#
    .SYNOPSIS
    Bounds ZIP central-directory allocation before ZipArchive materializes entries; ZIP64 and multi-volume inputs are unnecessary here.
    .PARAMETER Path
    Package ZIP path.
    .PARAMETER FileLimit
    Maximum entry count.
    .PARAMETER ByteLimit
    Maximum compressed package size plus bounded metadata.
    #>
    param([string]$Path,[int]$FileLimit,[long]$ByteLimit)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,65557,$true)
    try{
        if($stream.Length -gt $ByteLimit+16777216 -or $stream.Length -lt 22){throw 'ArchiveContainerSizeLimit'}
        $length=[int][Math]::Min(65557,$stream.Length);$tail=[byte[]]::new($length);$stream.Position=$stream.Length-$length
        [void]$stream.ReadExactlyAsync([Memory[byte]]::new($tail)).AsTask().GetAwaiter().GetResult()
        for($index=$length-22;$index -ge 0;$index--){
            if([BitConverter]::ToUInt32($tail,$index) -ne 0x06054b50){continue}
            if($index+22+[BitConverter]::ToUInt16($tail,$index+20) -ne $length){continue}
            $entries=[BitConverter]::ToUInt16($tail,$index+10);$size=[BitConverter]::ToUInt32($tail,$index+12)
            if($entries -eq 65535 -or $entries -gt $FileLimit -or $size -gt $FileLimit*1024 -or [BitConverter]::ToUInt16($tail,$index+4) -ne 0 -or [BitConverter]::ToUInt16($tail,$index+6) -ne 0 -or [BitConverter]::ToUInt16($tail,$index+8) -ne $entries){throw 'ArchiveDirectoryLimit'}
            return
        }
        throw 'ArchiveDirectoryMissing'
    }finally{$stream.Dispose()}
}
function Copy-PackageEntryBounded {
    <#
    .SYNOPSIS
    Hashes actual decompressed bytes while enforcing the declared size before writing excess data.
    .PARAMETER InputStream
    Open ZIP entry.
    .PARAMETER ExpectedBytes
    Validated uncompressed length.
    .PARAMETER OutputStream
    Optional destination; omitted during preflight verification.
    #>
    param([IO.Stream]$InputStream,[long]$ExpectedBytes,[IO.Stream]$OutputStream)
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    $buffer=[byte[]]::new(32768);$total=0L
    try{
        while(($count=$InputStream.ReadAsync($buffer,0,$buffer.Length).GetAwaiter().GetResult()) -gt 0){
            $total+=$count
            if($total -gt $ExpectedBytes){throw 'ArchiveActualSizeLimit'}
            $hash.AppendData($buffer,0,$count)
            if($OutputStream){[void]$OutputStream.WriteAsync($buffer,0,$count).GetAwaiter().GetResult()}
        }
        if($total -ne $ExpectedBytes){throw 'ArchiveTruncatedFile'}
        return [Convert]::ToHexString($hash.GetHashAndReset())
    }finally{$hash.Dispose()}
}
if(Test-Path -LiteralPath $ExtractionDirectory){throw 'ExtractionDirectoryAlreadyExists'}
$expected=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh')
$manifests=@(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.manifest.json' -File)
$archives=@(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.zip' -File)
if($manifests.Count -ne $expected.Count -or $archives.Count -ne $expected.Count){throw 'PackageSetIncompleteOrUnexpected'}
$plans=[Collections.Generic.List[object]]::new()
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$total=0L;$fileCount=0
# Phase one validates and hashes *all* ZIP members. Nothing is extracted or imported.
foreach($manifestFile in $manifests){
    if($manifestFile.Length -gt 8388608){throw 'PackageManifestTooLarge'}
    $manifest=Get-Content -LiteralPath $manifestFile.FullName -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
    $name=[string]$manifest.Module
    if($name -cnotin $expected -or $manifestFile.Name -cne ($name+'.manifest.json') -or !$names.Add($name)){throw 'UnexpectedPackageModule'}
    $declared=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    if($manifest.Files.Count -gt $MaxFiles){throw 'PackageManifestFileLimit'}
    $portable=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($file in $manifest.Files){
        Assert-PackageRelativePath $file.Path
        if(!$portable.Add($file.Path) -or $declared.ContainsKey($file.Path)){throw 'DuplicatePackagePath'}
        if($file.SHA256 -cnotmatch '^[A-F0-9]{64}$' -or $file.Bytes -isnot [long] -and $file.Bytes -isnot [int] -or $file.Bytes -lt 0 -or $file.Bytes -gt $MaxFileBytes){throw 'InvalidPackageFileMetadata'}
        if($name -notmatch '\.Tests\.PoSh$' -and [IO.Path]::GetFileName($file.Path) -match '\.Tests\.|Fixture|\.sqlite$'){throw 'TestOrCaptureInBusinessPackage'}
        $declared.Add($file.Path,$file)
    }
    if(!$declared.ContainsKey($name+'.psd1')){throw 'PackageModuleManifestMissing'}
    $archivePath=Join-Path $PackageDirectory ($name+'.zip')
    Assert-PackageDirectoryBounds $archivePath $MaxFiles $MaxTotalBytes
    $zip=[IO.Compression.ZipFile]::OpenRead($archivePath)
    try{
        if($zip.Entries.Count -ne $declared.Count){throw 'UnexpectedArchiveFiles'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in $zip.Entries){
            Assert-PackageRelativePath $entry.FullName
            if(!$entry.FullName.StartsWith($name+'/',[StringComparison]::Ordinal)){throw 'ArchiveModuleBoundaryViolation'}
            $relative=$entry.FullName.Substring($name.Length+1)
            if(!$declared.ContainsKey($relative) -or !$seen.Add($relative)){throw 'UndeclaredOrDuplicateArchiveFile'}
            $mode=($entry.ExternalAttributes -shr 16) -band 0xf000
            if($mode -notin @(0,0x8000)){throw 'ArchiveSpecialFileRejected'}
            $file=$declared[$relative]
            $total+=$entry.Length;$fileCount++
            if($entry.Length -ne $file.Bytes -or $entry.Length -gt $MaxFileBytes -or $total -gt $MaxTotalBytes -or $fileCount -gt $MaxFiles){throw 'ArchiveSizeLimit'}
            $stream=$entry.Open()
            try{$hash=Copy-PackageEntryBounded $stream $entry.Length}finally{$stream.Dispose()}
            if($hash -cne $file.SHA256){throw 'ArchiveHashMismatch'}
        }
    }finally{$zip.Dispose()}
    $plans.Add(@{Name=$name;Archive=$archivePath;Files=$declared})
}
# Phase two copies only validated entries and rechecks hashes against replacement races.
$ExtractionDirectory=[IO.Path]::GetFullPath($ExtractionDirectory)
$ownedDirectory=$ExtractionDirectory+'.verify-'+[guid]::NewGuid().ToString('N')
if($IsWindows){[void][IO.Directory]::CreateDirectory($ownedDirectory)}else{[void][IO.Directory]::CreateDirectory($ownedDirectory,([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute))}
try{[IO.Directory]::Move($ownedDirectory,$ExtractionDirectory)}catch{[IO.Directory]::Delete($ownedDirectory);throw}
foreach($plan in $plans){
    $zip=[IO.Compression.ZipFile]::OpenRead($plan.Archive)
    try{
        foreach($entry in $zip.Entries){
            Assert-PackageRelativePath $entry.FullName
            if(!$entry.FullName.StartsWith($plan.Name+'/',[StringComparison]::Ordinal)){throw 'ArchiveChangedAfterValidation'}
            $relative=$entry.FullName.Substring($plan.Name.Length+1)
            if(!$plan.Files.ContainsKey($relative) -or $entry.Length -ne $plan.Files[$relative].Bytes){throw 'ArchiveChangedAfterValidation'}
            $destination=Join-Path $ExtractionDirectory $entry.FullName
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            $inputStream=$entry.Open();$outputStream=[IO.FileStream]::new($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,32768,$true)
            try{$hash=Copy-PackageEntryBounded $inputStream $entry.Length $outputStream}finally{$outputStream.Dispose();$inputStream.Dispose()}
            if($hash -cne $plan.Files[$relative].SHA256){throw 'ArchiveChangedAfterValidation'}
        }
        if($zip.Entries.Count -ne $plan.Files.Count){throw 'ArchiveChangedAfterValidation'}
    }finally{$zip.Dispose()}
}
$handlers=$null
if($TestImport){
    $previousModulePath=$env:PSModulePath
    try{
        $env:PSModulePath=$ExtractionDirectory+[IO.Path]::PathSeparator+$previousModulePath
        Import-Module (Join-Path $ExtractionDirectory 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -Force
        Import-Module (Join-Path $ExtractionDirectory 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1') -Force
        $handlers=@(Get-QuietHandler).Count
    }finally{$env:PSModulePath=$previousModulePath}
}
[pscustomobject]@{Verified=$true;Authenticated=$false;ImportTested=[bool]$TestImport;ExtractionDirectory=$ExtractionDirectory;Files=$fileCount;UncompressedBytes=$total;Handlers=$handlers}
