#requires -Version 7.6
Set-StrictMode -Version Latest

function Test-RoadmapGraph {
    <#
    .SYNOPSIS
    Resolves a bounded prerequisite graph without recursively traversing input.
    .PARAMETER Nodes
    Nodes with unique identifiers and explicit dependsOn arrays.
    .PARAMETER Name
    Graph identity included in diagnostics.
    #>
    param([AllowEmptyCollection()][object[]]$Nodes, [string]$Name)
    $errors = [Collections.Generic.List[string]]::new()
    $remaining = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $order = [Collections.Generic.List[string]]::new()
    if (!$Nodes.Count -or $Nodes.Count -gt 2048) {
        return [pscustomobject]@{Errors=@("GraphSize:$Name");Order=@()}
    }
    foreach ($node in $Nodes) {
        if (!$node.id -or $node.id -cnotmatch '^[A-Za-z][A-Za-z0-9-]{0,63}$' -or $node.dependsOn -isnot [array]) {
            $errors.Add("GraphShape:$Name"); continue
        }
        if (!$remaining.TryAdd($node.id, $node)) { $errors.Add("DuplicateNode:${Name}:$($node.id)") }
    }
    foreach ($node in $remaining.Values) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($dependency in $node.dependsOn) {
            if (!$remaining.ContainsKey([string]$dependency)) { $errors.Add("MissingDependency:${Name}:$($node.id):$dependency") }
            if (!$seen.Add([string]$dependency)) { $errors.Add("DuplicateDependency:${Name}:$($node.id):$dependency") }
        }
    }
    if (!$errors.Count) {
        while ($remaining.Count) {
            $ready = @($remaining.Keys | Where-Object {
                $dependencies = $remaining[$_].dependsOn
                @($dependencies | Where-Object { $remaining.ContainsKey($_) }).Count -eq 0
            } | Sort-Object -CaseSensitive)
            if (!$ready.Count) { $errors.Add("Cycle:${Name}:$((@($remaining.Keys) | Sort-Object -CaseSensitive) -join ',')"); break }
            foreach ($id in $ready) { $order.Add($id); [void]$remaining.Remove($id) }
        }
    }
    [pscustomobject]@{ Errors = $errors.ToArray(); Order = $order.ToArray() }
}

