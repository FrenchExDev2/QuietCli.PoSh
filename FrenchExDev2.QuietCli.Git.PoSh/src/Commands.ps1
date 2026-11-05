function Invoke-QuietGitNative {
    <#
.SYNOPSIS
Executes one Git operation with explicit business parsing, never generic raw capture.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Arguments
    Exact effective Git argument vector.
    .PARAMETER Output
    Streaming business parser.
    .PARAMETER Complete
    Business finalizer.
    .PARAMETER Data
    Initial business object.
    .PARAMETER Role
    Business, Observation or Probe.
    .PARAMETER Delimiter
    Optional bounded record delimiter.
    .PARAMETER SuccessExitCodes
    Documented successful exit conditions.
    .PARAMETER StdoutMode
    Text or byte business events.
    .PARAMETER StderrMode
    Text or byte error events.
    #>
    param($Runtime,[string[]]$Arguments,[scriptblock]$Output,[scriptblock]$Complete,[AllowNull()]$Data,[string]$Role='Business',[string]$Delimiter,[int[]]$SuccessExitCodes=@(0),[string]$StdoutMode='Text',[string]$StderrMode='Text')
    $options=@{AsObject=$true;WorkingDirectory=$Runtime.Request.WorkingDirectory;Environment=@{LC_ALL='C';LANG='C';GIT_PAGER='cat'};Role=$Role;Data=$Data;Output=$Output;Complete=$Complete;FilePath=$Runtime.Request.FilePath;ArgumentList=$Arguments;TimeoutSeconds=$Runtime.Request.TimeoutSeconds;SuccessExitCodes=$SuccessExitCodes;StdoutMode=$StdoutMode;StderrMode=$StderrMode}
    foreach($key in $Runtime.Request.Environment.Keys){$options.Environment[$key]=$Runtime.Request.Environment[$key]}
    if($Role -ne 'Business'){$options.Environment.GIT_OPTIONAL_LOCKS='0';$options.Environment.GIT_NO_LAZY_FETCH='1'}
    if($PSBoundParameters.ContainsKey('Delimiter')){$options.RecordDelimiter=$Delimiter}
    if($Role -eq 'Business'){foreach($key in @('InputText','InputBytes','InputPath','Interaction','Transport','TerminalSize','CancellationFile','CancellationToken','ReadBlockBytes','DrainTimeoutSeconds')){if($Runtime.Request.ContainsKey($key)){$options[$key]=$Runtime.Request[$key]}}}
    # Use a vector of explicit facade options, not a shell command string.
    $tokens=[Collections.Generic.List[object]]::new();foreach($key in $options.Keys){$tokens.Add('-'+$key);if($key -ne 'AsObject'){$tokens.Add($options[$key])}}
    $quietArguments=$tokens.ToArray()
    quiet @quietArguments
}
function Read-QuietGitScalar {
    <#
.SYNOPSIS
Reads one bounded scalar observation; it is not a capture of the command's output.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Arguments
    Read-only Git command.
    .PARAMETER Codes
    Documented non-error exit conditions.
    #>
    param($Runtime,[string[]]$Arguments,[int[]]$Codes=@(0))
    Invoke-QuietGitNative $Runtime $Arguments -Role Observation -SuccessExitCodes $Codes -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){if($r.Data.Length+$e.Text.Length -gt 4096){throw 'ScalarObservationTooLarge'};[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString().TrimEnd("`r","`n")}
}
function Invoke-QuietGitCommand {
    <#
.SYNOPSIS
Dispatches documented streaming Git semantics and refuses missing semantic handlers.
    .PARAMETER Runtime
    Caller-local parent runtime.
    #>
    param($Runtime)
    $request=Get-GitInvocation @{ArgumentList=$Runtime.Request.ArgumentList}
    if($request.Error){throw $request.Reason}
    $name=$request.Name;$prefix=@($request.Global)+@('--no-pager','-c','color.ui=false')
    $version=$Runtime.State.DetectedVersion
    $numeric=Get-GitNumericVersion $version
    $definition=@($script:GitInventory.Commands|Where-Object Name -CEQ $name)|Select-Object -First 1
    if(!$definition){throw "CommandOutsidePinnedInventory: $name"}
    $branch='2.'+$numeric.Minor+'.0'
    if($branch -notin $definition.Versions){throw "CommandNotInRelease: $name on $branch"}
    $binding=Get-GitArgumentToken -Request $request -Version $version
    if(!$binding.Complete){throw ('ArgumentGrammarIncomplete: '+(@($binding.Unknowns.Reason) -join '; '))}
    # Documentation extraction masks are observations, not a complete absence policy:
    # shared diff/pretty options moved out of command manuals in newer releases.
    # The module's stable range and curated arity grammar select this handler;
    # native Git validates accepted option combinations. Version qualification remains explicit.
    if($script:GitExecutors.ContainsKey($name)){Assert-QuietGitInteraction $Runtime $request $binding;return & ($script:GitExecutors[$name]) $Runtime $request $binding $prefix}
    if($name -in @('version','rev-parse','symbolic-ref','hash-object','write-tree','commit-tree','mktree','mktag','merge-base','show-ref','for-each-ref','ls-files','ls-tree','count-objects','check-ref-format','check-ignore','check-attr','check-mailmap','log','rev-list','shortlog','describe','name-rev','branch','tag','remote','config','ls-remote')){
        $state=[Collections.Generic.List[string]]::new()
        $codes=if($name -in @('check-ref-format','check-ignore','symbolic-ref','merge-base','show-ref')){@(0,1)}else{@(0)}
        $result=Invoke-QuietGitNative $Runtime ($prefix+@($name)+@($request.Arguments)) -Data $state -SuccessExitCodes $codes -Delimiter "`n" -Output {param($e,$r)if($e.Stream -eq 'stdout'){$r.Data.Add($e.Text.TrimEnd("`r"))}} -Complete {param($r),$r.Data.ToArray()}
        return ConvertFrom-QuietGitQuery $name $result.Data $result.Execution.Native.ExitCode $version
    }
    if($name -in @('init','init-db','add','rm','mv','update-index','update-ref','read-tree','reset','checkout','restore','switch','clean','merge','cherry-pick','revert','gc','prune','repack','pack-refs','prune-packed','multi-pack-index','maintenance','rerere','sparse-checkout','replace','notes','stash','submodule','fetch','clone','pull')){
        $r=Invoke-QuietGitNative $Runtime ($prefix+@($name)+@($request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
        return @{Command=$name;GitVersion=$version;ExitCode=$r.Execution.Native.ExitCode;EffectStatus='Executed';Observation='Native exit only; detailed semantic effects are not yet qualified.'}
    }
    throw "ContractNotImplemented: $name. Inventory membership is not semantic support."
}
function ConvertFrom-QuietGitQuery {
    <#
.SYNOPSIS
Projects streamed query records into a typed business result where implemented.
    .PARAMETER Name
    Git query name.
    .PARAMETER Lines
    Explicit business records collected by the query handler.
    .PARAMETER ExitCode
    Native exit condition.
    .PARAMETER Version
    Observed Git version.
    #>
    param([string]$Name,[string[]]$Lines,[int]$ExitCode,[string]$Version)
    $data=[ordered]@{Command=$Name;GitVersion=$Version;ExitCode=$ExitCode}
    switch($Name){
        {$_ -in @('hash-object','write-tree','commit-tree','mktree','mktag','merge-base','rev-list')} {
            $data.Objects=@(foreach($line in $Lines){
                if($line -match '^[0-9a-f]{40}(?:[0-9a-f]{24})?$'){@{ObjectId=$line;Algorithm=$(if($line.Length -eq 40){'sha1'}else{'sha256'})}}
            })
        }
        count-objects {$data.Counts=[ordered]@{};foreach($line in $Lines){if($line -match '^([a-z-]+): (\d+)$'){$data.Counts[$Matches[1]]=[long]$Matches[2]}};$data.SizeUnit='KiB'}
        {$_ -in @('show-ref','ls-remote')} {
            $data.References=@(foreach($line in $Lines){
                if($line -match '^([0-9a-f]{40}(?:[0-9a-f]{24})?)\s+(.+)$'){@{ObjectId=$Matches[1];Name=$Matches[2]}}
            })
        }
        check-ref-format {$data.Valid=$ExitCode -eq 0;$data.NormalizedName=if($Lines.Count){$Lines[0]}else{$null}}
        symbolic-ref {$data.Exists=$ExitCode -eq 0;$data.Reference=if($Lines.Count){$Lines[0]}else{$null}}
        default {$data.Records=$Lines;$data.Semantics='Native textual records; advanced variants remain unqualified.'}
    }
    return $data
}
function Get-QuietGitCoverage {
    <#
.SYNOPSIS
Reports official inventory separately from implemented and qualified command forms. #>
    [CmdletBinding()]param()
    foreach($command in $script:GitInventory.Commands){
        $specialized=$script:GitExecutors.ContainsKey($command.Name)
        $parsers=if($script:GitHandlerCatalogue.ParserTypes.ContainsKey($command.Name)){@($script:GitHandlerCatalogue.ParserTypes[$command.Name])}else{@()}
        [pscustomobject]@{Command=$command.Name;Versions=$command.Versions;Declared=$script:GitSpecifications.ContainsKey($command.Name);Specialized=$specialized;Handler=$(if($specialized){$script:GitHandlerCatalogue.Handlers[$command.Name]}else{$null});HandlerLanguage=$(if($specialized){'PowerShell'}else{$null});ParserTypes=$parsers;Implementation=$(if($specialized){'StreamingBusinessHandler'}else{'PartialOrMissing'});Qualification='Pending';EntireInventoryQualified=$false}
    }
}

function Invoke-QuietGitCommit {
    <#
    .SYNOPSIS
    Executes one documented Git operation with its own streaming business handler.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Git-owned arguments.
    .PARAMETER Binding
    Bound command options.
    .PARAMETER Prefix
    Native global arguments.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $version=$Runtime.State.DetectedVersion

        $explicitMessage=@($Binding.Options|Where-Object{$_.Name -cin @('-m','--message','-F','--file','--no-edit','--reuse-message','-C')}).Count -gt 0
        if(!$explicitMessage -and !$Runtime.Request.ContainsKey('Interaction')){throw 'CommitMessageOrExplicitInteractionRequired'}
        $before=Read-QuietGitScalar $Runtime ($prefix+@('rev-parse','--verify','HEAD')) @(0,128)
        $result=Invoke-QuietGitNative $Runtime ($prefix+@('commit')+@($request.Arguments)) -Data $null -Output {param($e,$r)} -Complete {param($r)}
        $after=Read-QuietGitScalar $Runtime ($prefix+@('rev-parse','--verify','HEAD')) @(0,128)
        return [ordered]@{Command='commit';GitVersion=$version;Before=$(if($before.Execution.Native.ExitCode -eq 0){$before.Data}else{$null});After=$(if($after.Execution.Native.ExitCode -eq 0){$after.Data}else{$null});Changed=($before.Data -cne $after.Data);ExitCode=$result.Execution.Native.ExitCode;Observation='Local HEAD before/after; not an atomic snapshot or proof of hook effects.'}

}
function Invoke-QuietGitPush {
    <#
    .SYNOPSIS
    Executes one documented Git operation with its own streaming business handler.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Git-owned arguments.
    .PARAMETER Binding
    Bound command options.
    .PARAMETER Prefix
    Native global arguments.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $version=$Runtime.State.DetectedVersion

        if($Runtime.Request.Transport -ne 'Pipe'){throw 'PushPorcelainRequiresPipe: use explicit -Output for terminal control.'}
        Import-QuietGitParser
     $state=@{References=[Collections.Generic.List[object]]::new();Remote=$null}
        $result=Invoke-QuietGitNative $Runtime ($prefix+@('push','--porcelain')+@($request.Arguments)) -Data $state -Delimiter "`n" -Output {
            param($e,$r)
            if($e.Stream -ne 'stdout'){return}
         [FrenchExDev2.QuietCli.Git.GitPush]::Receive($e.Text,$r.Data)
     } -Complete {param($r)@{Command='push';Remote=$r.Data.Remote;References=$r.Data.References.ToArray();ExitCode=$r.Execution.ExitCode}}
        return $result.Data

}
