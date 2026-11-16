#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietCompanionBuildKey {
    <#
    .SYNOPSIS
    Computes a target-specific cache key from compiled source closures and effective package declarations.
    .PARAMETER WorkspaceRoot
    Checkout owning the source graph.
    .PARAMETER Suite
    Selected suite and its technical module dependencies.
    .PARAMETER RuntimeIdentifier
    Actual build target.
    .PARAMETER ReadyToRun
    Separates precompiled publications from portable smoke preparations.
    #>
    param([string]$WorkspaceRoot,[string]$Suite,[string]$RuntimeIdentifier,[switch]$ReadyToRun)
    $modules=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot -Suite $Suite)
    $projects=@(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $modules|Select-Object -ExpandProperty Project -Unique)
    $inputs=@(foreach($project in $projects){Get-QuietBinaryInputs $WorkspaceRoot $project})
    $digest=Get-QuietManifestDigest $inputs
    'quietcli-build-v2-'+$RuntimeIdentifier+'-'+$Suite+'-'+$ReadyToRun.ToString().ToLowerInvariant()+'-'+$digest
}

function Test-QuietReusableBuild {
    <#
    .SYNOPSIS
    Accepts existing outputs only after their sources, payload hashes, configuration and requested RID slots match.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER Modules
    Exact module dependency closure.
    .PARAMETER Configuration
    Requested compiler configuration.
    .PARAMETER RuntimeIdentifier
    Required engine publications.
    .PARAMETER ReadyToRunRuntimeIdentifier
    Required precompiled engine publications.
    #>
    param([string]$WorkspaceRoot,[string[]]$Modules,[string]$Configuration,[string[]]$RuntimeIdentifier,[string[]]$ReadyToRunRuntimeIdentifier)
    try{
        foreach($distribution in Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $Modules){
            $manifest=Test-QuietBuildManifest $WorkspaceRoot $distribution.Output
            if($manifest.Configuration -cne $Configuration){return $false}
        }
        foreach($rid in $RuntimeIdentifier){
            $manifest=Test-QuietBuildManifest $WorkspaceRoot ('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid)
            if($manifest.Configuration -cne $Configuration -or ($rid -cin $ReadyToRunRuntimeIdentifier -and !$manifest.ReadyToRun)){return $false}
        }
        foreach($rid in $ReadyToRunRuntimeIdentifier){
            $manifest=Test-QuietBuildManifest $WorkspaceRoot ('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid)
            if($manifest.Configuration -cne $Configuration -or !$manifest.ReadyToRun){return $false}
        }
        return $true
    }catch{return $false}
}
Export-ModuleMember -Function Get-QuietCompanionBuildKey,Test-QuietReusableBuild
