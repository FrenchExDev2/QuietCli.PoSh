#requires -Version 7.6
<#
.SYNOPSIS
Passes the immutable workflow revision and raw pull request body to the selective CI planner.
.PARAMETER Suite
Requested companion suites for manual dispatch.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Suite)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($env:GITHUB_SHA,'Generate GitHub CI plan outputs')){return}
$root=Split-Path $PSScriptRoot -Parent
$payload=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
$selection=switch -CaseSensitive ($env:GITHUB_EVENT_NAME) {
    'workflow_dispatch' {@{Suite=$Suite}}
    'push' {@{Base=$payload.before}}
    'pull_request' {
        $pr=$payload.pull_request
        if($env:GITHUB_REF -cnotmatch '\Arefs/pull/([1-9][0-9]*)/merge\z'){throw 'PullRequestCiRefInvalid'}
        $number=[int]$Matches[1]
        if(!$pr -or !$pr.Contains('body') -or !$pr.head.sha -or !$pr.base.sha){
            Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestCi.psm1')) -DisableNameChecking -ErrorAction Stop
            $pr=Read-QuietPullRequestCiSnapshot $root $env:GITHUB_REPOSITORY $number
            if($pr.merge_commit_sha -cne $env:GITHUB_SHA){throw 'PullRequestCiCheckpointChanged'}
        }
        if($pr.number -ne $number -or $pr.head.sha -cnotmatch '\A[a-f0-9]{40}\z'){throw 'PullRequestCiSnapshotUnavailable'}
        @{Base=$pr.base.sha;PullRequestBody=$pr.body}
    }
    default {throw 'CiImpactUnsupportedEvent'}
}
$null=& ([IO.Path]::Combine($PSScriptRoot,'New-CiImpactPlan.ps1')) @selection -Revision $env:GITHUB_SHA -Event $env:GITHUB_EVENT_NAME -OutputPath $env:GITHUB_OUTPUT -Confirm:$false
if($env:GITHUB_EVENT_NAME -ceq 'pull_request'){
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT,"pr_number=$number`npr_head=$($pr.head.sha)`npr_base=$($pr.base.sha)`n",[Text.UTF8Encoding]::new($false))
}
