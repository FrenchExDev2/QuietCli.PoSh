# Objectif : Établir la provenance et les licences des ressources existantes sans téléchargement ni remplacement implicite.
#requires -Version 7.6
<#
.SYNOPSIS
Creates a resource lock from an explicitly supplied inspected source manifest and preserves its license evidence.
.PARAMETER ReferenceRoot
Existing source module containing resources/dependencies.json and third_party.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$ReferenceRoot,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$source=Get-Content (Join-Path $ReferenceRoot 'resources/dependencies.json') -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
$moduleRoot=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
$files=[Collections.Generic.List[object]]::new();$packages=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($file in Get-ChildItem (Join-Path $moduleRoot 'resources') -Recurse -File|Where-Object Name -NE 'dependencies.lock.json'){
    $relative=[IO.Path]::GetRelativePath($moduleRoot,$file.FullName).Replace('\','/')
    $original=$relative.Replace('resources/tokenizers/','resources/runtime/')
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $declared=@($source.Files|Where-Object Path -CEQ $original)
    if($declared.Count -eq 1){if($hash -cne $declared[0].SHA256){throw ('ReferenceResourceMismatch: '+$relative)}}
    elseif($relative -notlike 'resources/transport/*.sha256'){throw ('UnattributedResource: '+$relative)}
    $package=if($relative -like 'resources/runtime/*'){'sqlitepclraw.lib.e_sqlite3'}elseif($relative -like 'resources/transport/*'){'quietcli-pty'}else{
        switch($file.Name){
            'Microsoft.Bcl.Memory.dll' {'microsoft.bcl.memory'}
            'Microsoft.ML.Tokenizers.dll' {'microsoft.ml.tokenizers'}
            'Microsoft.ML.Tokenizers.Data.O200kBase.dll' {'microsoft.ml.tokenizers.data.o200kbase'}
            'Microsoft.ML.Tokenizers.Data.Cl100kBase.dll' {'microsoft.ml.tokenizers.data.cl100kbase'}
            default {throw 'UnknownManagedResource'}
        }
    }
    $assemblyVersion=$null
    if($relative -like 'resources/tokenizers/*'){$assemblyVersion=[Reflection.AssemblyName]::GetAssemblyName($file.FullName).Version.ToString()}
    $version=if($package -eq 'quietcli-pty'){'source-build'}else{$source.Packages[$package]}
    $files.Add(@{Path=$relative;SHA256=$hash;Bytes=$file.Length;Package=$package;Version=$version;AssemblyVersion=$assemblyVersion;ReferencePath=$original})
    if(!$packages.ContainsKey($package)){
        $licenseSource=Join-Path $ReferenceRoot ('third_party/'+$(if($package -eq 'quietcli-pty'){'transport'}else{$package}))
        $licenseDestination=Join-Path $moduleRoot ('third_party/'+$package)
        [void][IO.Directory]::CreateDirectory($licenseDestination)
        foreach($license in Get-ChildItem -LiteralPath $licenseSource -File){
            $text=[IO.File]::ReadAllTextAsync($license.FullName,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace("`r`n","`n").Replace("`r","`n")
            [void][IO.File]::WriteAllTextAsync((Join-Path $licenseDestination $license.Name),$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }
        $licenseFiles=@(Get-ChildItem -LiteralPath $licenseDestination -File|ForEach-Object{
            @{Path=[IO.Path]::GetRelativePath($moduleRoot,$_.FullName).Replace('\','/');SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash;OriginalSHA256=(Get-FileHash -LiteralPath (Join-Path $licenseSource $_.Name) -Algorithm SHA256).Hash;Normalization='UTF-8 LF'}
        })
        $packages.Add($package,@{Id=$package;Version=$version;Source=$(if($package -eq 'quietcli-pty'){'resources/transport/*/build.json'}else{"https://api.nuget.org/v3-flatcontainer/$package/$version/$package.$version.nupkg"});LicenseEvidence=$licenseFiles;Provenance='Content matches the inspected local source manifest; package author authenticity is not inferred from a checksum.'})
    }
}
Write-WorkspaceJson (Join-Path $moduleRoot 'resources/dependencies.lock.json') @{SchemaVersion=1;Files=$files.ToArray();Packages=@($packages.Values);Policy='Verify pinned content before native or managed loading. Updates and advisory review are explicit maintenance operations.'}
[pscustomobject]@{Resources=$files.Count;Packages=$packages.Count;Downloaded=$false}
