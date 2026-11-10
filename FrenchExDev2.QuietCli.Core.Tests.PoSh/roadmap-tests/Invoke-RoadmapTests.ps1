#requires -Version 7.6
<#
.SYNOPSIS
Exercises the planning checker using independent invariants and retained fault controls.
.PARAMETER WorkspaceRoot
Monorepo under assessment; source files are never mutated by the suite.
.PARAMETER RunDirectory
Owned external report directory created by the monitored launcher.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
$state = [ordered]@{Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';Task='Roadmap contracts: examples, properties, fuzz and mutations';Workspace=$WorkspaceRoot;ProjectDirectory=$PSScriptRoot;Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Starting';Error=$null}
$statusPath = Join-Path $RunDirectory 'status.json'
$cases = [Collections.Generic.List[object]]::new()
$seed = 20261110
$modulePath = Join-Path $WorkspaceRoot 'scripts/lib/Roadmap.Contracts.psm1'

function Assert-Case {
    <#
    .SYNOPSIS
    Records a named independent expectation and updates the shared monitor.
    .PARAMETER Name
    Stable scenario identifier.
    .PARAMETER Condition
    Observed business invariant.
    .PARAMETER Category
    Evidence category, kept separate in the report.
    #>
    param([string]$Name,[bool]$Condition,[string]$Category='example')
    $cases.Add([pscustomobject]@{Name=$Name;Category=$Category;Passed=$Condition})
    if ($Condition) { $state.Passed++ } else { $state.Failed++ }
    $state.Case=$Name
    Write-WorkspaceJson $statusPath $state
}

function Copy-Model {
    <#
    .SYNOPSIS
    Produces independent mutable JSON input for one fault scenario.
    .PARAMETER Value
    JSON-compatible baseline value.
    #>
    param($Value)
    ConvertFrom-Json -InputObject (ConvertTo-Json $Value -Depth 64) -Depth 64
}

function Invoke-Assessment {
    <#
    .SYNOPSIS
    Calls a selected checker module, including an explicitly loaded source mutant.
    .PARAMETER Module
    Imported checker identity.
    .PARAMETER Model
    Roadmap planning model.
    .PARAMETER Registry
    Requirement registry.
    .PARAMETER Files
    Actual roadmap inventory.
    #>
    param($Module,$Model,$Registry,[string[]]$Files)
    & $Module { param($m,$r,$f) Test-RoadmapModel -Model $m -Registry $r -RoadmapFiles $f } $Model $Registry $Files
}

