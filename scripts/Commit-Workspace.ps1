#requires -Version 7.6
<#
.SYNOPSIS
Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.
.DESCRIPTION
Before staging, runs Invoke-WorkspaceChecks.ps1: script docs, workflow receipts/graphs/index,
new-script WhatIf/Confirm support, documentation credits and aggregate credits. The same registry
validates exported staged snapshots with NoAll. Explicit skip switches or SkipCheck report omissions;
NoSyncChecks skips documentation checks but retains the independent script safety check.
Separately, warns (does not block) when a script file about to be committed (working tree, staged
or untracked, relative to $WorkspaceRoot) has no matching change to its mirrored doc under
docs/scripts/ - the doc Sync-ScriptsReadme.ps1 requires to exist, but whose content it never
inspects for staleness. Pass -NoScriptDocDriftWarning to override (silence) that warning; it never
blocks the commit on its own regardless.
Also warns (does not block) when a changed file - from its own `quiet git status` call, the one
intentional use of the quiet module in this otherwise quiet-independent script - is binary content
or larger than -MaxChangedFileSize, unless .gitattributes already marks it binary. Pass
-NoCommitFileSnifferWarning to override (silence) that warning; it never blocks the commit either.
Fully supports -WhatIf/-Confirm (SupportsShouldProcess): with -WhatIf, the sync gates and the drift
warning still run and report exactly as they would for a real commit, but the workspace lock is not
refreshed, nothing is staged and no commit is created.
With -NoAll, the working tree and index are never refreshed or staged. An isolated temporary index
snapshot supplies the source-lock and documentation checks, including during WhatIf preview.
.PARAMETER Message
Required commit message, without trailers.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Repository
Only Workspace exists; retained to reject accidental requests for independent module commits.
.PARAMETER CoAuthoredBy
Opt-in, no trailer by default. Co-Authored-By trailers appended after the message, one per
contributing agent explicitly named by the caller; each entry is either `Name <email>` or a known
agent name from `$knownCoAuthors` (see docs/agents/README.md for the documented list). Skips an
entry already present verbatim in Message so a caller-supplied trailer is never duplicated.
.PARAMETER NoAll
Commits only the prepared index. Does not refresh the working-tree lock or stage any file.
Requires a repositories.lock.json matching the staged sources; validates an isolated index snapshot
before committing. Prepare and stage the matching lock together with the selected source changes.
.PARAMETER NoScriptsReadmeCheck
Skips the scripts/README documentation-coverage gate (Sync-ScriptsReadme.ps1).
.PARAMETER NoDocsCreditsCheck
Skips the docs credits-block gate (Sync-DocsCredits.ps1).
.PARAMETER NoCreditsCheck
Skips the aggregated CREDITS.md gate (Sync-Credits.ps1).
.PARAMETER NoSyncChecks
Skips documentation checks, including GitHub workflow, resource and script review documentation.
The ScriptShouldProcess check remains active unless explicitly skipped.
.PARAMETER NoResourcesCheck
Skips generated resource inventory and dependency documentation validation.
.PARAMETER NoScriptContractsCheck
Skips obsolete objective-boilerplate detection and full script preview review validation.
.PARAMETER NoGitHubWorkflowDocsCheck
Skips workflow documentation receipts, generated job graphs and index validation.
.PARAMETER NoScriptShouldProcessCheck
Skips the new-script WhatIf/Confirm policy check.
.PARAMETER SkipCheck
Names in the shared Invoke-WorkspaceChecks registry to skip explicitly; each skip is reported.
.PARAMETER NoScriptDocDriftWarning
Overrides (silences) the script/doc drift warning described above. The warning is informational
only; it never blocks the commit whether this switch is passed or not.
.PARAMETER MaxChangedFileSize
Human-readable size (see Common.ps1's ConvertTo-QuietByteCount: "500KB", "1MiB", "2GiB", or a bare
integer for raw bytes) above which a changed file is flagged by the binary/size sniffer. Default
"500KB".
.PARAMETER NoCommitFileSnifferWarning
Overrides (silences) the binary/oversized-file warning described above. The warning is
informational only; it never blocks the commit whether this switch is passed or not.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Add Build-Workspace DRY refactor" -CoAuthoredBy Claude
Runs every sync gate and the drift warning, then stages and commits as usual.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Quick fix" -NoSyncChecks -NoScriptDocDriftWarning
Skips every documentation-sync gate and the drift warning; still refreshes the lock, stages and
commits.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Preview" -WhatIf
Runs the gates and reports script/doc drift, but refreshes nothing, stages nothing and commits
nothing.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Commit selected changes" -NoAll
Validates and commits the prepared index with its matching source lock; preserves unstaged changes.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Vendor a tool" -MaxChangedFileSize 2MiB
Raises the binary/oversized-file sniffer's threshold to 2 MiB for this run only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Message,
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('Workspace')][string]$Repository = 'Workspace',
    [string[]]$CoAuthoredBy = $null,
    [switch]$NoAll,
    [switch]$NoScriptsReadmeCheck,
    [switch]$NoDocsCreditsCheck,
    [switch]$NoCreditsCheck,
    [switch]$NoSyncChecks,
    [switch]$NoGitHubWorkflowDocsCheck,
    [switch]$NoScriptShouldProcessCheck,
    [switch]$NoResourcesCheck,
    [switch]$NoScriptContractsCheck,
    [string[]]$SkipCheck=@(),
    [switch]$NoScriptDocDriftWarning,
    [string]$MaxChangedFileSize = '500KB',
    [switch]$NoCommitFileSnifferWarning
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot Common.ps1)
$maxChangedFileBytes = ConvertTo-QuietByteCount $MaxChangedFileSize

