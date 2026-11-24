#requires -Version 7.6



function Read-QuietPullRequestChecklist {
    <#
    .SYNOPSIS
    Reads the single delimited CI checklist and returns its selected identifiers and source range.
    .PARAMETER Body
    Raw pull request Markdown.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Body)

    $lines = $Body -split '\r\n|\n|\r'
    $options = [ordered]@{mutation=$false; 'script-mutation'=$false; 'mutation-serial'=$false; readytorun=$false; preview=$false}
    $legacy = [string[]]@('mutation','readytorun','preview')
    $standard = [string[]]@($options.Keys | Where-Object {$_ -cne 'mutation'})
    # Existing PR descriptions predate this optional row.
    $options['script-mutation-no-input-cache']=$false
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $table = [Collections.Generic.List[string]]::new()
    $start = $end = -1
    $fence = ''
    $index = -1
    foreach ($line in $lines) {
        $index++
        $inside = $start -ne -1 -and $end -eq -1
        if ($fence) {
            if ($line -cmatch ('^ {0,3}' + [regex]::Escape($fence) + [regex]::Escape($fence[0]) + '*\s*$')) {$fence = ''}
        } elseif (!$inside -and $line -cmatch '^ {0,3}(`{3,}|~{3,})') {
            $fence = $Matches[1]
        } elseif ($line -ceq '<!-- quietcli-ci:begin -->') {
            if ($start -ne -1) {throw 'PullRequestCiChecklistDuplicate'}
            $start = $index
        } elseif ($line -ceq '<!-- quietcli-ci:end -->') {
            if (!$inside) { throw 'PullRequestCiChecklistIncomplete' }
            if ($table.Count) {
                if (!$seen.SetEquals([string[]]@('mutation-serial'))) { throw 'PullRequestCiChecklistInvalidTable' }
                foreach ($cell in Read-QuietPullRequestTable $table.ToArray()) {
                    [void]$seen.Add($cell.Id)
                    $options[$cell.Id] = $cell.Checked
                }
            } elseif (!$seen.SetEquals($legacy) -and (!$seen.IsSupersetOf($standard) -or $seen.Contains('mutation'))) {
                throw 'PullRequestCiChecklistIncomplete'
            }
            $end = $index
        } elseif ($inside -and ![string]::IsNullOrWhiteSpace($line)) {
            if ($line.TrimStart().StartsWith('|')) { $table.Add($line); continue }
            if ($line -cnotmatch '^\s*- \[([ xX])\] .+ <!-- ci:([a-z0-9-]+) -->\s*$') {throw 'PullRequestCiChecklistInvalidRow'}
            $id = $Matches[2]
            $checked=$Matches[1] -cne ' '
            if($id -cnotin $options.Keys -and $id -cnotmatch '\A(?:run-profile-mutation|profiling|performance)-[a-z][a-z0-9]*\z'){
                throw 'PullRequestCiChecklistUnknownOption'
            }
            if (!$seen.Add($id)) {throw 'PullRequestCiChecklistDuplicateOption'}
            $options[$id] = $checked
        }
    }
    if ($start -ne -1 -and $end -eq -1) {throw 'PullRequestCiChecklistIncomplete'}
    $companionOptions=[string[]]@($options.Keys|Where-Object {$_ -cnotin @('mutation','script-mutation','script-mutation-no-input-cache','mutation-serial','readytorun','preview')})
    [Array]::Sort($companionOptions,[StringComparer]::Ordinal)
    $canonical=@('mutation','script-mutation')+$companionOptions+@('script-mutation-no-input-cache','mutation-serial','readytorun','preview')
    [pscustomobject]@{
        StartLine = $start
        EndLine = $end
        Available = [string[]]@($canonical | Where-Object {$seen.Contains($_)})
        Selected = [string[]]@($canonical | Where-Object {$options[$_]})
    }
}

