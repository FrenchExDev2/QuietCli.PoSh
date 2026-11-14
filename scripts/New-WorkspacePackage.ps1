#requires -Version 7.6
<#
.SYNOPSIS
Packages every locked, independently versioned source/test module; never publishes them.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER OutputDirectory
New artifact directory.
.PARAMETER RequireReadyToRun
Rejects packages unless both CLR builds are verified ReadyToRun for all six release RIDs.
.PARAMETER Module
Optional exact source project names to package; omitted packages are not archived.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory,[switch]$RequireReadyToRun,[string[]]$Module=@())
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-WorkspacePackage')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/AgentDocuments.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
Assert-QuietPtyPublications $WorkspaceRoot
$lock=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'repositories.lock.json')) -Encoding utf8 -Raw|ConvertFrom-Json
foreach($name in $Module){if($name -cnotin @($lock.Projects.Name)){throw ('PackageProjectUnknown: '+$name)}}
$roots=if($Module.Count){$Module}else{@($lock.Projects.Name)}
$selected=@(Get-QuietWorkspaceBuildSelection -WorkspaceRoot $WorkspaceRoot -Module $roots)
foreach($distribution in @(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $selected)){
    $null=Test-QuietBuildManifest $WorkspaceRoot $distribution.Output
}
foreach($rid in @(if($selected -ccontains 'FrenchExDev2.QuietCli.Core.PoSh'){(Get-QuietRuntimeTargets $WorkspaceRoot).Rid})){
    $build=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid)
    if($build.RuntimeIdentifier -cne $rid){throw ('EngineDistributionMissing: '+$rid)}
    if($RequireReadyToRun){
        foreach($slot in @('engine','inprocess')){
            $portable=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/'+$slot)
            $compiled=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/'+$slot+'/'+$rid)
            if($rid -cnotin @($portable.ReadyToRunTargets) -or !$compiled.ReadyToRun -or $compiled.RuntimeIdentifier -cne $rid -or $compiled.Configuration -cne 'Release'){throw ('ReadyToRunDistributionMissing: '+$slot+'/'+$rid)}
        }
    }
}
if(Test-Path -LiteralPath $OutputDirectory){throw 'PackageOutputAlreadyExists'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
foreach($repository in $lock.Projects | Where-Object {!$Module.Count -or $_.Name -cin $Module}){
    $source=[IO.Path]::Combine($WorkspaceRoot,$repository.Path);$stage=[IO.Path]::Combine($OutputDirectory,$repository.Name)
    [void][IO.Directory]::CreateDirectory($stage)
    foreach($item in Get-ChildItem -LiteralPath $source -Force){
        if($item.Name -in @('.git','.gitignore','bin','obj','artifacts','engine','fixture','engine-tests','parser-tests','tools','recall-tools','global.json')){continue}
        Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse
    }
    if(!(Test-Path -LiteralPath ([IO.Path]::Combine($stage,($repository.Name+'.psd1'))))){throw 'PackageManifestMissing'}
    if($repository.Name -eq 'FrenchExDev2.QuietCli.Core.PoSh'){Copy-QuietProductionAgentDocuments -WorkspaceRoot $WorkspaceRoot -ModuleDirectory $stage}
    $files=foreach($file in Get-ChildItem -LiteralPath $stage -Recurse -File|Sort-Object FullName){@{Path=[IO.Path]::GetRelativePath($stage,$file.FullName).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;Bytes=$file.Length}}
    Write-WorkspaceJson ([IO.Path]::Combine($OutputDirectory,($repository.Name+'.manifest.json'))) @{Module=$repository.Name;Revision=(Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD'));SourceSHA256=$repository.SourceSHA256;Files=@($files)}
    $archive=[IO.Path]::Combine($OutputDirectory,($repository.Name+'.zip'))
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