function Invoke-QuietCommitChecks {
    <#
    .SYNOPSIS
    Maps compatibility switches to the shared registry, for either working-tree or index validation.
    .PARAMETER Root
    Exact tree or staged snapshot being checked.
    #>
    param([string]$Root)
    $skipped=@($SkipCheck)
    if($NoSyncChecks -or $NoScriptsReadmeCheck){$skipped+='ScriptsReadme'}
    if($NoSyncChecks -or $NoDocsCreditsCheck){$skipped+='DocsCredits'}
    if($NoSyncChecks -or $NoCreditsCheck){$skipped+='Credits'}
    if($NoSyncChecks -or $NoGitHubWorkflowDocsCheck){$skipped+='GitHubWorkflowDocs'}
    if($NoScriptShouldProcessCheck){$skipped+='ScriptShouldProcess'}
    if($NoSyncChecks -or $NoResourcesCheck){$skipped+='Resources'}
    if($NoSyncChecks -or $NoScriptContractsCheck){$skipped+='ScriptContracts'}
    Invoke-WorkspaceChecksForCommit -Root $Root -Skipped $skipped
}
function Invoke-WorkspaceChecksForCommit {
    <#
    .SYNOPSIS
    Runs the registry from the trusted script location against the selected tree.
    .PARAMETER Root
    Tree whose content is checked.
    .PARAMETER Skipped
    Explicitly omitted registry names.
    #>
    param([string]$Root,[string[]]$Skipped)
    & (Join-Path $PSScriptRoot 'Invoke-WorkspaceChecks.ps1') -WorkspaceRoot $Root -SkipCheck @($Skipped|Sort-Object -Unique)
}

