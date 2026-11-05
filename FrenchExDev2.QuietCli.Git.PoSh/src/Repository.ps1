function Read-QuietGitReferences {
    <#
.SYNOPSIS
Observes local refs as parsed NUL fields without a captured output document.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Prefix
    Native globals.
    .PARAMETER Role
    Auxiliary role or Business when explicitly requested.
    #>
    param($Runtime,[string[]]$Prefix,[string]$Role='Observation')
    $data=@{Refs=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('for-each-ref','--format=%(refname)%00%(objectname)%00%(objecttype)%00%(symref)%00')) $data -Role $Role -FieldCount 4 -Commit {param($f,$data)$data.Refs.Add(@{Name=$f[0];ObjectId=$f[1];Type=$f[2];SymbolicTarget=$f[3]})}
    return $r
}
function Get-QuietGitRefChanges {
    <#
.SYNOPSIS
Compares independently observed local refs without inferring remote or hook effects.
    .PARAMETER Before
    Parsed refs before the mutation.
    .PARAMETER After
    Parsed refs after the mutation.
    #>
    param([object[]]$Before,[object[]]$After)
    $old=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $new=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($ref in $Before){$key=if($ref.Name -is [string]){$ref.Name}else{$ref.Name.Base64};$old[$key]=$ref}
    foreach($ref in $After){$key=if($ref.Name -is [string]){$ref.Name}else{$ref.Name.Base64};$new[$key]=$ref}
    $names=[Collections.Generic.SortedSet[string]]::new($old.Keys,[StringComparer]::Ordinal)
    $names.UnionWith($new.Keys)
    foreach($name in $names){
        $a=$null;$b=$null
        [void]$old.TryGetValue($name,[ref]$a);[void]$new.TryGetValue($name,[ref]$b)
        if(!$a -or !$b -or $a.ObjectId -cne $b.ObjectId){@{Kind=$(if(!$a){'Added'}elseif(!$b){'Removed'}else{'Updated'});Name=$name;Before=$(if($a){$a.ObjectId}else{$null});After=$(if($b){$b.ObjectId}else{$null})}}
    }
}
function Invoke-QuietGitObservedMutation {
    <#
.SYNOPSIS
Runs one mutation and observes local HEAD/refs before and after; never repeats it.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git command and original arguments.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,[string[]]$Prefix)
    $before=Read-QuietGitReferences $Runtime $Prefix
    $headBefore=Read-QuietGitScalar $Runtime ($Prefix+@('rev-parse','--verify','HEAD')) @(0,128)
    $branchBefore=Read-QuietGitScalar $Runtime ($Prefix+@('symbolic-ref','-q','HEAD')) @(0,1,128)
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
    $after=Read-QuietGitReferences $Runtime $Prefix
    $headAfter=Read-QuietGitScalar $Runtime ($Prefix+@('rev-parse','--verify','HEAD')) @(0,128)
    $branchAfter=Read-QuietGitScalar $Runtime ($Prefix+@('symbolic-ref','-q','HEAD')) @(0,1,128)
    return @{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;OperationOutcome=$native.Outcome;HeadBefore=$(if($headBefore.Execution.Native.ExitCode -eq 0){$headBefore.Data}else{$null});HeadAfter=$(if($headAfter.Execution.Native.ExitCode -eq 0){$headAfter.Data}else{$null});BranchBefore=$(if($branchBefore.Execution.Native.ExitCode -eq 0){$branchBefore.Data}else{$null});BranchAfter=$(if($branchAfter.Execution.Native.ExitCode -eq 0){$branchAfter.Data}else{$null});ReferenceChanges=@(Get-QuietGitRefChanges @($before.Data.Refs) @($after.Data.Refs));Observation=@{BeforeAvailable=($before.Outcome -eq 'Success');AfterAvailable=($after.Outcome -eq 'Success');Scope='Local refs and HEAD only; non-atomic observations, no fetch and no inferred hook effects.'}}
}
function Invoke-QuietGitTree {
    <#
.SYNOPSIS
Parses ls-tree with NUL paths, with awkward-path and explicit-format preservation.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git ls-tree request.
    .PARAMETER Binding
    Bound options.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if('--format' -cin $flags){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('ls-tree')+@($Request.Arguments)) 'ls-tree' -Delimiter $(if('-z' -cin $flags){[byte]0}else{[byte]10})}
    $arguments=Get-QuietGitArguments $Binding @('--name-only','--name-status','--long','-l','-z')
    $data=@{Command='ls-tree';GitVersion=$Runtime.State.DetectedVersion;Entries=[Collections.Generic.List[object]]::new();Scope=@{PathRepresentation='NUL-delimited UTF-8 or explicit raw bytes';Requested=$Request.Original}}
    $decode=Get-Command ConvertFrom-QuietGitBytes
    $parser={
        param($record,$data)
        if(!$record.Length){return};$tab=[Array]::IndexOf($record,[byte]9);if($tab -lt 0){throw 'MalformedTreeRecord'}
        $header=[Text.Encoding]::ASCII.GetString($record,0,$tab)
        if($header -notmatch '^(\d+) (blob|tree|commit) ([0-9a-f]+)\s+(\d+|-)\s*$'){throw 'MalformedTreeHeader'}
        $fields=@($Matches[1],$Matches[2],$Matches[3],$Matches[4]);$bytes=[byte[]]::new($record.Length-$tab-1);[Array]::Copy($record,$tab+1,$bytes,0,$bytes.Length)
        $data.Entries.Add(@{Mode=$fields[0];Type=$fields[1];ObjectId=$fields[2];Size=$(if($fields[3] -eq '-'){$null}else{[long]$fields[3]});Path=(& $decode $bytes)})
    }.GetNewClosure()
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('ls-tree','-z','--long')+$arguments) $data -Delimiter 0 -Parser $parser
    return $r.Data
}
function Read-QuietGitWorktrees {
    <#
.SYNOPSIS
Parses the worktree porcelain protocol with NUL path preservation.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Prefix
    Native globals.
    .PARAMETER Arguments
    Additional list arguments.
    .PARAMETER Role
    Business or Observation.
    #>
    param($Runtime,[string[]]$Prefix,[string[]]$Arguments=@(),[string]$Role='Business')
    $data=@{Command='worktree';GitVersion=$Runtime.State.DetectedVersion;Worktrees=[Collections.Generic.List[object]]::new();Current=$null}
    $decode=Get-Command ConvertFrom-QuietGitBytes
    $parser={
        param($record,$data)
        if(!$record.Length){if($data.Current){$data.Worktrees.Add($data.Current);$data.Current=$null};return}
        $space=[Array]::IndexOf($record,[byte]32)
        $key=if($space -lt 0){[Text.Encoding]::ASCII.GetString($record)}else{[Text.Encoding]::ASCII.GetString($record,0,$space)}
        $value=if($space -ge 0){$bytes=[byte[]]::new($record.Length-$space-1);[Array]::Copy($record,$space+1,$bytes,0,$bytes.Length);& $decode $bytes}else{$true}
        if($key -eq 'worktree'){if($data.Current){$data.Worktrees.Add($data.Current)};$data.Current=@{Path=$value;HeadOid=$null;Branch=$null;Bare=$false;Detached=$false;Locked=$null;Prunable=$null};return}
        if(!$data.Current){throw 'WorktreeFieldWithoutEntry'}
        switch -CaseSensitive ($key){HEAD {$data.Current.HeadOid=$value} branch {$data.Current.Branch=$value} bare {$data.Current.Bare=$true} detached {$data.Current.Detached=$true} locked {$data.Current.Locked=$value} prunable {$data.Current.Prunable=$value} default {$data.Current[$key]=$value}}
    }.GetNewClosure()
    Invoke-QuietGitRecords $Runtime ($Prefix+@('worktree','list','--porcelain','-z')+$Arguments) $data -Role $Role -Delimiter 0 -Parser $parser -Finalize {param($data)if($data.Current){$data.Worktrees.Add($data.Current)};$data.Remove('Current');$data}
}
function Invoke-QuietGitWorktree {
    <#
.SYNOPSIS
Distinguishes list and mutation using the bound first subcommand.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git worktree request.
    .PARAMETER Binding
    Bound argument policy.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $sub=$Binding.Subcommand
    if(!$sub -and $Request.Arguments.Count){$sub=$Request.Arguments[0]}
    if(!$sub -or $sub -eq 'list'){
        $arguments=Get-QuietGitArguments $Binding @('--porcelain','-z','--verbose','-v')
        if($arguments.Count -and $arguments[0] -eq 'list'){$arguments=@($arguments|Select-Object -Skip 1)}
        $r=Read-QuietGitWorktrees $Runtime $Prefix -Arguments $arguments;return $r.Data
    }
    $before=Read-QuietGitWorktrees $Runtime $Prefix -Role Observation
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@('worktree')+@($Request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
    $after=Read-QuietGitWorktrees $Runtime $Prefix -Role Observation
    return @{Command='worktree';Subcommand=$sub;ExitCode=$native.Execution.Native.ExitCode;Before=$before.Data.Worktrees;After=$after.Data.Worktrees;Observation='Independent non-atomic local worktree observations.'}
}
