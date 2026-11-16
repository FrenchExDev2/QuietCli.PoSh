
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
function Invoke-QuietScriptNewQuietPreviewTag {
#requires -Version 7.6
<#
.SYNOPSIS
Creates a local annotated timestamp preview tag or an exact module release tag.
.DESCRIPTION
Without Version, tags the exact HEAD of a clean repository without committing or pushing.
With Version and versions differing from HEAD, commits the manifest edits on the current work branch
only; no tag is created and no branch is pushed. Deliver that commit through a pull request.
With Version matching HEAD (or NoCommit), creates annotated tags and pushes exactly those tags once HEAD
is contained in the remote delivery branch, unless NoPush. With PushTag, atomically pushes existing local
release tags after the same delivery check. Existing release tags are rejected locally and remotely.
WhatIf permits a dirty checkout and uses local metadata only, without writes or network calls.
.PARAMETER WorkspaceRoot
QuietCli2 repository root; defaults to this script's checkout, independently of the current directory.
.PARAMETER Timestamp
Optional reproducible instant; defaults to the current UTC time at invocation.
.PARAMETER Release
Uses the public module namespace and complete manifest version; pushing this tag requests publication.
.PARAMETER Module
Exactly one independently versioned source component (alias or full package name, not All); release creation
requires its public packaging capability. Release several modules together with Invoke-QuietRelease.ps1.
.PARAMETER Version
Requested version; selects the commit/tag/push release mode instead of legacy local timestamp tagging.
.PARAMETER Preview
Explicit positive preview number, or null to detect the next numeric preview from local and remote tags.
.PARAMETER NextPreview
Detects the next numeric preview of the selected package from local and remote tags.
.PARAMETER NoCommit
Requires selected manifest versions already committed; skips automatic version edits and commit.
.PARAMETER NoPush
Creates only local tags; still reads remote tags to detect existing identities.
.PARAMETER PushTag
Existing local annotated release tags to push atomically, including every member of their batch.
.PARAMETER Remote
Configured Git remote, origin by default.
.PARAMETER DeliveryBranch
Protected remote branch that must already contain the tagged commit, develop by default.
.PARAMETER Message
Optional release commit message.
.EXAMPLE
./scripts/New-QuietPreviewTag.ps1 -WhatIf
.EXAMPLE
$tag = ./scripts/New-QuietPreviewTag.ps1
.EXAMPLE
./scripts/New-QuietPreviewTag.ps1 -PushTag FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',DefaultParameterSetName='Local')]
param(
    [string]$WorkspaceRoot = (Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),
    [Parameter(ParameterSetName='Local')][DateTimeOffset]$Timestamp = [DateTimeOffset]::UtcNow,
    [Parameter(ParameterSetName='Local')][switch]$Release,
    [string[]]$Module=@('Core'),
    [Parameter(Mandatory,ParameterSetName='Publish')][string]$Version,
    [Parameter(ParameterSetName='Publish')][Nullable[int]]$Preview,
    [Parameter(ParameterSetName='Publish')][switch]$NextPreview,
    [Parameter(ParameterSetName='Publish')][switch]$NoCommit,
    [Parameter(ParameterSetName='Publish')][switch]$NoPush,
    [Parameter(Mandatory,ParameterSetName='PushTags')][string[]]$PushTag,
    [Parameter(ParameterSetName='Publish')][Parameter(ParameterSetName='PushTags')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Publish')][Parameter(ParameterSetName='PushTags')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',
    [Parameter(ParameterSetName='Publish')][string]$Message
)
$ErrorActionPreference = 'Stop'
# One module per run: several modules share one pull request and one tag batch only through the facade.
if ($Module.Count -ne 1 -or $Module[0] -eq 'All') {
    throw 'PreviewTagRequiresOneModule: pass a single -Module; release several modules with Invoke-QuietRelease.ps1.'
}
$sourceRoot = Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent
# Git's RequiredModules registration resolves Core commands from the process-global scope, so Core is
# imported globally first. Registration is in-memory only, so it also runs under -WhatIf.
$savedWhatIf = $WhatIfPreference; $savedConfirm = $ConfirmPreference
try {
    $WhatIfPreference = $false; $ConfirmPreference = 'None'
    foreach ($component in @('Core', 'Git')) {
        $name = "FrenchExDev2.QuietCli.$component.PoSh"
        $path = [IO.Path]::Combine((Resolve-QuietWorkspacePath -WorkspaceRoot $sourceRoot -RelativePath $name),($name+'.psm1'))
        $loaded = Get-Module -Name $name -All
        if ($loaded -and @($loaded | Where-Object { ![StringComparer]::OrdinalIgnoreCase.Equals($_.Path, $path) }).Count) {
            throw "PreviewTagUnexpectedModulePath: $name; start a fresh PowerShell session."
        }
        $manifest = (Resolve-QuietWorkspacePath -WorkspaceRoot $sourceRoot -RelativePath "$name/$name.psd1")
        if ($component -ceq 'Core') { Import-Module $manifest -Scope Global -ErrorAction Stop -DisableNameChecking }
        elseif (!$loaded) { Import-Module $manifest -ErrorAction Stop -DisableNameChecking }
        if (![StringComparer]::OrdinalIgnoreCase.Equals((Get-Module -Name $name).Path, $path)) {
            throw "PreviewTagUnexpectedModulePath: $name"
        }
    }
} finally { $WhatIfPreference = $savedWhatIf; $ConfirmPreference = $savedConfirm }
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PreviewTag.psm1')) -DisableNameChecking -ErrorAction Stop
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
if($PSCmdlet.ParameterSetName -ceq 'PushTags'){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseTags.psm1')) -DisableNameChecking -ErrorAction Stop
    $options=@{Tag=$PushTag;Remote=$Remote;DeliveryBranch=$DeliveryBranch;GitCommand={param($arguments) Invoke-QuietPreviewGit -Arguments $arguments};WhatIf=$WhatIfPreference}
    if($PSBoundParameters.ContainsKey('Confirm')){$options.Confirm=$PSBoundParameters['Confirm']}
    Push-QuietReleaseTags @options
    return
}
if($PSCmdlet.ParameterSetName -ceq 'Publish'){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseTags.psm1')) -DisableNameChecking -ErrorAction Stop
    $scriptDirectory=([IO.Path]::GetDirectoryName($PSScriptRoot))
    $invokeGit={param($arguments) Invoke-QuietPreviewGit -Arguments $arguments}
    $commit={
        param($root,$message,$paths)
        $allowed=@($paths)
        $changed=@((Invoke-QuietPreviewGit @('diff','--name-only','HEAD')).Lines)
        if(@($changed|Where-Object {$_ -cnotin $allowed}).Count){throw 'ReleaseUnrelatedChangesBeforeCommit'}
        $null=Invoke-QuietPreviewGit (@('add','--')+$allowed)
        & ([IO.Path]::Combine($scriptDirectory,'Commit-Workspace.ps1')) -WorkspaceRoot $root -NoAll -Message $message -Confirm:$false | Out-Null
    }
    $options=@{WorkspaceRoot=$WorkspaceRoot;Module=$Module;Version=$Version;Preview=$Preview;PreviewSpecified=$PSBoundParameters.ContainsKey('Preview');NextPreview=$NextPreview;NoCommit=$NoCommit;NoPush=$NoPush;Remote=$Remote;DeliveryBranch=$DeliveryBranch;Message=$Message;GitCommand=$invokeGit;CommitCommand=$commit;WhatIf=$WhatIfPreference}
    if($PSBoundParameters.ContainsKey('Confirm')){$options.Confirm=$PSBoundParameters['Confirm']}
    Invoke-QuietModuleRelease @options
    return
}
$Module=$Module[0]
if(!$Release -and $Module -cne 'Core'){throw 'CompanionTagRequiresReleaseMode'}
$project="FrenchExDev2.QuietCli.$Module.PoSh"
$manifestPath = [IO.Path]::Combine($WorkspaceRoot,"$project/$project.psd1")
$manifest=Import-PowerShellDataFile -LiteralPath $manifestPath
$version = [string]$manifest.ModuleVersion
if($Release){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'ModulePackage.psm1')) -DisableNameChecking
    $identity=Get-QuietModulePackageIdentity -Path ([IO.Path]::Combine($WorkspaceRoot,"$project/$project.psm1")) -RequireManifest
    $version=$identity.Version
    $publicName=$identity.Name
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'GalleryRelease.psm1')) -DisableNameChecking -ErrorAction Stop
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

}
Export-ModuleMember -Function 'Invoke-QuietScriptNewQuietPreviewTag'
