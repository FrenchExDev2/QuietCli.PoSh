function ConvertFrom-QuietGitBytesBaseline {
    <#
.SYNOPSIS
Decodes a business field losslessly; invalid UTF-8 remains explicitly represented as bytes.
    .PARAMETER Bytes
    Exact bytes of one Git field or record.
    #>
    param([byte[]]$Bytes)
    try{return [Text.UTF8Encoding]::new($false,$true).GetString($Bytes)}
    catch{return @{Encoding='RawBytes';Base64=[Convert]::ToBase64String($Bytes);Bytes=$Bytes.Length}}
}

function Receive-QuietGitStatusRecordBaseline {
    <#
.SYNOPSIS
Parses porcelain-v2 bytes, preserving raw paths and rename source boundaries.
    .PARAMETER Record
    Exact NUL-delimited bytes.
    .PARAMETER Data
    Parsed status state.
    #>
    param([byte[]]$Record,[hashtable]$Data)
    if($Data.Pending){$Data.Pending.OriginalPath=ConvertFrom-QuietGitBytesBaseline $Record;$Data.Pending=$null;return}
    if(!$Record.Length){return}
    if($Record[0] -eq 35){
        $space=[Array]::IndexOf($Record,[byte]32,2);if($space -lt 0){return}
        $key=[Text.Encoding]::ASCII.GetString($Record,2,$space-2)
        $bytes=[byte[]]::new($Record.Length-$space-1);[Array]::Copy($Record,$space+1,$bytes,0,$bytes.Length);$value=ConvertFrom-QuietGitBytesBaseline $bytes
        switch -CaseSensitive ($key){
            'branch.head' {$Data.Detached=$value -is [string] -and $value -ceq '(detached)';$Data.Branch=if($Data.Detached){$null}else{$value}}
            'branch.oid' {$Data.Unborn=$value -is [string] -and $value -ceq '(initial)';$Data.HeadOid=if($Data.Unborn){$null}else{$value}}
            'branch.upstream' {$Data.Upstream=$value}
            'branch.ab' {if($value -isnot [string] -or $value -notmatch '^\+(\d+) -(\d+)$'){throw 'MalformedBranchDivergence'};$Data.Ahead=[long]$Matches[1];$Data.Behind=[long]$Matches[2]}
            stash {$Data.StashCount=[long]$value}
        }
        return
    }
    $kind=[char]$Record[0];$entry=$null
    if($kind -cin @('?','!')){
        if($Record.Length -lt 3 -or $Record[1] -ne 32){throw 'MalformedStatusPath'}
        $bytes=[byte[]]::new($Record.Length-2);[Array]::Copy($Record,2,$bytes,0,$bytes.Length)
        $entry=@{Kind=$(if($kind -eq '?'){'Untracked'}else{'Ignored'});Status=$(if($kind -eq '?'){'??'}else{'!!'});Path=(ConvertFrom-QuietGitBytesBaseline $bytes);OriginalPath=$null;Submodule=$null}
        if($kind -eq '?'){$Data.Counts.Untracked++;$Data.Counts.Changed++}else{$Data.Counts.Ignored++}
    }elseif($kind -cin @('1','2','u')){
        $limit=switch($kind){'1' {8} '2' {9} default {10}};$fields=[Collections.Generic.List[string]]::new();$start=0
        for($index=0;$index -lt $Record.Length -and $fields.Count -lt $limit;$index++){if($Record[$index] -eq 32){$fields.Add([Text.Encoding]::ASCII.GetString($Record,$start,$index-$start));$start=$index+1}}
        if($fields.Count -ne $limit -or $start -ge $Record.Length -or $fields[1] -notmatch '^[.MADRCUT]{2}$'){throw 'MalformedPorcelainStatusRecord'}
        $bytes=[byte[]]::new($Record.Length-$start);[Array]::Copy($Record,$start,$bytes,0,$bytes.Length)
        $entry=@{Kind=$(if($kind -eq 'u'){'Conflicted'}elseif($kind -eq '2'){'RenamedOrCopied'}else{'Tracked'});Status=$fields[1];Path=(ConvertFrom-QuietGitBytesBaseline $bytes);OriginalPath=$null;Submodule=$fields[2]}
        $Data.Counts.Changed++
        if($kind -eq 'u'){$Data.Counts.Conflicted++}else{if($fields[1][0] -ne '.'){$Data.Counts.Staged++};if($fields[1][1] -ne '.'){$Data.Counts.Unstaged++}}
        if($kind -eq '2'){$Data.Pending=$entry;if($fields[8].StartsWith('R')){$Data.Counts.Renamed++}}
    }else{throw 'UnknownPorcelainStatusRecord'}
    $Data.Entries.Add($entry)
}