Write-WorkspaceJson $statusPath $state
try {
    $module = Import-Module $modulePath -PassThru -Force
    $docs = Join-Path $WorkspaceRoot 'docs'
    $model = Get-Content -LiteralPath (Join-Path $docs 'requirements/software-ecosystem-factory.roadmaps.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 64
    $registry = Get-Content -LiteralPath (Join-Path $docs 'requirements/software-ecosystem-factory.requirements.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 64
    $files = @(Get-ChildItem -LiteralPath $docs -Filter 'ROADMAP-*.md' -File | ForEach-Object Name)
    $baseline = Get-RoadmapAssessment $WorkspaceRoot
    Write-WorkspaceJson (Join-Path $RunDirectory 'planning-assessment.json') $baseline
    Assert-Case 'baseline planning passes with product readiness withheld' ($baseline.Passed -and !$baseline.ImplementationReady -and $baseline.ProductQualification -ceq 'NotAssessed' -and $baseline.ReadinessGaps.Count -gt 0)
    Assert-Case 'all files and all ten i3 acceptance scenarios are represented' ($baseline.Counts.Roadmaps -eq $files.Count -and @($registry.requirements | Where-Object feature -CEQ I3).Count -eq 10)
    Assert-Case 'every product evidence remains NotRun' (@($registry.requirements.acceptance.evidence | Where-Object status -CNE NotRun).Count -eq 0)
    Assert-Case 'requested delivery target is i3' ($model.target -ceq 'C:/code/FrenchExDev/FrenchExDev_i3')
    $ancestors=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pending=[Collections.Generic.Queue[string]]::new();$pending.Enqueue('I3')
    while($pending.Count){$nodeId=$pending.Dequeue();if($ancestors.Add($nodeId)){foreach($dependency in ($model.deliveryNodes|Where-Object id -CEQ $nodeId).dependsOn){$pending.Enqueue($dependency)}}}
    Assert-Case 'i3 excludes domain engines while including qualified local registries' (@($ancestors | Where-Object {$_ -in @('FSM','IEC','MSG','EXT','CORE','G2','SM1')}).Count -eq 0 -and 'REG' -cin $ancestors -and 'PSREG1' -cin $ancestors)
    Assert-Case 'Manager local runtime has only HOST and GP component dependencies' ((($model.runtimeNodes|Where-Object id -CEQ ManagerLocal).dependsOn|Sort-Object) -join ',' -ceq 'GitProject,WorkspaceHost')

    $faults = @(
        @{Name='cycle';Change={param($m,$r) $m.deliveryNodes[0].dependsOn=@('I3')};Code='Cycle:delivery:'},
        @{Name='runtime cycle';Change={param($m,$r) $m.runtimeNodes[1].dependsOn=@('ManagerLocal')};Code='Cycle:runtime:'},
        @{Name='missing delivery';Change={param($m,$r) $m.roadmaps[0].deliverables.design=''};Code='MissingDeliverable:'},
        @{Name='missing prerequisite';Change={param($m,$r) $m.deliveryNodes[0].dependsOn=@('Nonexistent')};Code='MissingDependency:'},
        @{Name='duplicate node';Change={param($m,$r) $m.deliveryNodes+=@($m.deliveryNodes[0])};Code='DuplicateNode:'},
        @{Name='duplicate requirement';Change={param($m,$r) $r.requirements+=@($r.requirements[0])};Code='DuplicateRequirement:'},
        @{Name='unlinked kind';Change={param($m,$r) $r.requirements[0].kindLinks=@('FAC-design')};Code='UnresolvedKind:'},
        @{Name='orphan source';Change={param($m,$r) $r.requirements[0].sources[0].document='ROADMAP-Missing.md'};Code='UnresolvedSource:'},
        @{Name='missing AC';Change={param($m,$r) $r.requirements[0].acceptance[0].then=''};Code='IncompleteAC:'},
        @{Name='false passed evidence';Change={param($m,$r) $r.requirements[0].acceptance[0].verification.status='Executed';$r.requirements[0].acceptance[0].verification.implementationRef='fixture:test';$r.requirements[0].acceptance[0].evidence.status='Passed'};Code='UnsubstantiatedEvidence:'},
        @{Name='verified without evidence';Change={param($m,$r) $r.requirements[0].status='Verified'};Code='UnverifiedMaturity:'},
        @{Name='blocking learning feedback';Change={param($m,$r) $m.feedback[0].blocking=$true};Code='UncontrolledFeedback'},
        @{Name='orphan work item';Change={param($m,$r) $r.workItems[0].deliverableRef='roadmap:Missing/design'};Code='UnresolvedDeliverable:'}
    )
    foreach ($fault in $faults) {
        $m=Copy-Model $model; $r=Copy-Model $registry; & $fault.Change $m $r
        $result=Invoke-Assessment $module $m $r $files
        Assert-Case $fault.Name (!$result.Passed -and @($result.Errors | Where-Object { $_.StartsWith($fault.Code,[StringComparison]::Ordinal) }).Count -gt 0)
    }
    $result=Invoke-Assessment $module $model $registry ($files+@('ROADMAP-Unclassified.md'))
    Assert-Case 'extra roadmap is rejected' (!$result.Passed -and 'UnclassifiedRoadmap:ROADMAP-Unclassified.md' -cin $result.Errors)

    # Independent edge-order properties; no expected topological list is generated by the product.
    $random=[Random]::new($seed)
    for ($iteration=0;$iteration -lt 80;$iteration++) {
        $nodes=@();$count=$random.Next(2,18)
        for ($i=0;$i -lt $count;$i++) {
            $deps=@(for($j=0;$j -lt $i;$j++){if($random.Next(3) -eq 0){"N$j"}})
            $nodes+=@([pscustomobject]@{id="N$i";dependsOn=$deps})
        }
        $shuffled=@($nodes | Sort-Object { $random.Next() })
        $graph=& $module {param($n) Test-RoadmapGraph -Nodes $n -Name property} (,$shuffled)[0]
        $valid=$graph.Errors.Count -eq 0 -and $graph.Order.Count -eq $count
        foreach($node in $nodes){foreach($dep in $node.dependsOn){$valid=$valid -and [Array]::IndexOf($graph.Order,$dep) -lt [Array]::IndexOf($graph.Order,$node.id)}}
        Assert-Case "DAG edge order and permutation $iteration" $valid property
        $nodes[0].dependsOn=@('N0')
        $graph=& $module {param($n) Test-RoadmapGraph -Nodes $n -Name property} (,$nodes)[0]
        Assert-Case "self-cycle rejected $iteration" (@($graph.Errors | Where-Object { $_ -like 'Cycle:*' }).Count -gt 0) property
    }

    # Invalid object shapes and boundary cases are retained, not counted as product tests.
    $malformed=@($null,0,'text',@{},[pscustomobject]@{schemaVersion=999},[pscustomobject]@{schemaVersion=1;kinds=@()},@{schemaVersion=1;kinds=@('design','impl','test','obs');roadmaps=@()})
    foreach($sample in $malformed){
        $rejected=try { !(Invoke-Assessment $module $sample $registry $files).Passed } catch { $true }
        Assert-Case "malformed model $($cases.Count)" $rejected fuzz
    }
    foreach($name in @('', '../escape', 'A/B', ('N'+[char]0), ('A'*65), 'é', 'a b')){
        $bad=@([pscustomobject]@{id=$name;dependsOn=@()})
        $graph=& $module {param($n) Test-RoadmapGraph -Nodes $n -Name fuzz} (,$bad)[0]
        Assert-Case "malformed graph identity $($cases.Count)" ($graph.Errors.Count -gt 0) fuzz
    }
    foreach($size in @(0,2049)){
        $boundary=@(for($n=0;$n -lt $size;$n++){[pscustomobject]@{id="N$n";dependsOn=@()}})
        $graph=& $module {param($n) Test-RoadmapGraph -Nodes $n -Name boundary} (,$boundary)[0]
        Assert-Case "graph size boundary $size" ('GraphSize:boundary' -cin $graph.Errors -and $graph.Order.Count -eq 0) fuzz
    }

    # Exercise file I/O, WhatIf, idempotence, stale views, and archive tampering in an owned copy.
    $fixture=Join-Path $RunDirectory 'fixture'
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'docs/requirements'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'docs/audits'))
    foreach($file in $files){Copy-Item -LiteralPath (Join-Path $docs $file) -Destination (Join-Path $fixture ('docs/'+$file))}
    Copy-Item -LiteralPath (Join-Path $docs 'requirements/software-ecosystem-factory.roadmaps.json'),(Join-Path $docs 'requirements/software-ecosystem-factory.requirements.json'),(Join-Path $docs 'requirements/software-ecosystem-factory.execution.json') -Destination (Join-Path $fixture 'docs/requirements')
    Copy-Item -LiteralPath (Join-Path $docs 'audits/2026-11-10-claude-ecosystem-plan.source.txt') -Destination (Join-Path $fixture 'docs/audits')
    $target=Join-Path $fixture ('docs/'+$files[0])
    $text=[IO.File]::ReadAllTextAsync($target,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $stale=$text.Replace('Responsable : Unassigned.','Responsable : changed.')
    [void][IO.File]::WriteAllTextAsync($target,$stale,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    Assert-Case 'stale projection rejected' (!(Get-RoadmapAssessment $fixture).Passed)
    $before=(Get-FileHash -LiteralPath $target).Hash
    $output=@(Sync-RoadmapContractView -WorkspaceRoot $fixture -WhatIf)
    Assert-Case 'WhatIf has no pipeline data or writes' ($output.Count -eq 0 -and $before -ceq (Get-FileHash -LiteralPath $target).Hash)
    $output=@(Sync-RoadmapContractView -WorkspaceRoot $fixture -Confirm:$false)
    Assert-Case 'sync repairs only the managed projection without incidental output' ($output.Count -eq 0 -and (Get-RoadmapAssessment $fixture).Passed -and $text -ceq [IO.File]::ReadAllTextAsync($target,[Text.Encoding]::UTF8).GetAwaiter().GetResult())
    $before=(Get-FileHash -LiteralPath $target).Hash
    $timestamp=(Get-Item -LiteralPath $target).LastWriteTimeUtc
    Sync-RoadmapContractView -WorkspaceRoot $fixture -Confirm:$false
    Assert-Case 'second sync performs no rewrite' ($before -ceq (Get-FileHash -LiteralPath $target).Hash -and $timestamp -eq (Get-Item -LiteralPath $target).LastWriteTimeUtc) property
    $mirror=Join-Path $RunDirectory 'plan-mirror.md'
    Sync-RoadmapContractView -WorkspaceRoot $fixture -PlanPath $mirror -WhatIf
    Assert-Case 'plan mirror WhatIf creates nothing' (!(Test-Path -LiteralPath $mirror))
    Sync-RoadmapContractView -WorkspaceRoot $fixture -PlanPath $mirror -Confirm:$false
    $mirrorText=[IO.File]::ReadAllTextAsync($mirror,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    Assert-Case 'explicit plan mirror resolves local links' ($mirrorText.Contains('C:/') -and !$mirrorText.Contains('](ROADMAP-') -and !$mirrorText.Contains('](requirements/'))
    $archive=Join-Path $fixture 'docs/audits/2026-11-10-claude-ecosystem-plan.source.txt'
    Add-Content -LiteralPath $archive -Value 'tampered' -Encoding utf8
    Assert-Case 'archive tampering rejected' ('SourceArchiveHashMismatch' -cin (Get-RoadmapAssessment $fixture).Errors)
    $jsonPath=Join-Path $fixture 'docs/requirements/software-ecosystem-factory.roadmaps.json'
    foreach($raw in @('{','[]','null','{"schemaVersion":', '{"schemaVersion":1,"roadmaps":[}')){
        [void][IO.File]::WriteAllTextAsync($jsonPath,$raw,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        Assert-Case "malformed JSON $($cases.Count)" (!(Get-RoadmapAssessment $fixture).Passed) fuzz
    }

    $source=[IO.File]::ReadAllTextAsync($modulePath,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $mutations=@(
        @{Name='cycle detection';From='$errors.Add("Cycle:${Name}:$((@($remaining.Keys) | Sort-Object -CaseSensitive) -join '','')"); break';To='break';Fault='cycle'},
        @{Name='missing deliverable';From='$errors.Add("MissingDeliverable:$($map.id):$kind")';To='$null = $kind';Fault='missing delivery'},
        @{Name='unsubstantiated evidence';From='$ac.evidence.status -in @(''Passed'',''Failed'')';To='$ac.evidence.status -in @(''Never'')';Fault='false passed evidence'},
        @{Name='roadmap inventory';From='$errors.Add("UnclassifiedRoadmap:$file")';To='$null = $file';Fault='unclassified'}
    )
    $mutationResults=[Collections.Generic.List[object]]::new()
    foreach($mutation in $mutations){
        if(([regex]::Matches($source,[regex]::Escape($mutation.From))).Count -ne 1){throw "MutationTargetInvalid:$($mutation.Name)"}
        $mutantPath=Join-Path $RunDirectory ("Mutant$($mutationResults.Count).psm1")
        [void][IO.File]::WriteAllTextAsync($mutantPath,$source.Replace($mutation.From,$mutation.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $mutant=Import-Module $mutantPath -PassThru -Force
        $m=Copy-Model $model;$r=Copy-Model $registry;$f=$files
        if($mutation.Fault -eq 'unclassified'){$f=$files+@('ROADMAP-Unclassified.md')}
        else{$fault=$faults | Where-Object Name -EQ $mutation.Fault; & $fault.Change $m $r}
        $observed=Invoke-Assessment $mutant $m $r $f
        $outcome=if($observed.Passed){'Killed'}else{'Survived'}
        $mutationResults.Add([pscustomobject]@{Name=$mutation.Name;Outcome=$outcome;SourceSha256=(Get-FileHash -LiteralPath $mutantPath).Hash;Witness=$mutation.Fault})
        Assert-Case "mutation $($mutation.Name)" ($outcome -eq 'Killed') mutation
        Remove-Module $mutant
    }
    Write-WorkspaceJson (Join-Path $RunDirectory 'mutations.json') $mutationResults.ToArray()
    . (Join-Path $PSScriptRoot 'Test-MigrationAndProgression.ps1')
    $state.State=if($state.Failed){'Failed'}else{'Success'}
} catch {$state.State='Crash';$state.Error=$_.Exception.ToString();$state.Failed++}
finally {
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $groups=@($cases | Group-Object Category | ForEach-Object {[pscustomobject]@{Category=$_.Name;Executed=$_.Count;Passed=@($_.Group | Where-Object Passed).Count;Failed=@($_.Group | Where-Object {!$_.Passed}).Count}})
    $sourceFiles=@($modulePath,$PSCommandPath,(Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapTests.ps1'),(Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapContract.ps1'))
    $sourceFiles+=@(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'docs/requirements') -File | ForEach-Object FullName)
    $sourceFiles+=@('scripts/lib/Migration.Dependencies.psm1','scripts/lib/Migration.Exports.psm1','scripts/lib/Roadmap.Progression.psm1','scripts/Test-MigrationDependencies.ps1','scripts/Test-MigrationGate.ps1','scripts/Test-PowerShellModuleExports.ps1','scripts/workers/Invoke-ModuleExportProbe.ps1','scripts/Get-RoadmapExecutionPlan.ps1','FrenchExDev2.QuietCli.Core.Tests.PoSh/roadmap-tests/Test-MigrationAndProgression.ps1' | ForEach-Object { Join-Path $WorkspaceRoot $_ })
    $sourceFiles+=@('scripts/lib/LocalGallery.Probe.psm1','scripts/Test-LocalGalleryContainer.ps1','scripts/workers/Invoke-LocalGalleryProbe.ps1','scripts/workers/Invoke-LocalGalleryClient.ps1' | ForEach-Object { Join-Path $WorkspaceRoot $_ })
    $sourceFiles+=@(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'docs') -Filter 'ROADMAP-*.md' -File | ForEach-Object FullName)
    $identities=@(foreach($file in $sourceFiles){[pscustomobject]@{Path=$file;Sha256=(Get-FileHash -LiteralPath $file).Hash}})
    $summary=[pscustomobject]@{State=$state;Seed=$seed;Categories=$groups;Cases=$cases.ToArray();Sources=$identities;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Planning tooling only; no product acceptance or release qualification.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') $summary
    Write-WorkspaceJson $statusPath $state
}
if($state.State -ne 'Success'){exit 1}
