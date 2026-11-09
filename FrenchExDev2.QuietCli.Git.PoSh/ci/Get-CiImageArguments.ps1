# Objectif : Definir les entrees verifiees du module Git pour son image CI derivee de Core.
<#
.SYNOPSIS
Resolves the Git module's own CI image build arguments and Containerfile fragment, without reading or
touching anything that belongs to Core.
.DESCRIPTION
The module never authors a Containerfile of its own: it only declares this fragment (its own ordered
Stages -- package lists, build ARGs, fetch script, final-stage overlay), and Core's own
Get-QuietModuleContainerfile renders the actual Containerfile text from it, on top of Core's generic
ARG CORE_IMAGE skeleton. The module's compiled git binary dynamically links libcurl/libexpat at runtime
(fetch-git-tools.sh's build never passes NO_CURL/NO_EXPAT), so the module's own final stage declares
those as its own Packages -- Core's base image is never required to carry them for this module's sake.
Invoked directly as a script -- not dot-sourced -- by scripts/New-CiModuleImage.ps1, which calls every
Core-consumer module at this exact same relative path: this file IS the module's declared contract.
.PARAMETER WorkspaceRoot
Monorepo containing the reviewed image and upstream source locks.
.PARAMETER Platform
'debian' or 'alpine', as already resolved from Core's own plan for the requested RID.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][ValidateSet('debian','alpine')][string]$Platform)
$ErrorActionPreference='Stop'
$moduleRoot='FrenchExDev2.QuietCli.Git.PoSh'
$lock=Get-Content (Join-Path $WorkspaceRoot "$moduleRoot/metadata/locks/ci-image.lock.json") -Encoding utf8 -Raw|ConvertFrom-Json
if($lock.SchemaVersion -ne 1){throw 'CiModuleGitLockSchemaMismatch'}
$upstream=Get-Content (Join-Path $WorkspaceRoot "$moduleRoot/metadata/locks/UpstreamSources.json") -Encoding utf8 -Raw|ConvertFrom-Json
$source=@($upstream.Sources|Where-Object Version -CEQ $lock.GitVersion)
if($source.Count -ne 1 -or $source[0].SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or $source[0].URL -cne ('https://codeload.github.com/git/git/tar.gz/refs/tags/v'+$lock.GitVersion)){throw 'CiModuleGitSourceInvalid'}
$arguments=[ordered]@{GIT_URL=$source[0].URL;GIT_SHA256=$source[0].SHA256}
$paths=@("$moduleRoot/metadata/locks/ci-image.lock.json","$moduleRoot/metadata/locks/UpstreamSources.json","$moduleRoot/.github/containers/fetch-git-tools.sh")
$toolsPackages=if($Platform -ceq 'debian'){'curl build-essential libssl-dev zlib1g-dev libcurl4-openssl-dev libexpat1-dev'}else{'curl build-base openssl-dev zlib-dev curl-dev expat-dev linux-headers'}
$ciPackages=if($Platform -ceq 'debian'){'libcurl4 libexpat1'}else{'libcurl expat'}
$containerfile=[pscustomobject]@{
    Platform=$Platform
    Objective="Ajouter Git compile depuis les sources, pinne par SHA-256, par-dessus l'image Core deja verifiee."
    Stages=@(
        [pscustomobject]@{Name='tools';Packages=$toolsPackages;Args=@('GIT_URL','GIT_SHA256');FetchScript='fetch-git-tools.sh'}
        [pscustomobject]@{Name='ci';Packages=$ciPackages;Copy=@([pscustomobject]@{Stage='tools';Spec='/opt/git /opt/git'});PathPrefix='/opt/git/bin'}
    )
}
[pscustomobject]@{Arguments=$arguments;InputPaths=$paths;Containerfile=$containerfile}
