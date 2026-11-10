#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-RoadmapExecutionPlan {
    <#
    .SYNOPSIS
    Computes dependency waves with exclusive resource separation; never dispatches proposed commands.
    .PARAMETER Model
    Canonical roadmap model containing the prerequisite graph.
    .PARAMETER Execution
    Canonical lifecycle and production/verification recipe contracts.
    .PARAMETER Target
    Optional exact delivery node identifier. Omit to schedule the complete portfolio.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model,[Parameter(Mandatory)]$Execution,[string]$Target)
    $ErrorActionPreference='Stop'
    $contractPath=Join-Path $PSScriptRoot 'Roadmap.Contracts.psm1'
    $contracts=Get-Module -All | Where-Object Path -EQ $contractPath | Select-Object -First 1
    if(!$contracts){$contracts=Import-Module $contractPath -PassThru -ErrorAction Stop}
    $graph=& $contracts {param($nodes) Test-RoadmapGraph -Nodes $nodes -Name progression} (,$Model.deliveryNodes)[0]
    if($graph.Errors.Count){throw "ProgressionGraphInvalid:$($graph.Errors -join ';')"}
    if($Execution.schemaVersion -ne 1 -or $Execution.lifecycle.Count -lt 8){throw 'ExecutionContractInvalid'}
    $recipes=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($recipe in $Execution.recipes){
        if(!$recipes.TryAdd($recipe.node,$recipe) -or $recipe.node -cnotin $graph.Order){throw 'ExecutionRecipeIdentityInvalid'}
        foreach($field in @('kind','produce','verify','channel','status')){if([string]::IsNullOrWhiteSpace($recipe.$field)){throw 'ExecutionRecipeIncomplete'}}
        if($recipe.status -cnotin @('Proposed','Available') -or !$recipe.resources.Count){throw 'ExecutionRecipeIncomplete'}
        if($recipe.produce -cnotmatch '^[A-Za-z]+-[A-Za-z0-9]+$' -or $recipe.verify -cnotmatch '^[A-Za-z]+-[A-Za-z0-9]+$'){throw 'ExecutionCommandInvalid'}
    }
    foreach($id in $graph.Order){if(!$recipes.ContainsKey($id)){throw "ExecutionRecipeMissing:$id"}}
    foreach($recipe in $Execution.recipes){
        if($recipe.channel -cnotin @('BootstrapArchive','Evidence','WorkspaceRepository','LocalNuGet','LocalPSResource','LocalBoth')){throw 'ExecutionChannelUnknown'}
        $requiredFeeds=switch($recipe.channel){LocalNuGet {@('REG')} LocalPSResource {@('PSREG0')} LocalBoth {@('REG','PSREG0')} default {@()}}
        if(!$requiredFeeds){continue}
        $closure=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $feedQueue=[Collections.Generic.Queue[string]]::new();$feedQueue.Enqueue($recipe.node)
        while($feedQueue.Count){$current=$feedQueue.Dequeue();if($closure.Add($current)){foreach($dependency in ($Model.deliveryNodes | Where-Object id -CEQ $current).dependsOn){$feedQueue.Enqueue($dependency)}}}
        foreach($feed in $requiredFeeds){if(!$closure.Contains($feed)){throw "DeliveryChannelPrerequisiteMissing:$($recipe.node):$feed"}}
    }
    if($Target -and $Target -cnotin $graph.Order){throw "ExecutionTargetUnknown:$Target"}
    $wanted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pending=[Collections.Generic.Queue[string]]::new()
    if($Target){$pending.Enqueue($Target)}else{foreach($id in $graph.Order){$pending.Enqueue($id)}}
    while($pending.Count){$id=$pending.Dequeue();if($wanted.Add($id)){foreach($dep in ($Model.deliveryNodes | Where-Object id -CEQ $id).dependsOn){$pending.Enqueue($dep)}}}
    $done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $waves=[Collections.Generic.List[object]]::new()
    while($done.Count -lt $wanted.Count){
        $ready=@($wanted | Where-Object { $id=$_; !$done.Contains($id) -and @((($Model.deliveryNodes | Where-Object id -CEQ $id).dependsOn) | Where-Object {!$done.Contains($_)}).Count -eq 0 } | Sort-Object -CaseSensitive)
        $locks=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $batch=[Collections.Generic.List[object]]::new()
        foreach($id in $ready){
            $recipe=$recipes[$id]
            if(@($recipe.resources | Where-Object {$locks.Contains($_)}).Count){continue}
            foreach($resource in $recipe.resources){[void]$locks.Add($resource)}
            $consumers=@($Model.deliveryNodes | Where-Object {$id -cin $_.dependsOn} | ForEach-Object { $_.id })
            $batch.Add([pscustomobject]@{Node=$id;DependsOn=($Model.deliveryNodes | Where-Object id -CEQ $id).dependsOn;Enables=$consumers;Recipe=$recipe;Artifact=($Model.deliveryNodes | Where-Object id -CEQ $id).artifact;DeliveryGate='NotRun'})
        }
        if(!$batch.Count){throw 'ExecutionSchedulerStalled'}
        $waves.Add([pscustomobject]@{Wave=$waves.Count;Nodes=$batch.ToArray()})
        foreach($entry in $batch){[void]$done.Add($entry.Node)}
    }
    [pscustomobject]@{SchemaVersion=1;PlanningOnly=$true;Target=if($Target){$Target}else{'All'};Objective=$Model.objective;Lifecycle=$Execution.lifecycle;Preview=$Execution.preview;Waves=$waves.ToArray();ProductExecution='NotRun';Policy='A completed wave only describes ordering. Advance requires exact package/hash, independent acceptance evidence and recovery receipt. Development containers are owned source directories; OCI containers are explicit registry/runtime adapters.'}
}

Export-ModuleMember -Function Get-RoadmapExecutionPlan