function Receive-QuietGitPatchRecordBaseline {
    <#
.SYNOPSIS
Parses one patch line while preserving non-UTF8 payloads and combined diff records.
    .PARAMETER Record
    Exact bytes excluding LF.
    .PARAMETER Data
    Parsed patch state.
    #>
    param([byte[]]$Record,[hashtable]$Data)
    $line=ConvertFrom-QuietGitBytesBaseline $Record
    if($line -isnot [string]){
        $row=@{Kind='ByteContent';Content=$line}
        if($Data.CurrentHunk){$Data.CurrentHunk.Lines.Add($row)}elseif($Data.CurrentFile){$Data.CurrentFile.Metadata.Add($row)}else{$Data.Preamble.Add($row)}
        return
    }
    if($line -match '^diff --(git|cc|combined) (.*)$'){
        $file=@{Header=$line;CommitId=$Data.CurrentCommit;Combined=($Matches[1] -ne 'git');Labels=$Matches[2];OldLabel=$null;NewLabel=$null;OldMode=$null;NewMode=$null;Binary=$false;Metadata=[Collections.Generic.List[object]]::new();Hunks=[Collections.Generic.List[object]]::new()}
        $Data.Files.Add($file);$Data.CurrentFile=$file;$Data.CurrentHunk=$null;return
    }
    if($line -match '^commit ([0-9a-f]+)'){$Data.CurrentCommit=$Matches[1];$Data.Commits.Add(@{ObjectId=$Matches[1]});$Data.CurrentFile=$null;$Data.CurrentHunk=$null;$Data.Preamble.Add(@{Text=$line});return}
    if(!$Data.CurrentFile){$Data.Preamble.Add(@{Text=$line});return}
    $file=$Data.CurrentFile
    if($line -match '^(@@+)(.*)\1(.*)$'){
        $hunk=@{Header=$line;Combined=($Matches[1].Length -gt 2);Ranges=@([regex]::Matches($Matches[2],'[-+]\d+(?:,\d+)?')|ForEach-Object{$_.Value});Lines=[Collections.Generic.List[object]]::new()}
        $file.Hunks.Add($hunk);$Data.CurrentHunk=$hunk;return
    }
    if($Data.CurrentHunk){
        $kind=if($line.StartsWith('\ No newline')){'NoFinalNewline'}elseif($Data.CurrentHunk.Combined){'CombinedContent'}elseif($line.StartsWith('+')){'Addition'}elseif($line.StartsWith('-')){'Deletion'}else{'Context'}
        $Data.CurrentHunk.Lines.Add(@{Kind=$kind;Text=$line});return
    }
    switch -Regex ($line){
        '^--- (.*)$' {$file.OldLabel=$Matches[1]}
        '^\+\+\+ (.*)$' {$file.NewLabel=$Matches[1]}
        '^(?:old mode|deleted file mode) (\d+)$' {$file.OldMode=$Matches[1]}
        '^(?:new mode|new file mode) (\d+)$' {$file.NewMode=$Matches[1]}
        '^(?:Binary files |GIT binary patch)' {$file.Binary=$true}
    }
    $file.Metadata.Add(@{Text=$line})
}

