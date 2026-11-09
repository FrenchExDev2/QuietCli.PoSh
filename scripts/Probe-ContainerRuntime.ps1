#requires -Version 7.6
<#
.SYNOPSIS
Collects Linux host identity and explicitly loads verified SQLite assets inside an owned diagnostic container.
.PARAMETER OutputPath
Owned JSON report path inside the container.
.PARAMETER AssetsRoot
Read-only diagnostic input convention: RID directories and assets.json beside them.
.PARAMETER ExpectedRuntimeIdentifier
Portable target whose SQLite ABI is checked independently from the reported RID.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$AssetsRoot,
    [Parameter(Mandatory)][ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ci.Process.ps1')
. (Join-Path $PSScriptRoot 'RuntimeTargets.ps1')
function Save-RuntimeProbe {
    <# .SYNOPSIS
    Saves each phase before a native load, retaining evidence even if the child crashes.
    #>
    [void][IO.File]::WriteAllTextAsync($OutputPath,($report|ConvertTo-Json -Depth 12).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
function Invoke-RuntimeNativeProbe {
    <# .SYNOPSIS
    Loads exactly one checksum-verified diagnostic asset without initializing a database or the product.
    .PARAMETER Rid
    Literal directory selected by either the reported or requested RID.
    #>
    param([string]$Rid)
    if($Rid -cnotmatch '^[a-z][a-z0-9_.-]+$' -or $Rid.Contains('..')){return @{Outcome='InvalidRid';HashMatches=$false}}
    $file=Join-Path $AssetsRoot ($Rid+'/libe_sqlite3.so')
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){return @{Outcome='Missing';HashMatches=$false;Path=$file}}
    $entries=@($inventory|Where-Object Rid -CEQ $Rid)
    $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if($entries.Count -ne 1 -or $hash -cne $entries[0].SHA256){return @{Outcome='IntegrityFailure';HashMatches=$false;Path=$file}}
    $native=Get-QuietElfHeader $file
    $family=if($Rid.Contains('-musl-')){'Musl'}else{'Gnu'}
    if($native.Machine -ne $report.ElfMachine -or $family -cne $report.Libc){return @{Outcome='SkippedIncompatibleHost';HashMatches=$true;Path=$file;SHA256=$hash}}
    $handle=[IntPtr]::Zero
    try{
        $handle=[Runtime.InteropServices.NativeLibrary]::Load($file)
        $address=[Runtime.InteropServices.NativeLibrary]::GetExport($handle,'sqlite3_libversion')
        $callback=[Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($address,[QuietRuntimeSqliteVersion])
        $version=[Runtime.InteropServices.Marshal]::PtrToStringUTF8($callback.Invoke())
        @{Outcome='Success';HashMatches=$true;Path=$file;SHA256=$hash;SQLiteVersion=$version}
    }catch{@{Outcome='Failed';HashMatches=$true;Path=$file;SHA256=$hash;Error=$_.Exception.Message}}
    finally{if($handle -ne [IntPtr]::Zero){[Runtime.InteropServices.NativeLibrary]::Free($handle)}}
}
$inventory=Get-Content -LiteralPath (Join-Path $AssetsRoot 'assets.json') -Raw -Encoding utf8|ConvertFrom-Json
$executable=[Environment]::ProcessPath
$elf=Get-QuietElfHeader $executable
$maps=@(Get-Content -LiteralPath '/proc/self/maps' -Encoding utf8 | Where-Object {$_ -match '/(?:ld-musl[^ /]*|libc\.musl[^ /]*|libc\.so\.6)(?:\s|$)'} | ForEach-Object {($_ -split '\s+')[-1]} | Select-Object -Unique)
$libc=if(@($maps|Where-Object {$_ -match 'musl'}).Count){'Musl'}elseif(@($maps|Where-Object {$_ -match 'libc\.so\.6$'}).Count){'Gnu'}else{'Unknown'}
$os=@{}
foreach($line in Get-Content -LiteralPath '/etc/os-release' -Encoding utf8){if($line -match '^(ID|VERSION_ID)=(.*)$'){$os[$Matches[1]]=$Matches[2].Trim('"',"'")}}
$report=[ordered]@{SchemaVersion=1;Phase='Identity';Linux=$IsLinux;PowerShellVersion=$PSVersionTable.PSVersion.ToString();RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;
    FrameworkMajor=[Environment]::Version.Major;FrameworkDescription=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;RuntimeDirectory=[Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory();
    ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant();OSArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant();
    HostExecutable=$executable;ElfMachine=$elf.Machine;Libc=$libc;LoadedLibcPaths=$maps;OSRelease=$os;
    RuntimeRoots=@{DOTNET_ROOT=$env:DOTNET_ROOT;DOTNET_ROOT_X64=$env:DOTNET_ROOT_X64;DOTNET_ROOT_ARM64=$env:DOTNET_ROOT_ARM64};RawNative=$null;ExpectedNative=$null}
Save-RuntimeProbe
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
/// <summary>SQLite's no-argument version function; used only by an explicit diagnostic load.</summary>
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate IntPtr QuietRuntimeSqliteVersion();
'@
$report.Phase='RawNativeLoad';Save-RuntimeProbe
$report.RawNative=Invoke-RuntimeNativeProbe $report.RuntimeIdentifier
$report.Phase='ExpectedNativeLoad';Save-RuntimeProbe
$report.ExpectedNative=Invoke-RuntimeNativeProbe $ExpectedRuntimeIdentifier
$report.Phase='Complete';Save-RuntimeProbe
