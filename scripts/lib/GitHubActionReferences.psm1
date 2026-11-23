#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-QuietGitHubActionFiles {
    <#
    .SYNOPSIS
    Lists the workflow and composite action YAML files of a checkout, in ordinal order of their relative path.
    .DESCRIPTION
    Returns .github/workflows/*.yml and *.yaml (not recursive, as GitHub reads them) and every action.yml or
    action.yaml under .github/actions. Each item is {RelativePath, FullPath}, RelativePath using '/'. A missing
    directory contributes nothing. A file reached through a link (reparse point) throws GitHubActionFileLinked,
    so a rewrite can never escape the checkout.
    .PARAMETER WorkspaceRoot
    Checkout whose .github directory is read.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $files=[Collections.Generic.List[object]]::new()
    $workflows=[IO.Path]::Combine($root,'.github','workflows')
    if([IO.Directory]::Exists($workflows)){
        foreach($file in [IO.Directory]::EnumerateFiles($workflows)){
            if([IO.Path]::GetExtension($file) -cin @('.yml','.yaml')){$files.Add($file)}
        }
    }
    $actions=[IO.Path]::Combine($root,'.github','actions')
    if([IO.Directory]::Exists($actions)){
        foreach($file in [IO.Directory]::EnumerateFiles($actions,[string]::Empty,[IO.SearchOption]::AllDirectories)){
            if([IO.Path]::GetFileName($file) -cin @('action.yml','action.yaml')){$files.Add($file)}
        }
    }
    $items=@(foreach($file in $files){
        $attributes=(Get-Item -LiteralPath $file -Force -ErrorAction Stop).Attributes
        if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('GitHubActionFileLinked: '+$file)}
        [pscustomobject]@{RelativePath=[IO.Path]::GetRelativePath($root,$file).Replace('\','/');FullPath=$file}
    })
    # Sort-Object is culture-aware; an ordinal sort keeps the order identical on every host.
    [Array]::Sort([object[]]$items,[Comparison[object]]{param($left,$right)[string]::CompareOrdinal($left.RelativePath,$right.RelativePath)})
    $items
}

function ConvertFrom-QuietGitHubActionUses {
    <#
    .SYNOPSIS
    Finds every `uses:` step or job reference of a workflow or action text, line by line, without evaluating YAML.
    .DESCRIPTION
    A reference line is `[- ]uses: <value>` with an optional quote around the value and an optional `# comment`.
    Each match returns {Path, LineNumber, Prefix, Quote, Value, Comment, Kind, Owner, Repository, SubPath, Ref,
    RefKind, Action}. Kind is Local (./ or ../), Docker (docker://) or Remote. A Remote value is
    owner/repository[/path]@ref; Action is owner/repository, the unit whose releases are resolved. RefKind is
    Sha (40 lowercase hexadecimal digits), Version (v1, v1.2 or v1.2.3) or Other (a branch or any other ref).
    A Remote value that is not owner/repository[/path]@ref throws GitHubActionReferenceInvalid with its location.
    Lines inside block scalars (run: |) can match too; GitHub does not interpret them, so neither should a
    caller rewrite them: such a line rarely starts with uses:, and the caller reviews the diff.
    .PARAMETER Text
    Whole file content, LF or CRLF.
    .PARAMETER Path
    Relative path reported with each reference.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)][string]$Path)
    $lines=$Text.Split("`n")
    for($index=0;$index -lt $lines.Count;$index++){
        $line=$lines[$index].TrimEnd([char]13)
        $match=[regex]::Match($line,'\A(?<prefix>[ \t]*(?:-[ \t]+)?uses:[ \t]*)(?<quote>[''"]?)(?<value>[^\s''"#]+)\k<quote>(?:[ \t]+#[ \t]?(?<comment>.*?))?[ \t]*\z')
        if(!$match.Success){continue}
        $value=$match.Groups['value'].Value
        $reference=[ordered]@{Path=$Path;LineNumber=$index+1;Line=$line;Prefix=$match.Groups['prefix'].Value;Quote=$match.Groups['quote'].Value;Value=$value;Comment=$null;Kind='Remote';Owner=$null;Repository=$null;SubPath=$null;Ref=$null;RefKind=$null;Action=$null}
        if($match.Groups['comment'].Success){$reference.Comment=$match.Groups['comment'].Value}
        if($value.StartsWith('./',[StringComparison]::Ordinal) -or $value.StartsWith('../',[StringComparison]::Ordinal)){$reference.Kind='Local'}
        elseif($value.StartsWith('docker://',[StringComparison]::Ordinal)){$reference.Kind='Docker'}
        else{
            $remote=[regex]::Match($value,'\A(?<owner>[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/(?<repository>[A-Za-z0-9._-]{1,100})(?<sub>(?:/[A-Za-z0-9._-]+)+)?@(?<ref>[A-Za-z0-9._/+-]{1,255})\z')
            if(!$remote.Success -or $remote.Groups['repository'].Value -cin @('.','..')){throw ('GitHubActionReferenceInvalid: '+$Path+':'+($index+1)+' '+$value)}
            $reference.Owner=$remote.Groups['owner'].Value
            $reference.Repository=$remote.Groups['repository'].Value
            if($remote.Groups['sub'].Success){$reference.SubPath=$remote.Groups['sub'].Value.Substring(1)}
            $reference.Ref=$remote.Groups['ref'].Value
            $reference.RefKind=Get-QuietGitHubActionRefKind -Ref $reference.Ref
            $reference.Action=$reference.Owner+'/'+$reference.Repository
        }
        [pscustomobject]$reference
    }
}

function Get-QuietGitHubActionRefKind {
    <#
    .SYNOPSIS
    Classifies a uses: ref as Sha (a full lowercase commit id), Version (v1, v1.2, v1.2.3) or Other.
    .PARAMETER Ref
    The text after '@'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Ref)
    if($Ref -cmatch '\A[0-9a-f]{40}\z'){return 'Sha'}
    if($Ref -cmatch '\Av\d{1,9}(?:\.\d{1,9}){0,2}\z'){return 'Version'}
    'Other'
}

function Format-QuietGitHubActionUses {
    <#
    .SYNOPSIS
    Renders a parsed Remote reference line with a new ref and comment, keeping its indentation, key and quote.
    .DESCRIPTION
    The result is Prefix + Quote + owner/repository[/path]@Ref + Quote, followed by ' # Comment' when Comment is
    not empty. Parsing the rendered line with ConvertFrom-QuietGitHubActionUses returns the same Action, SubPath,
    Ref and Comment. A ref or comment containing a line break throws GitHubActionReferenceInvalid.
    .PARAMETER Reference
    A Remote reference returned by ConvertFrom-QuietGitHubActionUses.
    .PARAMETER Ref
    New ref, for example a commit id or a release tag.
    .PARAMETER Comment
    New comment without '#', or empty for none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Reference,[Parameter(Mandatory)][string]$Ref,[AllowEmptyString()][AllowNull()][string]$Comment)
    if($Reference.Kind -cne 'Remote'){throw ('GitHubActionReferenceInvalid: only a Remote reference can be rendered, not '+$Reference.Kind)}
    if($Ref -cnotmatch '\A[A-Za-z0-9._/+-]{1,255}\z' -or ([string]$Comment).IndexOfAny([char[]]"`r`n") -ge 0){throw 'GitHubActionReferenceInvalid: ref or comment cannot be rendered on one line'}
    $action=$Reference.Action
    if($Reference.SubPath){$action+='/'+$Reference.SubPath}
    $value=$action+'@'+$Ref
    $line=$Reference.Prefix+$Reference.Quote+$value+$Reference.Quote
    if(![string]::IsNullOrWhiteSpace($Comment)){$line+=' # '+$Comment.Trim()}
    $line
}

function Get-QuietGitHubActionRewrittenText {
    <#
    .SYNOPSIS
    Returns a file text with some whole lines replaced, after checking that each line still holds its expected text.
    .DESCRIPTION
    Each change is {LineNumber, Line, NewLine}: the 1-based line, its text without line ending, and the
    replacement. Line endings (LF or CRLF, per line) and every other byte of the text are kept. A line number
    outside the text, or a line whose current text differs from Line, throws GitHubActionSourceChanged; two
    changes of the same line throw GitHubActionChangeDuplicated. Nothing is written.
    .PARAMETER Text
    Current file text.
    .PARAMETER Changes
    Line replacements.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Changes)
    $lines=$Text.Split("`n")
    $seen=[Collections.Generic.HashSet[int]]::new()
    foreach($change in $Changes){
        $number=[int]$change.LineNumber
        if(!$seen.Add($number)){throw ('GitHubActionChangeDuplicated: line '+$number)}
        if($number -lt 1 -or $number -gt $lines.Count){throw ('GitHubActionSourceChanged: line '+$number+' is outside the file')}
        $current=$lines[$number-1]
        $ending=if($current.EndsWith("`r",[StringComparison]::Ordinal)){"`r"}else{''}
        if($current.Substring(0,$current.Length-$ending.Length) -cne [string]$change.Line){throw ('GitHubActionSourceChanged: line '+$number+' no longer holds the parsed reference')}
        if(([string]$change.NewLine).IndexOfAny([char[]]"`r`n") -ge 0){throw ('GitHubActionReferenceInvalid: line '+$number+' replacement spans several lines')}
        $lines[$number-1]=[string]$change.NewLine+$ending
    }
    $lines -join "`n"
}

Export-ModuleMember -Function 'Get-QuietGitHubActionFiles','ConvertFrom-QuietGitHubActionUses','Get-QuietGitHubActionRefKind','Format-QuietGitHubActionUses','Get-QuietGitHubActionRewrittenText'