function Get-GitArgumentTokenBaseline {
    <#
.SYNOPSIS
    Binds options, their values, operands and literal separators without executing Git.
    .DESCRIPTION
    Uses curated Git module metadata. Required values are consumed even when they
    look like options or '--'. Bare optional values never consume the next argv.
    Unknown arity stops interpretation; the remaining original argv is preserved.
    Complete means token binding succeeded, not that Git accepts the values,
    option combination, command availability or repository state.
    .PARAMETER Command
    Git command name, without the git executable or its global options.
    .PARAMETER ArgumentList
    The exact argv following that command. Empty string values are preserved.
    .PARAMETER Request
    Existing Git request with Name and Arguments, as an alternative to Command.
    .PARAMETER Version
    Observed or explicitly supplied version, retained in the result. Availability
    and version compatibility remain the separate registry's responsibility.
    .PARAMETER Schema
    Explicit curated schema, for deterministic pure tokenization tests.
    .OUTPUTS
    Binding object: Complete, Tokens, Options, Operands, OperandTokens, Subcommand,
    Unknowns, OriginalArguments and EmitArguments. Never rewrite incomplete output.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Command')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Command')][Alias('CommandName')][string]$Command,
        [Parameter(ParameterSetName = 'Command')][AllowEmptyCollection()][AllowEmptyString()][string[]]$ArgumentList = @(),
        [Parameter(Mandatory, ParameterSetName = 'Request')][hashtable]$Request,
        [AllowNull()][string]$Version, [hashtable]$Schema
    )
    if ($PSCmdlet.ParameterSetName -eq 'Request') {
        $Command = $Request.Name
        $ArgumentList = @($Request.Arguments)
    }
    if ($null -eq $ArgumentList) { $ArgumentList = @() }
    $original = [string[]]$ArgumentList.Clone()
    $tokens = [Collections.Generic.List[object]]::new()
    $unknown = [Collections.Generic.List[object]]::new()
    if (!$Schema) { $Schema = Get-GitArgumentSchema }
    $policy = if ($Schema) { Get-GitArgumentPolicy -Command $Command -Schema $Schema }else { $null }
    $subcommand = $null
    $selectorSeen = $false
    $literal = $false
    $stop = $false
    $index = 0
    $unknownIndex = -1
    $reason = $null
    if (!$policy) {
        $unknownIndex = 0
        $reason = 'No curated argument policy is available for this command.'
    }
    if ($policy -and $policy.Policy.LiteralAllArguments) { $stop = $true }
    $nativeSelectorIndex = -1
    if ($policy -and $policy.Policy.NativeSubcommandScan) {
        for ($candidate = 0; $candidate -lt $original.Count; $candidate++) {
            if ($null -ne $original[$candidate] -and $original[$candidate] -cin @($policy.Policy.Subcommands.Keys)) {
                $nativeSelectorIndex = $candidate
                $subcommand = $original[$candidate]
                $policy = Get-GitArgumentPolicy -Command $Command -Schema $Schema -Subcommand $subcommand
                break
            }
        }
    }
    while ($unknownIndex -lt 0 -and $index -lt $original.Count) {
        $raw = $original[$index]
        if ($null -eq $raw) {
            $unknownIndex = $index
            $reason = 'A native argv item cannot be null; use an explicit empty string when intended.'
            break
        }
        if ($index -eq $nativeSelectorIndex) {
            $tokens.Add((New-GitArgumentUnit -Kind Subcommand -Raw $raw -Position $index -EmitArguments @($raw) -Name $raw))
            $selectorSeen = $true
            $index++
            continue
        }
        if ($literal -or $stop) {
            $tokens.Add((New-GitArgumentUnit -Kind Operand -Raw $raw -Position $index -EmitArguments @($raw)))
            $index++
            continue
        }
        if ($raw -ceq '--') {
            $tokens.Add((New-GitArgumentUnit -Kind Separator -Raw $raw -Position $index -EmitArguments @($raw)))
            $literal = $true
            $index++
            continue
        }
        if ($raw -ceq '-' -or !$raw.StartsWith('-')) {
            $selectorEligible = !$selectorSeen
            $selectorSeen = $true
            if ($selectorEligible -and $policy.Policy.Subcommands -and $raw -cin @($policy.Policy.Subcommands.Keys)) {
                $subcommand = $raw
                $tokens.Add((New-GitArgumentUnit -Kind Subcommand -Raw $raw -Position $index -EmitArguments @($raw) -Name $raw))
                $policy = Get-GitArgumentPolicy -Command $Command -Schema $Schema -Subcommand $subcommand
                if (!$policy) {
                    $unknownIndex = $index + 1
                    $reason = 'The subcommand argument policy could not be loaded.'
                    break
                }
                if ($policy.OpaqueTail) { $stop = $true }
            }
            else {
                $tokens.Add((New-GitArgumentUnit -Kind Operand -Raw $raw -Position $index -EmitArguments @($raw)))
                if ($policy.StopAtOperand) { $stop = $true }
            }
            $index++
            continue
        }
        if ($policy.NumericShortOption -and $raw -cmatch '^-(\d+)$') {
            $tokens.Add((New-GitArgumentUnit -Kind Option -Raw $raw -Position $index -EmitArguments @($raw) -Name $policy.NumericShortOption -ValueKind Required -Value $Matches[1] -HasValue $true -Binding NumericShort -ValuePosition $index -SourceProfile Revision))
            $index++
            continue
        }
        if ($raw.StartsWith('--')) {
            $parts = $raw -split '=', 2
            $name = $parts[0]
            if (!$policy.Definitions.ContainsKey($name)) {
                $unknownIndex = $index
                $reason = ('The arity of option ' + $name + ' is not curated for this command.')
                break
            }
            $definition = $policy.Definitions[$name]
            $value = $null
            $values = @()
            $hasValue = $false
            $span = 1
            $valuePosition = -1
            $binding = 'Bare'
            if ($parts.Count -eq 2) {
                if ('Equals' -notin $definition.Forms) {
                    $unknownIndex = $index
                    $reason = ('This option does not declare an equals-bound value: ' + $name)
                    break
                }
                $value = $parts[1]
                $hasValue = $true
                $valuePosition = $index
                $binding = 'Equals'
            }
            elseif ($definition.ValueKind -eq 'Required') {
                if ('Separate' -notin $definition.Forms) {
                    $unknownIndex = $index
                    $reason = ('This option requires an attached value: ' + $name)
                    break
                }
                if ($index + 1 -ge $original.Count -or $null -eq $original[$index + 1]) {
                    $unknownIndex = $index
                    $reason = ('A required option value is missing: ' + $name)
                    break
                }
                if ($index + 1 -eq $nativeSelectorIndex) {
                    $unknownIndex = $index
                    $reason = 'The native preliminary command selector occurs between an option and its value; this layout requires a dedicated binding.'
                    break
                }
                $value = $original[$index + 1]
                $hasValue = $true
                $span = 2
                $valuePosition = $index + 1
                $binding = 'Separate'
                if ($definition.Syntax -eq 'Cacheinfo') {
                    switch -Regex ($value) {
                        '^[0-7]+,[0-9a-f]{40}(?:[0-9a-f]{24})?,.*$' {
                            $span = 2
                            break
                        }
                        '^[0-7]+$' {
                            $span = 4
                            $binding = 'SeparateTuple'
                            break
                        }
                        default {
                            $unknownIndex = $index
                            $reason = 'The cacheinfo payload is neither its comma tuple nor its legacy three-value form.'
                        }
                    }
                    if ($unknownIndex -ge 0) { break }
                    if ($index + $span -gt $original.Count) {
                        $unknownIndex = $index
                        $reason = 'The legacy cacheinfo mode/object/path tuple is incomplete.'
                        break
                    }
                    if (@($original[($index + 1)..($index + $span - 1)] | Where-Object { $null -eq $_ }).Count) {
                        $unknownIndex = $index
                        $reason = 'A cacheinfo payload value cannot be null.'
                        break
                    }
                }
            }
            elseif ($definition.Syntax -cin @('PerlOptionalString', 'PerlOptionalInteger') -and $index + 1 -lt $original.Count -and $null -ne $original[$index + 1]) {
                $next = $original[$index + 1]
                if (!$next.StartsWith('-') -or ($definition.Syntax -ceq 'PerlOptionalInteger' -and $next -cmatch '^-\d+$')) {
                    if ($index + 1 -eq $nativeSelectorIndex) {
                        $unknownIndex = $index
                        $reason = 'The native preliminary command selector intersects an optional value layout not yet curated.'
                        break
                    }
                    $value = $next
                    $hasValue = $true
                    $span = 2
                    $valuePosition = $index + 1
                    $binding = 'SeparateOptional'
                }
            }
            elseif ('Bare' -notin $definition.Forms) {
                $unknownIndex = $index
                $reason = ('A bare spelling is not curated for ' + $name)
                break
            }
            $emit = @($original[$index..($index + $span - 1)])
            if ($hasValue) { $values = @(if ($span -gt 1) { $original[($index + 1)..($index + $span - 1)] }else { $value }) }
            $tokens.Add((New-GitArgumentUnit -Kind Option -Raw $raw -Position $index -EmitArguments $emit -Name $name -ValueKind $definition.ValueKind -Value $value -HasValue $hasValue -Binding $binding -Span $span -ValuePosition $valuePosition -SourceProfile $definition.Profile -Values $values))
            if ($name -ceq '--end-of-options' -or $name -cin @($policy.Policy.StopAfterOptions)) { $stop = $true }
            $index += $span
            continue
        }
        $pending = [Collections.Generic.List[object]]::new()
        $span = 1
        for ($offset = 1; $offset -lt $raw.Length; $offset++) {
            $name = '-' + $raw[$offset]
            if (!$policy.Definitions.ContainsKey($name)) {
                $unknownIndex = $index
                $reason = ('The arity of short option ' + $name + ' is not curated for this command.')
                break
            }
            $definition = $policy.Definitions[$name]
            $value = $null
            $hasValue = $false
            $valuePosition = -1
            $binding = 'Bare'
            $emit = @($name)
            if ($definition.ValueKind -ne 'None') {
                if ($offset + 1 -lt $raw.Length) {
                    if ('Attached' -notin $definition.Forms) {
                        $unknownIndex = $index
                        $reason = ('This short option does not declare an attached value: ' + $name)
                        break
                    }
                    $value = $raw.Substring($offset + 1)
                    $hasValue = $true
                    $valuePosition = $index
                    $binding = 'Attached'
                    $emit = @($name + $value)
                }
                elseif ($definition.ValueKind -eq 'Required') {
                    if ('Separate' -notin $definition.Forms) {
                        $unknownIndex = $index
                        $reason = ('This short option requires an attached value: ' + $name)
                        break
                    }
                    if ($index + 1 -ge $original.Count -or $null -eq $original[$index + 1]) {
                        $unknownIndex = $index
                        $reason = ('A required short-option value is missing: ' + $name)
                        break
                    }
                    if ($index + 1 -eq $nativeSelectorIndex) {
                        $unknownIndex = $index
                        $reason = 'The native preliminary command selector occurs between a short option and its value; this layout requires a dedicated binding.'
                        break
                    }
                    $value = $original[$index + 1]
                    $hasValue = $true
                    $span = 2
                    $valuePosition = $index + 1
                    $binding = 'Separate'
                    $emit = @($name, $value)
                }
            }
            $pending.Add((New-GitArgumentUnit -Kind Option -Raw $emit[0] -Position $index -EmitArguments $emit -Name $name -ValueKind $definition.ValueKind -Value $value -HasValue $hasValue -Binding $binding -Span $span -ValuePosition $valuePosition -ClusterOffset $offset -SourceProfile $definition.Profile))
            if ($hasValue) { break }
            if (!$policy.ShortGrouping -and $offset + 1 -lt $raw.Length) {
                $unknownIndex = $index
                $reason = 'Grouped short flags are not curated for this command parser.'
                break
            }
        }
        if ($unknownIndex -ge 0) { break }
        foreach ($item in $pending) { $tokens.Add($item) }
        $index += $span
    }
    if ($unknownIndex -ge 0) {
        $unknown.Add(@{Position = $unknownIndex; Raw = $(if ($unknownIndex -lt $original.Count) { $original[$unknownIndex] }else { $null }); Reason = $reason })
        for ($tail = $unknownIndex; $tail -lt $original.Count; $tail++) { $tokens.Add((New-GitArgumentUnit -Kind Unparsed -Raw $original[$tail] -Position $tail -EmitArguments @($original[$tail]))) }
    }
    $complete = $unknown.Count -eq 0
    $options = @($tokens | Where-Object Kind -CEQ Option)
    $operandTokens = @($tokens | Where-Object Kind -CEQ Operand)
    $emitArguments = @(if ($complete) { $tokens | ForEach-Object { $_.EmitArguments } }else { $original })
    [pscustomobject]@{SchemaVersion =1
        Command                     =$Command
        Version                     =$Version
        Complete                    =$complete
        Tokens                      =$tokens.ToArray()
        Options                     =$options
        Operands                    =@($operandTokens | ForEach-Object { $_.Raw })
        OperandTokens               =$operandTokens
        Subcommand                  =$subcommand
        Unknowns                    =$unknown.ToArray()
        OriginalArguments           =$original
        EmitArguments               =[string[]]$emitArguments
        PolicyScope                 ='Curated token binding; not exhaustive argument or value validation'
    }
}
