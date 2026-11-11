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
    if($Tag -cnotmatch '\A(QuietCli|QuietCli\.Git|QuietCli\.Vagrant)/v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z][A-Za-z0-9-]*)?)\z'){
        throw 'GalleryReleaseTagInvalid'
    }
    $publicName=$Matches[1];$version=$Matches[2]
    try{$null=[semver]$version}catch{throw 'GalleryReleaseTagInvalid'}
    $component=switch -Exact ($publicName){'QuietCli'{'Core'} 'QuietCli.Git'{'Git'} 'QuietCli.Vagrant'{'Vagrant'}}
    $project="FrenchExDev2.QuietCli.$component.PoSh"
    $manifest=Import-PowerShellDataFile -LiteralPath (Join-Path $WorkspaceRoot "$project/$project.psd1")
    $sourceVersion=[string]$manifest.ModuleVersion
    $label=[string]$manifest.PrivateData.PSData.Prerelease
    if($label){$sourceVersion+='-'+$label}
    if($sourceVersion -cne $version){throw 'GalleryReleaseTagManifestMismatch'}
    if($manifest.PrivateData.QuietCli.Publishable -isnot [bool] -or !$manifest.PrivateData.QuietCli.Publishable){
        throw "GalleryReleaseModuleNotPublishable: $publicName"
    }
    # Public companion identity/dependency staging and installation qualification must precede activation.
    if($component -cne 'Core'){throw "GalleryReleasePublicPackagingUnavailable: $publicName"}
    [pscustomobject]@{Tag=$Tag;Module=$publicName;Component=$component;Project=$project;Version=$version;Published=$false}
}
Export-ModuleMember -Function Resolve-QuietGalleryReleaseTag
