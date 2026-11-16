function Invoke-QuietGitRevision {
    <#
    .SYNOPSIS
    Separates verified IDs, documented scalar outputs and mixed revision output.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact rev-parse arguments.
    .PARAMETER Binding
    Bound output selectors and operands.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $kinds=@{
        '--absolute-git-dir'='Path';'--git-dir'='Path';'--git-common-dir'='Path';'--show-toplevel'='Path';'--show-prefix'='Path';'--show-cdup'='Path';'--shared-index-path'='Path';'--show-superproject-working-tree'='Path';'--git-path'='Path';'--resolve-git-dir'='Path'
        '--is-bare-repository'='Boolean';'--is-inside-git-dir'='Boolean';'--is-inside-work-tree'='Boolean';'--is-shallow-repository'='Boolean';'--show-object-format'='ObjectFormat';'--show-ref-format'='RefFormat'
    }
    $selectors=@($flags|Where-Object {$kinds.ContainsKey($_)})
    $other=@($flags|Where-Object {!$kinds.ContainsKey($_) -and $_ -cne '--path-format'})
    if($selectors.Count -eq 1 -and !$other.Count -and !$Binding.Operands.Count){
        if($Runtime.Request.Transport -ne 'Pipe'){throw 'ScalarBusinessProtocolRequiresPipe'}
        Import-QuietGitParser
        $data=@{Command='rev-parse';GitVersion=$Runtime.State.DetectedVersion;Kind=$kinds[$selectors[0]];Selector=$selectors[0];Collector=[FrenchExDev2.QuietCli.Git.GitScalarOutput]::new()}
        $r=Invoke-QuietGitNative $Runtime ($Prefix+@('rev-parse')+@($Request.Arguments)) -Data $data -StdoutMode Bytes -StderrMode Bytes -Output {
            param($event,$runtime)
            if($event.Stream -ceq 'stdout'){$runtime.Data.Collector.Append($event.Bytes)}
        } -Complete {
            param($runtime)
            @{Command=$runtime.Data.Command;GitVersion=$runtime.Data.GitVersion;Kind=$runtime.Data.Kind;Selector=$runtime.Data.Selector;Value=$runtime.Data.Collector.Finish()}
        }
        if($r.Execution.Native.ExitCode -eq 0 -and $r.Data.Kind -ceq 'Boolean'){$r.Data.Value=[FrenchExDev2.QuietCli.Git.GitScalarOutput]::ParseBoolean($r.Data.Value)}
        $r.Data.ExitCode=$r.Execution.Native.ExitCode
        return $r.Data
    }
    if('--verify' -cin $flags -and !@($flags|Where-Object {$_ -cnotin @('--verify','--quiet','-q','--end-of-options')}).Count){return Invoke-QuietGitObjectQuery $Runtime $Request $Binding $Prefix}
    return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('rev-parse')+@($Request.Arguments)) rev-parse
}
function Invoke-QuietGitDescribe {
    <#
    .SYNOPSIS
    Parses unambiguous long descriptions while retaining custom suffix and contains modes.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact describe selection and candidates.
    .PARAMETER Binding
    Bound display and suffix options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if(@($flags|Where-Object {$_ -cin @('--contains','--dirty','--broken')}).Count -or @($Binding.Options|Where-Object {$_.Name -ceq '--abbrev' -and $_.Value -ceq '0'}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('describe')+@($Request.Arguments)) describe}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('--long')
    $data=@{Command='describe';GitVersion=$Runtime.State.DetectedVersion;Descriptions=[Collections.Generic.List[object]]::new();Scope='Native long description; abbreviations do not establish full IDs or hash algorithms.'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('describe','--long')+$arguments) $data -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitDescribeRecords]::Receive($record,$data)}
    return $r.Data
}
function Invoke-QuietGitRevisionNames {
    <#
    .SYNOPSIS
    Returns native revision labels/names without interpreting symbolic labels as object hashes.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact name-rev request.
    .PARAMETER Binding
    Bound name-only/stdin formatting modes.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if(@($Binding.Options.Name|Where-Object {$_ -cin @('--name-only','--annotate-stdin','--stdin')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('name-rev')+@($Request.Arguments)) name-rev}
    Import-QuietGitParser
    $data=@{Command='name-rev';GitVersion=$Runtime.State.DetectedVersion;Names=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('name-rev')+@($Request.Arguments)) $data -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitRevisionNames]::Receive($record,$data)}
    return $r.Data
}
function Invoke-QuietGitShortlog {
    <#
    .SYNOPSIS
    Parses requested shortlog summaries without discarding default commit subjects.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact shortlog selection and formatting.
    .PARAMETER Binding
    Bound summary/group options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if(!@($Binding.Options.Name|Where-Object {$_ -cin @('-s','--summary')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('shortlog')+@($Request.Arguments)) shortlog}
    Import-QuietGitParser
    $data=@{Command='shortlog';GitVersion=$Runtime.State.DetectedVersion;Groups=[Collections.Generic.List[object]]::new();Scope='Exact native summary labels and counts; labels are not guessed to be author names or email addresses.'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('shortlog')+@($Request.Arguments)) $data -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitShortlogRecords]::Receive($record,$data)}
    return $r.Data
}
