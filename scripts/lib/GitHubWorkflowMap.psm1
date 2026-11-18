#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionReferences.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkflowDocumentation.psm1')) -DisableNameChecking -ErrorAction Stop

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
    if ($Reference.StartsWith('./',[StringComparison]::Ordinal)) { return "$label (chemin local hors catalogue ou introuvable)" }
    $label
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
        '| '+$number+' | '+(Format-QuietWorkflowMapText $label)+' | '+$effects+' | '+(Format-QuietWorkflowMapText $step['if'])+' |'
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
        '# Carte des workflows GitHub Actions','','<a name="sommaire"></a>','## Sommaire','',
        '- [Déclencheurs et appels entre workflows](#declencheurs)', '- Workflows'
    ))
    foreach ($entry in $workflows) { $lines.Add('  - ['+$entry.Name+'](#'+$entry.Anchor+')') }
    if ($actions.Count) {
        $lines.Add('- Actions locales')
        foreach ($entry in $actions) { $lines.Add('  - ['+$entry.Name+'](#'+$entry.Anchor+')') }
    }
    $lines.AddRange([string[]]@(
        '','<a name="declencheurs"></a>','## Déclencheurs et appels entre workflows','',
        'Les flèches pleines relient un événement aux workflows qui le déclarent. Les flèches en pointillés représentent les appels de workflows réutilisables dans ce dépôt.',
        'Les filtres, les conditions `if` et les matrices peuvent limiter les exécutions. Les appels déclenchés par du code et le contenu des dépendances externes sortent du périmètre de cette carte.',
        '','~~~mermaid','flowchart LR'
    ))
    $eventNodes = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $callEdges = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $workflows) {
        $lines.Add('    '+$entry.Id+'["'+(Format-QuietWorkflowMapText $entry.Name -Mermaid)+'"]')
        foreach ($eventName in $entry.Events.Keys) {
            if ($eventName -ceq 'workflow_call') { continue }
            if (!$eventNodes.Contains($eventName)) {
                $eventId = 'e'+$eventNodes.Count
                $eventNodes.Add($eventName,$eventId)
                $lines.Add('    '+$eventId+'(["'+(Format-QuietWorkflowMapText $eventName -Mermaid)+'"])')
            }
            $lines.Add('    '+$eventNodes[$eventName]+' --> '+$entry.Id)
        }
        foreach ($job in $entry.Body['jobs'].Values) {
            $target = Get-QuietWorkflowMapTarget -Reference $job['uses'] -Entries $entries
            if ($target -and $target.IsWorkflow) {
                $edge = '    '+$entry.Id+' -.-> '+$target.Id
                if ($callEdges.Add($edge)) { $lines.Add($edge) }
            }
        }
    }
    $lines.AddRange([string[]]@('~~~',''))

    foreach ($entry in $workflows) {
        $source = Format-QuietWorkflowMapLink -Directory $directory -Target $entry.Path
        $contract = [IO.Path]::Combine($WorkspaceRoot,'docs','ci','github','script-'+[IO.Path]::GetFileNameWithoutExtension($entry.Path)+'.md')
        $links = '[YAML source]('+$source+') · [Sommaire](#sommaire)'
        if ([IO.File]::Exists($contract)) { $links += ' · [Documentation du workflow]('+(Format-QuietWorkflowMapLink $directory $contract)+')' }
        $lines.AddRange([string[]]@('<a name="'+$entry.Anchor+'"></a>','## '+$entry.Name,'',$links,''))
        if ($entry.Events.Count) {
            $lines.AddRange([string[]]@('| Déclencheur | Filtres déclarés |','| --- | --- |'))
            foreach ($eventName in $entry.Events.Keys) {
                $eventOptions = $entry.Events[$eventName]
                $filter = if ($eventOptions -and $eventName -cnotin @('workflow_call','workflow_dispatch')) {
                    Format-QuietWorkflowMapText (ConvertTo-Json -InputObject $eventOptions -Compress -Depth 30)
                }
                $lines.Add('| '+$eventName+' | '+$filter+' |')
            }
            $lines.Add('')
        }

        $jobs = $entry.Body['jobs']
        $ids = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $actionNodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $lines.AddRange([string[]]@('~~~mermaid','flowchart TD','    entry(["Workflow déclenché"])'))
        foreach ($jobName in $jobs.Keys) {
            $id = 'j'+$ids.Count
            $ids.Add([string]$jobName,$id)
            $label = Format-QuietWorkflowMapText $jobName -Mermaid
            $lines.Add('    '+$id+'["'+$label+'"]')
        }
        foreach ($jobName in $jobs.Keys) {
            $job = $jobs[$jobName]
            $id = $ids[[string]$jobName]
            if (!$job['needs']) { $lines.Add('    entry --> '+$id) }
            foreach ($dependency in $job['needs']) {
                if (!$ids.Contains([string]$dependency)) { throw "WorkflowMapUnknownJob: $($entry.Name)/$jobName needs $dependency" }
                $lines.Add('    '+$ids[[string]$dependency]+' --> '+$id)
            }
            if ($job['uses']) {
                $label = Format-QuietWorkflowMapText $job['uses'] -Mermaid
                $lines.Add('    '+$id+' -.-> c'+$id+'["'+$label+'"]')
            }
            $jobActions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($step in $job['steps']) {
                $action = Get-QuietWorkflowMapTarget -Reference $step['uses'] -Entries $entries
                if (!$action -or $action.IsWorkflow -or !$jobActions.Add($action.Id)) { continue }
                if ($actionNodes.Add($action.Id)) {
                    $label = Format-QuietWorkflowMapText $action.Name -Mermaid
                    $lines.Add('    '+$action.Id+'["'+$label+'"]')
                }
                $lines.Add('    '+$id+' -.-> '+$action.Id)
            }
        }
        $lines.AddRange([string[]]@('~~~',''))
        foreach ($jobName in $jobs.Keys) {
            $job = $jobs[$jobName]
            $lines.AddRange([string[]]@('### '+$jobName,''))
            if ($job['if']) { $lines.AddRange([string[]]@('Condition · '+(Format-QuietWorkflowMapText $job['if']),'')) }
            if ($job['strategy'] -is [Collections.IDictionary] -and $job['strategy'].Keys -ccontains 'matrix') {
                $matrix = Format-QuietWorkflowMapText (ConvertTo-Json -InputObject $job['strategy']['matrix'] -Compress -Depth 30)
                $lines.AddRange([string[]]@('Matrice déclarée · '+$matrix,''))
            }
            if ($job['uses']) {
                $reference = Format-QuietWorkflowMapReference -Reference $job['uses'] -Entries $entries
                $lines.AddRange([string[]]@('Appelle '+$reference+'.',''))
            }
            if ($job['steps']) {
                $lines.AddRange([string[]]@('| Ordre | Étape | Action ou script | Condition |','| ---: | --- | --- | --- |'))
                $lines.AddRange([string[]]@(Get-QuietWorkflowMapStepRows -Steps $job['steps'] -Entries $entries -Root $WorkspaceRoot -Directory $directory))
                $lines.Add('')
            }
        }
    }

    foreach ($entry in $actions) {
        $source = Format-QuietWorkflowMapLink -Directory $directory -Target $entry.Path
        $lines.AddRange([string[]]@('<a name="'+$entry.Anchor+'"></a>','## Action locale · '+$entry.Name,'','[YAML source]('+$source+') · [Sommaire](#sommaire)',''))
        $run = $entry.Body['runs']
        if ($run -isnot [Collections.IDictionary]) { throw "WorkflowMapInvalidAction: $($entry.Name)" }
        if ($run['using'] -cne 'composite') {
            $lines.AddRange([string[]]@('Type · '+(Format-QuietWorkflowMapText $run['using']),''))
            continue
        }
        $lines.AddRange([string[]]@('~~~mermaid','sequenceDiagram','    participant A as '+(Format-QuietWorkflowMapText $entry.Name -Mermaid)))
        foreach ($step in $run['steps']) {
            $label = $step['name'] ?? $step['uses'] ?? $step['id'] ?? 'run'
            $lines.Add('    A->>A: '+(Format-QuietWorkflowMapText $label -Mermaid))
        }
        $lines.AddRange([string[]]@('~~~','','| Ordre | Étape | Action ou script | Condition |','| ---: | --- | --- | --- |'))
        $lines.AddRange([string[]]@(Get-QuietWorkflowMapStepRows -Steps $run['steps'] -Entries $entries -Root $WorkspaceRoot -Directory $directory))
        $lines.Add('')
    }

    [pscustomobject]@{ Markdown = $lines -join "`n"; Workflows = $workflows.Count; Actions = $actions.Count }
}

Export-ModuleMember -Function 'New-QuietGitHubWorkflowMap'