function New-QuietPullRequestBody {
    <#
    .SYNOPSIS
    Composes a pull request body, standard checklist and optional Markdown footer.
    .PARAMETER Body
    Original pull request description.
    .PARAMETER Template
    Versioned Markdown template with the standard CI checklist.
    .PARAMETER Footer
    Optional Markdown appended below the checklist.
    .PARAMETER CiOption
    Explicit selection overriding the incoming checklist; an empty array deselects every option.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Body,
        [Parameter(Mandatory)][string]$Template,
        [AllowEmptyString()][string]$Footer,
        [AllowEmptyCollection()][string[]]$CiOption
    )

    $source = Read-QuietPullRequestChecklist $Body
    $standard = Read-QuietPullRequestChecklist $Template
    if ($standard.StartLine -lt 0 -or $standard.Selected.Count) {throw 'PullRequestCiChecklistTemplateInvalid'}
    if ((Read-QuietPullRequestChecklist $Footer).StartLine -ge 0) {throw 'PullRequestCiChecklistFooterDuplicate'}
    $selection = if ($PSBoundParameters.ContainsKey('CiOption')) {$CiOption} else {$source.Selected}
    if ('mutation' -cin $selection -and 'script-mutation' -cin $standard.Available) {
        $selection = @($selection | Where-Object {$_ -cne 'mutation'}) + @('script-mutation','run-profile-mutation-core')
    }
    foreach ($id in $selection) {
        if ($id -cnotin $standard.Available) {throw 'PullRequestCiChecklistUnknownOption'}
    }
    $checklist = ($Template -split '\r\n|\n|\r')[$standard.StartLine..$standard.EndLine]
    foreach ($id in $selection) {
        $checklist = $checklist -creplace ("^- \[ \](.*<!-- ci:" + [regex]::Escape($id) + " -->\s*)$"), '- [x]$1'
        $checklist = $checklist -creplace ('\x60\[ \]\x60(?= <!-- ci:' + [regex]::Escape($id) + ' -->)'), '`[x]`'
    }
    if ($source.StartLine -ge 0) {
        $lines = $Body -split '\r\n|\n|\r'
        $updated = @(
            if ($source.StartLine -gt 0) {$lines[0..($source.StartLine - 1)]}
            $checklist
            if ($source.EndLine + 1 -lt $lines.Count) {$lines[($source.EndLine + 1)..($lines.Count - 1)]}
        )
        $parts = @($updated -join "`n"; $Footer)
    } else {
        $parts = @($Body; ($Template -creplace '(?s)<!-- quietcli-ci:begin -->.*?<!-- quietcli-ci:end -->', ($checklist -join "`n")); $Footer)
    }
    $result = (($parts | Where-Object {![string]::IsNullOrWhiteSpace($_)} | ForEach-Object {$_.TrimEnd("`r", "`n")}) -join "`n`n") + "`n"
    if ((Read-QuietPullRequestChecklist $result).StartLine -lt 0) {throw 'PullRequestCiChecklistNotVisible'}
    $result
}

function Expand-QuietPullRequestTemplate {
    <#
    .SYNOPSIS
    Renders clickable GitHub task-list items for the supported effects of each target.
    .PARAMETER Template
    Markdown containing the standard checklist and shared options.
    .PARAMETER Configuration
    Validated companion catalogue.
    #>
    param([Parameter(Mandatory)][string]$Template,[Parameter(Mandatory)]$Configuration)
    $lines=$Template -split '\r\n|\n|\r'
    $body=Read-QuietPullRequestChecklist $Template
    if('script-mutation' -cnotin $body.Available){throw 'PullRequestCiChecklistTemplateInvalid'}
    $helpUrl='https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md'
    $targets = @($Configuration.Companions.Values | ForEach-Object { $_.Name }) + @('Scripts')
    $effects = Get-QuietPullRequestEffectMap
    $expanded = @(
        if ($body.StartLine -gt 0) { $lines[0..($body.StartLine - 1)] }
        '<!-- quietcli-ci:begin -->'
        ''
        foreach ($target in $targets) {
            foreach ($effect in $effects.Keys) {
                $definition = $effects[$effect]
                $option = Get-QuietPullRequestCellOption $definition $target
                if ($option -and ($effect -cne 'Mutation testing' -or $target -ceq 'Scripts' -or $Configuration.Companions[$target].Mutation)) {
                    "- [ ] **$target** — [$effect]($helpUrl#$($definition.Anchor)) <!-- ci:$option -->"
                }
            }
        }
        "- [ ] Run mutation workers sequentially for all targets [Details]($helpUrl#sequential-mutation-workers) <!-- ci:mutation-serial -->"
        '<!-- quietcli-ci:end -->'
        if ($body.EndLine + 1 -lt $lines.Count) { $lines[($body.EndLine + 1)..($lines.Count - 1)] }
    )
    $expanded -join [char]10
}