function Test-RoadmapModel {
    <#
    .SYNOPSIS
    Checks planning invariants separately from implementation readiness and product qualification.
    .PARAMETER Model
    Parsed roadmap contract model.
    .PARAMETER Registry
    Parsed requirements registry; planned test identifiers are not treated as executed tests.
    .PARAMETER RoadmapFiles
    Actual ROADMAP-*.md names in the selected documentation directory.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)]$Registry,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RoadmapFiles)
    $errors = [Collections.Generic.List[string]]::new()
    $gaps = [Collections.Generic.List[string]]::new()
    $orders = [ordered]@{}
    try {
        if ($Model.schemaVersion -ne 1 -or $Registry.schemaVersion -ne 1) { $errors.Add('UnsupportedSchema') }
        foreach ($kind in @('design','impl','test','obs')) {
            if ($kind -cnotin $Model.kinds -or $kind -cnotin $Registry.kinds) { $errors.Add("MissingKind:$kind") }
        }
        if ($Model.kinds.Count -ne 4 -or $Registry.kinds.Count -ne 4) { $errors.Add('InvalidKinds') }
        $maps = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($map in $Model.roadmaps) {
            if (!$maps.TryAdd($map.id, $map)) { $errors.Add("DuplicateRoadmap:$($map.id)") }
            if (!$files.Add($map.file)) { $errors.Add("DuplicateRoadmapFile:$($map.file)") }
            if ($map.file -cnotmatch '^ROADMAP-[A-Za-z0-9-]+\.md$' -or $map.file -cnotin $RoadmapFiles) { $errors.Add("MissingRoadmap:$($map.file)") }
            foreach ($field in @('id','family','tier','outcome','engineering','entry','exit','risk')) {
                if ([string]::IsNullOrWhiteSpace($map.$field)) { $errors.Add("MissingRoadmapField:$($map.id):$field") }
            }
            if ($map.type -cnotin @('portfolio','review','contract','product','qualification','delivery')) { $errors.Add("RoadmapType:$($map.id)") }
            foreach ($kind in $Model.kinds) {
                if ([string]::IsNullOrWhiteSpace($map.deliverables.$kind)) { $errors.Add("MissingDeliverable:$($map.id):$kind") }
            }
            foreach ($field in @('name','context','problem','forces','participants','collaboration','consequences','alternative','oracle')) {
                if ([string]::IsNullOrWhiteSpace($map.pattern.$field)) { $errors.Add("MissingPatternField:$($map.id):$field") }
            }
        }
        foreach ($file in $RoadmapFiles) { if (!$files.Contains($file)) { $errors.Add("UnclassifiedRoadmap:$file") } }
        foreach ($name in @('delivery','runtime')) {
            $graph = Test-RoadmapGraph -Nodes $Model."${name}Nodes" -Name $name
            foreach ($errorCode in $graph.Errors) { $errors.Add($errorCode) }
            $orders[$name] = $graph.Order
        }
        foreach ($map in $maps.Values) {
            if (!$map.nodes.Count) { $errors.Add("MissingDeliveryNode:$($map.id)") }
            foreach ($node in $map.nodes) { if ($node -cnotin $Model.deliveryNodes.id) { $errors.Add("UnknownDeliveryNode:$($map.id):$node") } }
        }
        foreach ($feedback in $Model.feedback) {
            if ($feedback.blocking -ne $false -or $feedback.type -cne 'next-revision-learning' -or !$feedback.control -or
                $feedback.from -cnotin $Model.deliveryNodes.id -or $feedback.to -cnotin $Model.deliveryNodes.id) { $errors.Add('UncontrolledFeedback') }
        }
        $items = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($item in $Registry.workItems) {
            if (!$items.TryAdd($item.id, $item)) { $errors.Add("DuplicateWorkItem:$($item.id)") }
            $family = $item.id -creplace '-(design|impl|test|obs)$',''
            if (!$maps.ContainsKey($family) -or $item.kind -cnotin $Model.kinds) { $errors.Add("UnknownWorkItem:$($item.id)"); continue }
            if ($item.plan -cne $maps[$family].file -or $item.deliverableRef -cne "roadmap:$family/$($item.kind)") { $errors.Add("UnresolvedDeliverable:$($item.id)") }
            if ($item.owner -eq 'Unassigned' -or !$item.owner) { $gaps.Add("Owner:$($item.id)") }
            if ($item.status -cne 'Planned') { $gaps.Add("ReviewWorkItemMaturity:$($item.id)") }
        }
        $requirements = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $identifiers = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $requirementNodes = [Collections.Generic.List[object]]::new()
        foreach ($requirement in $Registry.requirements) {
            if (!$requirements.TryAdd($requirement.id, $requirement)) { $errors.Add("DuplicateRequirement:$($requirement.id)") }
            $requirementNodes.Add([pscustomobject]@{id=$requirement.id; dependsOn=$requirement.dependsOn})
            if (!$maps.ContainsKey($requirement.feature)) { $errors.Add("UnknownFeature:$($requirement.id)") }
            if (!$requirement.statement -or !$requirement.sources.Count -or !$requirement.acceptance.Count) { $errors.Add("IncompleteRequirement:$($requirement.id)") }
            if ($requirement.status -cnotin @('Proposed','Accepted','Implemented','Verified','Released','Retired','Blocked')) { $errors.Add("RequirementStatus:$($requirement.id)") }
            if (!$identifiers.Add($requirement.id)) { $errors.Add("DuplicateIdentifier:$($requirement.id)") }
            if ($requirement.owner -eq 'Unassigned' -or !$requirement.owner) { $gaps.Add("Owner:$($requirement.id)") }
            if ($requirement.status -cnotin @('Accepted','Implemented','Verified','Released')) { $gaps.Add("ContractDecision:$($requirement.id)") }
            foreach ($kind in $Model.kinds) {
                $expected = "$($requirement.feature)-$kind"
                if ($expected -cnotin $requirement.kindLinks -or !$items.ContainsKey($expected)) { $errors.Add("UnresolvedKind:$($requirement.id):$kind") }
            }
            if ($requirement.kindLinks.Count -ne 4) { $errors.Add("InvalidKindLinks:$($requirement.id)") }
            foreach ($source in $requirement.sources) {
                if ($source.document -like 'ROADMAP-*' -and !$files.Contains($source.document)) { $errors.Add("UnresolvedSource:$($requirement.id)") }
            }
            foreach ($ac in $requirement.acceptance) {
                foreach ($field in @('id','given','when','then')) { if ([string]::IsNullOrWhiteSpace($ac.$field)) { $errors.Add("IncompleteAC:$($requirement.id):$field") } }
                if (!$identifiers.Add($ac.id) -or !$ac.verification.id -or !$identifiers.Add($ac.verification.id)) { $errors.Add("DuplicateOrMissingTestOrAC:$($requirement.id)") }
                if ($ac.verification.status -cnotin @('Planned','Implemented','Executed') -or $ac.evidence.status -cnotin @('Passed','Failed','Skipped','NotRun','Unknown')) { $errors.Add("EvidenceState:$($ac.id)") }
                if ($ac.verification.status -cne 'Planned' -and !$ac.verification.implementationRef) { $errors.Add("MissingTestImplementation:$($ac.id)") }
                if ($ac.evidence.status -in @('Passed','Failed') -and ($ac.verification.status -cne 'Executed' -or !$ac.verification.implementationRef -or !$ac.evidence.artifacts.Count -or !$ac.evidence.sourceIdentity -or !$ac.evidence.environmentIdentity)) { $errors.Add("UnsubstantiatedEvidence:$($ac.id)") }
                if ($ac.evidence.status -cne 'NotRun' -and $ac.verification.status -ceq 'Planned') { $errors.Add("PlannedTestHasEvidence:$($ac.id)") }
                if ($requirement.status -in @('Verified','Released') -and $ac.evidence.status -cne 'Passed') { $errors.Add("UnverifiedMaturity:$($requirement.id)") }
            }
        }
        foreach ($map in $maps.Values) { if (!@($Registry.requirements | Where-Object feature -CEQ $map.family).Count) { $errors.Add("EmptyRoadmapFamily:$($map.id)") } }
        $graph = Test-RoadmapGraph -Nodes $requirementNodes.ToArray() -Name requirements
        foreach ($errorCode in $graph.Errors) { $errors.Add($errorCode) }; $orders['requirements'] = $graph.Order
        $gaps.Add('UnresolvedArtifactVersions:planned-product-packages')
        $gaps.Add('UnapprovedApiContracts:planned-product-commands')
        $gaps.Add('UnbudgetedCampaigns:per-language-and-component')
        $gaps.Add('UnverifiedRecoveryProcedures:per-delivery')
    } catch { $errors.Add("InvalidModel:$($_.Exception.Message)") }
    [pscustomobject]@{
        Gate = 'PlanConsistent'; Passed = ($errors.Count -eq 0)
        Errors = $errors.ToArray(); ImplementationReady = $false; ReadinessGaps = $gaps.ToArray()
        ProductQualification = 'NotAssessed'; Orders = [pscustomobject]$orders
    }
}