function Assert-QuietStagedWorkspaceLock {
    <#
    .SYNOPSIS
    Checks a prepared index against its own source lock without staging working-tree changes.
    .PARAMETER WorkspaceRoot
    Repository whose index is exported read-only to an owned temporary snapshot.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $changes=Invoke-CiProcess -FilePath git -ArgumentList @('-C',$WorkspaceRoot,'diff','--cached','--quiet','--exit-code') -WorkingDirectory $WorkspaceRoot
    if($changes.ExitCode -eq 0){throw 'CommitWorkspaceNothingStaged'}
    if($changes.ExitCode -ne 1 -or $changes.Outcome -ne 'Failed'){throw 'CommitWorkspaceIndexUnavailable'}
    $temporaryRoot=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'QuietCli2/commit-index'))
    $snapshot=[IO.Path]::GetFullPath((Join-Path $temporaryRoot ([guid]::NewGuid().ToString('N'))))
    if(![IO.Path]::IsPathFullyQualified($snapshot) -or !($snapshot.StartsWith($temporaryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal))){throw 'CommitWorkspaceSnapshotPathInvalid'}
    [void][IO.Directory]::CreateDirectory($snapshot)
    try{
        $null=Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'checkout-index','--all',('--prefix='+$snapshot.Replace('\','/')+'/')) $WorkspaceRoot
        $lockPath=Join-Path $snapshot 'repositories.lock.json'
        if(!(Test-Path -LiteralPath $lockPath -PathType Leaf)){throw 'CommitWorkspaceStagedLockMissing'}
        $lock=Get-Content -LiteralPath $lockPath -Raw -Encoding utf8|ConvertFrom-Json
        $identity=Get-QuietWorkspaceIdentity $snapshot
        $projects=@(Get-QuietWorkspaceProjects $snapshot)
        if($lock.SchemaVersion -ne 3 -or $lock.Layout -cne 'Monorepo' -or
            $lock.Repository.SourceSHA256 -cne $identity.Repository.SourceSHA256 -or
            @($lock.Projects).Count -ne $projects.Count){throw 'CommitWorkspaceStagedLockMismatch'}
        foreach($project in $projects){
            $locked=@($lock.Projects|Where-Object Name -CEQ $project.Name)
            $actual=@($identity.Projects|Where-Object Name -CEQ $project.Name)[0]
            if($locked.Count -ne 1 -or $locked[0].Path -cne $project.Path -or
                $locked[0].SourceSHA256 -cne $actual.SourceSHA256 -or
                (@($locked[0].Dependencies|Sort-Object) -join "`n") -cne (@($project.Dependencies|Sort-Object) -join "`n")){
                throw 'CommitWorkspaceStagedLockMismatch'
            }
        }
        Invoke-QuietCommitChecks -Root $snapshot
    }finally{
        # The absolute, generated snapshot was checked against its dedicated temporary root above.
        if(Test-Path -LiteralPath $snapshot){Remove-Item -LiteralPath $snapshot -Recurse -Force -WhatIf:$false -Confirm:$false}
    }
}

function Test-QuietScriptDocDrift {
    <#
    .SYNOPSIS
    Warns when a changed script file has no matching change to its mirrored doc under docs/scripts/.
    .PARAMETER ChangedPaths
    Repository-relative, forward-slash paths about to be committed (working tree + staged + untracked).
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ChangedPaths)
    $scriptsPrefix = 'scripts/'
    $selfName = Split-Path $PSCommandPath -Leaf
    $changedScripts = @($ChangedPaths | Where-Object {
        $_.StartsWith($scriptsPrefix) -and $_ -match '\.(ps1|psm1)$' -and (Split-Path $_ -Leaf) -ne $selfName
    })
    foreach ($scriptRelative in $changedScripts) {
        $underScripts = $scriptRelative.Substring($scriptsPrefix.Length)
        $docRelative = 'docs/scripts/' + $underScripts.Substring(0, $underScripts.LastIndexOf('.')) + '.md'
        if ($ChangedPaths -notcontains $docRelative) {
            Write-Warning "ScriptDocDrift: $scriptRelative changed without a matching change to $docRelative. Update the doc, or pass -NoScriptDocDriftWarning to override."
        }
    }
}

function Test-QuietBinaryContent {
    <#
    .SYNOPSIS
    Applies the standard git/diff NUL-byte heuristic to a file's leading bytes.
    .PARAMETER Path
    Absolute path of an existing, readable file.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new([Math]::Min(8000, $stream.Length))
        $read = $stream.Read($buffer, 0, $buffer.Length)
        for ($i = 0; $i -lt $read; $i++) { if ($buffer[$i] -eq 0) { return $true } }
        return $false
    } finally { $stream.Dispose() }
}

