function Invoke-QuietGitObjectQuery {
    <#
    .SYNOPSIS
    Parses complete object identities without silently dropping alternative output modes.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original Git command and operands.
    .PARAMETER Binding
    Git-owned options.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $flags=@($Binding.Options.Name)
    if($Request.Name -ceq 'merge-base' -and '--is-ancestor' -cin $flags){
        $native=Invoke-QuietGitNative $Runtime ($Prefix+@('merge-base')+@($Request.Arguments)) -Data $null -SuccessExitCodes @(0,1) -Output {param($event,$runtime)} -Complete {param($runtime)}
        return @{Command='merge-base';GitVersion=$Runtime.State.DetectedVersion;ExitCode=$native.Execution.Native.ExitCode;IsAncestor=($native.Execution.Native.ExitCode -eq 0);Scope='Requested native ancestry predicate only.'}
    }
    if($Request.Name -ceq 'rev-list'){
        $nonIdentity=@('--abbrev-commit','--abbrev','--abbrev-commit','--binary','--boundary','--check','--children','--cherry-mark','--count','--disk-usage','--filter-print-omitted','--format','--graph','--header','--left-right','--missing','--missing-only','--name-only','--name-status','--numstat','--objects','--objects-edge','--objects-edge-aggressive','--oneline','--patch','-p','--pretty','--raw','--source','--stat','--timestamp','-z')
        if(@($flags|Where-Object {$_ -cin $nonIdentity}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('rev-list')+@($Request.Arguments)) rev-list -Delimiter $(if('-z' -cin $flags){0}else{10})}
    }
    $data=@{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;Objects=[Collections.Generic.List[object]]::new();WithParents=('--parents' -cin $flags);Found=$false}
    $codes=if($Request.Name -ceq 'merge-base'){@(0,1)}else{@(0)}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $data -Codes $codes -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitObjectRecords]::Receive($record,$data)
    }
    $r.Data.Found=$r.Data.Objects.Count -gt 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
