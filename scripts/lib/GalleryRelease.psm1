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
function Resolve-QuietGalleryReleaseBatch {
    <#
    .SYNOPSIS
    Validates a bounded annotated release batch and chooses one dependency-ordered leader.
    .PARAMETER WorkspaceRoot
    Checkout whose unchanged manifests own every tag.
    .PARAMETER Tag
    Triggering module tag; ordinary manual tags form a single-module batch.
    .PARAMETER Revision
    Exact commit shared by the tags.
    .PARAMETER Annotation
    Optional tag annotation containing one QuietCli-Release-Batch JSON line.
    .PARAMETER Tags
    Explicit batch members for package validation, instead of annotation parsing.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot,[string]$Tag,[ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,[string]$Annotation,[string[]]$Tags)
    if(!$PSBoundParameters.ContainsKey('Tags')){
        $Tags=@($Tag)
        $records=@([regex]::Matches($Annotation,'(?m)^QuietCli-Release-Batch: (.+)\r?$'))
        if($records.Count -gt 1 -or $Annotation.Length -gt 32768){throw 'GalleryReleaseBatchInvalid'}
        if($records.Count){
            $json=$records[0].Groups[1].Value
            $document=[Text.Json.JsonDocument]::Parse($json)
            try{
                $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach($property in $document.RootElement.EnumerateObject()){if(!$keys.Add($property.Name)){throw 'GalleryReleaseBatchInvalid'}}
            }finally{$document.Dispose()}
            $data=$json|ConvertFrom-Json
            if(($data.SchemaVersion -isnot [int] -and $data.SchemaVersion -isnot [long]) -or $data.SchemaVersion -ne 1 -or $data.Revision -cne $Revision -or $data.Tags -isnot [array] -or @($data.PSObject.Properties.Name|Where-Object {$_ -cnotin @('SchemaVersion','Revision','Tags')}).Count){throw 'GalleryReleaseBatchInvalid'}
            $Tags=@($data.Tags)
        }
    }
    if(!$Tags.Count -or $Tags.Count -gt 32 -or $Tag -cnotin $Tags){throw 'GalleryReleaseBatchInvalid'}
    $plans=@($Tags|ForEach-Object {Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag $_})
    if(@($plans.Module|Select-Object -Unique).Count -ne $plans.Count){throw 'GalleryReleaseBatchDuplicateModule'}
    $ordered=@(Select-QuietGalleryReleaseTargets -WorkspaceRoot $WorkspaceRoot -Module $plans.Module|ForEach-Object {$module=$_.Module;$plans|Where-Object Module -CEQ $module})
    [pscustomobject]@{Revision=$Revision;LeaderTag=$ordered[0].Tag;IsLeader=($Tag -ceq $ordered[0].Tag);Tags=@($ordered.Tag);Releases=$ordered}
}
Export-ModuleMember -Function Get-QuietGalleryReleaseTargets,Select-QuietGalleryReleaseTargets,Resolve-QuietGalleryReleaseTag,Resolve-QuietGalleryReleaseBatch
