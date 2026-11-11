#requires -Version 7.6
<#
.SYNOPSIS
Creates a local annotated timestamp preview tag or an exact module release tag.
.DESCRIPTION
Without Version, tags the exact HEAD of a clean repository without committing or pushing.
With Version, updates selected manifests, commits, creates annotated tags and pushes unless
NoCommit or NoPush is supplied. Existing release tags are rejected locally and remotely.
WhatIf permits a dirty checkout and uses local metadata only, without writes or network calls.
.PARAMETER WorkspaceRoot
QuietCli2 repository root; defaults to this script's checkout, independently of the current directory.
.PARAMETER Timestamp
Optional reproducible instant; defaults to the current UTC time at invocation.
.PARAMETER Release
Uses the public module namespace and complete manifest version; pushing this tag requests publication.
.PARAMETER Module
Independently versioned source component; release creation requires its public packaging capability.
.PARAMETER Version
Requested version; selects the commit/tag/push release mode instead of legacy local timestamp tagging.
.PARAMETER Preview
Explicit positive preview number, or null to detect the next numeric preview from local and remote tags.
.PARAMETER NextPreview
Detects the next numeric preview independently for every selected package.
.PARAMETER NoCommit
Requires selected manifest versions already committed; skips automatic version edits and commit.
.PARAMETER NoPush
Creates only local tags; still reads remote tags to detect existing identities.
.PARAMETER Remote
Configured Git remote, origin by default.
.PARAMETER Message
Optional release commit message.
.EXAMPLE
./scripts/New-QuietPreviewTag.ps1 -WhatIf
.EXAMPLE
$tag = ./scripts/New-QuietPreviewTag.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',DefaultParameterSetName='Local')]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [Parameter(ParameterSetName='Local')][DateTimeOffset]$Timestamp = [DateTimeOffset]::UtcNow,
    [Parameter(ParameterSetName='Local')][switch]$Release,
    [string[]]$Module=@('Core'),
    [Parameter(Mandatory,ParameterSetName='Publish')][string]$Version,
    [Parameter(ParameterSetName='Publish')][Nullable[int]]$Preview,
    [Parameter(ParameterSetName='Publish')][switch]$NextPreview,
    [Parameter(ParameterSetName='Publish')][switch]$NoCommit,
    [Parameter(ParameterSetName='Publish')][switch]$NoPush,
    [Parameter(ParameterSetName='Publish')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Publish')][string]$Message
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
foreach ($component in @('Core', 'Git')) {
    $name = "FrenchExDev2.QuietCli.$component.PoSh"
    $path = Join-Path $sourceRoot "$name/$name.psm1"
    $loaded = Get-Module -Name $name
    if ($loaded -and @($loaded | Where-Object { ![StringComparer]::OrdinalIgnoreCase.Equals($_.Path, $path) }).Count) {
        throw "PreviewTagUnexpectedModulePath: $name; start a fresh PowerShell session."
    }
    if (!$loaded) { Import-Module (Join-Path $sourceRoot "$name/$name.psd1") -ErrorAction Stop }
    if (![StringComparer]::OrdinalIgnoreCase.Equals((Get-Module -Name $name).Path, $path)) {
        throw "PreviewTagUnexpectedModulePath: $name"
    }
}
Import-Module (Join-Path $PSScriptRoot 'lib/PreviewTag.psm1') -Force
$WorkspaceRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot, $PWD.Path))

function Invoke-QuietPreviewGit {
    <#
    .SYNOPSIS
    Runs one explicit Git operation, retaining bounded metadata lines, first value and output presence.
    .PARAMETER Arguments
    Exact native arguments; no shell expansion or implicit retries.
    #>
    param([string[]]$Arguments)
    $result = quiet -AsObject -C preview-tag -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" `
        -Data @{ Value = ''; HasOutput = $false; Lines=[Collections.Generic.List[string]]::new(); Bytes=0L } -Output {
            param($event, $runtime)
            if ($event.Stream -ne 'stdout') { return }
            $line = $event.Text.TrimEnd([char[]]"`r`n")
            if (!$line.Length) { return }
            $runtime.Data.Bytes+=[Text.Encoding]::UTF8.GetByteCount($line)
            if($runtime.Data.Lines.Count -ge 50000 -or $runtime.Data.Bytes -gt 4MB){throw 'ReleaseGitMetadataLimitExceeded'}
            $runtime.Data.Lines.Add($line)
            if (!$runtime.Data.HasOutput) {
                if ($line.Length -gt 4096) { throw 'PreviewTagValueTooLong' }
                $runtime.Data.Value = $line
            }
            $runtime.Data.HasOutput = $true
        } -Complete { param($runtime) $runtime.Data } -FilePath git -ArgumentList $Arguments
    if ($result.Outcome -ne 'Success' -or $result.Execution.Native.ExitCode -ne 0 -or
        !$result.Completeness.Source -or !$result.Completeness.Analysis -or @($result.Error).Count) {
        throw "PreviewTagGitFailed: $($Arguments[0]); $($result.Outcome). No retry was attempted."
    }
    return $result.Data
}