function Invoke-QuietGitReferenceQuery {
    <#
    .SYNOPSIS
    Streams local or explicitly requested advertised refs with separate predicate and format modes.
    .PARAMETER Runtime
    Parent invocation; ls-remote contacts only its explicitly requested source.
    .PARAMETER Request
    Original command and arguments.
    .PARAMETER Binding
    Bound output and filtering options.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $flags=@($Binding.Options.Name)
    if($Request.Name -ceq 'for-each-ref'){
        if(@($flags|Where-Object {$_ -cin @('--format','--shell','--python','--perl','--tcl','-z')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('for-each-ref')+@($Request.Arguments)) for-each-ref -Delimiter $(if('-z' -cin $flags){0}else{10})}
        $data=@{Command='for-each-ref';GitVersion=$Runtime.State.DetectedVersion;References=[Collections.Generic.List[object]]::new()}
        $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('for-each-ref','--format=%(refname)%00%(objectname)%00%(objecttype)%00%(symref)%00')+@($Request.Arguments)) $data -FieldCount 4 -Commit {
            param($fields,$data)
            $data.References.Add(@{Name=$fields[0];ObjectId=$fields[1];Type=$fields[2];SymbolicTarget=$fields[3]})
        }
        return $r.Data
    }
    if($Request.Name -ceq 'show-ref'){
        if('--exists' -cin $flags){
            $r=Invoke-QuietGitNative $Runtime ($Prefix+@('show-ref')+@($Request.Arguments)) -Data $null -SuccessExitCodes @(0,2) -Output {param($event,$runtime)} -Complete {param($runtime)}
            return @{Command='show-ref';GitVersion=$Runtime.State.DetectedVersion;Exists=($r.Execution.Native.ExitCode -eq 0);ExitCode=$r.Execution.Native.ExitCode}
        }
        if(@($flags|Where-Object {$_ -cin @('--hash','-s','--abbrev','--exclude-existing')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('show-ref')+@($Request.Arguments)) show-ref -Codes @(0,1)}
    }
    if($Request.Name -ceq 'ls-remote' -and '--get-url' -cin $flags){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('ls-remote')+@($Request.Arguments)) ls-remote}
    $codes=if($Request.Name -ceq 'show-ref'){@(0,1)}elseif('--exit-code' -cin $flags){@(0,2)}else{@(0)}
    $data=@{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;References=[Collections.Generic.List[object]]::new();Found=$false}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $data -Codes $codes -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitReferenceRecords]::Receive($record,$data)
    }
    $r.Data.Found=$r.Data.References.Count -gt 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    if($Request.Name -ceq 'show-ref' -and @($flags|Where-Object {$_ -cin @('--quiet','-q')}).Count){$r.Data.Found=$r.Execution.Native.ExitCode -eq 0}
    return $r.Data
}
function Invoke-QuietGitIndexQuery {
    <#
    .SYNOPSIS
    Normalizes ls-files framing only, preserving requested record layouts explicitly.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original ls-files arguments and pathspecs.
    .PARAMETER Binding
    Bound output and selection flags.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $flags=@($Binding.Options.Name)
    if(@($flags|Where-Object {$_ -cin @('--debug','--eol','--format','--abbrev','--resolve-undo','-t','-v','-f')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('ls-files')+@($Request.Arguments)) ls-files -Delimiter $(if('-z' -cin $flags){0}else{10})}
    $arguments=Get-QuietGitArguments $Binding @('-z')
    $data=@{Command='ls-files';GitVersion=$Runtime.State.DetectedVersion;Files=[Collections.Generic.List[object]]::new();WithStage=(@($flags|Where-Object {$_ -cin @('--stage','-s','--unmerged','-u')}).Count -gt 0);PathRepresentation='NUL-delimited UTF-8 or explicit raw bytes'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('ls-files','-z')+$arguments) $data -Delimiter 0 -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitIndexRecords]::Receive($record,$data)
    }
    return $r.Data
}
function Invoke-QuietGitCountQuery {
    <#
    .SYNOPSIS
    Reads numeric object counters with explicit units and separately retained alternates.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original count-objects request.
    .PARAMETER Binding
    Bound output flags.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if(@($Binding.Options.Name|Where-Object {$_ -cin @('--human-readable','-H')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('count-objects')+@($Request.Arguments)) count-objects}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('--verbose','-v')
    $data=@{Command='count-objects';GitVersion=$Runtime.State.DetectedVersion;Counts=@{};Alternates=[Collections.Generic.List[object]]::new();SizeUnit='KiB'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('count-objects','-v')+$arguments) $data -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitObjectCounts]::Receive($record,$data)
    }
    return $r.Data
}
function Invoke-QuietGitSymbolicRef {
    <#
    .SYNOPSIS
    Separates a symbolic-ref read from an explicit reference mutation.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original symbolic-ref request.
    .PARAMETER Binding
    Bound options and operands.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if($Binding.Operands.Count -gt 1 -or '--delete' -cin $flags -or '-d' -cin $flags){return Invoke-QuietGitObservedMutation $Runtime $Request $Prefix}
    Import-QuietGitParser
    $data=@{Command='symbolic-ref';GitVersion=$Runtime.State.DetectedVersion;Values=[Collections.Generic.List[object]]::new();Exists=$false;Reference=$null}
    $codes=if('--quiet' -cin $flags -or '-q' -cin $flags){@(0,1)}else{@(0)}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('symbolic-ref')+@($Request.Arguments)) $data -Codes $codes -Parser {param($record,$data)$data.Values.Add([FrenchExDev2.QuietCli.Git.GitRecords]::Decode($record))}
    if($r.Data.Values.Count -gt 1){throw 'UnexpectedSymbolicReferenceCount'}
    $r.Data.Exists=$r.Execution.Native.ExitCode -eq 0
    if($r.Data.Values.Count){$r.Data.Reference=$r.Data.Values[0]}
    $r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
function Invoke-QuietGitRefValidation {
    <#
    .SYNOPSIS
    Preserves Git's exact ref validation result without treating native errors as valid names.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original validation request.
    .PARAMETER Binding
    Bound normalization options.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $data=@{Command='check-ref-format';GitVersion=$Runtime.State.DetectedVersion;Valid=$false;NormalizedName=$null;Values=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('check-ref-format')+@($Request.Arguments)) $data -Codes @(0,1) -Parser {param($record,$data)$data.Values.Add([FrenchExDev2.QuietCli.Git.GitRecords]::Decode($record))}
    $r.Data.Valid=$r.Execution.Native.ExitCode -eq 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    if($r.Data.Values.Count){$r.Data.NormalizedName=$r.Data.Values[0]}
    return $r.Data
}
function Invoke-QuietGitVersion {
    <#
    .SYNOPSIS
    Returns the requested native version and explicitly requested build information.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original version request.
    .PARAMETER Binding
    Bound build-information options.
    .PARAMETER Prefix
    Git global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $data=@{Command='version';Version=$null;BuildInformation=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('version')+@($Request.Arguments)) $data -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitVersionRecords]::Receive($record,$data)}
    if($r.Outcome -eq 'Success' -and !$r.Data.Version){throw 'MissingGitVersion'}
    return $r.Data
}
