#requires -Version 7.6
function Get-QuietGalleryReleaseTargets {
    <#
    .SYNOPSIS
    Discovers independently versioned business packages from the existing workspace manifests.
    .PARAMETER WorkspaceRoot
    Source checkout; test projects are never publication targets.
    .PARAMETER IncludeDisabled
    Includes disabled business modules for explicit policy diagnostics.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[switch]$IncludeDisabled)
    . (Join-Path $PSScriptRoot '../WorkspaceProjects.ps1')
    Import-Module (Join-Path $PSScriptRoot 'ModulePackage.psm1')
    foreach($project in Get-QuietWorkspaceProjects $WorkspaceRoot | Where-Object {!$_.IsTest}){
        $identity=Get-QuietModulePackageIdentity -Path (Join-Path $project.Directory ($project.Name+'.psm1')) -RequireManifest
        if($identity.Publishable -isnot [bool] -and $null -ne $identity.Publishable){throw 'GalleryPublicationPolicyMustBeBoolean'}
        if(!$IncludeDisabled -and !$identity.Publishable){continue}
        [pscustomobject]@{Component=$project.Suite;Module=$identity.Name;Project=$project.Name;Version=$identity.Version;ManifestPath=$identity.ManifestPath;ModulePath=$identity.ModulePath;Publishable=($identity.Publishable -is [bool] -and $identity.Publishable);Dependencies=$identity.Dependencies;Manifest=$project.Manifest}
    }
}

function Select-QuietGalleryReleaseTargets {
    <#
    .SYNOPSIS
    Selects publishable packages by discovered component alias, full package name or All.
    .PARAMETER WorkspaceRoot
    Source checkout.
    .PARAMETER Module
    One or more requested aliases or package names.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string[]]$Module=@('Core'))
    $targets=@(Get-QuietGalleryReleaseTargets $WorkspaceRoot -IncludeDisabled)
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if(!$Module.Count){throw 'GalleryModuleSelectionRequired'}
    foreach($name in $Module){
        $matches=@($targets|Where-Object {$_.Component -ieq $name -or $_.Module -ieq $name -or ($name -ieq 'All' -and $_.Publishable)})
        if(!$matches.Count){throw ('GalleryReleaseModuleUnknown: '+$name)}
        foreach($target in $matches){
            if(!$target.Publishable){throw ('GalleryReleaseModuleNotPublishable: '+$target.Module)}
            [void]$selected.Add($target.Module)
        }
    }
    $targets|Where-Object {$selected.Contains($_.Module)}
}

function Resolve-QuietGalleryReleaseTag {
    <#
    .SYNOPSIS
    Resolves an independently versioned release tag against its owning source manifest.
    .PARAMETER WorkspaceRoot
    Selected source checkout; no Git, network or publication operation is performed.
    .PARAMETER Tag
    Exact public module namespace followed by /v and the complete Gallery version.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$Tag)
    if($Tag -cnotmatch '\A([A-Za-z][A-Za-z0-9_.-]*)/v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z][A-Za-z0-9-]*)?)\z'){
        throw 'GalleryReleaseTagInvalid'
    }
    $publicName=$Matches[1];$version=$Matches[2]
    try{$null=[semver]$version}catch{throw 'GalleryReleaseTagInvalid'}
    $target=@(Get-QuietGalleryReleaseTargets $WorkspaceRoot -IncludeDisabled|Where-Object Module -CEQ $publicName)
    if($target.Count -ne 1){throw 'GalleryReleaseModuleUnknown'}
    if(!$target[0].Publishable){throw "GalleryReleaseModuleNotPublishable: $publicName"}
    if($target[0].Version -cne $version){throw 'GalleryReleaseTagManifestMismatch'}
    [pscustomobject]@{Tag=$Tag;Module=$publicName;Component=$target[0].Component;Project=$target[0].Project;Version=$version;Published=$false}
}
Export-ModuleMember -Function Get-QuietGalleryReleaseTargets,Select-QuietGalleryReleaseTargets,Resolve-QuietGalleryReleaseTag
