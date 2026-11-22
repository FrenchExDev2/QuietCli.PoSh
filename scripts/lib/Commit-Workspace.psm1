
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
function Invoke-QuietScriptCommitWorkspace {
#requires -Version 7.6
<#
.SYNOPSIS
Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.
.DESCRIPTION
Before staging, runs Invoke-WorkspaceChecks.ps1: script layout/naming, script docs, workflow receipts/graphs/index,
new-script WhatIf/Confirm support, documentation credits and aggregate credits. The same registry
validates exported staged snapshots with NoAll. Explicit skip switches or SkipCheck report omissions;
NoSyncChecks skips documentation checks but retains independent script layout and safety checks.
After a successful commit, writes the selective CI plan for that commit to CiPlanPath.
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
warning still run and report exactly as they would for a real commit, but nothing is staged
and no commit is created.
With -NoAll, the working tree and index are never refreshed or staged. An isolated temporary index
snapshot supplies the manifest and documentation checks, including during WhatIf preview.
.PARAMETER Message
Required commit message, without trailers.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER CiPlanPath
Markdown plan destination. Relative paths are anchored in WorkspaceRoot, with .artifacts/plan.md as the default.
.PARAMETER Repository
Only Workspace exists; retained to reject accidental requests for independent module commits.
.PARAMETER CoAuthoredBy
Opt-in, no trailer by default. Co-Authored-By trailers appended after the message, one per
contributing agent explicitly named by the caller; each entry is either `Name <email>` or a known
agent name from `$knownCoAuthors` (see docs/agents/README.md for the documented list). Skips an
entry already present verbatim in Message so a caller-supplied trailer is never duplicated.
.PARAMETER NoAll
Commits only the prepared index without staging any file.
Validates manifests and source/documentation policy in an isolated index snapshot before committing.
Internal source identity belongs to Git and execution evidence, not a committed source lock.
.PARAMETER NoScriptsReadmeCheck
Skips the scripts/README documentation-coverage gate (Sync-ScriptsReadme.ps1).
.PARAMETER NoDocsCreditsCheck
Skips the docs credits-block gate (Sync-DocsCredits.ps1).
.PARAMETER NoCreditsCheck
Skips the aggregated CREDITS.md gate (Sync-Credits.ps1).
.PARAMETER NoSyncChecks
Skips documentation checks, including GitHub workflow, resource and script review documentation.
The ScriptLayout and ScriptShouldProcess checks remain active unless explicitly skipped.
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
Human-readable size (see Common.psm1's ConvertTo-QuietByteCount: "500KB", "1MiB", "2GiB", or a bare
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
Skips every documentation-sync gate and the drift warning; still stages and commits.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Preview" -WhatIf
Runs the gates and reports script/doc drift, but refreshes nothing, stages nothing and commits
nothing.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Commit selected changes" -NoAll
Validates and commits the prepared index; preserves unstaged changes.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Vendor a tool" -MaxChangedFileSize 2MiB
Raises the binary/oversized-file sniffer's threshold to 2 MiB for this run only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Message,
    [string]$WorkspaceRoot = (Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),
    [ValidateNotNullOrWhiteSpace()][string]$CiPlanPath = '.artifacts/plan.md',
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
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Common.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot, $PWD.ProviderPath)
$planPath = [IO.Path]::GetFullPath($CiPlanPath, $WorkspaceRoot)
$maxChangedFileBytes = ConvertTo-QuietByteCount $MaxChangedFileSize

function Invoke-QuietCommitChecks {
    <#
    .SYNOPSIS
    Maps compatibility switches to the shared registry, for either working-tree or index validation.
    .PARAMETER Root
    Exact tree or staged snapshot being checked.
    #>
    param([string]$Root)
    $null=Get-QuietWorkspaceProjects $Root
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
    $registry=[IO.Path]::Combine(([IO.Path]::GetDirectoryName($PSScriptRoot)),'Invoke-WorkspaceChecks.ps1')
    $skips=@($Skipped|Sort-Object -Unique)
    if($Root -ceq $WorkspaceRoot){& $registry -WorkspaceRoot $Root -SkipCheck $skips;return}
    # A parser loaded from a prepared snapshot locks its DLL on Windows until process exit.
    # Run the trusted registry in a child process before deleting that owned snapshot.
    $skipLiteral=(@($skips|ForEach-Object {"'"+$_.Replace("'","''")+"'"}) -join ',')
    $code="`$ErrorActionPreference='Stop';try{& '"+$registry.Replace("'","''")+"' -WorkspaceRoot '"+$Root.Replace("'","''")+"' -SkipCheck @("+$skipLiteral+")|ForEach-Object {[Console]::Out.WriteLine('QUIET_INDEX_CHECK:'+(`$_|ConvertTo-Json -Compress -Depth 4))}}catch{[Console]::Error.WriteLine('QUIET_INDEX_ERROR:'+(`$_.Exception.Message|ConvertTo-Json -Compress));exit 1}"
    $state=@{Failure=$null;Checks=[Collections.Generic.List[object]]::new()}
    $result=Invoke-CiProcess -FilePath (Get-Command pwsh -CommandType Application|Select-Object -First 1).Source -ArgumentList @('-NonInteractive','-OutputFormat','Text','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))) -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 600 -State $state -OnOutput {
        param($event,$state)
        foreach($line in $event.Text.Split([char]10,[StringSplitOptions]::RemoveEmptyEntries)){
            if($line.StartsWith('QUIET_INDEX_ERROR:',[StringComparison]::Ordinal)){$state.Failure=$line.Substring(18)|ConvertFrom-Json}
            elseif($line.StartsWith('QUIET_INDEX_CHECK:',[StringComparison]::Ordinal)){$state.Checks.Add(($line.Substring(18)|ConvertFrom-Json))}
            else{Write-Host $line}
        }
    }
    if($result.Outcome -ne 'Success'){
        if($state.Failure){throw $state.Failure}
        throw 'CommitWorkspaceIndexChecksFailed'
    }
    $state.Checks.ToArray()
}

function Assert-QuietStagedWorkspaceChecks {
    <#
    .SYNOPSIS
    Checks a prepared index's manifests and policy without staging working-tree changes.
    .PARAMETER WorkspaceRoot
    Repository whose index is exported read-only to an owned temporary snapshot.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $changes=Invoke-CiProcess -FilePath git -ArgumentList @('-C',$WorkspaceRoot,'diff','--cached','--quiet','--exit-code') -WorkingDirectory $WorkspaceRoot
    if($changes.ExitCode -eq 0){throw 'CommitWorkspaceNothingStaged'}
    if($changes.ExitCode -ne 1 -or $changes.Outcome -ne 'Failed'){throw 'CommitWorkspaceIndexUnavailable'}
    $temporaryRoot=[IO.Path]::GetFullPath(([IO.Path]::Combine(([IO.Path]::GetTempPath()),'QuietCli2/commit-index')))
    $snapshot=[IO.Path]::GetFullPath(([IO.Path]::Combine($temporaryRoot,([guid]::NewGuid().ToString('N')))))
    if(![IO.Path]::IsPathFullyQualified($snapshot) -or !($snapshot.StartsWith($temporaryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal))){throw 'CommitWorkspaceSnapshotPathInvalid'}
    [void][IO.Directory]::CreateDirectory($snapshot)
    try{
        $null=Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'checkout-index','--all',('--prefix='+$snapshot.Replace('\','/')+'/')) $WorkspaceRoot
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
    $selfName = Split-Path ([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'../Commit-Workspace.ps1'))) -Leaf
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
    $moduleRoot = Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent
    foreach($name in @('Core','Git')){
        $moduleName='FrenchExDev2.QuietCli.'+$name+'.PoSh'
        $expected=[IO.Path]::GetFullPath([IO.Path]::Combine((Resolve-QuietWorkspacePath $moduleRoot $moduleName),($moduleName+'.psm1')))
        foreach($loaded in @(Get-Module $moduleName -All)){
            if($loaded.Path -cne $expected){throw ('CommitLocalModulePathMismatch: '+$moduleName+'; start a fresh session.')}
        }
    }
    $coreManifest=[IO.Path]::Combine($moduleRoot,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    # Git's RequiredModules registration resolves Core commands from the process-global scope.
    $savedWhatIf=$WhatIfPreference;$savedConfirm=$ConfirmPreference
    try{
        # In-memory command registration is required even for a read-only preview.
        $WhatIfPreference=$false;$ConfirmPreference='None'
        Import-Module $coreManifest -Scope Global -DisableNameChecking -ErrorAction Stop
        if (-not (Get-Module FrenchExDev2.QuietCli.Git.PoSh)) { Import-Module ([IO.Path]::Combine($moduleRoot,'src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1')) -DisableNameChecking -ErrorAction Stop }
    }finally{$WhatIfPreference=$savedWhatIf;$ConfirmPreference=$savedConfirm}
    $status = quiet -AsObject -WorkingDirectory $WorkspaceRoot git status
    if ($status.Outcome -ne 'Success') {
        Write-Warning "CommitFileSniffer: could not read 'git status' via quiet (Outcome=$($status.Outcome)); skipping the binary/oversized-file check."
        return
    }
    foreach ($entry in @($status.Data.Entries)) {
        if ($entry.Kind -eq 'Ignored') { continue }
        if ($entry.Path -isnot [string]) { continue }
        if ($entry.Status -and $entry.Status.Contains('D')) { continue }
        $full = (Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $entry.Path)
        if (!(Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $attr = quiet -AsObject -WorkingDirectory $WorkspaceRoot -- git check-attr binary -- $entry.Path
        if ($attr.Outcome -eq 'Success' -and @($attr.Data.Entries).Count -and $attr.Data.Entries[0].Value -ceq 'set') { continue }
        $size = (Get-Item -LiteralPath $full -Force).Length
        $isBinary = Test-QuietBinaryContent -Path $full
        if ($isBinary -or $size -gt $MaxBytes) {
            $reason = if ($isBinary) { 'binary content' } else { "size $size bytes exceeds $MaxBytes bytes" }
            Write-Warning "CommitFileSniffer: $($entry.Path) ($reason). Mark it binary in .gitattributes if intentional, or pass -NoCommitFileSnifferWarning to override."
        }
    }
}

function Get-QuietCommitPlanRevision {
    <#
    .SYNOPSIS
    Reads and validates a Git revision for the post-commit planner.
    .PARAMETER Arguments
    Git arguments for a query returning one SHA or an optional ref that does not exist.
    #>
    param([string[]]$Arguments)
    $state = @{ Sha = $null }
    $result = Invoke-CiProcess -FilePath git -ArgumentList $Arguments -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {
        param($record, $state)
        if ($record.Stream -ceq 'stdout') { $state.Sha = $record.Text }
    }
    if ($result.Outcome -ceq 'Success' -and $state.Sha -cmatch '\A[a-f0-9]{40}\z') { return $state.Sha }
    if ($result.ExitCode -ne 1 -or '--quiet' -cnotin $Arguments) { throw "CommitWorkspacePlanRevisionUnavailable: $($Arguments -join ' ')" }
}

function Write-QuietCommitCiPlan {
    <#
    .SYNOPSIS
    Generates the Markdown CI forecast from the committed source tree.
    .PARAMETER Revision
    SHA of the newly created commit.
    #>
    param([string]$Revision)
    $delivery = Get-QuietCommitPlanRevision @('rev-parse','--verify','--quiet','refs/remotes/origin/develop')
    $base = if ($delivery) {
        Get-QuietCommitPlanRevision @('merge-base',$delivery,$Revision)
    } else {
        Get-QuietCommitPlanRevision @('rev-parse','--verify','--quiet',($Revision+'^'))
    }
    if (!$base) { $base = '4b825dc642cb6eb9a060e54bf8d69288fbee4904' }

    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $snapshot = [IO.Path]::GetFullPath(('quiet-commit-plan-'+[guid]::NewGuid().ToString('N')), $temporaryRoot)
    if ([IO.Path]::GetDirectoryName($snapshot) -ne [IO.Path]::TrimEndingDirectorySeparator($temporaryRoot)) {
        throw 'CommitWorkspacePlanSnapshotPathInvalid'
    }
    $archive = $snapshot+'.tar'
    [void][IO.Directory]::CreateDirectory($snapshot)
    try {
        $null = Invoke-WorkspaceNative git @('archive','--format=tar',('--output='+$archive),$Revision) $WorkspaceRoot
        [System.Formats.Tar.TarFile]::ExtractToDirectory($archive,$snapshot,$false)
        $coreName = 'FrenchExDev2.QuietCli.Core.PoSh'
        $sourceCore = Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $coreName
        $snapshotCore = Resolve-QuietWorkspacePath -WorkspaceRoot $snapshot -RelativePath $coreName
        $parser = [IO.Path]::Combine($sourceCore,'resources/yaml/YamlDotNet.dll')
        if ([IO.File]::Exists($parser)) {
            $destination = [IO.Path]::Combine($snapshotCore,'resources/yaml/YamlDotNet.dll')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [IO.File]::Copy($parser,$destination,$true)
        }
        $planner = [IO.Path]::Combine([IO.Path]::GetDirectoryName($PSScriptRoot),'New-CiImpactPlan.ps1')
        # Loading the snapshot's YAML parser in a child releases its file before Windows cleanup.
        $diagnostics = [Collections.Generic.Queue[string]]::new()
        $result = Invoke-CiProcess -FilePath pwsh -ArgumentList @('-NonInteractive','-File',$planner,'-WorkspaceRoot',$WorkspaceRoot,'-SourceRoot',$snapshot,'-Base',$base,'-Revision',$Revision,'-MarkdownPath',$planPath) -WorkingDirectory $WorkspaceRoot -State $diagnostics -OnOutput {
            param($record,$state)
            if ($record.Stream -ceq 'stderr') {
                if ($state.Count -eq 8) { $null = $state.Dequeue() }
                $state.Enqueue($record.Text)
            } else { Write-Host $record.Text }
        }
        if ($result.Outcome -cne 'Success' -or ![IO.File]::Exists($planPath)) {
            throw "CommitWorkspacePlanUnavailable ($($result.Outcome)): $($diagnostics -join ' ')"
        }
        Write-Host "CI plan for $Revision written to $planPath"
    } finally {
        if ([IO.File]::Exists($archive)) { [IO.File]::Delete($archive) }
        Remove-Item -LiteralPath $snapshot -Recurse -Force -ErrorAction Stop
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

if($NoAll){Assert-QuietStagedWorkspaceChecks -WorkspaceRoot $WorkspaceRoot}

if (!$NoAll -and $PSCmdlet.ShouldProcess($WorkspaceRoot, "git add --all --")) {
    $null = Invoke-WorkspaceNative git @('-C', $WorkspaceRoot, 'add', '--all', '--') $WorkspaceRoot
}
if ($PSCmdlet.ShouldProcess($WorkspaceRoot, "git commit -m <message>")) {
    Invoke-WorkspaceNative git @('-C', $WorkspaceRoot, 'commit', '-m', $finalMessage) $WorkspaceRoot
    $revision = $null
    try {
        $revision = Get-QuietCommitPlanRevision @('rev-parse','HEAD')
        Write-QuietCommitCiPlan -Revision $revision
    } catch {
        Write-Warning "Commit succeeded ($revision). CI plan generation failed for '$planPath': $($_.Exception.Message)"
    }
}

}
Export-ModuleMember -Function 'Invoke-QuietScriptCommitWorkspace'
