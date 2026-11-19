#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'MergedBranches.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietOriginBranchTool {
    <#
    .SYNOPSIS
    Runs Git or gh and returns its bounded standard output on success.
    .PARAMETER FilePath
    Tool to invoke.
    .PARAMETER ArgumentList
    Exact native arguments.
    .PARAMETER WorkspaceRoot
    Working directory of the tool.
    #>
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkspaceRoot)
    $buffer = [Text.StringBuilder]::new()
    $result = Invoke-CiProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 120 -MaxRecordChars 1048576 -State $buffer -OnOutput {
        param($record, $buffer)
        if ($record.Stream -eq 'stdout') {
            if ($buffer.Length + $record.Text.Length -ge 1048576) { throw 'MergedOriginOutputTooLarge' }
            [void]$buffer.AppendLine($record.Text)
        }
    }
    if ($result.Outcome -ne 'Success' -or $result.ExitCode -ne 0) {
        throw "MergedOriginToolFailed: $FilePath $($ArgumentList[0]) ($($result.Outcome), exit $($result.ExitCode))"
    }
    $buffer.ToString().TrimEnd("`r", "`n")
}

function Get-QuietMergedOriginBranchPlan {
    <#
    .SYNOPSIS
    Evaluates each advertised origin branch against merged pull request evidence.
    .PARAMETER RemoteRefs
    Output of git ls-remote --symref origin HEAD 'refs/heads/*'.
    .PARAMETER PullRequests
    Ordinal dictionary of the latest same-repository pull requests merged into develop.
    #>
    param([string]$RemoteRefs, [object]$PullRequests)
    $defaultRef = ''
    $headTip = $null
    $refLines = foreach ($line in ($RemoteRefs -split '\r?\n')) {
        if ($line -cmatch '\Aref: (?<ref>refs/heads/\S+)\tHEAD\z') {
            if ($defaultRef) { throw 'MergedOriginDefaultAmbiguous' }
            $defaultRef = $Matches.ref
        } elseif ($line -cmatch '\A(?<oid>[0-9a-f]{40}(?:[0-9a-f]{24})?)\tHEAD\z') {
            if ($headTip) { throw 'MergedOriginDefaultAmbiguous' }
            $headTip = $Matches.oid
        } else {
            $line
        }
    }
    $heads = ConvertFrom-QuietWorkBranchLsRemote -Text ($refLines -join "`n")
    if (!$heads.ContainsKey('refs/heads/develop')) { throw 'MergedOriginDevelopMissing' }
    $defaultTip = $null
    if (!$heads.TryGetValue($defaultRef, [ref]$defaultTip) -or $defaultTip -cne $headTip) {
        throw 'MergedOriginDefaultUnknown'
    }
    foreach ($ref in ($heads.Keys | Sort-Object -CaseSensitive)) {
        if (!$ref.StartsWith('refs/heads/', [StringComparison]::Ordinal)) { throw 'MergedOriginUnexpectedRef' }
        $branch = $ref.Substring('refs/heads/'.Length)
        $pr = $null
        $reason = if ($ref -ceq $defaultRef -or $branch -in 'develop', 'main', 'master') {
            'Protected'
        } elseif (!$PullRequests.TryGetValue($branch, [ref]$pr)) {
            'NoMergedPullRequest'
        } elseif ($heads[$ref] -cne $pr.HeadRefOid) {
            'TipDiffersFromPullRequest'
        } else {
            'MergedPullRequest'
        }
        [pscustomobject]@{
            Branch = $branch
            Ref = $ref
            Tip = $heads[$ref]
            PullRequest = ${pr}?.Number
            Reason = $reason
            State = if ($reason -eq 'MergedPullRequest') { 'Eligible' } else { 'Kept' }
        }
    }
}

function Invoke-QuietScriptRemoveQuietMergedOriginBranches {
    <#
    .SYNOPSIS
    Plans or atomically deletes origin branches with exact merged pull request evidence.
    .PARAMETER WorkspaceRoot
    Checkout with a github.com origin.
    .PARAMETER Limit
    Maximum merged pull requests to read from GitHub.
    .PARAMETER Apply
    Requests deletion of eligible branches, subject to confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$WorkspaceRoot = ([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..'))),
        [ValidateRange(1, 1000)][int]$Limit = 1000,
        [switch]$Apply
    )
    $ErrorActionPreference = 'Stop'
    if ($WhatIfPreference) {
        $null = $PSCmdlet.ShouldProcess('origin', 'Check and optionally remove branches merged into develop')
        return
    }
    $WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot, $PWD.Path)
    $fetchUrl = Invoke-QuietOriginBranchTool git @('remote', 'get-url', '--all', 'origin') $WorkspaceRoot
    $pushUrl = Invoke-QuietOriginBranchTool git @('remote', 'get-url', '--push', '--all', 'origin') $WorkspaceRoot
    $repository = Get-QuietMergedBranchRepository -RemoteUrl $fetchUrl
    $pushRepository = Get-QuietMergedBranchRepository -RemoteUrl $pushUrl
    if (!$repository -or $repository -ine $pushRepository) { throw 'MergedOriginRepositoryMismatch' }

    $refs = Invoke-QuietOriginBranchTool git @('ls-remote', '--symref', 'origin', 'HEAD', 'refs/heads/*') $WorkspaceRoot
    $json = Invoke-QuietOriginBranchTool gh @('pr', 'list', '--repo', "github.com/$repository", '--state', 'merged', '--base', 'develop', '--limit', [string]$Limit, '--json', 'number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository') $WorkspaceRoot
    $pullRequests = ConvertFrom-QuietMergedBranchPullRequests -Json $json -BaseBranch develop
    if ((ConvertFrom-Json -InputObject $json -NoEnumerate).Count -ge $Limit) {
        Write-Warning 'MergedOriginLimitReached: older pull requests might be missing from this plan.'
    }
    $plan = @(Get-QuietMergedOriginBranchPlan -RemoteRefs $refs -PullRequests $pullRequests)
    $candidates = @($plan | Where-Object State -eq 'Eligible')
    if ($Apply -and $candidates.Count) {
        $target = "$repository on origin ($($candidates.Branch -join ', '))"
        if ($PSCmdlet.ShouldProcess($target, 'Delete branches with an atomic, SHA-guarded Git push')) {
            $leases = @($candidates | ForEach-Object { "--force-with-lease=$($_.Ref):$($_.Tip)" })
            $deletions = @($candidates | ForEach-Object { ":$($_.Ref)" })
            $arguments = @('-c', 'remote.origin.mirror=false', 'push', '--atomic', '--no-follow-tags', '--recurse-submodules=no') + $leases + @('origin') + $deletions
            try {
                $null = Invoke-QuietOriginBranchTool git $arguments $WorkspaceRoot
            } catch {
                throw "MergedOriginDeletionUnconfirmed: rerun the read-only plan before retrying. $($_.Exception.Message)"
            }
            foreach ($candidate in $candidates) { $candidate.State = 'Deleted' }
        }
    }
    $plan
}

Export-ModuleMember -Function Invoke-QuietScriptRemoveQuietMergedOriginBranches
