#requires -Version 7.6
<#
.SYNOPSIS
Exports or installs the revision-bound compiled distributions shared by GitHub PR jobs.
.PARAMETER Mode
Export, Verify a cached archive, or Import into a fresh checkout.
.PARAMETER WorkspaceRoot
Checkout of the revision that produced the distributions.
.PARAMETER Directory
Directory containing build.zip and its checksum receipt.
.PARAMETER Revision
Exact checkout revision, normally GITHUB_SHA.
.PARAMETER Baseline
Includes the optional IL engine publications in an export.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Export','Verify','Import')][string]$Mode,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$Directory='./artifacts/ci-build',
    [ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision=$env:GITHUB_SHA,
    [switch]$Baseline
)
$ErrorActionPreference='Stop'
if(!$Revision -or ($Baseline -and $Mode -cne 'Export')){throw 'CiBuildArtifactArgumentsInvalid'}
$root=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
$directoryPath=[IO.Path]::GetFullPath($Directory,$PWD.Path)
$archivePath=[IO.Path]::Combine($directoryPath,'build.zip')
$receiptPath=[IO.Path]::Combine($directoryPath,'receipt.json')
$baselinePath='artifacts/ci-build-baseline'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
$libraries=@(Get-QuietWorkspaceBuildProjects $root | ForEach-Object {
    if($_.Output -cnotmatch '\A(src/.+?/lib)/'){throw "CiBuildArtifactOutputOutsideModuleLib: $($_.Output)"}
    $Matches[1]
} | Sort-Object -Unique)
if(!$libraries.Count){throw 'CiBuildArtifactOutputsMissing'}
if(!$PSCmdlet.ShouldProcess($directoryPath,"$Mode compiled CI distributions")){return}

if($Mode -ceq 'Export'){
    if([IO.File]::Exists($archivePath) -or [IO.File]::Exists($receiptPath)){throw 'CiBuildArtifactAlreadyExists'}
    [void][IO.Directory]::CreateDirectory($directoryPath)
    $paths=@($libraries)
    if($Baseline){$paths+=$baselinePath}
    $zip=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($path in $paths){
            $source=[IO.Path]::Combine($root,$path)
            foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force){
                if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'CiBuildArtifactLinkRejected'}
                $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
                $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Fastest)
            }
        }
    }finally{$zip.Dispose()}
    $receipt=[ordered]@{SchemaVersion=1;Revision=$Revision;SHA256=(Get-FileHash -LiteralPath $archivePath).Hash;Baseline=[bool]$Baseline}
    [IO.File]::WriteAllText($receiptPath,($receipt | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    return
}

$receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
if($receipt.SchemaVersion -ne 1 -or $receipt.Revision -cne $Revision -or $receipt.Baseline -isnot [bool] -or
    $receipt.SHA256 -cne (Get-FileHash -LiteralPath $archivePath).Hash){throw 'CiBuildArtifactReceiptMismatch'}
if($Mode -ceq 'Verify'){return}

$paths=@($libraries)
if($receipt.Baseline){$paths+=$baselinePath}
$staging=[IO.Directory]::CreateTempSubdirectory('quietcli-build-').FullName
try{
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath,$staging)
    foreach($path in $paths){
        if(![IO.Directory]::Exists([IO.Path]::Combine($staging,$path))){throw "CiBuildArtifactDistributionMissing: $path"}
        if(Test-Path -LiteralPath ([IO.Path]::Combine($root,$path))){throw "CiBuildArtifactDestinationExists: $path"}
    }
    foreach($path in $paths){
        $source=[IO.Path]::Combine($staging,$path)
        $target=[IO.Path]::Combine($root,$path)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        # Copy preserves the workspace layout when RUNNER_TEMP is on another volume.
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        if($IsLinux){
            foreach($apphost in Get-ChildItem -LiteralPath $target -Filter 'QuietCli.Engine' -File -Recurse){
                [IO.File]::SetUnixFileMode($apphost.FullName,[IO.File]::GetUnixFileMode($apphost.FullName) -bor [IO.UnixFileMode]::UserExecute)
            }
        }
    }
}finally{[IO.Directory]::Delete($staging,$true)}
Write-Host "Installed compiled CI distributions for $Revision."
