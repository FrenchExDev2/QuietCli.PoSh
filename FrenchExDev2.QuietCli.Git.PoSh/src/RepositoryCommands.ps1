function Read-QuietGitWorkingState {
    <#
    .SYNOPSIS
    Observes HEAD, branch, index and worktree in one porcelain-v2 process.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Prefix
    Native global context, without user business operands.
    #>
    param($Runtime,[string[]]$Prefix)
    Import-QuietGitParser
    $data=@{Branch=$null;HeadOid=$null;Unborn=$null;Detached=$null;Pending=$null;Entries=[Collections.Generic.List[object]]::new();Counts=@{Changed=0L;Staged=0L;Unstaged=0L;Untracked=0L;Conflicted=0L;Renamed=0L;Ignored=0L}}
    Invoke-QuietGitRecords $Runtime ($Prefix+@('--no-optional-locks','status','--porcelain=v2','--branch','-z','--untracked-files=all','--ignore-submodules=none')) $data -Role Observation -Delimiter 0 -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitRecords]::Status($record,$data)
    } -Finalize {
        param($data)
        if($data.Pending){throw 'IncompleteRenameSource'}
        $data.Remove('Pending');$data.Clean=$data.Counts.Changed -eq 0
        $data
    }
}
function Invoke-QuietGitRepositoryMutation {
    <#
    .SYNOPSIS
    Executes a worktree operation exactly once with independent before/after observations.
    .PARAMETER Runtime
    Parent invocation including any explicit interaction.
    .PARAMETER Request
    Original Git command and operands.
    .PARAMETER Binding
    Git-owned argument binding.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if($Request.Name -eq 'clean' -and @($Binding.Options.Name|Where-Object {$_ -cin @('-n','--dry-run')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('clean')+@($Request.Arguments)) clean}
    if($Request.Name -eq 'rebase' -and '--show-current-patch' -cin $Binding.Options.Name){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('rebase')+@($Request.Arguments)) rebase}
    if($Runtime.Request.Transport -ne 'Pipe'){throw 'ObservedWorktreeOperationRequiresPipe'}
    $before=Read-QuietGitWorkingState $Runtime $Prefix
    if($before.Outcome -ne 'Success' -or !$before.Completeness.Source -or !$before.Completeness.Analysis){throw 'InitialWorkingStateUnavailable: operation was not executed.'}
    $trackRefs=$Request.Name -cin @('switch','reset','merge','rebase','cherry-pick','revert')
    $refsBefore=if($trackRefs){Read-QuietGitReferences $Runtime $Prefix}else{$null}
    if($trackRefs -and ($refsBefore.Outcome -ne 'Success' -or !$refsBefore.Completeness.Source -or !$refsBefore.Completeness.Analysis)){throw 'InitialReferencesUnavailable: operation was not executed.'}
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
    $after=Read-QuietGitWorkingState $Runtime $Prefix
    $refsAfter=if($trackRefs){Read-QuietGitReferences $Runtime $Prefix}else{$null}
    $available=$after.Outcome -eq 'Success' -and $after.Completeness.Source -and $after.Completeness.Analysis
    $conflicts=if($available){$after.Data.Counts.Conflicted}else{$null}
    $data=@{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;OperationOutcome=$native.Outcome;State=[FrenchExDev2.QuietCli.Git.GitOperationOutcome]::Outcome($native.Execution.Native.ExitCode,$conflicts);Before=$before.Data;After=$after.Data;Conflicts=$conflicts;ReferenceChanges=@();Observation=@{BeforeAvailable=($before.Outcome -eq 'Success' -and $before.Completeness.Source -and $before.Completeness.Analysis);AfterAvailable=$available;Scope='Non-atomic local HEAD, index and worktree observations; no inferred file contents, hook effects or remote state.'}}
    if($trackRefs){$data.ReferenceChanges=@(Get-QuietGitRefChanges @($refsBefore.Data.Refs) @($refsAfter.Data.Refs));$data.Observation.ReferencesAvailable=$refsBefore.Outcome -eq 'Success' -and $refsAfter.Outcome -eq 'Success'}
    return $data
}
function Invoke-QuietGitTag {
    <#
    .SYNOPSIS
    Separates structured tag listings, signature verification and ref mutations.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact tag arguments.
    .PARAMETER Binding
    Bound options and operands.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $list=@($flags|Where-Object {$_ -cin @('--list','-l','--contains','--no-contains','--merged','--no-merged','--points-at','--format','--sort','--column','-n')}).Count -gt 0
    if(@($flags|Where-Object {$_ -cin @('--verify','-v')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('tag')+@($Request.Arguments)) tag}
    $write=@($flags|Where-Object {$_ -cin @('--delete','-d','--annotate','-a','--sign','-s','--force','-f','--message','-m','--file','-F')}).Count -gt 0
    if($write -or ($Binding.Operands.Count -gt 0 -and !$list)){return Invoke-QuietGitObservedMutation $Runtime $Request $Prefix}
    if(@($flags|Where-Object {$_ -cin @('--format','-n','--column')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('tag')+@($Request.Arguments)) tag}
    $arguments=Get-QuietGitArguments $Binding @('--list','-l')
    $data=@{Command='tag';GitVersion=$Runtime.State.DetectedVersion;Tags=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('tag','--list','--format=%(refname:short)%00%(objectname)%00%(objecttype)%00%(*objectname)%00')+$arguments) $data -FieldCount 4 -Commit {
        param($fields,$data)
        $data.Tags.Add(@{Name=$fields[0];ObjectId=$fields[1];Type=$fields[2];TargetObjectId=$fields[3]})
    }
    return $r.Data
}
function Read-QuietGitRemotes {
    <#
    .SYNOPSIS
    Reads local remote configuration without contacting a remote server.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Prefix
    Git global context.
    .PARAMETER Role
    Business query or observation role.
    #>
    param($Runtime,[string[]]$Prefix,[string]$Role='Observation')
    Import-QuietGitParser
    $data=@{Command='remote';Remotes=[Collections.Generic.List[object]]::new()}
    Invoke-QuietGitRecords $Runtime ($Prefix+@('remote','-v')) $data -Role $Role -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitRemoteRecords]::Remote($record,$data)
    }
}
function Invoke-QuietGitRemote {
    <#
    .SYNOPSIS
    Lists configured remotes or executes one requested remote operation.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact remote arguments.
    .PARAMETER Binding
    Bound subcommand and operands.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if(!$Binding.Subcommand -and !$Binding.Operands.Count){$r=Read-QuietGitRemotes $Runtime $Prefix -Role Business;return $r.Data}
    if($Binding.Subcommand -cin @('get-url','show')){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('remote')+@($Request.Arguments)) remote}
    $before=Read-QuietGitRemotes $Runtime $Prefix
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@('remote')+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
    $after=Read-QuietGitRemotes $Runtime $Prefix
    return @{Command='remote';Subcommand=$Binding.Subcommand;GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;Before=$before.Data.Remotes;After=$after.Data.Remotes;Observation=@{BeforeAvailable=($before.Outcome -eq 'Success');AfterAvailable=($after.Outcome -eq 'Success');Scope='Non-atomic local remote configuration only; remote refs are not inferred.'}}
}
function Invoke-QuietGitConfig {
    <#
    .SYNOPSIS
    Parses explicit config queries losslessly; executes config writes without echoing values.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original config arguments.
    .PARAMETER Binding
    Bound operation and scope options.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name);$sub=$Binding.Subcommand
    $list=$sub -ceq 'list' -or '--list' -cin $flags -or '-l' -cin $flags
    $write=$sub -cin @('set','unset','rename-section','remove-section','edit') -or @($flags|Where-Object {$_ -cin @('--add','--replace-all','--unset','--unset-all','--rename-section','--remove-section','--edit','-e')}).Count -gt 0
    $get=$sub -ceq 'get' -or '--get' -cin $flags -or '--get-all' -cin $flags -or (!$sub -and !$write -and !$list -and $Binding.Operands.Count -eq 1)
    if(!$sub -and !$list -and !$get -and $Binding.Operands.Count -ge 2){$write=$true}
    if($write){
        $native=Invoke-QuietGitNative $Runtime ($Prefix+@('config')+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
        return @{Command='config';GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;Operation='Write';OperationOutcome=$native.Outcome;Scope='Requested native config write only; values are not echoed and effective settings are not inferred.'}
    }
    if((!$list -and !$get) -or @($flags|Where-Object {$_ -cin @('--show-origin','--show-scope','--name-only','--get-regexp','--get-urlmatch','--get-color','--get-colorbool')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('config')+@($Request.Arguments)) config -Delimiter $(if('-z' -cin $flags -or '--null' -cin $flags){0}else{10})}
    Import-QuietGitParser
    $nativeArguments=Get-QuietGitArguments $Binding @('-z','--null')
    if($sub){$index=[Array]::IndexOf([string[]]$nativeArguments,$sub);$vector=@($nativeArguments[0..$index])+@('--null');if($index+1 -lt $nativeArguments.Count){$vector+=@($nativeArguments[($index+1)..($nativeArguments.Count-1)])}}
    else{$vector=@('--null')+$nativeArguments}
    $data=@{Command='config';GitVersion=$Runtime.State.DetectedVersion;Entries=[Collections.Generic.List[object]]::new();Values=[Collections.Generic.List[object]]::new();Found=$false;Operation=$(if($list){'List'}else{'Get'})}
    $parser=if($list){{param($record,$data)[FrenchExDev2.QuietCli.Git.GitConfigRecords]::Config($record,$data)}}else{{param($record,$data)$data.Values.Add([FrenchExDev2.QuietCli.Git.GitRecords]::Decode($record))}}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('config')+$vector) $data -Delimiter 0 -Codes $(if($get){@(0,1)}else{@(0)}) -Parser $parser
    $r.Data.Found=$r.Execution.Native.ExitCode -eq 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
function Invoke-QuietGitCreate {
    <#
    .SYNOPSIS
    Executes init/clone once and verifies repository identity when the explicit destination is known.
    .PARAMETER Runtime
    Parent invocation; clone contacts only the requested source.
    .PARAMETER Request
    Exact init or clone arguments.
    .PARAMETER Binding
    Bound options and destination operands.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
    $operands=@($Binding.Operands)
    $destination=if($Request.Name -eq 'init'){if($operands.Count){$operands[-1]}else{'.'}}elseif($operands.Count -eq 2){$operands[-1]}else{$null}
    $identity=$null
    if($native.Outcome -eq 'Success' -and $null -ne $destination){
        $git=Read-QuietGitScalar $Runtime ($Prefix+@('-C',$destination,'rev-parse','--absolute-git-dir'))
        $bare=Read-QuietGitScalar $Runtime ($Prefix+@('-C',$destination,'rev-parse','--is-bare-repository'))
        $identity=@{Available=($git.Outcome -eq 'Success' -and $bare.Outcome -eq 'Success');GitDirectory=$git.Data;Bare=($bare.Data -ceq 'true')}
    }
    return @{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;Destination=$destination;Repository=$identity;DestinationObserved=($null -ne $identity -and $identity.Available);Scope='Requested native creation only; implicit clone destinations and recursive submodule state are not inferred.'}
}
