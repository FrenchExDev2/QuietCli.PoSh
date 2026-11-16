function Assert-QuietGitIndexObservationScope {
    <#
    .SYNOPSIS
    Rejects output destinations and temporary files outside the observed active index/worktree.
    .PARAMETER Name
    Native plumbing command.
    .PARAMETER Flags
    Bound option names, independent of operand text.
    #>
    param([string]$Name,[string[]]$Flags)
    if($Name -ceq 'read-tree' -and '--index-output' -cin $Flags){throw 'AlternateIndexOutputNotQualified'}
    if($Name -ceq 'checkout-index' -and @($Flags|Where-Object {$_ -cin @('--temp','--prefix')}).Count){throw 'CheckoutDestinationNotQualified'}
}
function Read-QuietGitIndexEntries {
    <#
    .SYNOPSIS
    Observes complete stage/mode/object/path tuples using the existing caller-local C# parser.
    .PARAMETER Runtime
    Parent invocation, including an explicit GIT_INDEX_FILE when supplied.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,[string[]]$Prefix)
    Import-QuietGitParser
    $data=@{Files=[Collections.Generic.List[object]]::new();WithStage=$true}
    Invoke-QuietGitRecords $Runtime ($Prefix+@('ls-files','--stage','-z')) $data -Role Observation -Delimiter 0 -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitIndexRecords]::Receive($record,$data)
    }
}
function Invoke-QuietGitIndexMutation {
    <#
    .SYNOPSIS
    Executes one requested index operation and reports independent scoped observations.
    .PARAMETER Runtime
    Caller request and explicitly supplied input/environment.
    .PARAMETER Request
    Exact plumbing command and arguments.
    .PARAMETER Binding
    Bound options for destination and query guards.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Assert-QuietGitIndexObservationScope $Request.Name @($Binding.Options.Name)
    if($Request.Name -ceq 'update-index' -and '--show-index-version' -cin $Binding.Options.Name){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $Request.Name}
    if($Runtime.Request.Transport -ne 'Pipe'){throw 'ObservedIndexOperationRequiresPipe'}
    $before=Read-QuietGitIndexEntries $Runtime $Prefix
    if($before.Outcome -ne 'Success' -or !$before.Completeness.Source -or !$before.Completeness.Analysis){throw 'InitialIndexUnavailable: operation was not executed.'}
    $native=Invoke-QuietGitNative $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) -Data $null -Output {param($event,$runtime)} -Complete {param($runtime)}
    $after=Read-QuietGitIndexEntries $Runtime $Prefix
    $available=$after.Outcome -eq 'Success' -and $after.Completeness.Source -and $after.Completeness.Analysis
    return @{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;OperationOutcome=$native.Outcome;Before=$before.Data.Files;After=$after.Data.Files;Observation=@{BeforeAvailable=$true;AfterAvailable=$available;Scope='Non-atomic active-index stage/mode/object/path tuples only. No claim about stat cache, assume-unchanged/skip-worktree flags, index extensions, created file contents, hooks or submodule effects.'}}
}
