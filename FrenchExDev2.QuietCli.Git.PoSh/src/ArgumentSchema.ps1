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
    if (!$Schema) { $Schema = Get-GitArgumentSchema }
    Import-QuietGitParser
    $observed=if($null -eq $Version){[System.Management.Automation.Language.NullString]::Value}else{$Version}
    return [FrenchExDev2.QuietCli.Git.GitArguments]::Bind($Command,$ArgumentList,$observed,$Schema)
}