function Get-RoadmapContractView {
    <#
    .SYNOPSIS
    Projects one roadmap delivery contract without copying editable acceptance criteria.
    .PARAMETER Roadmap
    Canonical roadmap record.
    .PARAMETER Registry
    Canonical requirements used only for their stable identifiers.
    .PARAMETER Execution
    Canonical production recipes; proposed command names are never executed by rendering.
    .PARAMETER Model
    Delivery graph used to identify downstream consumers.
    #>
    param($Roadmap, $Registry, $Execution, $Model)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<!-- roadmap-contract:begin -->')
    $lines.Add("## Contrat de livraison et revue d'ingénierie")
    $lines.Add('')
    $lines.Add('Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).')
    $lines.Add('')
    $lines.Add("**$($Roadmap.id)** — $($Roadmap.type) — $($Roadmap.tier).")
    $lines.Add(''); $lines.Add($Roadmap.outcome); $lines.Add('')
    $lines.Add('| Kind | Livrable planifié et vérifiable |')
    $lines.Add('| --- | --- |')
    foreach ($kind in @('design','impl','test','obs')) { $lines.Add("| $kind | $($Roadmap.deliverables.$kind.Replace('|','\|')) |") }
    $lines.Add('')
    $ids = @($Registry.requirements | Where-Object feature -CEQ $Roadmap.family | ForEach-Object { $_.id })
    $lines.Add("Traçabilité : $($ids -join ', '). Lots : $($Roadmap.nodes -join ', '). Une relation de lot est un prérequis de livraison, pas un import runtime.")
    $lines.Add(''); $lines.Add('| ID | Exigence | Vérification prévue |'); $lines.Add('| --- | --- | --- |')
    foreach ($requirement in $Registry.requirements | Where-Object feature -CEQ $Roadmap.family) {
        $checks=@(foreach($ac in $requirement.acceptance){"$($ac.id) → $($ac.verification.id) ($($ac.verification.method), $($ac.evidence.status))"})
        $lines.Add("| $($requirement.id) | $($requirement.statement.Replace('|','\|')) | $($checks -join '; ') |")
    }
    $lines.Add(''); $lines.Add("**Décision de patterns : $($Roadmap.pattern.name).**")
    foreach ($field in @('context','problem','forces','participants','collaboration','consequences','alternative','oracle')) {
        $labels = @{context='Contexte';problem='Problème';forces='Forces';participants='Participants';collaboration='Collaboration';consequences='Conséquences';alternative='Alternative';oracle='Oracle indépendant'}
        $lines.Add(''); $lines.Add("$($labels[$field]) : $($Roadmap.pattern.$field)")
    }
    $lines.Add(''); $lines.Add("**SOLID / DRY / MODULAR :** $($Roadmap.engineering)")
    $lines.Add(''); $lines.Add("Entrée : $($Roadmap.entry)")
    $lines.Add(''); $lines.Add("Sortie : $($Roadmap.exit)")
    $lines.Add(''); $lines.Add("Risque : $($Roadmap.risk)")
    if($Execution){
        $lines.Add('');$lines.Add('### Moyens de progression et dépendants');$lines.Add('')
        $lines.Add('Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu''un paquet.');$lines.Add('')
        $lines.Add('| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |');$lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach($id in $Roadmap.nodes){
            $recipe=$Execution.recipes | Where-Object node -CEQ $id
            $consumers=@($Model.deliveryNodes | Where-Object {$id -cin $_.dependsOn} | ForEach-Object { $_.id })
            $lines.Add("| $id | $($recipe.produce) → $($recipe.verify) | $($recipe.channel) | $($consumers -join ', ') | $($recipe.resources -join ', ') | $($recipe.status) |")
        }
        $lines.Add('');$lines.Add('Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.')
    }
    $lines.Add(''); $lines.Add('Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.')
    $lines.Add('<!-- roadmap-contract:end -->')
    return ($lines -join "`n")
}

