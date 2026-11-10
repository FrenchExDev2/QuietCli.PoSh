#requires -Version 7.6
# This companion fragment runs only inside the monitored complete roadmap worker.
$progressionModule=Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Roadmap.Progression.psm1') -PassThru -Force
$migrationModule=Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Migration.Dependencies.psm1') -PassThru -Force
$execution=Get-Content (Join-Path $docs 'requirements/software-ecosystem-factory.execution.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
$plan=Get-RoadmapExecutionPlan -Model $model -Execution $execution -Target CON
$waveByNode=@{}
foreach($wave in $plan.Waves){foreach($entry in $wave.Nodes){$waveByNode[$entry.Node]=$wave.Wave}}
Assert-Case 'Conduit is the final objective and SoftwareContract name is accepted' ($model.softwareContract.name -ceq 'FrenchExDev2.SoftwareContract' -and $model.softwareContract.decision -ceq 'UserAccepted' -and $plan.Target -ceq 'CON' -and $plan.ProductExecution -ceq 'NotRun')
Assert-Case 'personal workspace Git repository keeps hosted repositories independent' ($model.workspaceRepository.owner -ceq 'stephaneerard' -and $model.workspaceRepository.nestedRepositories.Contains('excluded') -and $null -eq $model.workspaceRepository.remoteSlug)
Assert-Case 'Result enables Builder and FSM in parallel' ($waveByNode.BUILDER -eq $waveByNode.FSM -and $waveByNode.RESULT -lt $waveByNode.FSM)
Assert-Case 'seed precedes feeds and accepted i3 follows registry lifecycle' ($waveByNode.I3SEED -lt $waveByNode.REG -and $waveByNode.I3SEED -lt $waveByNode.PSREG0 -and $waveByNode.SMREG -lt $waveByNode.I3)
foreach($wave in $plan.Waves){
    $resources=@($wave.Nodes.Recipe.resources)
    Assert-Case "exclusive resources wave $($wave.Wave)" ($resources.Count -eq @($resources | Sort-Object -Unique).Count) property
    foreach($entry in $wave.Nodes){foreach($dependency in $entry.DependsOn){Assert-Case "producer $dependency before $($entry.Node)" ($waveByNode[$dependency] -lt $wave.Wave) property}}
}
$rejected=try{$null=Get-RoadmapExecutionPlan $model $execution -Target Missing;$false}catch{$true}
Assert-Case 'unknown configured progression target refused' $rejected fuzz
$bad=Copy-Model $execution;$bad.recipes=@($bad.recipes | Where-Object node -CNE FSM)
$rejected=try{$null=Get-RoadmapExecutionPlan $model $bad;$false}catch{$_.Exception.Message -like 'ExecutionRecipeMissing:*'}
Assert-Case 'missing production means refused' $rejected
$missingFeed=Copy-Model $model
($missingFeed.deliveryNodes | Where-Object id -CEQ RACPKG).dependsOn=@('REG','STD','MIG0')
$rejected=try{$null=Get-RoadmapExecutionPlan $missingFeed $execution;$false}catch{$_.Exception.Message -ceq 'DeliveryChannelPrerequisiteMissing:RACPKG:PSREG0'}
Assert-Case 'local mixed package requires both actual delivery channels' $rejected
$bad=Copy-Model $execution;$bad.recipes[0].produce='Invoke-Thing; Remove-Item'
$rejected=try{$null=Get-RoadmapExecutionPlan $model $bad;$false}catch{$true}
Assert-Case 'recipe is a command contract rather than executable text' $rejected fuzz
$tiny=[pscustomobject]@{objective='fixture';deliveryNodes=@([pscustomobject]@{id='A';dependsOn=@();artifact='A'},[pscustomobject]@{id='B';dependsOn=@();artifact='B'})}
$tinyExec=[pscustomobject]@{schemaVersion=1;lifecycle=$execution.lifecycle;preview=$execution.preview;recipes=@([pscustomobject]@{node='A';kind='Tooling';produce='New-A';verify='Test-A';channel='Evidence';status='Proposed';resources=@('shared')},[pscustomobject]@{node='B';kind='Tooling';produce='New-B';verify='Test-B';channel='Evidence';status='Proposed';resources=@('shared')})}
Assert-Case 'independent nodes sharing a mutable resource are separated' ((Get-RoadmapExecutionPlan $tiny $tinyExec).Waves.Count -eq 2)

function Write-MigrationFixtureText {
    <#
    .SYNOPSIS
    Writes UTF-8/LF fixture files within the owned external run directory.
    .PARAMETER Path
    Owned target path.
    .PARAMETER Content
    Literal fixture content, never evaluated by the test driver.
    #>
    param([string]$Path,[string]$Content)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [void][IO.File]::WriteAllTextAsync($Path,$Content.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
$migrationRoot=Join-Path $RunDirectory 'migration-fixture'
$policyPath=Join-Path $RunDirectory 'migration-policy.json'
$candidate=Join-Path $migrationRoot 'candidate'
$policy=[pscustomobject]@{schemaVersion=1;default='Exclude';externalDependencies=@();items=@([pscustomobject]@{id='Candidate';path='candidate';intent='Migrate';approved=$true})}
Write-MigrationFixtureText $policyPath (ConvertTo-Json $policy -Depth 12)
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') ". './helper.ps1'`n"
Write-MigrationFixtureText (Join-Path $candidate 'helper.ps1') "'safe'`n"
$good=Get-MigrationDependencyReport -SourceRoot $migrationRoot -PolicyPath $policyPath
Assert-Case 'literal script dependency resolves without execution' ($good.Passed -and $good.Files.Count -eq 2 -and $good.Dependencies[0].State -ceq 'ResolvedLocal' -and $good.MigrationQualification -ceq 'NotAssessed')
$reportPath=Join-Path $RunDirectory 'migration-whatif.json'
Export-MigrationDependencyReport $good $reportPath -WhatIf
Assert-Case 'migration report WhatIf writes nothing' (!(Test-Path -LiteralPath $reportPath))
Export-MigrationDependencyReport $good $reportPath -Confirm:$false
Assert-Case 'dependency evidence carries source policy and checker hashes' ((Test-Path -LiteralPath $reportPath) -and $good.PolicySha256 -and $good.CheckerSha256 -and $good.Files[0].Sha256)
$rejected=try{Export-MigrationDependencyReport $good $reportPath -Confirm:$false;$false}catch{$_.Exception.Message -ceq 'MigrationReportExists'}
Assert-Case 'saved migration evidence is never overwritten' $rejected
$rejected=try{$null=Get-MigrationDependencyReport $migrationRoot $policyPath -ItemId Unlisted;$false}catch{$true}
Assert-Case 'unlisted migration candidate refused' $rejected

Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') ". './missing.ps1'`n"
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'missing script dependency blocks migration gate' (!$badReport.Passed -and $badReport.Dependencies[0].State -ceq 'Missing')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') ". './helper.ps1'`n"
Write-MigrationFixtureText (Join-Path $candidate 'helper.ps1') ". './main.ps1'`n"
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'static dependency cycles block migration gate' (!$badReport.Passed -and @($badReport.Issues | Where-Object {$_ -like 'DependencyCycle:*'}).Count -eq 1)
Write-MigrationFixtureText (Join-Path $candidate 'helper.ps1') "'safe'`n"
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') 'Import-Module $computedName'
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'computed module dependency requires evaluation' (!$badReport.Passed -and $badReport.Dependencies[0].State -ceq 'NeedsEvaluation')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') 'Import-Module ExplicitTool'
$policy.externalDependencies=@([pscustomobject]@{kind='Module';name='ExplicitTool';version='1.2.3';source='local-feed'})
Write-MigrationFixtureText $policyPath (ConvertTo-Json $policy -Depth 12)
$declared=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'explicit external dependency is a declaration rather than installed evidence' ($declared.Passed -and $declared.Dependencies[0].State -ceq 'DeclaredExternal' -and $declared.MigrationQualification -ceq 'NotAssessed')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') '& $unknownCommand ExplicitTool'
$dynamic=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'dynamic dispatch cannot borrow approval from a literal argument' (!$dynamic.Passed -and $dynamic.Dependencies[0].Kind -ceq 'DynamicCommand' -and $dynamic.Dependencies[0].State -ceq 'NeedsEvaluation')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "Import-Module ExplicitTool -RequiredVersion '9.9.9'"
$mismatch=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'required module version conflicts with declared environment pin' (!$mismatch.Passed -and $mismatch.Dependencies[0].State -ceq 'VersionMismatch')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "Import-Module ExplicitTool -MinimumVersion '1.0.0'"
$range=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'module version range requires evaluated resolution rather than an assumed pin' (!$range.Passed -and $range.Dependencies[0].State -ceq 'NeedsEvaluation')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "Import-Module ExplicitTool -RequiredVersion:'9.9.9'"
$inlineVersion=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'inline named module version retains its exact constraint' (!$inlineVersion.Passed -and $inlineVersion.Dependencies[0].State -ceq 'VersionMismatch')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "#requires -Modules @{ModuleName='ExplicitTool'; ModuleVersion='9.0.0'}`n"
$requiredRange=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'requires module minimum version is not treated as an exact environment pin' (!$requiredRange.Passed -and $requiredRange.Dependencies[0].State -ceq 'NeedsEvaluation')
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "Set-Content -LiteralPath '$($RunDirectory.Replace("'","''"))/must-not-exist.txt' -Value injected"
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'inspected code never executes and unknown commands require decisions' (!(Test-Path -LiteralPath (Join-Path $RunDirectory 'must-not-exist.txt')) -and !$badReport.Passed)
Write-MigrationFixtureText (Join-Path $candidate 'main.ps1') "'safe'`n"
Write-MigrationFixtureText (Join-Path $candidate 'app.csproj') '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="missing.csproj"/><PackageReference Include="Unknown.Package" Version="1.0.0"/></ItemGroup></Project>'
Write-MigrationFixtureText (Join-Path $candidate 'app.sln') 'Project("{GUID}") = "App", "app.csproj", "{GUID}"'
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'solution and project refs are covered and evaluated graph is required' (!$badReport.Passed -and @($badReport.Files | Where-Object Kind -EQ '.sln').Count -eq 1 -and @($badReport.Issues | Where-Object {$_ -like '*EvaluatedBuildGraphRequired*'}).Count -eq 1 -and @($badReport.Dependencies | Where-Object State -EQ Missing).Count -gt 0)
Write-MigrationFixtureText (Join-Path $candidate 'app.csproj') '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///never-read">]><Project>&e;</Project>'
$badReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'XML DTD and external entities are refused' (!$badReport.Passed -and @($badReport.Files | Where-Object Status -EQ Unreadable).Count -eq 1) fuzz
foreach($path in @('../escape','/absolute','candidate/../../outside')){
    $badPolicy=Copy-Model $policy;$badPolicy.items[0].path=$path
    Write-MigrationFixtureText $policyPath (ConvertTo-Json $badPolicy -Depth 12)
    $rejected=try{$null=Get-MigrationDependencyReport $migrationRoot $policyPath;$false}catch{$true}
    Assert-Case "whitelist traversal refused $path" $rejected fuzz
}
Write-MigrationFixtureText $policyPath (ConvertTo-Json $policy -Depth 12)
for($iteration=0;$iteration -lt 12;$iteration++){
    $badPolicy=Copy-Model $policy;$badPolicy.items[0].id="Item$iteration";$badPolicy.items[0].approved=$false
    Write-MigrationFixtureText $policyPath (ConvertTo-Json $badPolicy -Depth 12)
    $observed=Get-MigrationDependencyReport $migrationRoot $policyPath
    Assert-Case "unapproved identity cannot pass $iteration" (!$observed.Passed -and @($observed.Issues | Where-Object {$_ -like '*SelectionNotApproved'}).Count -eq 1) property
}
$emptyPath=Join-Path $migrationRoot 'empty'
Write-MigrationFixtureText (Join-Path $emptyPath 'src/.gitkeep') ''
$emptyPolicy=Copy-Model $policy;$emptyPolicy.items[0].path='empty';$emptyPolicy.items[0].intent='Create'
Write-MigrationFixtureText $policyPath (ConvertTo-Json $emptyPolicy -Depth 12)
$emptyReport=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'gitkeep-only source is a scaffold with no migrated behavior' ($emptyReport.Items[0].StructureOnly -and $emptyReport.Items[0].Eligibility -ceq 'ScaffoldCandidate' -and !$emptyReport.Passed -and $emptyReport.MigrationQualification -ceq 'NotAssessed')
Write-MigrationFixtureText (Join-Path $emptyPath 'active.ps1') "'existing-code'"
$partial=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'empty subdirectories never hide nonempty parent behavior' (!$partial.Items[0].StructureOnly)

# Targeted mutations must disable the independent rejection witness; import failures are crashes.
$migrationSource=Get-Content (Join-Path $WorkspaceRoot 'scripts/lib/Migration.Dependencies.psm1') -Raw -Encoding utf8
$migrationMutants=@(
    @{Name='whitelist selection';From="throw `"MigrationItemNotWhitelisted:`$id`"";To='$null = $id';Witness='unknown'},
    @{Name='approval guard';From="if(!`$item.approved -or `$item.intent -eq 'Assess')";To='if($false)';Witness='approval'},
    @{Name='report WhatIf';From="if(`$PSCmdlet.ShouldProcess(`$full,'Create migration dependency evidence'))";To='if($true)';Witness='whatif'}
)
foreach($mutation in $migrationMutants){
    if(([regex]::Matches($migrationSource,[regex]::Escape($mutation.From))).Count -ne 1){throw "MigrationMutationTargetInvalid:$($mutation.Name)"}
    $mutantPath=Join-Path $RunDirectory ('MigrationMutant'+$mutation.Witness+'.psm1')
    Write-MigrationFixtureText $mutantPath ($migrationSource.Replace($mutation.From,$mutation.To))
    $mutant=Import-Module $mutantPath -PassThru -Force
    $simple=Copy-Model $policy;$simple.items[0].path='empty';$simple.items[0].intent='Migrate'
    if($mutation.Witness -eq 'approval'){$simple.items[0].approved=$false}
    Write-MigrationFixtureText $policyPath (ConvertTo-Json $simple -Depth 12)
    $killed=switch($mutation.Witness){
        unknown {try{$null=& $mutant {param($root,$p) Get-MigrationDependencyReport $root $p -ItemId Unknown} $migrationRoot $policyPath;$true}catch{$false}}
        approval {(& $mutant {param($root,$p) Get-MigrationDependencyReport $root $p} $migrationRoot $policyPath).Passed}
        whatif {$mutationReport=Join-Path $RunDirectory 'mutant-whatif.json';& $mutant {param($r,$p) Export-MigrationDependencyReport $r $p -WhatIf} $good $mutationReport;Test-Path -LiteralPath $mutationReport}
    }
    $mutationResults.Add([pscustomobject]@{Name=$mutation.Name;Outcome=if($killed){'Killed'}else{'Survived'};SourceSha256=(Get-FileHash $mutantPath).Hash;Witness=$mutation.Witness})
    Assert-Case "migration mutant $($mutation.Name)" $killed mutation
    Remove-Module $mutant
}
Write-WorkspaceJson (Join-Path $RunDirectory 'mutations.json') $mutationResults.ToArray()

# Import observation complements static inspection and never runs in the controller's process.
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Migration.Exports.psm1') -Force
$probePolicy=Copy-Model $policy;$probePolicy.items[0].path='probe'
Write-MigrationFixtureText $policyPath (ConvertTo-Json $probePolicy -Depth 12)
$probeSource=Join-Path $migrationRoot 'probe/ExportWitness.psm1'
Write-MigrationFixtureText $probeSource "function Get-PublicWitness { 'public' }`nfunction Get-PrivateWitness { 'private' }`nExport-ModuleMember -Function Get-PublicWitness`n"
$probeRun=Join-Path $RunDirectory 'exports-success'
$preview=@(Test-PowerShellModuleExports -SourceRoot $migrationRoot -PolicyPath $policyPath -ItemId Candidate -EntryPath ExportWitness.psm1 -ExpectedFunctions Get-PublicWitness -WorkspaceRoot $WorkspaceRoot -RunDirectory $probeRun -WhatIf)
Assert-Case 'export probe WhatIf imports nothing and creates no report directory' ($preview.Count -eq 0 -and !(Test-Path -LiteralPath $probeRun) -and !(Get-Module ExportWitness))
$probeResult=Test-PowerShellModuleExports -SourceRoot $migrationRoot -PolicyPath $policyPath -ItemId Candidate -EntryPath ExportWitness.psm1 -ExpectedFunctions Get-PublicWitness -ExpectedCmdlets @() -StageCopy -WorkspaceRoot $WorkspaceRoot -RunDirectory $probeRun -Confirm:$false
Assert-Case 'Get-Module observes actual public exports after isolated import' ($probeResult.State -ceq 'Success' -and $probeResult.Qualification -ceq 'ExportContractPassed' -and $probeResult.Observation.Functions.Count -eq 1 -and $probeResult.Observation.Functions[0] -ceq 'Get-PublicWitness' -and !(Get-Module ExportWitness))
$probeMismatch=Test-PowerShellModuleExports -SourceRoot $migrationRoot -PolicyPath $policyPath -ItemId Candidate -EntryPath ExportWitness.psm1 -ExpectedFunctions Get-PrivateWitness -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory 'exports-mismatch') -Confirm:$false
Assert-Case 'private function is not mistaken for a real exported function' ($probeMismatch.State -ceq 'Failed' -and $probeMismatch.Qualification -ceq 'Failed')
Write-MigrationFixtureText $probeSource "Import-Module MissingDependencyForExportWitness -ErrorAction Stop`n"
$probeFailure=Test-PowerShellModuleExports -SourceRoot $migrationRoot -PolicyPath $policyPath -ItemId Candidate -EntryPath ExportWitness.psm1 -ExpectedFunctions @() -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory 'exports-import-failure') -Confirm:$false
Assert-Case 'failed import is an explicit failed observation' ($probeFailure.State -ceq 'Failed' -and $null -eq $probeFailure.Observation)

# The full migration gate includes qualification of the checker itself.
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Migration.Dependencies.psm1') -Force
$gateSummary=Join-Path $RunDirectory 'gate-tooling-fixture.json'
$gateFixture=[pscustomobject]@{State=[pscustomobject]@{State='Failed';Failed=1};Categories=@();Sources=@()}
Write-MigrationFixtureText $gateSummary (ConvertTo-Json $gateFixture -Depth 12)
$gate=Test-MigrationQualification -DependencyReportPath $reportPath -ToolingSummaryPath $gateSummary
Assert-Case 'migration gate requires qualified checker and fresh policy' (!$gate.Passed -and 'CheckerQualificationFailed' -cin $gate.Errors -and 'StaleMigrationPolicy' -cin $gate.Errors)
Assert-Case 'migration gate withholds cutover without product restore and recovery evidence' ('MissingProductTestsRestoreRecoveryEvidence' -cin $gate.Errors)

# Local-gallery argument/preview controls never start a server or contact a registry.
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/LocalGallery.Probe.psm1') -Force
$galleryPreview=Join-Path $RunDirectory 'gallery-preview'
$preview=@(Test-LocalGalleryContainer -Image 'example/baget:fixture' -LinuxClientImage 'example/client:fixture' -RunDirectory $galleryPreview -WorkspaceRoot $WorkspaceRoot -WhatIf)
Assert-Case 'localhost gallery WhatIf creates no directory or native process' ($preview.Count -eq 0 -and !(Test-Path -LiteralPath $galleryPreview))
foreach($badImage in @('','bad image','a;command','$(command)','--flag',"name`nother","name`n")){
    $rejected=try{$null=Test-LocalGalleryContainer -Image $badImage -LinuxClientImage 'example/client:fixture' -RunDirectory $galleryPreview -WorkspaceRoot $WorkspaceRoot -WhatIf;$false}catch{$true}
    Assert-Case "malformed gallery image $($cases.Count)" $rejected fuzz
}

# Case-insensitive source extensions are inspected; neither a wildcard nor project conditions imply resolution.
Write-MigrationFixtureText $policyPath (ConvertTo-Json $emptyPolicy -Depth 12)
Write-MigrationFixtureText (Join-Path $emptyPath 'Upper.PS1') 'Import-Module NotDeclared'
$upper=Get-MigrationDependencyReport $migrationRoot $policyPath
Assert-Case 'uppercase PowerShell files remain in migration scope' (@($upper.Files | Where-Object Path -Like '*Upper.PS1').Count -eq 1 -and @($upper.Dependencies | Where-Object Target -EQ NotDeclared).Count -eq 1)

$progressionSource=Get-Content (Join-Path $WorkspaceRoot 'scripts/lib/Roadmap.Progression.psm1') -Raw -Encoding utf8
$resourceGuard='if(@($recipe.resources | Where-Object {$locks.Contains($_)}).Count){continue}'
if(([regex]::Matches($progressionSource,[regex]::Escape($resourceGuard))).Count -ne 1){throw 'ProgressionMutationTargetInvalid'}
$mutantPath=Join-Path $RunDirectory 'ProgressionMutant.psm1'
Copy-Item -LiteralPath $modulePath -Destination (Join-Path $RunDirectory 'Roadmap.Contracts.psm1')
Write-MigrationFixtureText $mutantPath ($progressionSource.Replace($resourceGuard,'if($false){continue}'))
$mutant=Import-Module $mutantPath -PassThru -Force
$observed=& $mutant {param($m,$e) Get-RoadmapExecutionPlan $m $e} $tiny $tinyExec
$killed=$observed.Waves.Count -eq 1
$mutationResults.Add([pscustomobject]@{Name='parallel resource guard';Outcome=if($killed){'Killed'}else{'Survived'};SourceSha256=(Get-FileHash $mutantPath).Hash;Witness='shared resource'})
Assert-Case 'parallel scheduler mutant overlaps independent exclusive resources' $killed mutation
Remove-Module $mutant
Write-WorkspaceJson (Join-Path $RunDirectory 'mutations.json') $mutationResults.ToArray()

# Positive fixture evidence checks gate logic only; it is never published as product migration evidence.
$gatePolicy=Copy-Model $policy;$gatePolicy.items[0].path='gate-simple';$gatePolicy.items[0].approved=$true;$gatePolicy.items[0].intent='Migrate'
Write-MigrationFixtureText (Join-Path $migrationRoot 'gate-simple/main.ps1') "'safe-fixture'"
Write-MigrationFixtureText $policyPath (ConvertTo-Json $gatePolicy -Depth 12)
$gateDependency=Get-MigrationDependencyReport $migrationRoot $policyPath
$gateDependencyPath=Join-Path $RunDirectory 'gate-dependencies-fixture.json'
Export-MigrationDependencyReport $gateDependency $gateDependencyPath -Confirm:$false
$qualifiedFixture=[pscustomobject]@{State=[pscustomobject]@{State='Success';Failed=0};Categories=@(foreach($category in @('property','fuzz','mutation')){[pscustomobject]@{Category=$category;Executed=1;Failed=0}});Sources=@(foreach($name in @('Migration.Dependencies.psm1','Migration.Exports.psm1')){$path=Join-Path $WorkspaceRoot ('scripts/lib/'+$name);[pscustomobject]@{Path=$path;Sha256=(Get-FileHash -LiteralPath $path).Hash}})}
Write-MigrationFixtureText $gateSummary (ConvertTo-Json $qualifiedFixture -Depth 16)
$receiptPath=Join-Path $RunDirectory 'gate-receipt-fixture.json'
$artifactPath=Join-Path $RunDirectory 'gate-artifact-fixture.txt'
Write-MigrationFixtureText $artifactPath 'fixture evidence, not real product acceptance'
$artifact=[pscustomobject]@{Path=$artifactPath;Sha256=(Get-FileHash -LiteralPath $artifactPath).Hash}
$receipt=[pscustomobject]@{DependencyReportSha256=(Get-FileHash -LiteralPath $gateDependencyPath).Hash;Tests=[pscustomobject]@{State='Passed';Artifacts=@($artifact)};Restore=[pscustomobject]@{State='Passed';Artifacts=@($artifact)};Recovery=[pscustomobject]@{State='Passed';Artifacts=@($artifact)}}
Write-MigrationFixtureText $receiptPath (ConvertTo-Json $receipt -Depth 16)
Assert-Case 'complete fresh fixture evidence satisfies gate shape and freshness' ((Test-MigrationQualification $gateDependencyPath $gateSummary -AcceptanceReceiptPath $receiptPath).Passed)
Write-MigrationFixtureText $artifactPath 'changed fixture evidence'
$stale=Test-MigrationQualification $gateDependencyPath $gateSummary -AcceptanceReceiptPath $receiptPath
Assert-Case 'changed acceptance artifacts invalidate the gate' (!$stale.Passed -and 'AcceptanceArtifactChanged:Restore' -cin $stale.Errors)
