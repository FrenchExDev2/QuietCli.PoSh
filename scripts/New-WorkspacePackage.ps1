# Objectif : Construire des archives de modules avec manifestes SHA-256, sans inclure les tests dans les modules métier.
#requires -Version 7.6
<#
.SYNOPSIS
Packages four independently versioned modules; never publishes them.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER OutputDirectory
New artifact directory.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
Assert-QuietPtyPublications $WorkspaceRoot
foreach($framework in @('net10.0','net11.0')){$null=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Git.PoSh/lib/parser/'+$framework)}
$null=Test-QuietBuildManifest $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
$null=Test-QuietBuildManifest $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/engine'
foreach($rid in (Get-QuietRuntimeTargets $WorkspaceRoot).Rid){
    $build=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid)
    if($build.RuntimeIdentifier -cne $rid){throw ('EngineDistributionMissing: '+$rid)}
}
if(Test-Path -LiteralPath $OutputDirectory){throw 'PackageOutputAlreadyExists'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$lock=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'repositories.lock.json') -Encoding utf8 -Raw|ConvertFrom-Json
foreach($repository in $lock.Projects){
    $source=Join-Path $WorkspaceRoot $repository.Path;$stage=Join-Path $OutputDirectory $repository.Name
    [void][IO.Directory]::CreateDirectory($stage)
    foreach($item in Get-ChildItem -LiteralPath $source -Force){
        if($item.Name -in @('.git','.gitignore','bin','obj','artifacts','engine','fixture','engine-tests','parser-tests','tools','recall-tools','global.json')){continue}
        Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse
    }
    if(!(Test-Path -LiteralPath (Join-Path $stage ($repository.Name+'.psd1')))){throw 'PackageManifestMissing'}
    $files=foreach($file in Get-ChildItem -LiteralPath $stage -Recurse -File|Sort-Object FullName){@{Path=[IO.Path]::GetRelativePath($stage,$file.FullName).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;Bytes=$file.Length}}
    Write-WorkspaceJson (Join-Path $OutputDirectory ($repository.Name+'.manifest.json')) @{Module=$repository.Name;Revision=(Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD'));SourceSHA256=$repository.SourceSHA256;Files=@($files)}
    $archive=Join-Path $OutputDirectory ($repository.Name+'.zip')
    $output=[IO.FileStream]::new($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,32768,$true)
    $zip=[IO.Compression.ZipArchive]::new($output,[IO.Compression.ZipArchiveMode]::Create,$false,[Text.Encoding]::UTF8)
    try{
        [string[]]$paths=@(Get-ChildItem -LiteralPath $stage -Recurse -File|ForEach-Object{$_.FullName})
        [Array]::Sort($paths,[StringComparer]::Ordinal)
        foreach($file in $paths){
            $relative=$repository.Name+'/'+[IO.Path]::GetRelativePath($stage,$file).Replace('\','/')
            $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
            $entry.ExternalAttributes=-2119958528
            $inputStream=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,32768,$true)
            $entryStream=$entry.Open()
            try{[void]$inputStream.CopyToAsync($entryStream).GetAwaiter().GetResult()}finally{$entryStream.Dispose();$inputStream.Dispose()}
        }
    }finally{$zip.Dispose();$output.Dispose()}
    [pscustomobject]@{Module=$repository.Name;Archive=$archive;SHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;Published=$false}
}
