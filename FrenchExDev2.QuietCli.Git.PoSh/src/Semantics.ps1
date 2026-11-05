function Invoke-QuietGitMutation {
    <#
.SYNOPSIS
Validates interactive mutation requirements before executing an observed mutation once.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Original Git request.
    .PARAMETER Binding
    Git-owned argument binding; values that look like flags remain values.
    .PARAMETER Prefix
    Native globals, before the subcommand.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    return Invoke-QuietGitObservedMutation $Runtime $Request $Prefix
}
function Assert-QuietGitInteraction {
    <#
    .SYNOPSIS
    Requires an explicit input/controller for forms that open an interactive editor or patch selector.
    .PARAMETER Runtime
    Parent request carrying any explicit input.
    .PARAMETER Request
    Git-owned command name.
    .PARAMETER Binding
    Bound option units, excluding flag-looking option values.
    #>
    param($Runtime,$Request,$Binding)
    $flags=@($Binding.Options.Name)
    $interactive=@($flags|Where-Object {$_ -cin @('--interactive','--patch','-p','--edit-description')}).Count -gt 0
    if($Request.Name -eq 'rebase' -and ('-i' -cin $flags -or '--edit-todo' -cin $flags)){$interactive=$true}
    if($Request.Name -eq 'clean' -and '-i' -cin $flags){$interactive=$true}
    if($Request.Name -eq 'config' -and ($Binding.Subcommand -ceq 'edit' -or '--edit' -cin $flags -or '-e' -cin $flags)){$interactive=$true}
    if($Request.Name -cin @('merge','cherry-pick','revert') -and ('--edit' -cin $flags -or '-e' -cin $flags)){$interactive=$true}
    if($Request.Name -eq 'tag' -and @($flags|Where-Object {$_ -cin @('--annotate','-a','--sign','-s')}).Count -and !@($flags|Where-Object {$_ -cin @('--message','-m','--file','-F')}).Count){$interactive=$true}
    if($interactive -and !@('Interaction','InputText','InputBytes','InputPath'|Where-Object {$Runtime.Request.ContainsKey($_)}).Count){throw 'ExplicitInteractionRequired'}
}
function Invoke-QuietGitBranch {
    <#
.SYNOPSIS
Separates branch listings from mutations instead of treating every branch invocation as text.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git branch request.
    .PARAMETER Binding
    Git argument policy.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $writes=@('-d','-D','--delete','-m','-M','--move','-c','-C','--copy','--set-upstream-to','-u','--unset-upstream','--edit-description')
    $explicitList='--list' -cin $flags -or '--contains' -cin $flags -or '--merged' -cin $flags -or '--no-merged' -cin $flags -or '--points-at' -cin $flags
    $operands=@($Binding.Tokens|Where-Object Kind -EQ Operand)
    if(@($flags|Where-Object{$_ -cin $writes}).Count -or $operands.Count -gt 0 -and !$explicitList){return Invoke-QuietGitObservedMutation $Runtime $Request $Prefix}
    if('--format' -cin $flags -or '--show-current' -cin $flags){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('branch')+@($Request.Arguments)) 'branch'}
    $arguments=Get-QuietGitArguments $Binding @('-v','--verbose','--column','--no-column')
    $data=@{Command='branch';GitVersion=$Runtime.State.DetectedVersion;Branches=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('branch','--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00')+$arguments) $data -FieldCount 4 -Commit {param($f,$data)$data.Branches.Add(@{Name=$f[0];ObjectId=$f[1];Current=($f[2] -ceq '*');Upstream=$f[3]})}
    return $r.Data
}
function Invoke-QuietGitStash {
    <#
.SYNOPSIS
Preserves stash subcommand and separator semantics without mistaking option values for subcommands.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git stash request.
    .PARAMETER Binding
    Bound tokens.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $sub=$Binding.Subcommand
    if(!$sub -and $Request.Arguments.Count -and $Request.Arguments[0] -notlike '-*'){$sub=$Request.Arguments[0]}
    if($sub -eq 'list'){
        $flags=@($Binding.Options.Name)
        if(@($flags|Where-Object{$_ -cin @('--format','--pretty','--oneline','-p','--patch','--stat','--raw','--graph')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('stash')+@($Request.Arguments)) 'stash'}
        $arguments=Get-QuietGitArguments $Binding
        $arguments=@($arguments|Select-Object -Skip 1)
        $data=@{Command='stash';GitVersion=$Runtime.State.DetectedVersion;Stashes=[Collections.Generic.List[object]]::new()}
        $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('stash','list','--format=%gd%x00%H%x00%gs%x00')+$arguments) $data -FieldCount 3 -Commit {param($f,$data)$data.Stashes.Add(@{Reference=$f[0];ObjectId=$f[1];Subject=$f[2]})}
        return $r.Data
    }
    if($sub -eq 'show'){
        $patchRequest=$Request.Clone();$patchRequest.Name='stash';return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('stash')+@($Request.Arguments)) 'stash'
    }
    return Invoke-QuietGitObservedMutation $Runtime $Request $Prefix
}
