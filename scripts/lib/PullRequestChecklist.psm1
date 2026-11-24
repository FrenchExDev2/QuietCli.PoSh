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
            if(!$inside -or (!$seen.SetEquals($legacy) -and (!$seen.IsSupersetOf($standard) -or $seen.Contains('mutation')))){
                throw 'PullRequestCiChecklistIncomplete'
            }
            $end = $index
        } elseif ($inside -and ![string]::IsNullOrWhiteSpace($line)) {
            if ($line -cnotmatch '^\s*- \[([ xX])\] .+ <!-- ci:([a-z0-9-]+) -->\s*$') {throw 'PullRequestCiChecklistInvalidRow'}
            $id = $Matches[2]
            $checked=$Matches[1] -cne ' '
            if($id -cnotin $options.Keys -and $id -cnotmatch '\A(?:run-profile-mutation|profiling)-[a-z][a-z0-9]*\z'){
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
    Renders companion checkbox rows from the validated YAML catalogue.
    .PARAMETER Template
    Markdown containing the standard checklist and shared options.
    .PARAMETER Configuration
    Validated companion catalogue.
    #>
    param([Parameter(Mandatory)][string]$Template,[Parameter(Mandatory)]$Configuration)
    $lines=$Template -split '\r\n|\n|\r'
    $body=Read-QuietPullRequestChecklist $Template
    if('script-mutation' -cnotin $body.Available){throw 'PullRequestCiChecklistTemplateInvalid'}
    $expanded=foreach($line in $lines){
        if($line -cmatch '<!-- ci:(?:run-profile-mutation|profiling)-[a-z][a-z0-9]* -->\s*$'){continue}
        $line
        if($line -cmatch '<!-- ci:script-mutation -->\s*$'){
            foreach($companion in $Configuration.Companions.Values){
                $id=$companion.Name.ToLowerInvariant()
                if($companion.Mutation){"- [ ] Run $($companion.Name) mutation testing <!-- ci:run-profile-mutation-$id -->"}
                "- [ ] Profile the $($companion.Name) PowerShell tests <!-- ci:profiling-$id -->"
            }
        }
    }
    $expanded -join [char]10
}

Export-ModuleMember -Function Read-QuietPullRequestChecklist,New-QuietPullRequestBody,Expand-QuietPullRequestTemplate