function Get-QuietPullRequestEffectMap {
    <#
    .SYNOPSIS
    Defines the supported CI effects and their option identifiers.
    #>
    [ordered]@{
        'Mutation testing' = @{Anchor='companion-mutation'; Companion='run-profile-mutation-{0}'; Scripts='script-mutation'}
        'Performance' = @{Anchor='companion-performance'; Companion='performance-{0}'}
        'Profiling' = @{Anchor='companion-profiling'; Companion='profiling-{0}'}
        'Refresh mutation cache' = @{Anchor='refresh-the-script-mutation-cache'; Scripts='script-mutation-no-input-cache'}
        'ReadyToRun comparison' = @{Anchor='readytorun-performance'; Core='readytorun'}
        'PowerShell Preview' = @{Anchor='powershell-preview'; Core='preview'}
    }
}

function Get-QuietPullRequestCellOption {
    <#
    .SYNOPSIS
    Resolves the stable CI option for one effect and target.
    .PARAMETER Effect
    Effect definition from the shared effect map.
    .PARAMETER Target
    Named companion or Scripts.
    #>
    param([hashtable]$Effect,[string]$Target)
    if ($Target -cin @('Core','Scripts') -and $Effect.ContainsKey($Target)) { return $Effect[$Target] }
    if ($Target -cne 'Scripts' -and $Effect.Companion) {
        return ($Effect.Companion -f $Target.ToLowerInvariant())
    }
}

function Read-QuietPullRequestTable {
    <#
    .SYNOPSIS
    Reads the target columns and effect rows of the generated CI table.
    .PARAMETER Lines
    Markdown table header, separator and effect rows.
    #>
    param([string[]]$Lines)
    $effects = Get-QuietPullRequestEffectMap
    if ($Lines.Count -ne ($effects.Count + 2)) { throw 'PullRequestCiChecklistIncomplete' }
    $headers = @($Lines[0].Trim().Trim('|').Split('|').Trim())
    if ($headers.Count -lt 3 -or $headers[0] -cne 'Effect' -or $headers[-1] -cne 'Scripts') {
        throw 'PullRequestCiChecklistInvalidTable'
    }
    $targets = $headers[1..($headers.Count - 1)]
    $unique = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($target in $targets) {
        if ($target -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or !$unique.Add($target)) { throw 'PullRequestCiChecklistInvalidTable' }
    }
    $separator = @($Lines[1].Trim().Trim('|').Split('|').Trim())
    if ($separator.Count -ne $headers.Count -or @($separator -cnotmatch '^:?-{3,}:?$').Count) { throw 'PullRequestCiChecklistInvalidTable' }
    $rows = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $Lines[2..($Lines.Count - 1)]) {
        $cells = @($line.Trim().Trim('|').Split('|').Trim())
        if ($cells.Count -ne $headers.Count -or $cells[0] -cnotmatch '^\[([^\]]+)\]\(https://[^)]+\)$') { throw 'PullRequestCiChecklistMalformedEffectRow' }
        $effect = $Matches[1]
        if ($effect -cnotin $effects.Keys -or !$rows.Add($effect)) { throw 'PullRequestCiChecklistInvalidRow' }
        for ($i = 0; $i -lt $targets.Count; $i++) {
            $option = Get-QuietPullRequestCellOption $effects[$effect] $targets[$i]
            $cell = $cells[$i + 1]
            if ((!$option -or $option.StartsWith('run-profile-mutation-')) -and $cell -ceq '—') { continue }
            if (!$option -or $cell -cnotmatch ('^\x60\[([ xX])\]\x60 <!-- ci:' + [regex]::Escape($option) + ' -->$')) {
                throw 'PullRequestCiChecklistInvalidCell'
            }
            [pscustomobject]@{Id=$option; Checked=$Matches[1] -cne ' '}
        }
    }
}

Export-ModuleMember -Function Read-QuietPullRequestChecklist,New-QuietPullRequestBody,Expand-QuietPullRequestTemplate