$repository = (Invoke-QuietPreviewGit @('rev-parse', '--show-toplevel')).Value
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (!$WorkspaceRoot.Equals([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($repository)), $comparison)) {
    throw 'PreviewTagWorkspaceMustBeRepositoryRoot'
}
if($PSCmdlet.ParameterSetName -ceq 'Publish'){
    Import-Module (Join-Path $PSScriptRoot 'lib/ReleaseTags.psm1') -Force
    $scriptDirectory=$PSScriptRoot
    $invokeGit={param($arguments) Invoke-QuietPreviewGit -Arguments $arguments}
    $commit={
        param($root,$message,$paths)
        & (Join-Path $scriptDirectory 'Update-WorkspaceLock.ps1') -WorkspaceRoot $root | Out-Null
        $allowed=@($paths)+@('repositories.lock.json')
        $changed=@((Invoke-QuietPreviewGit @('diff','--name-only','HEAD')).Lines)
        if(@($changed|Where-Object {$_ -cnotin $allowed}).Count){throw 'ReleaseUnrelatedChangesBeforeCommit'}
        $null=Invoke-QuietPreviewGit (@('add','--')+$allowed)
        & (Join-Path $scriptDirectory 'Commit-Workspace.ps1') -WorkspaceRoot $root -NoAll -Message $message -Confirm:$false | Out-Null
    }
    $push={param($root,$remote,$branch) & (Join-Path $scriptDirectory 'Push-Workspace.ps1') -WorkspaceRoot $root -Remote $remote -Branch $branch -Confirm:$false | Out-Null}
    $options=@{WorkspaceRoot=$WorkspaceRoot;Module=$Module;Version=$Version;Preview=$Preview;PreviewSpecified=$PSBoundParameters.ContainsKey('Preview');NextPreview=$NextPreview;NoCommit=$NoCommit;NoPush=$NoPush;Remote=$Remote;Message=$Message;GitCommand=$invokeGit;CommitCommand=$commit;PushCommand=$push;WhatIf=$WhatIfPreference}
    if($PSBoundParameters.ContainsKey('Confirm')){$options.Confirm=$PSBoundParameters['Confirm']}
    Invoke-QuietModuleRelease @options
    return
}
if($Module.Count -ne 1){throw 'MultipleModuleTagsRequireVersionMode'}
$Module=$Module[0]
if(!$Release -and $Module -cne 'Core'){throw 'CompanionTagRequiresReleaseMode'}
$project="FrenchExDev2.QuietCli.$Module.PoSh"
$manifestPath = Join-Path $WorkspaceRoot "$project/$project.psd1"
$manifest=Import-PowerShellDataFile -LiteralPath $manifestPath
$version = [string]$manifest.ModuleVersion
if($Release){
    Import-Module (Join-Path $PSScriptRoot 'lib/ModulePackage.psm1')
    $identity=Get-QuietModulePackageIdentity -Path (Join-Path $WorkspaceRoot "$project/$project.psm1") -RequireManifest
    $version=$identity.Version
    $publicName=$identity.Name
    Import-Module (Join-Path $PSScriptRoot 'lib/GalleryRelease.psm1') -Force
    $plan=Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag "$publicName/v$version"
    $tag=$plan.Tag
}else{$tag = New-QuietPreviewTagName -Version $version -Timestamp $Timestamp}
$revision = (Invoke-QuietPreviewGit @('rev-parse', '--verify', 'HEAD^{commit}')).Value
if ($revision -cnotmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'PreviewTagInvalidRevision' }
$clean = !(Invoke-QuietPreviewGit @('status', '--porcelain=v1', '--untracked-files=normal')).HasOutput
$existing = Invoke-QuietPreviewGit @('tag', '--list', $tag)
if ($existing.HasOutput) { throw "PreviewTagAlreadyExists: $tag" }
$created = $false
if ($PSCmdlet.ShouldProcess("$WorkspaceRoot @ $revision", "Create annotated tag $tag")) {
    if (!$clean) { throw 'PreviewTagDirtyCheckout: commit changes before tagging HEAD.' }
    $message=if($Release){"$($plan.Module) $version release"}else{"QuietCli $version preview ($($Timestamp.ToUniversalTime().ToString('o')))"}
    $null = Invoke-QuietPreviewGit @('-c', 'tag.gpgSign=false', 'tag', '--annotate', '--message', $message, '--', $tag, $revision)
    $created = $true
}
[pscustomobject]@{
    Tag = $tag
    Version = $version
    TimestampUtc = $Timestamp.ToUniversalTime()
    Revision = $revision
    WorkspaceRoot = $WorkspaceRoot
    ManifestPath = $manifestPath
    Clean = $clean
    Created = $created
}