function Test-QuietCommitFileSniffer {
    <#
    .SYNOPSIS
    Warns (non-blocking) about a changed file that is binary content or larger than MaxBytes,
    unless it is already declared binary in .gitattributes.
    .PARAMETER WorkspaceRoot
    Repository whose pending changes (tracked + untracked, as `git status` reports them) are inspected.
    .PARAMETER MaxBytes
    Size threshold in bytes above which a non-exempted file is reported.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot, [Parameter(Mandatory)][long]$MaxBytes)
    # The module lives next to this script's own real location, not under the (possibly disposable
    # or fixture) $WorkspaceRoot being committed - matches the Measure-ColdStart.ps1 guard idiom.
    $moduleRoot = Split-Path $PSScriptRoot -Parent
    if (-not (Get-Command quiet -ErrorAction SilentlyContinue)) { Import-Module (Join-Path $moduleRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') }
    if (-not (Get-Module FrenchExDev2.QuietCli.Git.PoSh)) { Import-Module (Join-Path $moduleRoot 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1') }
    $status = quiet -AsObject -WorkingDirectory $WorkspaceRoot git status
    if ($status.Outcome -ne 'Success') {
        Write-Warning "CommitFileSniffer: could not read 'git status' via quiet (Outcome=$($status.Outcome)); skipping the binary/oversized-file check."
        return
    }
    foreach ($entry in @($status.Data.Entries)) {
        if ($entry.Kind -eq 'Ignored') { continue }
        if ($entry.Path -isnot [string]) { continue }
        if ($entry.Status -and $entry.Status.Contains('D')) { continue }
        $full = Join-Path $WorkspaceRoot $entry.Path
        if (!(Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $attr = quiet -AsObject -WorkingDirectory $WorkspaceRoot -- git check-attr binary -- $entry.Path
        if ($attr.Outcome -eq 'Success' -and @($attr.Data.Entries).Count -and $attr.Data.Entries[0].Value -ceq 'set') { continue }
        $size = (Get-Item -LiteralPath $full).Length
        $isBinary = Test-QuietBinaryContent -Path $full
        if ($isBinary -or $size -gt $MaxBytes) {
            $reason = if ($isBinary) { 'binary content' } else { "size $size bytes exceeds $MaxBytes bytes" }
            Write-Warning "CommitFileSniffer: $($entry.Path) ($reason). Mark it binary in .gitattributes if intentional, or pass -NoCommitFileSnifferWarning to override."
        }
    }
}

$knownCoAuthors = @{Claude = 'Claude Sonnet 5 <noreply@anthropic.com>'; Codex = 'Codex <noreply@openai.com>' }
$trailers = [Collections.Generic.List[string]]::new()
foreach ($entry in $CoAuthoredBy) {
    $resolved = if ($knownCoAuthors.ContainsKey($entry)) { $knownCoAuthors[$entry] } else { $entry }
    $trailer = 'Co-Authored-By: ' + $resolved
    if ($Message.Contains($trailer) -or $trailers.Contains($trailer)) { continue }
    $trailers.Add($trailer)
}
$finalMessage = if ($trailers.Count) { $Message.TrimEnd() + "`n`n" + ($trailers -join "`n") } else { $Message }

if (!$NoAll) { Invoke-QuietCommitChecks -Root $WorkspaceRoot }

if (!$NoScriptDocDriftWarning) {
    $tracked = @(if($NoAll){& git -C $WorkspaceRoot diff --cached --name-only}else{try { & git -C $WorkspaceRoot diff --name-only HEAD } catch { @() }})
    $untracked = @(if(!$NoAll){& git -C $WorkspaceRoot ls-files --others --exclude-standard})
    $changedPaths = @($tracked + $untracked | Where-Object { $_ } | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
    Test-QuietScriptDocDrift -ChangedPaths $changedPaths
}

if (!$NoCommitFileSnifferWarning) {
    Test-QuietCommitFileSniffer -WorkspaceRoot $WorkspaceRoot -MaxBytes $maxChangedFileBytes
}

if($NoAll){Assert-QuietStagedWorkspaceLock -WorkspaceRoot $WorkspaceRoot}

if (!$NoAll -and $PSCmdlet.ShouldProcess($WorkspaceRoot, 'Refresh workspace lock (Update-WorkspaceLock.ps1)')) {
    $null = & (Join-Path $PSScriptRoot Update-WorkspaceLock.ps1) -WorkspaceRoot $WorkspaceRoot
}
if (!$NoAll -and $PSCmdlet.ShouldProcess($WorkspaceRoot, "git add --all --")) {
    $null = Invoke-WorkspaceNative git @('-C', $WorkspaceRoot, 'add', '--all', '--') $WorkspaceRoot
}
if ($PSCmdlet.ShouldProcess($WorkspaceRoot, "git commit -m <message>")) {
    Invoke-WorkspaceNative git @('-C', $WorkspaceRoot, 'commit', '-m', $finalMessage) $WorkspaceRoot
}
