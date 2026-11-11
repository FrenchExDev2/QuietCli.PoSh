#requires -Version 7.6
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
    if($Tag -cnotmatch '\AFrenchExDev2\.QuietCli\.(Core|Git|Vagrant)\.PoSh/v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z][A-Za-z0-9-]*)?)\z'){
        throw 'GalleryReleaseTagInvalid'
    }
    $component=$Matches[1];$version=$Matches[2]
    try{$null=[semver]$version}catch{throw 'GalleryReleaseTagInvalid'}
    Import-Module (Join-Path $PSScriptRoot 'ModulePackage.psm1')
    $project="FrenchExDev2.QuietCli.$component.PoSh"
    $identity=Get-QuietModulePackageIdentity -Path (Join-Path $WorkspaceRoot "$project/$project.psm1") -RequireManifest
    $publicName=$identity.Name
    if($identity.Version -cne $version){throw 'GalleryReleaseTagManifestMismatch'}
    if($identity.Publishable -isnot [bool] -or !$identity.Publishable){
        throw "GalleryReleaseModuleNotPublishable: $publicName"
    }
    # Public companion identity/dependency staging and installation qualification must precede activation.
    if($component -cne 'Core'){throw "GalleryReleasePublicPackagingUnavailable: $publicName"}
    [pscustomobject]@{Tag=$Tag;Module=$publicName;Component=$component;Project=$project;Version=$version;Published=$false}
}
Export-ModuleMember -Function Resolve-QuietGalleryReleaseTag
