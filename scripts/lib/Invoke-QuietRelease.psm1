function Invoke-QuietScriptInvokeQuietRelease {
#requires -Version 7.6
<#
.SYNOPSIS
Releases modules end to end: version commit on a release/* branch, pull request, required CI, merge commit, then tags.
.DESCRIPTION
Wires the release flow to the checkout's quiet Git facade, Commit-Workspace, Push-Workspace and the GitHub CLI.
See Invoke-QuietRelease.ps1 for the operator contract.
.PARAMETER WorkspaceRoot
Clean QuietCli2 checkout; defaults to this script's checkout.
.PARAMETER Module
Discovered component aliases, full package names or All.
.PARAMETER Version
Common requested base or full version; preview counters remain independent per package.
.PARAMETER Preview
Explicit positive preview number, or null to detect the next numeric preview from local and remote tags.
.PARAMETER NextPreview
Detects the next numeric preview independently for every selected package.
.PARAMETER Message
Optional release commit message.
.PARAMETER Remote
Configured Git remote, origin by default.
.PARAMETER DeliveryBranch
Protected branch receiving the release pull request, develop by default.
.PARAMETER Resume
Receipt of an unfinished release flow to continue with its recorded request.
.PARAMETER Merge
Merges the pull request with a merge commit once the required check succeeds.
.PARAMETER PollSeconds
Interval between pull request observations, 30 seconds by default.
.PARAMETER TimeoutMinutes
Bound on waiting for the check and the merge, 120 minutes by default; a timeout is resumable.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High',DefaultParameterSetName='Start')]
param(
    [string]$WorkspaceRoot=(Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),
    [Parameter(ParameterSetName='Start')][string[]]$Module=@('Core'),
    [Parameter(Mandatory,ParameterSetName='Start')][string]$Version,
    [Parameter(ParameterSetName='Start')][Nullable[int]]$Preview,
    [Parameter(ParameterSetName='Start')][switch]$NextPreview,
    [Parameter(ParameterSetName='Start')][string]$Message,
    [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',
    [Parameter(Mandatory,ParameterSetName='Resume')][string]$Resume,
    [switch]$Merge,
    [ValidateRange(5,3600)][int]$PollSeconds=30,
    [ValidateRange(0,1440)][double]$TimeoutMinutes=120
)
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent
# Git's RequiredModules registration resolves Core commands from the process-global scope, so Core is
# imported globally first. Registration is in-memory only, so it also runs under -WhatIf.
$savedWhatIf=$WhatIfPreference;$savedConfirm=$ConfirmPreference
try{
    $WhatIfPreference=$false;$ConfirmPreference='None'
    foreach($component in @('Core','Git')){
        $name="FrenchExDev2.QuietCli.$component.PoSh"
        $path=[IO.Path]::Combine($sourceRoot,$name,($name+'.psm1'))
        $loaded=Get-Module -Name $name -All
        if($loaded -and @($loaded|Where-Object {![StringComparer]::OrdinalIgnoreCase.Equals($_.Path,$path)}).Count){throw "ReleaseFlowUnexpectedModulePath: $name; start a fresh PowerShell session."}
        $manifest=[IO.Path]::Combine($sourceRoot,"$name/$name.psd1")
        if($component -ceq 'Core'){Import-Module $manifest -Scope Global -ErrorAction Stop -DisableNameChecking}
        elseif(!$loaded){Import-Module $manifest -ErrorAction Stop -DisableNameChecking}
        if(![StringComparer]::OrdinalIgnoreCase.Equals((Get-Module -Name $name).Path,$path)){throw "ReleaseFlowUnexpectedModulePath: $name"}
    }
}finally{$WhatIfPreference=$savedWhatIf;$ConfirmPreference=$savedConfirm}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseFlow.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PullRequestUpdates.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path))
$scriptDirectory=[IO.Path]::GetDirectoryName($PSScriptRoot)

function Invoke-QuietReleaseGit {
    <#
    .SYNOPSIS
    Runs one explicit Git operation, retaining bounded metadata lines, first value and output presence.
    .PARAMETER Arguments
    Exact native arguments; no shell expansion or implicit retries.
    #>
    param([string[]]$Arguments)
    $result=quiet -AsObject -C release-flow -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" `
        -Data @{Value='';HasOutput=$false;Lines=[Collections.Generic.List[string]]::new();Bytes=0L} -Output {
            param($event,$runtime)
            if($event.Stream -ne 'stdout'){return}
            $line=$event.Text.TrimEnd([char[]]"`r`n")
            if(!$line.Length){return}
            $runtime.Data.Bytes+=[Text.Encoding]::UTF8.GetByteCount($line)
            if($runtime.Data.Lines.Count -ge 50000 -or $runtime.Data.Bytes -gt 4MB){throw 'ReleaseGitMetadataLimitExceeded'}
            $runtime.Data.Lines.Add($line)
            if(!$runtime.Data.HasOutput){
                if($line.Length -gt 4096){throw 'ReleaseGitValueTooLong'}
                $runtime.Data.Value=$line
            }
            $runtime.Data.HasOutput=$true
        } -Complete {param($runtime) $runtime.Data} -FilePath git -ArgumentList $Arguments
    if($result.Outcome -ne 'Success' -or $result.Execution.Native.ExitCode -ne 0 -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or @($result.Error).Count){
        throw "ReleaseFlowGitFailed: $($Arguments[0]); $($result.Outcome). No retry was attempted."
    }
    return $result.Data
}

$repository=(Invoke-QuietReleaseGit @('rev-parse','--show-toplevel')).Value
$comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if(!$WorkspaceRoot.Equals([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($repository)),$comparison)){throw 'ReleaseFlowWorkspaceMustBeRepositoryRoot'}
$options=@{WorkspaceRoot=$WorkspaceRoot;Merge=$Merge;PollSeconds=$PollSeconds;TimeoutMinutes=$TimeoutMinutes
    GitCommand={param($arguments) Invoke-QuietReleaseGit -Arguments $arguments}
    CommitCommand={
        param($root,$message,$paths)
        $allowed=@($paths)
        $changed=@((Invoke-QuietReleaseGit @('diff','--name-only','HEAD')).Lines)
        if(@($changed|Where-Object {$_ -cnotin $allowed}).Count){throw 'ReleaseUnrelatedChangesBeforeCommit'}
        $null=Invoke-QuietReleaseGit (@('add','--')+$allowed)
        & ([IO.Path]::Combine($scriptDirectory,'Commit-Workspace.ps1')) -WorkspaceRoot $root -NoAll -Message $message -Confirm:$false|Out-Null
    }
    PushBranchCommand={
        param($root,$remote,$branch)
        if($branch -cnotmatch '\Arelease/'){throw 'ReleaseFlowPushRestrictedToReleaseBranches'}
        & ([IO.Path]::Combine($scriptDirectory,'Push-Workspace.ps1')) -WorkspaceRoot $root -Remote $remote -Branch $branch -Confirm:$false|Out-Null
    }
    GitHubCommand={param($arguments) Invoke-QuietPullRequestTool $WorkspaceRoot gh $arguments}}
if($PSCmdlet.ParameterSetName -ceq 'Resume'){
    $options.Resume=$Resume
    $action='Resume the release flow recorded in '+$Resume+'; merge='+[bool]$Merge
}else{
    foreach($key in @('Module','Version','NextPreview','Message','Remote','DeliveryBranch')){if($PSBoundParameters.ContainsKey($key)){$options[$key]=$PSBoundParameters[$key]}}
    if($PSBoundParameters.ContainsKey('Preview')){$options.Preview=$Preview;$options.PreviewSpecified=$true}
    $action='Release '+(@($Module) -join ',')+' '+$Version+' through a release/* pull request into '+$DeliveryBranch+'; merge='+[bool]$Merge+'; tags follow the merge'
}
# One confirmation covers the whole flow; WhatIf delegates to the flow's local-only provisional plan.
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,$action)){
    if($WhatIfPreference){Invoke-QuietReleaseFlow @options -WhatIf}
    return
}
Invoke-QuietReleaseFlow @options -WhatIf:$false -Confirm:$false

}
Export-ModuleMember -Function 'Invoke-QuietScriptInvokeQuietRelease'
