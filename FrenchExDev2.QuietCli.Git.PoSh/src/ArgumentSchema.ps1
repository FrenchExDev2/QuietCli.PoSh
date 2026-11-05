# This lexer binds Git-owned option values. It is not a complete semantic validator.
function Get-GitArgumentSchema {
    <#
    .SYNOPSIS
    Reads and caches the module-owned argument grammar without native execution.
    #>
    $cached = Get-Variable -Scope Script -Name GitArgumentSchema -ErrorAction SilentlyContinue
    if ($cached -and $cached.Value) { return $cached.Value }
    $path = Join-Path $script:GitContractRoot 'metadata/Git.ArgumentSchema.json'
    if (!(Test-Path -LiteralPath $path)) { return $null }
    $script:GitArgumentSchema = Get-Content -LiteralPath $path -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $script:GitArgumentSchema
}
function Get-GitArgumentPolicy {
    <#
    .SYNOPSIS
    Resolves option arity and accepted forms for a Git command and subcommand.
    .PARAMETER Command
    Git command name.
    .PARAMETER Schema
    Curated module grammar.
    .PARAMETER Subcommand
    Optional nested command selecting a policy override.
    #>
    param([string]$Command, [hashtable]$Schema, [string]$Subcommand)
    $policy = $Schema.Commands[$Command]
    if (!$policy) { return $null }
    $profiles = [Collections.Generic.List[string]]::new()
    foreach ($name in $policy.Profiles) { $profiles.Add([string]$name) }
    $override = if ($Subcommand -and $policy.Subcommands) { $policy.Subcommands[$Subcommand] }else { $null }
    if ($override) { foreach ($name in $override.Profiles) { $profiles.Add([string]$name) } }
    $definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($profileName in $profiles) {
        $argumentProfile = $Schema.Profiles[$profileName]
        if (!$argumentProfile) { return $null }
        foreach ($kind in @('None', 'Required', 'Optional', 'EqualsRequired', 'AttachedRequired')) {
            foreach ($name in $argumentProfile[$kind]) {
                $valueKind = switch ($kind) { None { 'None' } Optional { 'Optional' } default { 'Required' } }
                $forms = switch ($kind) {
                    None { @('Bare') }
                    Required { if ($name.StartsWith('--')) { @('Separate', 'Equals') }else { @('Separate', 'Attached') } }
                    Optional { if ($name.StartsWith('--')) { @('Bare', 'Equals') }else { @('Bare', 'Attached') } }
                    EqualsRequired { @('Equals') }
                    AttachedRequired { @('Attached') }
                }
                $definitions[$name] = @{Name =$name
                    ValueKind                =$valueKind
                    Forms                    =@($forms)
                    Profile                  =$profileName
                }
            }
        }
        foreach ($name in $argumentProfile.Negatable) {
            if (!$name.StartsWith('--') -or !$definitions.ContainsKey($name)) { return $null }
            $negative = '--no-' + $name.Substring(2)
            $definitions[$negative] = @{Name =$negative
                ValueKind                    ='None'
                Forms                        =@('Bare')
                Profile                      =$profileName
            }
        }
        foreach ($custom in $argumentProfile.Custom) {
            $definitions[$custom.Name] = @{Name =$custom.Name
                ValueKind                       =$custom.ValueKind
                Forms                           =@($custom.Forms)
                Syntax                          =$custom.Syntax
                Profile                         =$profileName
            }
        }
    }
    $stop = [bool]$policy.StopAtOperand
    $group = [bool]$policy.ShortGrouping
    $numeric = $policy.NumericShortOption
    $opaque = [bool]$policy.OpaqueTail
    if ($override) {
        if ($override.Contains('StopAtOperand')) { $stop = [bool]$override.StopAtOperand }
        if ($override.Contains('ShortGrouping')) { $group = [bool]$override.ShortGrouping }
        if ($override.Contains('NumericShortOption')) { $numeric = $override.NumericShortOption }
        if ($override.Contains('OpaqueTail')) { $opaque = [bool]$override.OpaqueTail }
    }
    @{Definitions          =$definitions
        StopAtOperand      =$stop
        ShortGrouping      =$group
        NumericShortOption =$numeric
        OpaqueTail         =$opaque
        Policy             =$policy
        Profiles           =$profiles.ToArray()
    }
}
function New-GitArgumentUnit {
    <#
    .SYNOPSIS
    Creates a bound argument unit while retaining its exact native arguments.
    .PARAMETER Kind
    Option, operand or separator classification.
    .PARAMETER Raw
    Original token text.
    .PARAMETER Position
    Original argument index.
    .PARAMETER EmitArguments
    Original argument vector represented by this unit.
    .PARAMETER Name
    Canonical option name when applicable.
    .PARAMETER ValueKind
    None, required or optional value binding.
    .PARAMETER Value
    Bound option value.
    .PARAMETER HasValue
    Distinguishes a supplied empty value from an absent value.
    .PARAMETER Binding
    Bare, separate, equals or attached form.
    .PARAMETER Span
    Number of original arguments consumed.
    .PARAMETER ValuePosition
    Original index of a separate value.
    .PARAMETER ClusterOffset
    Position within a short-option cluster.
    .PARAMETER SourceProfile
    Grammar profile declaring the option.
    .PARAMETER Values
    Bound values, preserving empty strings.
    #>
    param([string]$Kind, [string]$Raw, [int]$Position, [string[]]$EmitArguments, [string]$Name,
        [string]$ValueKind = 'None', [AllowNull()][string]$Value, [bool]$HasValue = $false,
        [string]$Binding = 'None', [int]$Span = 1, [int]$ValuePosition = -1, [int]$ClusterOffset = 0, [string]$SourceProfile, [string[]]$Values)
    if (!$PSBoundParameters.ContainsKey('Values')) { $Values = @(if ($HasValue) { $Value }) }
    [pscustomobject]@{Kind =$Kind
        Name               =$Name
        Raw                =$Raw
        ValueKind          =$ValueKind
        Value              =$Value
        HasValue           =$HasValue
        Binding            =$Binding
        Values             =[string[]]$Values
        Position           =$Position
        Span               =$Span
        ValuePosition      =$ValuePosition
        ClusterOffset      =$ClusterOffset
        EmitArguments      =[string[]]$EmitArguments
        Profile            =$SourceProfile
    }
}
function Get-GitArgumentToken {
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
