#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionReferences.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkflowDocumentation.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Sync-DocsCredits.psm1')) -DisableNameChecking -ErrorAction Stop

function Format-QuietWorkflowMapLink {
    <#
    .SYNOPSIS
    Resolves a source or documentation path relative to the generated report.
    .PARAMETER Directory
    Absolute directory containing the report.
    .PARAMETER Target
    Absolute path to the linked file.
    #>
    param([string]$Directory,[string]$Target)

    $relative = [IO.Path]::GetRelativePath($Directory,$Target)
    if ([IO.Path]::IsPathRooted($relative)) { return ([uri]::new($Target)).AbsoluteUri }
    ($relative.Replace('\','/').Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

function Format-QuietWorkflowMapText {
    <#
    .SYNOPSIS
    Escapes a YAML label for a Mermaid quoted label or a GFM table cell.
    .PARAMETER Text
    Label taken from a workflow or action.
    .PARAMETER Mermaid
    Uses Mermaid's numeric entity syntax.
    #>
    param([string]$Text,[switch]$Mermaid)

    $textLine = $Text -replace '\s+',' '
    if ($Mermaid) {
        return [regex]::Replace($textLine, '[#"<>&;]', { param($character) '#'+[int][char]$character.Value+';' })
    }
    [regex]::Replace($textLine, '[&<>|`\[\]*_~\\]', { param($character) '&#'+[int][char]$character.Value+';' })
}

function Get-QuietWorkflowMapTarget {
    <#
    .SYNOPSIS
    Resolves an exact local uses reference against the scanned YAML catalogue.
    .PARAMETER Reference
    Literal GitHub Actions uses value.
    .PARAMETER Entries
    Case-sensitive catalogue keyed by repository-relative workflow file or action directory.
    #>
    param([string]$Reference,[Collections.IDictionary]$Entries)

    if ($Reference.StartsWith('./',[StringComparison]::Ordinal)) {
        return $Entries[$Reference.Substring(2)]
    }
}

function Format-QuietWorkflowMapReference {
    <#
    .SYNOPSIS
    Links a known local call and labels external or unresolved references.
    .PARAMETER Reference
    Literal uses value.
    .PARAMETER Entries
    Case-sensitive catalogue of local workflows and actions.
    #>
    param([string]$Reference,[Collections.IDictionary]$Entries)

    $label = Format-QuietWorkflowMapText $Reference
    $target = Get-QuietWorkflowMapTarget -Reference $Reference -Entries $Entries
    if ($target) { return ('['+$label+'](#'+$target.Anchor+')') }
    if ($Reference.StartsWith('./',[StringComparison]::Ordinal)) { return "$label (local path outside the catalogue or missing)" }
    $label
}

function Format-QuietWorkflowMapClick {
    <#
    .SYNOPSIS
    Emits Mermaid hyperlink syntax using a local Markdown fragment as the destination.
    .PARAMETER NodeId
    Generated Mermaid node identifier.
    .PARAMETER Anchor
    Generated section anchor, without the leading hash.
    #>
    param([ValidatePattern('\A[a-z][a-z0-9]*\z')][string]$NodeId,[ValidatePattern('\A[a-z0-9][a-z0-9-]*\z')][string]$Anchor)

    '    click '+$NodeId+' href "#'+$Anchor+'" "Open section" _self'
}

function Get-QuietWorkflowMapStepRows {
    <#
    .SYNOPSIS
    Formats step order, uses, script documentation and conditions as Markdown rows.
    .PARAMETER Steps
    Ordered step definitions under jobs or runs.
    .PARAMETER Entries
    Case-sensitive catalogue of local workflows and actions.
    .PARAMETER Root
    Absolute checkout root.
    .PARAMETER Directory
    Absolute directory containing the report.
    #>
    param([object[]]$Steps,[Collections.IDictionary]$Entries,[string]$Root,[string]$Directory)

    $number = 0
    foreach ($step in $Steps) {
        $number++
        if ($step -isnot [Collections.IDictionary]) { throw 'WorkflowMapInvalidStep' }
        $label = $step['name'] ?? $step['id']
        $effects = if ($step['uses']) {
            Format-QuietWorkflowMapReference -Reference $step['uses'] -Entries $Entries
        } else {
            $scripts = @(foreach ($path in Get-QuietWorkflowScriptPaths -Text $step['run']) {
                $doc = [IO.Path]::Combine($Root,[IO.Path]::ChangeExtension(('docs/'+$path),'.md'))
                $source = [IO.Path]::Combine($Root,$path)
                if ([IO.File]::Exists($doc)) { $target = $doc }
                elseif ([IO.File]::Exists($source)) { $target = $source }
                else { continue }
                '['+(Format-QuietWorkflowMapText $path)+']('+(Format-QuietWorkflowMapLink $Directory $target)+')'
            })
            if ($scripts.Count) { $scripts -join ', ' } else { '`run`' }
        }
        '| '+$number+' | '+(Format-QuietWorkflowMapText $label)+' | '+$effects+' | '+(Format-QuietWorkflowLiteral $step['if'])+' |'
    }
}

function New-QuietGitHubWorkflowMap {
    <#
    .SYNOPSIS
    Reads GitHub Actions YAML and renders a Markdown map without executing workflow logic.
    .PARAMETER WorkspaceRoot
    Absolute checkout root with .github/workflows and optional .github/actions.
    .PARAMETER OutputPath
    Absolute Markdown output path used to compute source and documentation links.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$OutputPath)

    $files = @(Get-QuietGitHubActionFiles -WorkspaceRoot $WorkspaceRoot)
    if (!($files.RelativePath -like '.github/workflows/*')) { throw 'WorkflowMapNoWorkflows' }
    $preview = @{ Preview = [bool]$WhatIfPreference }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $preview.ConfirmRestore = $PSBoundParameters['Confirm'] }
    $parser = Get-QuietWorkflowYamlParser @preview
    $entries = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $directory = [IO.Path]::GetDirectoryName($OutputPath)
    foreach ($file in $files) {
        $content = [IO.File]::ReadAllText($file.FullPath,[Text.UTF8Encoding]::new($false,$true))
        $yaml = $parser.Deserialize($content,[object])
        $isWorkflow = $file.RelativePath.StartsWith('.github/workflows/',[StringComparison]::Ordinal)
        $key = if ($isWorkflow) { $file.RelativePath } else { $file.RelativePath.Substring(0,$file.RelativePath.LastIndexOf('/')) }
        if ($entries.Contains($key)) { throw "WorkflowMapDuplicateLocalPath: $key" }
        if ($yaml -isnot [Collections.IDictionary] -or ($isWorkflow -and $yaml['jobs'] -isnot [Collections.IDictionary])) {
            throw "WorkflowMapInvalidYaml: $($file.RelativePath)"
        }
        $events = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        if ($isWorkflow) {
            if ($yaml['on'] -is [Collections.IDictionary]) {
                foreach ($eventName in $yaml['on'].Keys) { $events.Add([string]$eventName,$yaml['on'][$eventName]) }
            } else {
                foreach ($eventName in $yaml['on']) { $events.Add([string]$eventName,$null) }
            }
        }
        $prefix = if ($isWorkflow) { 'workflow-' } else { 'action-' }
        $slug = ($key -replace '^\.github/(workflows|actions)/','').ToLowerInvariant() -replace '[^a-z0-9-]','-'
        $entries.Add($key,[pscustomobject]@{
            Id = 'n'+$entries.Count
            Anchor = $prefix+$slug+'-'+$entries.Count
            Name = if ($isWorkflow) { [IO.Path]::GetFileName($key) } else { $key.Substring('.github/actions/'.Length) }
            Path = $file.FullPath
            IsWorkflow = $isWorkflow
            Body = $yaml
            Events = $events
        })
    }
    $workflows = @($entries.Values | Where-Object IsWorkflow)
    $actions = @($entries.Values | Where-Object { !$_.IsWorkflow })
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@(
        '# GitHub Actions workflow map','','<!-- Generated by scripts/Export-GitHubWorkflowMap.ps1. -->','',
        '<a name="table-of-contents"></a>','','## Table of contents','',
        '- [Triggers and calls between workflows](#workflow-triggers)', '- Workflows'
    ))
    foreach ($entry in $workflows) { $lines.Add('  - ['+$entry.Name+'](#'+$entry.Anchor+')') }
    if ($actions.Count) {
        $lines.Add('- Local actions')
        foreach ($entry in $actions) { $lines.Add('  - ['+$entry.Name+'](#'+$entry.Anchor+')') }
    }
    $lines.AddRange([string[]]@(
        '','<a name="workflow-triggers"></a>','','## Triggers and calls between workflows','',
        'Diagram nodes link to their sections in the document. If your viewer blocks Mermaid links, use the table of contents or the lists below the diagrams.',
        'Read each arrow from its source to its target. An event `triggers` a workflow, a workflow `declares` a job, and a job `calls` a reusable workflow or `uses` a local action. A job `depends on` each prerequisite listed in its `needs`.',
        'Filters, `if` conditions, and matrices can limit when jobs run. The map covers calls declared in YAML. Calls made from code and the contents of external dependencies are outside its scope.',
        '','~~~mermaid','flowchart LR'
    ))
    $eventNodes = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $callEdges = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $workflows) {
        $lines.Add('    '+$entry.Id+'["'+(Format-QuietWorkflowMapText $entry.Name -Mermaid)+'"]')
        $lines.Add((Format-QuietWorkflowMapClick $entry.Id $entry.Anchor))
        foreach ($eventName in $entry.Events.Keys) {
            if ($eventName -ceq 'workflow_call') { continue }
            if (!$eventNodes.Contains($eventName)) {
                $eventId = 'e'+$eventNodes.Count
                $slug = $eventName.ToLowerInvariant() -replace '[^a-z0-9-]','-'
                $eventNodes.Add($eventName,[pscustomobject]@{
                    Id = $eventId
                    Anchor = 'event-'+$slug+'-'+$eventId
                    Workflows = [Collections.Generic.List[object]]::new()
                })
                $lines.Add('    '+$eventId+'(["'+(Format-QuietWorkflowMapText $eventName -Mermaid)+'"])')
                $lines.Add((Format-QuietWorkflowMapClick $eventId $eventNodes[$eventName].Anchor))
            }
            $eventNode = $eventNodes[$eventName]
            $eventNode.Workflows.Add($entry)
            $lines.Add('    '+$eventNode.Id+' -->|triggers| '+$entry.Id)
        }
        foreach ($job in $entry.Body['jobs'].Values) {
            $target = Get-QuietWorkflowMapTarget -Reference $job['uses'] -Entries $entries
            if ($target -and $target.IsWorkflow) {
                $edge = '    '+$entry.Id+' -. calls .-> '+$target.Id
                if ($callEdges.Add($edge)) { $lines.Add($edge) }
            }
        }
    }
    $lines.AddRange([string[]]@('~~~',''))
    $eventIndex = foreach ($eventName in $eventNodes.Keys) {
        '['+(Format-QuietWorkflowMapText $eventName)+'](#'+$eventNodes[$eventName].Anchor+')'
    }
    if ($eventIndex) { $lines.AddRange([string[]]@(('Events · '+($eventIndex -join ' · ')),'')) }
    foreach ($eventName in $eventNodes.Keys) {
        $eventNode = $eventNodes[$eventName]
        $eventLinks = foreach ($entry in $eventNode.Workflows) { '['+$entry.Name+'](#'+$entry.Anchor+')' }
        $eventLabel = Format-QuietWorkflowMapText $eventName
        $lines.AddRange([string[]]@(('<a name="'+$eventNode.Anchor+'"></a>'),'',('### '+$eventLabel),'',($eventLinks -join ' · '),''))
    }

    foreach ($entry in $workflows) {
        $source = Format-QuietWorkflowMapLink -Directory $directory -Target $entry.Path
        $contract = [IO.Path]::Combine($WorkspaceRoot,'docs','ci','github','script-'+[IO.Path]::GetFileNameWithoutExtension($entry.Path)+'.md')
        $links = '[YAML source]('+$source+') · [Table of contents](#table-of-contents)'
        if ([IO.File]::Exists($contract)) { $links += ' · [Workflow documentation]('+(Format-QuietWorkflowMapLink $directory $contract)+')' }
        $lines.AddRange([string[]]@(('<a name="'+$entry.Anchor+'"></a>'),'',('## '+$entry.Name),'',$links,''))
        if ($entry.Events.Count) {
            $lines.AddRange([string[]]@('| Trigger | Declared filters |','| --- | --- |'))
            foreach ($eventName in $entry.Events.Keys) {
                $eventOptions = $entry.Events[$eventName]
                $filter = if ($eventOptions -and $eventName -cnotin @('workflow_call','workflow_dispatch')) {
                    Format-QuietWorkflowLiteral (ConvertTo-Json -InputObject $eventOptions -Compress -Depth 30)
                }
                $lines.Add('| '+$eventName+' | '+$filter+' |')
            }
            $lines.Add('')
        }

        $jobs = $entry.Body['jobs']
        $ids = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $actionNodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $jobLinks = [Collections.Generic.List[string]]::new()
        $entryLabel = Format-QuietWorkflowMapText $entry.Name -Mermaid
        $lines.AddRange([string[]]@('~~~mermaid','flowchart TD',('    entry(["'+$entryLabel+'"])')))
        $lines.Add((Format-QuietWorkflowMapClick 'entry' $entry.Anchor))
        foreach ($jobName in $jobs.Keys) {
            $id = 'j'+$ids.Count
            $ids.Add([string]$jobName,$id)
            $jobAnchor = $entry.Anchor+'-job-'+$id
            $label = Format-QuietWorkflowMapText $jobName -Mermaid
            $lines.Add('    '+$id+'["'+$label+'"]')
            $lines.Add((Format-QuietWorkflowMapClick $id $jobAnchor))
            $lines.Add('    entry -->|declares| '+$id)
            $jobLinks.Add('['+(Format-QuietWorkflowMapText $jobName)+'](#'+$jobAnchor+')')
        }
        foreach ($jobName in $jobs.Keys) {
            $job = $jobs[$jobName]
            $id = $ids[[string]$jobName]
            foreach ($dependency in $job['needs']) {
                if (!$ids.Contains([string]$dependency)) { throw "WorkflowMapUnknownJob: $($entry.Name)/$jobName needs $dependency" }
                $lines.Add('    '+$id+' -. depends on .-> '+$ids[[string]$dependency])
            }
            if ($job['uses']) {
                $target = Get-QuietWorkflowMapTarget -Reference $job['uses'] -Entries $entries
                $targetAnchor = if ($target -and $target.IsWorkflow) { $target.Anchor } else { $entry.Anchor+'-job-'+$id }
                $label = Format-QuietWorkflowMapText $job['uses'] -Mermaid
                $lines.Add('    '+$id+' -. calls .-> c'+$id+'["'+$label+'"]')
                $lines.Add((Format-QuietWorkflowMapClick ('c'+$id) $targetAnchor))
            }
            $jobActions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($step in $job['steps']) {
                $action = Get-QuietWorkflowMapTarget -Reference $step['uses'] -Entries $entries
                if (!$action -or $action.IsWorkflow -or !$jobActions.Add($action.Id)) { continue }
                if ($actionNodes.Add($action.Id)) {
                    $label = Format-QuietWorkflowMapText $action.Name -Mermaid
                    $lines.Add('    '+$action.Id+'["'+$label+'"]')
                    $lines.Add((Format-QuietWorkflowMapClick $action.Id $action.Anchor))
                }
                $lines.Add('    '+$id+' -. uses .-> '+$action.Id)
            }
        }
        $lines.AddRange([string[]]@('~~~',''))
        $lines.AddRange([string[]]@(('Jobs · '+($jobLinks -join ' · ')),''))
        foreach ($jobName in $jobs.Keys) {
            $job = $jobs[$jobName]
            $jobAnchor = $entry.Anchor+'-job-'+$ids[[string]$jobName]
            $lines.AddRange([string[]]@(('<a name="'+$jobAnchor+'"></a>'),'',('### '+$jobName),''))
            if ($job['if']) { $lines.AddRange([string[]]@(('Condition · '+(Format-QuietWorkflowLiteral $job['if'])),'')) }
            if ($job['strategy'] -is [Collections.IDictionary] -and $job['strategy'].Keys -ccontains 'matrix') {
                $matrix = $job['strategy']['matrix']
                if ($matrix -isnot [string]) { $matrix = ConvertTo-Json -InputObject $matrix -Compress -Depth 30 }
                $lines.AddRange([string[]]@(('Declared matrix · '+(Format-QuietWorkflowLiteral $matrix)),''))
            }
            if ($job['uses']) {
                $reference = Format-QuietWorkflowMapReference -Reference $job['uses'] -Entries $entries
                $lines.AddRange([string[]]@(('Calls '+$reference+'.'),''))
            }
            if ($job['steps']) {
                $lines.AddRange([string[]]@('| Order | Step | Action or script | Condition |','| ---: | --- | --- | --- |'))
                $lines.AddRange([string[]]@(Get-QuietWorkflowMapStepRows -Steps $job['steps'] -Entries $entries -Root $WorkspaceRoot -Directory $directory))
                $lines.Add('')
            }
        }
    }

    foreach ($entry in $actions) {
        $source = Format-QuietWorkflowMapLink -Directory $directory -Target $entry.Path
        $sourceLinks = '[YAML source]('+$source+') · [Table of contents](#table-of-contents)'
        $lines.AddRange([string[]]@(('<a name="'+$entry.Anchor+'"></a>'),'',('## Local action · '+$entry.Name),'',$sourceLinks,''))
        $run = $entry.Body['runs']
        if ($run -isnot [Collections.IDictionary]) { throw "WorkflowMapInvalidAction: $($entry.Name)" }
        if ($run['using'] -cne 'composite') {
            $lines.AddRange([string[]]@(('Type · '+(Format-QuietWorkflowMapText $run['using'])),''))
            continue
        }
        $lines.AddRange([string[]]@('~~~mermaid','sequenceDiagram',('    participant A as '+(Format-QuietWorkflowMapText $entry.Name -Mermaid))))
        foreach ($step in $run['steps']) {
            $label = $step['name'] ?? $step['uses'] ?? $step['id'] ?? 'run'
            $verb = if ($step['uses']) { 'uses' } else { 'runs' }
            $lines.Add('    A->>A: '+$verb+' · '+(Format-QuietWorkflowMapText $label -Mermaid))
        }
        $lines.AddRange([string[]]@('~~~','','| Order | Step | Action or script | Condition |','| ---: | --- | --- | --- |'))
        $lines.AddRange([string[]]@(Get-QuietWorkflowMapStepRows -Steps $run['steps'] -Entries $entries -Root $WorkspaceRoot -Directory $directory))
        $lines.Add('')
    }

    $credits = [IO.Path]::Combine($WorkspaceRoot,'CREDITS.md')
    if ([IO.File]::Exists($credits)) {
        $lines.Add((Format-QuietDocsCreditsBlock -Link (Format-QuietWorkflowMapLink $directory $credits)))
        $lines.Add('')
    }

    [pscustomobject]@{ Markdown = $lines -join "`n"; Workflows = $workflows.Count; Actions = $actions.Count }
}

Export-ModuleMember -Function 'New-QuietGitHubWorkflowMap'