function Read-RoadmapJson {
    <#
    .SYNOPSIS
    Reads bounded UTF-8 JSON with strict decoding and asynchronous file I/O.
    .PARAMETER Path
    Explicit local JSON path.
    #>
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 4MB) { throw 'RoadmapJsonTooLarge' }
    $text = [IO.File]::ReadAllTextAsync($Path, [Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    return ConvertFrom-Json -InputObject $text -Depth 64 -ErrorAction Stop
}

function Get-RoadmapAssessment {
    <#
    .SYNOPSIS
    Checks the on-disk planning baseline, generated views and immutable source snapshot.
    .PARAMETER WorkspaceRoot
    Selected monorepo root containing docs/requirements and ROADMAP files.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    try {
        $docs = Join-Path $WorkspaceRoot 'docs'
        $model = Read-RoadmapJson (Join-Path $docs 'requirements/software-ecosystem-factory.roadmaps.json')
        $registry = Read-RoadmapJson (Join-Path $docs 'requirements/software-ecosystem-factory.requirements.json')
        $execution = Read-RoadmapJson (Join-Path $docs 'requirements/software-ecosystem-factory.execution.json')
        Import-Module (Join-Path $PSScriptRoot 'Roadmap.Progression.psm1') -ErrorAction Stop
        $progression=Get-RoadmapExecutionPlan -Model $model -Execution $execution
        $files = @(Get-ChildItem -LiteralPath $docs -Filter 'ROADMAP-*.md' -File | ForEach-Object { $_.Name })
        $report = Test-RoadmapModel $model $registry $files
        $errors = [Collections.Generic.List[string]]::new(); foreach ($code in $report.Errors) { $errors.Add($code) }
        foreach ($map in $model.roadmaps) {
            $path = Join-Path $docs $map.file
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $content = [IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            $blocks = [regex]::Matches($content, '(?s)<!-- roadmap-contract:begin -->.*?<!-- roadmap-contract:end -->')
            if ($blocks.Count -ne 1 -or $blocks[0].Value -cne (Get-RoadmapContractView $map $registry $execution $model)) { $errors.Add("StaleRoadmapView:$($map.id)") }
            $human=[regex]::Replace($content,'(?s)<!-- roadmap-contract:begin -->.*?<!-- roadmap-contract:end -->','')
            if ($human -match '(?m)^\| ID \| (?:Exigence|Contrat à satisfaire) \|') { $errors.Add("UnmanagedRequirementTable:$($map.id)") }
            if ($content.Contains("`r") -or $content.Contains([char]0xfffd)) { $errors.Add("RoadmapEncoding:$($map.id)") }
        }
        $archive = [IO.Path]::GetFullPath((Join-Path $docs ('requirements/'+$registry.sourcePlan.archivePath)))
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $registry.sourcePlan.sha256) { $errors.Add('SourceArchiveHashMismatch') }
        $report.Errors = $errors.ToArray(); $report.Passed = ($errors.Count -eq 0)
        $report | Add-Member NoteProperty Counts ([pscustomobject]@{Roadmaps=$model.roadmaps.Count;Requirements=$registry.requirements.Count;WorkItems=$registry.workItems.Count})
        $report | Add-Member NoteProperty Progression ([pscustomobject]@{Waves=$progression.Waves.Count;Recipes=$execution.recipes.Count;ProductExecution='NotRun';FinalTarget='CON'})
        return $report
    } catch {
        return [pscustomobject]@{Gate='PlanConsistent';Passed=$false;Errors=@("InvalidPlanningFiles:$($_.Exception.Message)");ImplementationReady=$false;ReadinessGaps=@('PlanningFilesUnreadable');ProductQualification='NotAssessed'}
    }
}

function Sync-RoadmapContractView {
    <#
    .SYNOPSIS
    Updates only generated delivery views and work-item delivery references after model validation.
    .PARAMETER WorkspaceRoot
    Selected monorepo root; human roadmap prose is preserved outside managed blocks.
    .PARAMETER PlanPath
    Optional explicit Markdown mirror of the master plan, with resolved local links.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string]$PlanPath)
    $docs = Join-Path $WorkspaceRoot 'docs'
    $model = Read-RoadmapJson (Join-Path $docs 'requirements/software-ecosystem-factory.roadmaps.json')
    $registryPath = Join-Path $docs 'requirements/software-ecosystem-factory.requirements.json'
    $registry = Read-RoadmapJson $registryPath
    $execution = Read-RoadmapJson (Join-Path $docs 'requirements/software-ecosystem-factory.execution.json')
    Import-Module (Join-Path $PSScriptRoot 'Roadmap.Progression.psm1') -ErrorAction Stop
    $null=Get-RoadmapExecutionPlan -Model $model -Execution $execution
    foreach ($item in $registry.workItems) {
        $family = $item.id -creplace '-(design|impl|test|obs)$',''
        $item.deliverableRef = "roadmap:$family/$($item.kind)"
    }
    $files = @(Get-ChildItem -LiteralPath $docs -Filter 'ROADMAP-*.md' -File | ForEach-Object { $_.Name })
    $assessment = Test-RoadmapModel $model $registry $files
    if (!$assessment.Passed) { throw "RoadmapModelInvalid:$($assessment.Errors -join ';')" }
    $writes = [ordered]@{}
    $writes[$registryPath] = (ConvertTo-Json $registry -Depth 64).Replace("`r`n","`n")+"`n"
    foreach ($map in $model.roadmaps) {
        $path = Join-Path $docs $map.file
        $content = [IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace("`r`n","`n")
        $view = Get-RoadmapContractView $map $registry $execution $model
        $pattern = '(?s)<!-- roadmap-contract:begin -->.*?<!-- roadmap-contract:end -->'
        if ([regex]::Matches($content,$pattern).Count -gt 1) { throw "DuplicateRoadmapView:$($map.id)" }
        $placeholder='<!-- roadmap-contract:placeholder -->'
        if ($content.Contains($placeholder)) { throw 'UnexpectedRoadmapPlaceholder' }
        $content=[regex]::Replace($content,$pattern,$placeholder)
        $legacyTable='(?m)^\| ID \| (?:Exigence|Contrat à satisfaire) \|(?: Vérification prévue \|)?\n\|[^\n]+\|\n(?:\|[^\n]+\|\n)+'
        $content=[regex]::Replace($content,$legacyTable,"Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.`n")
        $updated = if ($content.Contains($placeholder)) {
            $content.Replace($placeholder,$view)
        } elseif ($content.Contains('<!-- credits:begin -->')) {
            $content.Replace('<!-- credits:begin -->', $view+"`n`n<!-- credits:begin -->")
        } else { $content.TrimEnd()+"`n`n"+$view+"`n" }
        $writes[$path] = $updated
    }
    if ($PlanPath) {
        $destination=[IO.Path]::GetFullPath($PlanPath,$PWD.Path)
        if ([IO.Path]::GetExtension($destination) -ine '.md' -or !(Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($destination)) -PathType Container) -or $writes.Contains($destination)) { throw 'InvalidRoadmapPlanDestination' }
        $sourcePath=Join-Path $docs 'ROADMAP-Ecosystem-Generator.md'
        $master=$writes[$sourcePath]
        $master=[regex]::Replace($master,'(?<=\]\()(?<path>[^)\s]+)(?=\))',[Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $link=$match.Groups['path'].Value
            if ($link -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $link.StartsWith('#')) { return $link }
            $parts=$link.Split('#',2)
            $resolved=[IO.Path]::GetFullPath((Join-Path $docs $parts[0])).Replace('\','/')
            if ($parts.Count -eq 2) { $resolved+='#'+$parts[1] }
            return $resolved
        })
        $writes[$destination]=$master
    }
    foreach ($path in $writes.Keys) {
        $old = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult() } else { $null }
        if ($old -cne $writes[$path] -and $PSCmdlet.ShouldProcess($path,'Update generated roadmap delivery contract')) {
            [void][IO.File]::WriteAllTextAsync($path,$writes[$path],[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }
    }
}

Export-ModuleMember -Function Test-RoadmapModel, Get-RoadmapAssessment, Sync-RoadmapContractView
