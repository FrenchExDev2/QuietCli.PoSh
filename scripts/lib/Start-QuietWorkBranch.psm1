#Objective: Starts a fix, feature or chore branch from the freshly pulled delivery branch and carries pending work over through a retained stash.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptStartQuietWorkBranch {
    <#
    .SYNOPSIS
    Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.
    .DESCRIPTION
    The new branch always starts from the base branch (develop by default) after a fast-forward-only pull,
    checked against the remote head, and never tracks it. It never starts from the current branch.
    The name, the kind (fix, feature or chore) and the base are validated before anything runs,
    including under WhatIf. The checkout must be on a branch, without conflicts or an in-progress merge,
    rebase, cherry-pick, revert, am or bisect. The branch must not already exist locally or on the remote.
    Pending tracked and untracked changes are shelved in a stash, then applied with --index on the new
    branch and compared path by path. The stash is retained. When a step fails before the branch exists,
    the original branch is checked out again and the shelf re-applied.
    .PARAMETER Branch
    New work branch, for example feature/script-tests; an existing branch is never reset.
    .PARAMETER Kind
    Work branch kind (fix, feature or chore; releases are tags), used with Name instead of Branch.
    .PARAMETER Name
    Branch name after the kind, for example script-tests.
    .PARAMETER WorkspaceRoot
    Checkout containing the pending work and configured remote.
    .PARAMETER BaseBranch
    Existing local delivery branch to update using a fast-forward-only pull; never a work branch.
    .PARAMETER Remote
    Configured remote supplying the base branch, without fetching tags.
    .PARAMETER ShelfName
    Optional message identifying the retained Git stash.
    #>
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Branch')]
    param(
        [Parameter(Mandatory,ParameterSetName='Branch')][string]$Branch,
        [Parameter(Mandatory,ParameterSetName='Kind')][string]$Kind,
        [Parameter(Mandatory,ParameterSetName='Kind')][string]$Name,
        [string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))),
        [string]$BaseBranch='develop',
        [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
        [string]$ShelfName
    )
    $ErrorActionPreference='Stop'
    $target=if($PSCmdlet.ParameterSetName -eq 'Kind'){Resolve-QuietWorkBranchName -Kind $Kind -Name $Name}else{Resolve-QuietWorkBranchName -Branch $Branch}
    $Branch=$target.Branch
    Assert-QuietWorkBranchBase -BaseBranch $BaseBranch
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,"Shelve pending work, pull $Remote/$BaseBranch and create $Branch")){return}
    $sourceRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))
    $savedWhatIf=$WhatIfPreference;$savedConfirm=$ConfirmPreference
    try{
        $WhatIfPreference=$false;$ConfirmPreference='None'
        foreach($module in @('Core','Git')){
            $manifest=(Resolve-QuietWorkspacePath -WorkspaceRoot $sourceRoot -RelativePath "FrenchExDev2.QuietCli.$module.PoSh/FrenchExDev2.QuietCli.$module.PoSh.psd1")
            $expected=[IO.Path]::GetFullPath([IO.Path]::ChangeExtension($manifest,'.psm1'))
            $loaded=Get-Module "FrenchExDev2.QuietCli.$module.PoSh"
            if($loaded -and $loaded.Path -cne $expected){throw ('WorkBranchModulePathMismatch: '+$module+'; start a fresh session.')}
            $scope=if($module -eq 'Core'){'Global'}else{'Local'}
            if(!$loaded -or $module -eq 'Core'){Import-Module $manifest -Scope $scope -ErrorAction Stop -DisableNameChecking}
            if((Get-Module "FrenchExDev2.QuietCli.$module.PoSh").Path -cne $expected){throw 'WorkBranchModulePathMismatch'}
        }
    }finally{$WhatIfPreference=$savedWhatIf;$ConfirmPreference=$savedConfirm}

    function Invoke-QuietWorkBranchGit {
        <#
        .SYNOPSIS
        Runs one exact Git operation and rejects failed or incomplete outcomes without retrying.
        .PARAMETER Arguments
        Native arguments, never interpreted by a shell.
        #>
        param([string[]]$Arguments)
        $result=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" -Data ([Text.StringBuilder]::new()) -Output {
            param($record,$runtime)
            if($record.Stream -ne 'stdout'){return}
            if($runtime.Data.Length+$record.Text.Length -gt 65536){throw 'WorkBranchMetadataTooLarge'}
            [void]$runtime.Data.AppendLine($record.Text)
        } -Complete {param($runtime) $runtime.Data.ToString().TrimEnd()} -FilePath git -ArgumentList $Arguments
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count){throw ('WorkBranchGitFailed: '+$Arguments[0])}
        return [string]$result.Data
    }
    function Get-QuietWorkBranchStatus {
        <#
        .SYNOPSIS
        Returns the complete quiet git status data of the checkout, or throws WorkBranchStatusFailed.
        #>
        $status=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot git status
        if($status.Outcome -ne 'Success' -or !$status.Completeness.Source -or !$status.Completeness.Analysis -or $status.Error.Count){throw 'WorkBranchStatusFailed'}
        return $status.Data
    }
    function Get-QuietWorkBranchFileStates {
        <#
        .SYNOPSIS
        Pairs each pending status entry with the SHA-256 of its working tree file, null when it is absent.
        .PARAMETER Entries
        Status entries with Path and Status.
        #>
        param([AllowEmptyCollection()][object[]]$Entries=@())
        @(foreach($entry in $Entries){
            $path=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $entry.Path)
            [pscustomobject]@{Path=$entry.Path;Status=$entry.Status;Hash=if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{$null}}
        })
    }

    $null=Invoke-QuietWorkBranchGit @('check-ref-format','--branch',$Branch)
    $null=Invoke-QuietWorkBranchGit @('check-ref-format','--branch',$BaseBranch)
    if(Invoke-QuietWorkBranchGit @('branch','--list',$Branch)){throw ('WorkBranchAlreadyExists: '+$Branch)}
    if(!(Invoke-QuietWorkBranchGit @('branch','--list',$BaseBranch))){throw ('WorkBranchLocalBaseMissing: '+$BaseBranch)}
    $status=Get-QuietWorkBranchStatus
    $problems=@(Get-QuietWorkBranchStatusProblems -Status $status)
    if($problems.Count){throw ('WorkBranchInitialStateInvalid: '+($problems -join ', '))}
    # Checked before shelving, so a refusal leaves the checkout untouched.
    $heads=ConvertFrom-QuietWorkBranchLsRemote -Text (Invoke-QuietWorkBranchGit @('ls-remote','--heads',$Remote,('refs/heads/'+$Branch),('refs/heads/'+$BaseBranch)))
    if($heads.ContainsKey('refs/heads/'+$Branch)){throw ('WorkBranchAlreadyExistsOnRemote: '+$Remote+'/'+$Branch)}
    if(!$heads.ContainsKey('refs/heads/'+$BaseBranch)){throw ('WorkBranchRemoteBaseMissing: '+$Remote+'/'+$BaseBranch)}
    $originalBranch=$status.Branch
    $files=@(Get-QuietWorkBranchFileStates -Entries @($status.Entries))
    $shelf=$null
    $created=$false
    try{
        if($files.Count){
            if(!$ShelfName){$ShelfName='quietcli-shelf-before-'+$Branch+'-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')}
            $null=Invoke-QuietWorkBranchGit @('stash','push','--include-untracked','--message',$ShelfName)
            $shelf=Invoke-QuietWorkBranchGit @('rev-parse','--verify','refs/stash')
            if($shelf -cnotmatch '\A[a-f0-9]{40}(?:[a-f0-9]{24})?\z'){throw 'WorkBranchShelfIdentityInvalid'}
            Write-Host ('Shelf retained: '+$shelf+' | '+$ShelfName)
        }
        if(!(Get-QuietWorkBranchStatus).Clean){throw 'WorkBranchShelfDidNotCleanCheckout'}
        $null=Invoke-QuietWorkBranchGit @('switch',$BaseBranch)
        $null=Invoke-QuietWorkBranchGit @('pull','--ff-only','--no-tags',$Remote,$BaseBranch)
        $baseCommit=Invoke-QuietWorkBranchGit @('rev-parse','HEAD')
        $remoteHeads=ConvertFrom-QuietWorkBranchLsRemote -Text (Invoke-QuietWorkBranchGit @('ls-remote','--heads',$Remote,('refs/heads/'+$BaseBranch)))
        $remoteCommit=$null
        if(!$remoteHeads.TryGetValue('refs/heads/'+$BaseBranch,[ref]$remoteCommit) -or $remoteCommit -cne $baseCommit){throw ('WorkBranchBaseDiffersFromRemote: '+$BaseBranch+' '+$baseCommit+' vs '+$Remote+' '+$remoteCommit)}
        $null=Invoke-QuietWorkBranchGit @('switch','--no-track','-c',$Branch,$BaseBranch)
        $created=$true
    }catch{
        $failure=$_.Exception.Message
        if($created){throw}
        $recovery=try{
            $null=Invoke-QuietWorkBranchGit @('switch',$originalBranch)
            if($shelf){
                $null=Invoke-QuietWorkBranchGit @('stash','apply','--index',$shelf)
                'pending work restored on '+$originalBranch+'; shelf '+$shelf+' retained'
            }else{'back on '+$originalBranch}
        }catch{
            if($shelf){'pending work kept in shelf '+$shelf+' ('+$ShelfName+'); restore it with git stash apply --index '+$shelf}else{'checkout left on its current branch'}
        }
        throw ($failure+' | '+$recovery)
    }
    if($shelf){$null=Invoke-QuietWorkBranchGit @('stash','apply','--index',$shelf)}
    $restored=Get-QuietWorkBranchStatus
    if($restored.Branch -cne $Branch -or $restored.Counts.Conflicted){throw ('WorkBranchRestoreFailed: shelf '+$shelf+' retained')}
    $changed=@(Compare-QuietWorkBranchShelf -Before $files -After @(Get-QuietWorkBranchFileStates -Entries @($restored.Entries)))
    if($changed.Count){throw ('WorkBranchShelfContentChanged: '+($changed -join ', ')+'; shelf '+$shelf+' retained')}
    [pscustomobject]@{Branch=$Branch;Kind=$target.Kind;BaseBranch=$BaseBranch;BaseCommit=$baseCommit;PreviousBranch=$originalBranch;Shelf=$shelf;ShelfName=$ShelfName;RestoredFiles=$files.Count;ShelfRetained=[bool]$shelf}
}

Export-ModuleMember -Function 'Invoke-QuietScriptStartQuietWorkBranch'
