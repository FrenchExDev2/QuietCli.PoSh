$workspaceHelpers=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1'
if(Test-Path -LiteralPath $workspaceHelpers){. $workspaceHelpers}
. (Join-Path $PSScriptRoot 'Script.Tests.ps1')
. (Join-Path $PSScriptRoot 'Configuration.TestSupport.ps1')
. (Join-Path $PSScriptRoot 'Recall.Large.Tests.ps1')
. (Join-Path $PSScriptRoot 'Recall.Rtk.ps1')
. (Join-Path $PSScriptRoot 'Recall.Tools.ps1')
. (Join-Path $PSScriptRoot 'Recall.Tests.ps1')
. (Join-Path $PSScriptRoot 'ReportPaths.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiDiagnostics.Tests.ps1')
. (Join-Path $PSScriptRoot 'GitHubCi.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiCompanions.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiOptimization.Tests.ps1')
. (Join-Path $PSScriptRoot 'TestCaseMetadata.Tests.ps1')
. (Join-Path $PSScriptRoot 'TestCaseScheduling.Tests.ps1')
$caseMetadataLibrary=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/TestCaseMetadata.psm1'
if(Test-Path -LiteralPath $caseMetadataLibrary){Import-Module $caseMetadataLibrary -ErrorAction Stop}
$caseSchedulingLibrary=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/TestCaseScheduling.psm1'
if(Test-Path -LiteralPath $caseSchedulingLibrary){Import-Module $caseSchedulingLibrary -ErrorAction Stop}
. (Join-Path $PSScriptRoot 'ReadyToRun.Tests.ps1')
. (Join-Path $PSScriptRoot 'AutomationContracts.Tests.ps1')
. (Join-Path $PSScriptRoot 'EnvFile.Tests.ps1')
. (Join-Path $PSScriptRoot 'PullRequestUpdates.Tests.ps1')
. (Join-Path $PSScriptRoot 'DevelopmentWorkstation.Tests.ps1')
. (Join-Path $PSScriptRoot 'Emit.Tests.ps1')
. (Join-Path $PSScriptRoot 'WorkspaceProjects.Tests.ps1')
. (Join-Path $PSScriptRoot 'CommitWorkspace.Tests.ps1')
. (Join-Path $PSScriptRoot 'RuntimeDiagnosis.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiImageRecipe.Tests.ps1')
. (Join-Path $PSScriptRoot 'WorkstationResources.Tests.ps1')
. (Join-Path $PSScriptRoot 'EditorExtensions.Tests.ps1')
#requires -Version 7.6
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Performance.Tests.ps1')
. (Join-Path $PSScriptRoot 'Import.Tests.ps1')
. (Join-Path $PSScriptRoot 'Status.Aggregation.ps1')
. (Join-Path $PSScriptRoot 'Status.Controlled.Tests.ps1')
. (Join-Path $PSScriptRoot 'Integration.Gate.Tests.ps1')
. (Join-Path $PSScriptRoot 'Evidence.Tests.ps1')
. (Join-Path $PSScriptRoot 'HostMatrix.Tests.ps1')
. (Join-Path $PSScriptRoot 'SecondPass.Tests.ps1')
. (Join-Path $PSScriptRoot 'Control.Tests.ps1')
. (Join-Path $PSScriptRoot 'CoreMigration.Tests.ps1')
. (Join-Path $PSScriptRoot 'ConfigurationDelivery.Tests.ps1')
. (Join-Path $PSScriptRoot 'AgentInstructions.Tests.ps1')
function Assert-QuietEqual {
    <#
.SYNOPSIS
Asserts an independently known expected value with an actionable failure.
    .PARAMETER Actual
    Observed value.
    .PARAMETER Expected
    Independent expectation.
    .PARAMETER Because
    Invariant being checked.
    #>
    param([AllowNull()]$Actual,[AllowNull()]$Expected,[string]$Because='Values must match')
    if($Actual -cne $Expected){throw "$Because : expected <$Expected>, observed <$Actual>"}
}
function Invoke-QuietConformance {
    <#
.SYNOPSIS
Checks the shared envelope invariants without serializing business values.
    .PARAMETER Result
    Result returned by a candidate handler.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$Result)
    Assert-QuietEqual $Result.PSObject.TypeNames[0] 'QuietCli2.Result'
    Assert-QuietEqual $Result.Execution.State 'Finalized'
    Assert-QuietEqual $Result.Measurement.OutputBytes $null 'AsObject must not invent a serialized size'
    Assert-QuietEqual $Result.Deliveries.Count 0 'AsObject must not serialize a delivery'
    foreach($source in $Result.Internal.Sources.Values){if($source.Contains('Capture') -or $source.Contains('Stdout') -or $source.Contains('Stderr')){throw 'Raw native output retained in source metadata'}}
}
function Invoke-QuietCoreTests {
    <#
.SYNOPSIS
Executes independent native byte and object invariants in a companion module.
    .PARAMETER OnProgress
    Callback receiving name, state, passed and failed counters.
    .PARAMETER WorkspaceRoot
    Workspace containing the engine and independent fixture.
    .PARAMETER RunDirectory
    Existing shared report directory, including mandatory controlled fixture evidence.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[string]$RunDirectory)
    if(!$RunDirectory){
        . (Join-Path $WorkspaceRoot 'scripts/ReportPaths.ps1')
        $RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'integration') ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($RunDirectory)
    }
    $integration=[Collections.Generic.List[object]]::new()
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    if(!(Test-Path -LiteralPath $fixture)){throw 'Build the independent C# fixture first.'}
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $performance=[Collections.Generic.List[object]]::new()
    $galleryEvidence=[Collections.Generic.List[object]]::new()
    $testScope=@{TtyExcluded=0}
    $cases=[ordered]@{}
    $cases['test case classifications are complete explicit and fail closed before filtering']={Test-QuietCaseMetadata -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['test execution declarations preserve barriers and bounded isolated workers']={Test-QuietCaseScheduling -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['CI optimization preserves Core prerequisites, parallel isolation and qualified checkpoints']={Test-QuietCiOptimization -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['CI failure regressions reject empty Docker parents and skipped profiling uploads']={Test-QuietCiFailureRegression -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['unit byte-count parsing validates sizes without filesystem or process effects']={Test-QuietByteCountParsing}
    $cases['native Emit listeners preserve Unicode order and bounded JSON/YAML deliveries']={Test-QuietEmitListeners -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['workspace project discovery keeps suite modes and package publication policy separate']={Test-QuietWorkspaceProjects -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['commit workspace documentation gates, script/doc drift and the -WhatIf/commit-once/no-remote contract']={Test-QuietCommitWorkspace -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['container runtime diagnosis separates image bootstrap from ABI and RID selection']={Test-QuietRuntimeDiagnosis -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['Alpine image recipe installs locked PowerShell and separates its runtime from the SDK']={Test-QuietCiImageRecipe -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['configuration and unique tokenized deliveries preserve their contracts']={
        $configuration=Invoke-QuietConfigurationDeliveryTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($configuration.Failed){throw ($configuration.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 8 -Compress)}
    }
    $cases['reusable scripts, factories and literal property regressions']={
        $scriptTests=Invoke-QuietScriptTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($scriptTests.Failed){throw ($scriptTests.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 8 -Compress)}
    }
    $cases['Recall capture and offline analysis regressions']={
        $recall=Invoke-QuietRecallTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        $testScope.TtyExcluded+=$recall.TtyExcluded
        if($recall.Failed){throw ($recall.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 12 -Compress)}
    }
    $cases['protocol configuration preserves bounds using host .NET APIs']={
        $performance.Add((& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
            param($tests,$workspace)
            . $tests
            Test-QuietProtocolSpecification -WorkspaceRoot $workspace
        } (Join-Path $PSScriptRoot 'ProtocolSpecification.Tests.ps1') $WorkspaceRoot))
    }
    $cases['direct status callbacks preserve generated Unicode record digests']={$performance.Add((Test-QuietStatusAggregation))}
    $cases['fresh sessions measure inert Core import against a paired baseline']={$performance.Add((Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot))}
    $cases['CI evidence preserves binary traces and rejects tampered mandatory profiles']={$performance.Add((Test-QuietEvidenceBundle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory))}
    $cases['mandatory integration receipts reject damaged evidence and targeted gate mutants']={$performance.Add((Test-QuietCoreIntegrationGate -WorkspaceRoot $WorkspaceRoot))}
    $cases['import diagnostics retain independent first-use controls']={$performance.Add((Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot))}
    $cases['owned complex repositories use only Core callbacks and exact state oracles']={$integration.Add((Invoke-QuietControlledStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory))}
    $cases['local report paths isolate workspaces and preserve CI upload contracts']={Test-QuietReportPaths -WorkspaceRoot $WorkspaceRoot}
    $cases['development workstation host properties and installer policy mutations']={Test-QuietDevelopmentWorkstation -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['workstation resources preserve active owners and reject foreign cleanup']={Test-QuietWorkstationResources -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['editor extension inventories preserve update and WhatIf contracts']={Test-QuietEditorExtensions -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['source identity includes profile helpers and excludes generated libraries']={
        . (Join-Path $WorkspaceRoot 'scripts/SourceIdentity.ps1')
        $directory=Join-Path $RunDirectory 'source-library-fixture'
        $expected=[Collections.Generic.List[string]]::new()
        foreach($index in 1..16){
            $relative='scripts/lib/module-é漢-'+$index+'.psm1'
            $path=Join-Path $directory $relative
            [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            [void][IO.File]::WriteAllTextAsync($path,('# helper '+$index+"`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $expected.Add($relative)
        }
        foreach($relative in @('Core/lib/generated.dll','scripts/bin/generated.dll','scripts/obj/generated.dll','artifacts/result.json','.git/private')){
            $path=Join-Path $directory $relative
            [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            [void][IO.File]::WriteAllTextAsync($path,'excluded',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }
        $oracle={
            param($subject)
            $observed=@(& $subject -Root $directory)
            Assert-QuietEqual (($observed.Path|Sort-Object) -join '|') (($expected|Sort-Object) -join '|')
        }
        & $oracle (Get-Command Get-QuietSourceFiles)
        foreach($relative in $expected){
            $before=Get-QuietManifestDigest @(Get-QuietSourceFiles $directory)
            [void][IO.File]::AppendAllTextAsync((Join-Path $directory $relative),"# changed`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if((Get-QuietManifestDigest @(Get-QuietSourceFiles $directory)) -ceq $before){throw 'HelperChangeMissingFromSourceIdentity'}
        }
        $source=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts/SourceIdentity.ps1') -Raw -Encoding utf8
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
        $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-QuietSourceFiles'},$true).Extent.Text
        $anchor="if(`$item.Name -eq 'lib' -and `$item.FullName -ne (Join-Path `$rootPath 'scripts/lib')){continue}"
        if(!$function.Contains($anchor)){throw 'SourceIdentityMutationAnchorMissing'}
        foreach($replacement in @("if(`$item.Name -eq 'lib'){continue}",'')){
            $killed=$false
            try{& {param($definition) . ([scriptblock]::Create($definition)); & $oracle (Get-Command Get-QuietSourceFiles)} ($function.Replace($anchor,$replacement))}catch{$killed=$true}
            Assert-QuietEqual $killed $true 'Both omitted source helpers and included generated libraries must be detected'
        }
    }
    $cases['Core migration preserves metadata and compares local helper costs']={foreach($sample in Measure-QuietCoreMigration -Dotnet $dotnet){$performance.Add($sample)}}
    $cases['typed controls preserve duplex bytes and request rejection in both hosts']={Test-QuietTypedControls -Fixture $fixture -Dotnet $dotnet}
    $cases['typed controls measure local JSON avoidance with identical stdin']={foreach($sample in Measure-QuietTypedControls -Fixture $fixture -Dotnet $dotnet){$performance.Add($sample)}}
    $cases['compiled text framing and gain reports preserve their contracts']={foreach($sample in Invoke-QuietSecondPassChecks -WorkspaceRoot $WorkspaceRoot){$performance.Add($sample)}}
    $cases['Gallery preserves prerelease labels and keeps numeric manifest versions separate']={
        & {
            param($scripts)
            . (Join-Path $scripts Common.ps1);. (Join-Path $scripts Gallery.ps1)
            foreach($label in @('preview','preview1','beta2')){
                $manifest=@{ModuleVersion='2.3.4';PrivateData=@{PSData=@{Prerelease=$label}}}
                if((Get-QuietGalleryModuleVersion $manifest) -cne ('2.3.4-'+$label)){throw 'GalleryPrereleaseSuffixLost'}
            }
            if((Get-QuietGalleryModuleVersion @{ModuleVersion='2.3.4'}) -cne '2.3.4'){throw 'StableGalleryVersionChanged'}
            foreach($invalid in @('2.3.4-','2.3.4-preview.1','2.3.4-preview/other','2.3.4+build','2.3')){
                $rejected=$false;try{$null=Get-QuietGalleryVersion $invalid}catch{$rejected=$_.Exception.Message -eq 'GalleryReleaseVersionMismatch'}
                if(!$rejected){throw ('UnsafeGalleryVersionAccepted: '+$invalid)}
            }
        } (Join-Path $WorkspaceRoot scripts)
    }
    $cases['Gallery previews preserve source identities, Core-only packages and offline publication boundaries']={
        . (Join-Path $PSScriptRoot 'GalleryPreview.Tests.ps1')
        $previewSummary=Invoke-QuietGalleryPreviewTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($previewSummary.Failed){throw ($previewSummary.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 5 -Compress)}
    }
    $cases['CI requires stable net10 and preview net11 integrated hosts on x64 and ARM64']={Assert-QuietHostMatrix $WorkspaceRoot}
    $cases['managed target follows the actual CLR including preview and future hosts']={
        $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
        & $core {
            foreach($major in @(10,11,12)){
                $target=Resolve-QuietManagedTarget -RuntimeMajor $major
                $expected=if($major -eq 10){'net10.0'}else{'net11.0'}
                if($target.Framework -cne $expected){throw 'ManagedRuntimeSelectionMismatch'}
            }
            $rejected=$false;try{$null=Resolve-QuietManagedTarget -RuntimeMajor 9}catch{$rejected=$true}
            if(!$rejected){throw 'IncompatibleHostAccepted'}
        }
        $identity=Get-QuietEngine
        if($identity.Mode -eq 'InProcess'){
            $expected=if([Environment]::Version.Major -ge 11){'.NETCoreApp,Version=v11.0'}else{'.NETCoreApp,Version=v10.0'}
            Assert-QuietEqual $identity.Engine.TargetFramework $expected
            Assert-QuietEqual $identity.Engine.ProcessId $PID
        }
    }
    $cases['compiled framing and direct engine measure local overhead independently']={
        foreach($sample in Measure-QuietLocalOverhead -Fixture $fixture -Dotnet $dotnet){$performance.Add($sample)}
    }
    $cases['CI failure diagnostics preserve redaction bounds and explicit local workflow selection']={Test-QuietCiDiagnostics -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['GitHub CI separates native containers, Docker fallback and workstation launchers']={Test-QuietGitHubCi -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['CI companion declarations separate integration suites and scale without workflow branches']={Test-QuietCiCompanions -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['GitHub CI JSON receipts create missing parents and preserve preview boundaries']={Test-QuietGitHubCiJsonReceipts -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['GitHub CI companion helpers load privately without caller profile dependencies']={Test-QuietCompanionHelperScope -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['GitHub CI container inputs include docs and restored packages without secrets or path escapes']={Test-QuietContainerInputs -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['solution build catalogue discovers new consumers and rejects malformed distributions']={Test-QuietWorkspaceBuildProjects -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['ReadyToRun builds and loads the matching RID and CLR with portable fallbacks']={Test-QuietReadyToRun -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['automation contracts require available runtimes accurate workflow graphs and safe previews']={Test-QuietAutomationContracts -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['configuration dotenv preserves literals and deterministic local GitHub presets']={Test-QuietEnvFiles -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['GitHub PR push updates preserve previews remote routing and checkpoint identity']={Test-QuietPullRequestUpdates -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['automation report streaming preserves Unicode fragments and bounded diagnostic tails']={Test-QuietReportStreaming -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['automation objective comments are inert and library loading stays silent']={Test-QuietObjectiveOutput -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['automation resource and script review gates inspect the prepared index']={Test-QuietResourceCommitChecks -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['explicit event collection compiled properties and targeted mutations']={
        . (Join-Path $PSScriptRoot ConfigurationDelivery.Mutation.ps1)
        $result=Invoke-QuietConfigurationDeliveryEngine -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory event-collection) -Mutation -MutationName @('emit-events-not-recorded','emit-unrequested-recording') -OnProgress {param($name,$state,$passed,$failed)Write-Host ('Mutation: '+$name+'; state='+$state+'; assertions='+$passed+'; failures='+$failed)}
        Write-WorkspaceJson (Join-Path $RunDirectory event-collection/campaign.json) $result
        if($result.Failed){throw 'ExplicitEventCollectionMutationFailed'}
    }
    $cases['automation commit pipeline checks staged workflow and preview contracts']={Test-QuietAutomationCommitChecks -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
    $cases['CI process execution is independent and preserves streams failures stdin and deadlines']={
        . (Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1')
        $state=@{stdout='';stderr=''}
        $r=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-Command','[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::Out.Write("sortie-é"); [Console]::Error.Write("diagnostic-λ"); exit 7') -State $state -OnOutput {param($e,$s)$s[$e.Stream]+=$e.Text}
        if($state.stdout -cne 'sortie-é' -or $state.stderr -cne 'diagnostic-λ'){
            $probe=@{Json=[Text.StringBuilder]::new()}
            $probeResult=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-Command','ConvertTo-Json -Compress -InputObject @{PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();OutputCodePage=[Console]::OutputEncoding.CodePage;InputCodePage=[Console]::InputEncoding.CodePage;OutputPreambleHex=[Convert]::ToHexString([Console]::OutputEncoding.GetPreamble());FixtureHex=[Convert]::ToHexString([Console]::OutputEncoding.GetBytes("sortie-é"))}') -State $probe -OnOutput {param($e,$s)if($e.Stream -eq 'stdout' -and $s.Json.Length -lt 2048){[void]$s.Json.Append($e.Text)}}
            $diagnostic=@{Runner=(Get-Command pwsh -CommandType Application).Source;ParentPowerShell=$PSVersionTable.PSVersion.ToString();ParentOutputCodePage=[Console]::OutputEncoding.CodePage;ReaderCodePage=65001;ProbeOutcome=$probeResult.Outcome;Child=$probe.Json.ToString();Stdout=$state.stdout;Stderr=$state.stderr;DecodedStdoutUtf8Hex=[Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes($state.stdout));DecodedStderrUtf8Hex=[Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes($state.stderr));ExpectedStdout='sortie-é';ExpectedStderr='diagnostic-λ';NativeExitCode=$r.ExitCode}
            Write-WorkspaceJson (Join-Path $RunDirectory 'ci-process-encoding-diagnostics.json') $diagnostic
            Write-Host ('CI encoding diagnostic: '+($diagnostic|ConvertTo-Json -Depth 4 -Compress))
        }
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.ExitCode 7
        Assert-QuietEqual $state.stdout 'sortie-é'
        Assert-QuietEqual $state.stderr 'diagnostic-λ'
        $state=@{Text=''}
        $r=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-Command','$value=[Console]::In.ReadToEndAsync().GetAwaiter().GetResult(); [Console]::Out.Write($value)') -InputText 'ci-stdin-sentinel' -State $state -OnOutput {param($e,$s)$s.Text+=$e.Text}
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $state.Text 'ci-stdin-sentinel'
        if(($r|ConvertTo-Json -Compress) -like '*ci-stdin-sentinel*'){throw 'CI process metadata exposed stdin'}
        $raw=@{Hex=''}
        $r=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-Command','$memory=[IO.MemoryStream]::new(); [void][Console]::OpenStandardInput().CopyToAsync($memory).GetAwaiter().GetResult(); [Console]::Out.Write([Convert]::ToHexString($memory.ToArray())); $memory.Dispose()') -InputText 'é' -State $raw -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Hex+=$e.Text}}
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $raw.Hex 'C3A9' 'CI stdin must preserve UTF-8 bytes without a BOM prefix'
        $r=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-Command','[Threading.Tasks.Task]::Delay(30000).GetAwaiter().GetResult()') -TimeoutSeconds 1 -OnOutput {param($e,$s)}
        Assert-QuietEqual $r.Outcome Timeout
    }
    $cases['every native property fuzz and mutation phase is mandatory for delivery']={
        . (Join-Path $WorkspaceRoot 'scripts/Assert-PtyQualification.ps1')
        $good=@{State=@{State='Success'};Baseline=@{State='Success';Assertions=43;PropertyGroups=6;Failed=0};Fuzz=@{State='Success';RequestedRuns=20000;ExecutedRuns=20000};Mutation=@{Selected=31;Killed=31;Survived=0;Invalid=0;Timeout=0;Error=0}}
        Assert-PtyQualification $good
        foreach($change in @(
            {param($s)$s.State.State='Failed'},
            {param($s)$s.Baseline.State='NotRun'},
            {param($s)$s.Baseline.Assertions=42},
            {param($s)$s.Baseline.PropertyGroups=5},
            {param($s)$s.Baseline.Failed=1},
            {param($s)$s.Fuzz.State='NotRequested'},
            {param($s)$s.Fuzz.State='Timeout'},
            {param($s)$s.Fuzz.ExecutedRuns=19999},
            {param($s)$s.Fuzz.ExecutedRuns=$null},
            {param($s)$s.Fuzz.RequestedRuns=1000;$s.Fuzz.ExecutedRuns=1000},
            {param($s)$s.Mutation.Selected=0;$s.Mutation.Killed=0},
            {param($s)$s.Mutation.Selected=30;$s.Mutation.Killed=30},
            {param($s)$s.Mutation.Killed=30;$s.Mutation.Survived=1},
            {param($s)$s.Mutation.Invalid=1},
            {param($s)$s.Mutation.Timeout=1},
            {param($s)$s.Mutation.Error=1}
        )){
            $candidate=$good|ConvertTo-Json -Depth 8|ConvertFrom-Json
            & $change $candidate
            $rejected=$false;try{Assert-PtyQualification $candidate}catch{$rejected=$_.Exception.Message -like 'NativeQualificationIncomplete*'}
            Assert-QuietEqual $rejected $true 'No missing or failed validation phase may authorize a delivery'
        }
    }
    $cases['native mutation refuses a mismatched guest before invoking a compiler']={
        $directory=Join-Path $WorkspaceRoot ('artifacts/mutation-platform-tests/'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        $actual=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        $wrong=if($actual -ceq 'linux-arm64'){'linux-x64'}else{'linux-arm64'}
        $script=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1'
        . (Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1')
        $r=Invoke-CiProcess -FilePath pwsh -ArgumentList @('-File',$script,'-WorkspaceRoot',$WorkspaceRoot,'-RunDirectory',$directory,'-CompilerPath','missing-compiler-must-not-run','-ExpectedRuntimeIdentifier',$wrong,'-Worker') -TimeoutSeconds 60 -OnOutput {param($e,$s)}
        Assert-QuietEqual $r.Outcome Failed
        $summary=Get-Content (Join-Path $directory 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
        if($summary.State.Error -notlike '*NativeMutationRuntimeMismatch*'){throw 'Wrong guest was not rejected before compiler discovery'}
        Assert-QuietEqual $summary.Mutation.Selected 0
        Assert-QuietEqual (Test-Path (Join-Path $directory 'inputs.json')) $false
    }
    $cases['release gate rejects failed skipped cancelled or incomplete required jobs']={
        $directory=Join-Path $WorkspaceRoot ('artifacts/gate-tests/'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        $script=Join-Path $WorkspaceRoot 'scripts/Assert-QualificationGate.ps1'
        $revision='1234567890abcdef1234567890abcdef12345678'
        foreach($skipTty in @($false,$true)){
        foreach($suite in @('All','Core','Git')){
            foreach($job in @('WindowsResult','LinuxResult','MutationResult')){
                foreach($result in @('success','failure','cancelled','skipped','')){
                    $expectedMutation=if($skipTty -or $suite -eq 'Git'){'skipped'}else{'success'}
                    $ready=if($job -eq 'MutationResult'){$result -ceq $expectedMutation}else{$result -ceq 'success'}
                    $id=[guid]::NewGuid().ToString('N')
                    $output=Join-Path $directory ($id+'.output');$receipt=Join-Path $directory ($id+'.json')
                    $arguments=@{Suite=$suite;SkipTty=$skipTty;Revision=$revision;WindowsResult='success';LinuxResult='success';MutationResult=$expectedMutation;ReceiptPath=$receipt;OutputPath=$output}
                    $arguments[$job]=$result
                    $accepted=$false
                    try{& $script @arguments;$accepted=$true}catch{if($ready){throw}}
                    Assert-QuietEqual $accepted $ready 'Only complete required job success may pass'
                    if(Test-Path -LiteralPath $receipt){
                        $decision=Get-Content -LiteralPath $receipt -Encoding utf8 -Raw|ConvertFrom-Json
                        Assert-QuietEqual $decision.MutationRequired (!$skipTty -and $suite -ne 'Git')
                        if($skipTty){Assert-QuietEqual $decision.TtyQualification 'Excluded'}
                    }else{
                        # Mandatory empty arguments are rejected by PowerShell binding before any receipt is written.
                        Assert-QuietEqual $ready $false
                        Assert-QuietEqual $result ''
                    }
                    Assert-QuietEqual (Test-Path $output) $ready 'A rejected revision must have no qualified_sha output'
                    if($ready){Assert-QuietEqual ((Get-Content $output -Encoding utf8 -Raw).Trim()) ('qualified_sha='+$revision)}
                }
            }
        }
        }
    }
    $cases['GitHub CI excludes native TTY campaigns and has no dangling job dependencies']={
        $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
        $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
        foreach($file in Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot '.github/workflows') -Filter '*.yml'){
            $reader=[IO.StringReader]::new([IO.File]::ReadAllTextAsync($file.FullName,[Text.Encoding]::UTF8).GetAwaiter().GetResult())
            try{$workflow=$parser.Deserialize($reader,[object])}finally{$reader.Dispose()}
            $jobs=$workflow['jobs']
            foreach($name in $jobs.Keys){
                if($name -match '(?i)pty|tty'){throw 'NativeTtyJobStillScheduled'}
                foreach($dependency in @($jobs[$name]['needs'])){
                    if($dependency -and !$jobs.ContainsKey($dependency)){throw ('DanglingJobDependency: '+$dependency)}
                }
                foreach($step in @($jobs[$name]['steps'])){
                    if(!$step){continue}
                    $command=[string]$step['run']
                    if($command -match 'Invoke-PtyMutation|Probe-Independent|Invoke-ContainerCi[^\r\n]+-Suite Mutation'){throw 'NativeTtyCampaignStillScheduled'}
                }
            }
            if($file.Name -ceq 'ci.yml'){
                foreach($name in @('windows','linux')){
                    $runs=@($jobs[$name]['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
                    if(!$runs.Contains('SkipTty=$true')){throw ('TtyScopeNotForwarded: '+$name)}
                }
                $gate=@($jobs['qualification-gate']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
                if(!$gate.Contains('-MutationResult skipped -SkipTty')){throw 'TtyGateExclusionNotExplicit'}
                if(@($jobs['qualification-gate']['needs']) -contains 'performance-results' -or $gate -match 'PERFORMANCE_RESULT|PerformanceEvidenceReportRequired'){throw 'OptionalPerformanceBlocksQualification'}
                foreach($trigger in @('workflow_call','workflow_dispatch')){
                    $option=$workflow['on'][$trigger]['inputs']['collect_performance']
                    if(!$option -or $option['type'] -cne 'boolean' -or [string]$option['default'] -cne 'false'){throw 'PerformanceMustBeExplicitlyRequested'}
                }
                if([string]$jobs['performance-results']['if'] -cne '${{ always() && inputs.collect_performance && needs.linux-matrix.outputs.has_core == ''true'' }}'){throw 'PerformanceAggregationNotOptIn'}
                $prepare=@($jobs['windows']['steps']|Where-Object {$_['name'] -ceq 'Prepare checksum-pinned PowerShell and CLR profilers'})
                if($prepare.Count -ne 1 -or [string]$prepare[0]['if'] -cne "needs.linux-matrix.outputs.has_core == 'true' && (inputs.collect_performance || (matrix.rid == 'win-x64' && matrix.channel == 'stable' && matrix.mode == 'InProcess'))" -or !([string]$prepare[0]['run']).Contains('-Module profiler,dottrace')){throw 'RequiredToolingDependenciesNotPrepared'}
                foreach($name in @('windows','linux','linux-test-driver')){
                    $runs=@($jobs[$name]['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
                    if($runs.Contains('if($env:QUIETCLI_SUITE -ne ''Git'')')){throw ('UnconditionalProfiling: '+$name)}
                    $reportSteps=@($jobs[$name]['steps']|Where-Object {$_['run'] -match 'New-CorePerformanceReport.ps1'})
                    if($reportSteps.Count -ne 1 -or [string]$reportSteps[0]['env']['QUIETCLI_COLLECT_PERFORMANCE'] -cne '${{ inputs.collect_performance }}' -or !([string]$reportSteps[0]['run']).Contains('if($env:QUIETCLI_COLLECT_PERFORMANCE -ceq ''true'' -and $env:QUIETCLI_SUITE_HAS_CORE -ceq ''true'')')){throw ('PerformanceReportNotOptIn: '+$name)}
                }
            }
        }
    }
    $cases['CI images cover four native Linux targets and invalidate the cache on recipe changes']={
        & {
            param($root)
            . (Join-Path $root 'scripts/CiImages.ps1')
            $expected=@{
                'linux-x64'=@('debian','x64');'linux-arm64'=@('debian','arm64')
                'linux-musl-x64'=@('alpine','x64');'linux-musl-arm64'=@('alpine','arm64')
            }
            foreach($rid in $expected.Keys){
                $plan=Get-QuietCiImagePlan $root $rid
                if($plan.Platform -cne $expected[$rid][0] -or $plan.Architecture -cne $expected[$rid][1]){throw 'CI image targets the wrong native platform'}
                if(!$plan.Arguments.SDK_URL.EndsWith('-'+$rid+'.tar.gz')){throw 'SDK archive belongs to another architecture/libc'}
                if($plan.Fingerprint -cnotmatch '^[a-f0-9]{64}$'){throw 'Cache identity missing'}
            }
            $copy=Join-Path $root ('artifacts/ci-image-contract/'+[guid]::NewGuid().ToString('N'))
            $files=@('global.json','build/ci-images.lock.json','scripts/CiImages.ps1','scripts/New-CiImage.ps1','FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1')
            $files+=@(Get-ChildItem (Join-Path $root '.github/containers') -File -Force|ForEach-Object {'.github/containers/'+$_.Name})
            foreach($file in $files){$destination=Join-Path $copy $file;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination));Copy-Item -LiteralPath (Join-Path $root $file) -Destination $destination}
            $before=Get-QuietCiImagePlan $copy linux-arm64
            [IO.File]::AppendAllText((Join-Path $copy '.github/containers/fetch-ci-tools.sh'),"`n# synthetic recipe change`n",[Text.UTF8Encoding]::new($false))
            $after=Get-QuietCiImagePlan $copy linux-arm64
            if($before.Fingerprint -ceq $after.Fingerprint){throw 'Changed recipe reused the old registry cache'}
            $lockPath=Join-Path $copy 'build/ci-images.lock.json'
            $lock=Get-Content $lockPath -Encoding utf8 -Raw|ConvertFrom-Json
            ($lock.Platforms|Where-Object Rid -CEQ linux-arm64).SDK_SHA512='invalid'
            [IO.File]::WriteAllText($lockPath,($lock|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
            $rejected=$false
            try{$null=Get-QuietCiImagePlan $copy linux-arm64}catch{$rejected=$_.Exception.Message -ceq 'CiImageDigestInvalid'}
            if(!$rejected){throw 'Unverifiable SDK archive accepted'}
        } $WorkspaceRoot
    }
    $cases['cold engine and warm block-size measurements retain no business output']={
        Stop-QuietEngine
        $cold=[Diagnostics.Stopwatch]::StartNew();$identity=Get-QuietEngine;$cold.Stop()
        $performance.Add(@{Kind='ColdEngine';Milliseconds=$cold.Elapsed.TotalMilliseconds;Runtime=$identity.Engine.Runtime})
        foreach($size in @(4096,16384)){
            $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
            $r=quiet -AsObject -Role Infrastructure -ReadBlockBytes $size -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 8388608
            $elapsed=$watch.Elapsed.TotalMilliseconds;$after=Get-QuietEngine
            Assert-QuietEqual $r.Outcome Success
            Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 8388608
            $performance.Add(@{Kind='WarmStream';ReadBlockBytes=$size;Bytes=8388608;ElapsedMs=$elapsed;NativeMs=$r.Execution.Native.ElapsedMs;CallbackMs=$r.Execution.CallbackMs;ProtocolBytes=($after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes);ProtocolRequests=$after.Requests-$before.Requests;Interpretation='One fixture sample, not a general speed claim.'})
        }
    }
    $cases['build provenance rejects changed binaries and stale source']={
        $directory=Join-Path $WorkspaceRoot ('artifacts/build-provenance/'+[guid]::NewGuid().ToString('N'))
        foreach($folder in @('FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture','FrenchExDev2.QuietCli.Core.PoSh','output')){[void][IO.Directory]::CreateDirectory((Join-Path $directory $folder))}
        $project='FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Synthetic.csproj'
        $files=@{'global.json'='{}';'Directory.Packages.props'='<Project />';'FrenchExDev2.QuietCli.Core.PoSh/protocol.json'='{}';$project='<Project />';'FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Program.cs'='// synthetic source';'output/Synthetic.dll'='synthetic binary'}
        foreach($entry in $files.GetEnumerator()){[void][IO.File]::WriteAllTextAsync((Join-Path $directory $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        & {
            param($scripts,$directory,$project)
            . (Join-Path $scripts 'Common.ps1')
            $inputs=@(Get-QuietBinaryInputs $directory $project)
            Write-QuietBuildManifest $directory $project output -Inputs $inputs
            $null=Test-QuietBuildManifest $directory output
            $packages=Join-Path $directory 'Directory.Packages.props'
            [void][IO.File]::WriteAllTextAsync($packages,'<Project><!-- changed dependency declaration --></Project>',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Test-QuietBuildManifest $directory output}catch{$rejected=$_.Exception.Message -like 'StaleBuild:*'}
            if(!$rejected){throw 'Changed central package declarations were accepted'}
            [void][IO.File]::WriteAllTextAsync($packages,'<Project />',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $binary=Join-Path $directory 'output/Synthetic.dll'
            [void][IO.File]::WriteAllTextAsync($binary,'modified binary',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Test-QuietBuildManifest $directory output}catch{$rejected=$_.Exception.Message -like 'BuildBinaryMismatch:*'}
            if(!$rejected){throw 'Modified binary was accepted'}
            [void][IO.File]::WriteAllTextAsync($binary,'synthetic binary',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Program.cs'),'// modified source',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Test-QuietBuildManifest $directory output}catch{$rejected=$_.Exception.Message -like 'StaleBuild:*'}
            if(!$rejected){throw 'Stale build was accepted'}
        } (Join-Path $WorkspaceRoot 'scripts') $directory $project
    }
    $cases['all six embedded engines have matching native and managed architectures']={
        & {
            param($root)
            . (Join-Path $root 'scripts/Common.ps1')
            $targets=@(Get-QuietRuntimeTargets $root)
            $expected=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')
            if($targets.Count -ne 6 -or @($expected|Where-Object {$_ -cnotin $targets.Rid}).Count){throw 'Release target set incomplete'}
            foreach($target in $targets){
                $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$target.Rid
                $manifest=Test-QuietBuildManifest $root $output
                if($manifest.RuntimeIdentifier -cne $target.Rid -or $manifest.PlatformTarget -cne $target.PlatformTarget){throw 'Compiler target metadata mismatch'}
                Assert-QuietRuntimePublication (Join-Path $root $output) $target
                $configuration=Get-Content -LiteralPath (Join-Path (Join-Path $root $output) 'QuietCli.Engine.runtimeconfig.json') -Encoding utf8 -Raw|ConvertFrom-Json
                [xml]$runtimeProject=Get-Content (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj') -Raw -Encoding utf8
                $expectedRuntime=@($runtimeProject.SelectNodes('//RuntimeFrameworkVersion')|Where-Object {$_.GetAttribute('Condition') -match 'net11\.0'})
                if($expectedRuntime.Count -ne 1 -or $configuration.runtimeOptions.framework.version -cne $expectedRuntime[0].InnerText){throw 'Published engine runtime does not match its source pin'}
            }
        } $WorkspaceRoot
        $identity=Get-QuietEngine
        $hostRid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        $expected=$hostRid
        if($identity.Mode -eq 'InProcess'){
            $directory=if([Environment]::Version.Major -ge 11){'lib/engine'}else{'lib/inprocess'}
            $build=Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/'+$directory+'/build-manifest.json')) -Raw -Encoding utf8|ConvertFrom-Json
            $slots=if($build.PSObject.Properties['ReadyToRunTargets']){@($build.ReadyToRunTargets)}else{@()}
            $expected=if($hostRid -cin $slots){$hostRid}else{'portable'}
        }
        Assert-QuietEqual $identity.Engine.BuildRuntimeIdentifier $expected
    }
    $cases['C# protocol and concurrent SQLite assertions']={
        $assembly=Join-Path $PSScriptRoot 'lib/engine-tests/QuietCli.Engine.Tests.dll'
        $nativeDirectory=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $nativeDirectory
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Passed 67
        Assert-QuietEqual $r.Data.Failed 0
    }
    $cases['PTY reports a merged terminal counter without fake stderr separation']={
        $r=quiet -AsObject -Transport Pty -Data @{Seen=0L;Text=[Text.StringBuilder]::new()} -Output {param($e,$r)$r.Data.Seen+=$e.ByteCount;[void]$r.Data.Text.Append($e.Text)} $dotnet $fixture terminal
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead $null
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead $null
        Assert-QuietEqual $r.Execution.Native.TerminalBytesRead $r.Data.Seen
        if(!$r.Data.Text.ToString().Contains('out') -or !$r.Data.Text.ToString().Contains('err')){throw 'PTY lost stdout or stderr'}
    }
    $cases['exact stdout/stderr counters with no capture']={
        $r=quiet -AsObject -StdoutMode Bytes -StderrMode Bytes -Data @{Seen=0L} -Output {param($e,$r)$r.Data.Seen+=$e.Bytes.Length} $dotnet $fixture mixed 123456 234567
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 123456
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead 234567
        Assert-QuietEqual $r.Data.Seen 358023
        Invoke-QuietConformance $r
    }
    $cases['AsObject does not enumerate or serialize business getters']={
        $business=[pscustomobject]@{Marker='local'}
        $business|Add-Member ScriptProperty Forbidden {throw 'Business object was enumerated for measurements'}
        $r=quiet -AsObject -Data $business -Output {param($e,$r)} $dotnet $fixture emit 10
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual ([object]::ReferenceEquals($r.Data,$business)) $true
        Invoke-QuietConformance $r
    }
    $cases['large output retains only bounded transport blocks']={
        $before=[GC]::GetTotalMemory($true)
        $r=quiet -AsObject -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 67108864
        $after=[GC]::GetTotalMemory($true)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 67108864
        if($after-$before -gt 33554432){throw 'Managed memory grew proportionally to discarded output'}
        Invoke-QuietConformance $r
    }
    $cases['nested callback inherits context without serializing child objects']={
        $r=quiet -AsObject -C nested -Data @{Child=$null} -Output {param($e,$r)if(!$r.Data.Child){$r.Data.Child=quiet -AsObject -Data @{Bytes=0L} -StdoutMode Bytes -Output {param($e,$r)$r.Data.Bytes+=$e.Bytes.Length} $dotnet $fixture emit 29}} $dotnet $fixture emit 17
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Child.Context nested
        Assert-QuietEqual $r.Data.Child.Data.Bytes 29
        Assert-QuietEqual $r.Execution.Children 1
        Assert-QuietEqual $r.Internal.Sources.Count 2
        Invoke-QuietConformance $r.Data.Child
    }
    $cases['assigned child failure remains visible']={
        $r=quiet -AsObject -Output {param($e,$r)$child=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture fail} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Execution.Issues.Count 1
    }
    $cases['context is not sticky across independent invocations']={
        $named=quiet -AsObject -C named -Output {param($e,$r)} $dotnet $fixture emit 1
        $generic=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $named.Context named
        Assert-QuietEqual $generic.Context $null
    }
    $cases['stdin bytes are exact and output is drained while feeding']={
        $bytes=[byte[]]::new(1048576);[Random]::new(42).NextBytes($bytes)
        $r=quiet -AsObject -InputBytes $bytes -Data @{Hash=[Text.StringBuilder]::new()} -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Hash.Append($e.Text)}} -Complete {param($r) @{Hash=$r.Data.Hash.ToString()}} $dotnet $fixture hash
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdinBytesWritten $bytes.Length
        Assert-QuietEqual $r.Data.Hash ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
    }
    $cases['UTF8 and NUL framing preserve split Unicode characters']={
        $r=quiet -AsObject -RecordDelimiter ([string][char]0) -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add($e.Text)} $dotnet $fixture unicode
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 2
        Assert-QuietEqual $r.Data[0] 'é漢🙂'
        Assert-QuietEqual $r.Data[1] 'fin'
    }
    $cases['truncated UTF8 fails analysis rather than dropping bytes']={
        $r=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture invalid
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 1
    }
    $cases['Complete runs once after Output failure and native drain']={
        $state=@{Calls=0}
        $r=quiet -AsObject -State $state -Output {param($e,$r)throw 'expected parser failure'} -Complete {param($r)$r.State.Calls++} $dotnet $fixture emit 131072
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $state.Calls 1
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 131072
    }
    $cases['accidental Output emission never becomes business Data']={
        $r=quiet -AsObject -Data @{Kept=$true} -Output {param($e,$r)'accidental'} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Data.Kept $true
    }
    $cases['timeout preserves partial native state']={
        $r=quiet -AsObject -TimeoutSeconds 0.3 -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Timeout
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['interactive cancellation affects only the owned child']={
        $r=quiet -AsObject -Interaction {param($r)$r.Cancel()} -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Cancelled
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['delimiter overflow fails analysis and still drains bytes']={
        $r=quiet -AsObject -RecordDelimiter "`n" -MaxRecordBytes 64 -Output {param($e,$r)} $dotnet $fixture emit 20000
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 20000
    }
    $cases['native arguments preserve empty strings spaces and Unicode']={
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)[void]$r.Data.Append($e.Text)} -Complete {param($r),@($r.Data.ToString()|ConvertFrom-Json)} $dotnet $fixture args '' 'a b' 'é🙂' '--native'
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 4
        Assert-QuietEqual $r.Data[0] ''
        Assert-QuietEqual $r.Data[2] 'é🙂'
    }
    $cases['delivery is bounded and AsObject remains unserialized until requested']={
        $r=quiet -AsObject -Data @{Values=@(1..100)} -Output {param($e,$r)} $dotnet $fixture emit 2000
        Assert-QuietEqual $r.Deliveries.Count 0
        $json=$r|ConvertTo-QuietJson -MaxItems 5 -MaxOutputBytes 1024
        $doc=$json|ConvertFrom-Json
        Assert-QuietEqual $doc.Data.Values.Count 5
        Assert-QuietEqual $doc.Truncation.Applied $true
        Assert-QuietEqual $r.Data.Values.Count 100
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($json))
        Assert-QuietEqual $r.Deliveries[0].Text $json
    }
    $cases['empty singleton and nested arrays preserve JSON shape']={
        $r=quiet -AsObject -Data @{Empty=@();One=@(7);Nested=@(@(1,2),@(3,4));Nothing=$null;Object=@{}} -Output {param($e,$r)} $dotnet $fixture emit 1
        $json=$r|ConvertTo-QuietJson
        $doc=$json|ConvertFrom-Json -AsHashtable
        Assert-QuietEqual ($doc.Data.Empty -is [array]) $true
        Assert-QuietEqual $doc.Data.Empty.Count 0
        Assert-QuietEqual $doc.Data.One.Count 1
        Assert-QuietEqual $doc.Data.Nested[0].Count 2
        Assert-QuietEqual $doc.Data.Nothing $null
    }
    $cases['bounded delivery preserves failure identity without serializing omitted business data']={
        $r=quiet -AsObject -Data @{Large=('é'*5000)} -Output {param($e,$r)throw ('diagnostic '*1000)} $dotnet $fixture emit 10
        $json=$r|ConvertTo-QuietJson -MaxOutputBytes 300
        $document=$json|ConvertFrom-Json
        Assert-QuietEqual $document.Outcome Failed
        Assert-QuietEqual $document.Error.Code OutputCallbackFailed
        Assert-QuietEqual $document.Truncation.Applied $true
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 300){throw 'Failure envelope exceeded the final budget'}
    }
    $cases['generic and named gain filters are independent']={
        $named=Get-QuietCliGain -C named -AsObject
        $generic=Get-QuietCliGain -Generic -AsObject
        if($named.Invocations -lt 1 -or $generic.Invocations -lt 1){throw 'Expected persisted named and generic invocations'}
        Assert-QuietEqual $named.RootDeliveryBytes $null
    }
    $cases['delivery token count observes produced text only']={
        $r=quiet -AsObject -Data @{Message='évidence'} -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Measurement.OutputTokens $null
        $text=Out-QuietResult -InputObject $r -Tokenizer o200k_base
        if($r.Measurement.OutputTokens -le 0){throw 'Exact delivery tokenizer was not applied'}
        Assert-QuietEqual $r.Measurement.NativeTokens $null
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($text))
    }
    $cases['production agent instructions preserve project rules and installed resources']={
        $agentReport=Invoke-QuietAgentInstructionTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        $integration.Add($agentReport)
        if($agentReport.Failed){throw ('AgentInstructionQualificationFailed: '+($agentReport.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Compress))}
    }
    $cases['module scaffolding creates inert handlers and independent failing test companions']={
        $parent=Join-Path $WorkspaceRoot ('artifacts/scaffold-tests/'+[guid]::NewGuid().ToString('N'))
        $name='Sample.QuietTool.PoSh'
        $generated=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent
        $manifest=Import-PowerShellDataFile (Join-Path $generated.Module ($name+'.psd1'))
        Assert-QuietEqual $manifest.RequiredModules.Count 1
        Assert-QuietEqual $manifest.RequiredModules[0].ModuleName FrenchExDev2.QuietCli.Core.PoSh
        $testName='Sample.QuietTool.Tests.PoSh'
        $testManifest=Import-PowerShellDataFile (Join-Path $generated.Tests ($testName+'.psd1'))
        Assert-QuietEqual $testManifest.RequiredModules.Count 2
        $module=Import-Module (Join-Path $generated.Module ($name+'.psd1')) -PassThru
        try{
            $catalogue=@(Get-QuietHandler -Binary quietfixture)
            Assert-QuietEqual $catalogue.Count 1
            Assert-QuietEqual $catalogue[0].Qualification NotImplemented
            $errors=$null;$tokens=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $generated.Tests ($testName+'.psm1')),[ref]$tokens,[ref]$errors)
            Assert-QuietEqual $errors.Count 0
            $function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
            if(!$function.GetHelpContent()){throw 'Generated test entry point has no readable help'}
            $rejected=$false
            try{$null=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent}catch{$rejected=$_.Exception.Message -eq 'ModuleDestinationExists'}
            Assert-QuietEqual $rejected $true
        }finally{Remove-Module $module}
        Assert-QuietEqual @(Get-QuietHandler -Binary quietfixture).Count 0
    }
    $cases['monitor duration preserves November timestamps in French and English cultures']={
        . (Join-Path $WorkspaceRoot 'scripts/Monitor.Time.ps1')
        $culture=[Globalization.CultureInfo]::CurrentCulture
        try{
            foreach($name in @('fr-FR','en-US')){
                [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($name)
                $start=[DateTimeOffset]::Parse('2026-11-04T20:00:00Z',[Globalization.CultureInfo]::InvariantCulture)
                $end=$start.AddSeconds(125)
                foreach($value in @($start,$start.UtcDateTime,'2026-11-04T20:00:00Z')){
                    Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $value -Now $end) 2m5s
                    Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $value -FinishedUtc $end -Now $end.AddDays(207)) 2m5s
                }
                $decoded='{"StartedUtc":"2026-11-04T20:00:00Z","FinishedUtc":"2026-11-04T20:02:05Z"}'|ConvertFrom-Json
                Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $decoded.StartedUtc -FinishedUtc $decoded.FinishedUtc) 2m5s
            }
        }finally{[Globalization.CultureInfo]::CurrentCulture=$culture}
    }
    $cases['PowerShell functions have readable help and sources parse without errors']={
        . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
        $paths=@(@(Get-QuietSourceFiles $WorkspaceRoot)|ForEach-Object {Join-Path $WorkspaceRoot $_.Path})+@(Join-Path $WorkspaceRoot 'repositories.lock.json')
        foreach($path in $paths){
            $bytes=[IO.File]::ReadAllBytesAsync($path).GetAwaiter().GetResult()
            if([Array]::IndexOf($bytes,[byte]0) -ge 0){continue}
            try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{continue}
            if($text.Contains("`r")){throw ('RepositoryTextMustUseLF: '+[IO.Path]::GetRelativePath($WorkspaceRoot,$path))}
        }
        $jsonPath=Join-Path $WorkspaceRoot ('artifacts/lf-writer/'+[guid]::NewGuid().ToString('N')+'.json')
        [void][IO.Directory]::CreateDirectory((Split-Path $jsonPath -Parent))
        $random=[Random]::new(72055)
        foreach($iteration in 1..64){
            $value="é漢 $($random.Next())`r`nvalue`rnext"
            Write-WorkspaceJson $jsonPath @{Value=$value;Empty='';Items=@(1,2)}
            $written=[IO.File]::ReadAllTextAsync($jsonPath,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            if($written.Contains("`r") -or ($written|ConvertFrom-Json).Value -cne $value){throw 'JsonWriterLineEndingsOrValueChanged: seed 72055'}
        }
        $directories=@((Get-QuietWorkspaceProjects $WorkspaceRoot).Path)+@('scripts')
        foreach($directory in $directories){
            foreach($file in Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot $directory) -Recurse -File -Include *.ps1,*.psm1 | Where-Object FullName -NotMatch '[\\/](bin|obj|lib|artifacts|\.git)[\\/]'){
                $tokens=$null;$errors=$null
                $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
                if($errors.Count){throw ('PowerShell syntax: '+$file.Name+': '+$errors[0].Message)}
                foreach($function in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
                    $help=$function.GetHelpContent()
                    if(!$help -or [string]::IsNullOrWhiteSpace($help.Synopsis)){throw ('Unreadable function help: '+$file.Name+' / '+$function.Name)}
                }
            }
        }
    }
    $cases['security audit counterexamples are closed with independent evidence']={
        $run=Join-Path $WorkspaceRoot ('artifacts/security-regressions/'+[guid]::NewGuid().ToString('N'))
        $worker=Join-Path $PSScriptRoot 'audit/Invoke-AuditWorker.ps1'
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -WorkspaceRoot $WorkspaceRoot -RunDirectory $run
        Assert-QuietEqual $r.Outcome Success ('Audit regression failed: '+$run)
        Assert-QuietEqual $r.Data.State Success
        Assert-QuietEqual $r.Data.Failed 0
    }
    $cases['packaged modules verify and import outside source checkouts']={
        $packageRoot=Join-Path $WorkspaceRoot ('artifacts/package-tests/'+[guid]::NewGuid().ToString('N'))
        $null=& (Join-Path $WorkspaceRoot 'scripts/Update-WorkspaceLock.ps1') -WorkspaceRoot $WorkspaceRoot
        Push-Location -LiteralPath $WorkspaceRoot
        try{$null=& (Join-Path $WorkspaceRoot 'scripts/New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'packages')))}finally{Pop-Location}
        $verify=Join-Path $WorkspaceRoot 'scripts/Verify-Distribution.ps1'
        $r=quiet -AsObject -Role Infrastructure -WorkingDirectory $WorkspaceRoot -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $verify -PackageDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'packages'))) -ExtractionDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'extracted'))) -TestImport
        Assert-QuietEqual $r.Outcome Success ('Package verifier: '+($r.Error|ConvertTo-Json -Compress))
        Assert-QuietEqual $r.Data.Verified $true
        Assert-QuietEqual ($r.Data.ImportedModules -join ',') (@(Get-QuietWorkspaceProjects $WorkspaceRoot | Where-Object {!$_.IsTest} | ForEach-Object Name) -join ',')
        if($r.Data.Handlers -lt 1){throw 'PackageBusinessHandlersMissing'}
    }
    $cases['PSGallery Core installs outside sources with its embedded engine and no Git companion']={
        $root=Join-Path $WorkspaceRoot ('artifacts/gallery-tests/'+[guid]::NewGuid().ToString('N'))
        $packages=Join-Path $root packages
        $prepared=& (Join-Path $WorkspaceRoot 'scripts/New-QuietGalleryPackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $packages -Version 0.2.0-preview
        Assert-QuietEqual $prepared.Version '0.2.0-preview'
        & {
            param($scripts,$packages)
            . (Join-Path $scripts Common.ps1);. (Join-Path $scripts Gallery.ps1)
            foreach($wrong in @('9.9.9','0.2.0','0.2.0-preview1')){
                $rejected=$false
                try{$null=Test-QuietGalleryPackageSet $packages -Version $wrong}catch{$rejected=$_.Exception.Message -eq 'GalleryReleaseVersionMismatch'}
                if(!$rejected){throw 'Wrong or stripped prerelease version was accepted'}
            }
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version 0.2.0-preview -ValidateOnly
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version 0.2.0-preview -WhatIf
            $plan=Test-QuietGalleryPackageSet $packages -Version '0.2.0-preview'
            if(@($plan.Packages).Count -ne 1 -or $plan.Packages[0].Module -cne 'QuietCli'){throw 'GalleryCoreOnlyRequired'}
        } (Join-Path $WorkspaceRoot scripts) $packages
        $probe=Join-Path $PSScriptRoot audit/Probe-GalleryInstall.ps1
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -NoProfile -File $probe -PackageDirectory $packages -InstallationDirectory (Join-Path $root installed)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Installed $true
        Assert-QuietEqual $r.Data.CoreLoadedFromPackage $true
        Assert-QuietEqual $r.Data.GitModuleLoaded $false
        Assert-QuietEqual $r.Data.NativeExecution Success
        Assert-QuietEqual $r.Data.PackageVersion '0.2.0-preview'
        $galleryEvidence.Add(@{Packages=$prepared.Packages;Targets=$prepared.Targets;Installation=$r.Data;ExternalPublication=$false})
    }
    $caseMetadata=@{
        'test execution declarations preserve barriers and bounded isolated workers'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'test case classifications are complete explicit and fail closed before filtering'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'workspace project discovery keeps suite modes and package publication policy separate'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'container runtime diagnosis separates image bootstrap from ABI and RID selection'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'Alpine image recipe installs locked PowerShell and separates its runtime from the SDK'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'configuration and unique tokenized deliveries preserve their contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'reusable scripts, factories and literal property regressions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'Recall capture and offline analysis regressions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'protocol configuration preserves bounds using host .NET APIs'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'direct status callbacks preserve generated Unicode record digests'=@{TestKind='Unit';Dependencies=@()}
        'fresh sessions measure inert Core import against a paired baseline'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'CI evidence preserves binary traces and rejects tampered mandatory profiles'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'mandatory integration receipts reject damaged evidence and targeted gate mutants'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'import diagnostics retain independent first-use controls'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'owned complex repositories use only Core callbacks and exact state oracles'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess','NativeProcess','EngineState')}
        'local report paths isolate workspaces and preserve CI upload contracts'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'development workstation host properties and installer policy mutations'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'workstation resources preserve active owners and reject foreign cleanup'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'editor extension inventories preserve update and WhatIf contracts'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'source identity includes profile helpers and excludes generated libraries'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'Core migration preserves metadata and compares local helper costs'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'typed controls preserve duplex bytes and request rejection in both hosts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'typed controls measure local JSON avoidance with identical stdin'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'compiled text framing and gain reports preserve their contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'Gallery preserves prerelease labels and keeps numeric manifest versions separate'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'Gallery previews preserve source identities, Core-only packages and offline publication boundaries'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'CI requires stable net10 and preview net11 integrated hosts on x64 and ARM64'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'managed target follows the actual CLR including preview and future hosts'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'compiled framing and direct engine measure local overhead independently'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'CI failure diagnostics preserve redaction bounds and explicit local workflow selection'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI separates native containers, Docker fallback and workstation launchers'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'solution build catalogue discovers new consumers and rejects malformed distributions'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'ReadyToRun builds and loads the matching RID and CLR with portable fallbacks'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'CI process execution is independent and preserves streams failures stdin and deadlines'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'every native property fuzz and mutation phase is mandatory for delivery'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'native mutation refuses a mismatched guest before invoking a compiler'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'release gate rejects failed skipped cancelled or incomplete required jobs'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI excludes native TTY campaigns and has no dangling job dependencies'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI images cover four native Linux targets and invalidate the cache on recipe changes'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'cold engine and warm block-size measurements retain no business output'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'build provenance rejects changed binaries and stale source'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'all six embedded engines have matching native and managed architectures'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'C# protocol and concurrent SQLite assertions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'PTY reports a merged terminal counter without fake stderr separation'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'exact stdout/stderr counters with no capture'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'AsObject does not enumerate or serialize business getters'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'large output retains only bounded transport blocks'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'nested callback inherits context without serializing child objects'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'assigned child failure remains visible'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'context is not sticky across independent invocations'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'stdin bytes are exact and output is drained while feeding'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'UTF8 and NUL framing preserve split Unicode characters'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'truncated UTF8 fails analysis rather than dropping bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'Complete runs once after Output failure and native drain'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'accidental Output emission never becomes business Data'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'timeout preserves partial native state'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'interactive cancellation affects only the owned child'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'delimiter overflow fails analysis and still drains bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'native arguments preserve empty strings spaces and Unicode'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'delivery is bounded and AsObject remains unserialized until requested'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'empty singleton and nested arrays preserve JSON shape'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded delivery preserves failure identity without serializing omitted business data'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'generic and named gain filters are independent'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'delivery token count observes produced text only'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'production agent instructions preserve project rules and installed resources'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'module scaffolding creates inert handlers and independent failing test companions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'monitor duration preserves November timestamps in French and English cultures'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'PowerShell functions have readable help and sources parse without errors'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'security audit counterexamples are closed with independent evidence'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'packaged modules verify and import outside source checkouts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'PSGallery Core installs outside sources with its embedded engine and no Git companion'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'CI optimization preserves Core prerequisites, parallel isolation and qualified checkpoints'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess');NativeTransport='OwnedFixture'}
        'CI failure regressions reject empty Docker parents and skipped profiling uploads'=@{TestKind='Integration';Dependencies=@('FileSystem');NativeTransport='Stubbed'}
        'CI companion declarations separate integration suites and scale without workflow branches'=@{TestKind='Integration';Dependencies=@('FileSystem');NativeTransport='Stubbed'}
        'configuration dotenv preserves literals and deterministic local GitHub presets'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub PR push updates preserve previews remote routing and checkpoint identity'=@{TestKind='Integration';Dependencies=@('FileSystem');NativeTransport='Stubbed'}
        'GitHub CI container inputs include docs and restored packages without secrets or path escapes'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI companion helpers load privately without caller profile dependencies'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'GitHub CI JSON receipts create missing parents and preserve preview boundaries'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'unit byte-count parsing validates sizes without filesystem or process effects'=@{TestKind='Unit';Dependencies=@()}
        'commit workspace documentation gates, script/doc drift and the -WhatIf/commit-once/no-remote contract'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'automation commit pipeline checks staged workflow and preview contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'automation resource and script review gates inspect the prepared index'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'automation contracts require available runtimes accurate workflow graphs and safe previews'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'automation report streaming preserves Unicode fragments and bounded diagnostic tails'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'automation objective comments are inert and library loading stays silent'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'native Emit listeners preserve Unicode order and bounded JSON/YAML deliveries'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'explicit event collection compiled properties and targeted mutations'=@{TestKind='Integration';Dependencies=@('FileSystem','DotNetBuild','NativeProcess')}
    }
    Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $caseMetadata
    $passed=0;$failed=0;$results=[Collections.Generic.List[object]]::new()
    # Development-only selection (QUIETCLI_TEST_CASE wildcard, QUIETCLI_TEST_STOP_ON_FIRST_FAILURE=1); the default run executes every case.
    $casePattern=$env:QUIETCLI_TEST_CASE;$stopOnFirst=$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'
    $stoppedAt=$null;$skipped=0;$ttyExcluded=0
    $selected=[Collections.Generic.List[string]]::new()
    foreach($entry in $cases.GetEnumerator()){
        if($env:QUIETCLI_TEST_SKIP_TTY -ceq '1' -and $entry.Key -clike 'PTY *'){$ttyExcluded++;continue}
        if($casePattern -and $entry.Key -notlike $casePattern){$skipped++;continue}
        $selected.Add($entry.Key)
    }
    $policy=Get-QuietTestExecutionPolicy -ManifestPath (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -CaseNames @($cases.Keys)
    $budget=1
    if($env:QUIETCLI_TEST_MAX_CONCURRENCY -and (![int]::TryParse($env:QUIETCLI_TEST_MAX_CONCURRENCY,[ref]$budget) -or $budget -lt 1 -or $budget -gt 32)){throw 'TestMaxConcurrencyInvalid'}
    $caseWorker=$env:QUIETCLI_TEST_CASE_WORKER -ceq '1'
    $plan=Get-QuietTestExecutionPlan -CaseNames $selected.ToArray() -Policy $policy -MaxConcurrency $budget
    Write-WorkspaceJson (Join-Path $RunDirectory 'core-execution-plan.json') $plan
    $batches=[Collections.Generic.List[object]]::new()
    foreach($stage in $plan.Stages){
        if($stoppedAt){$skipped+=$stage.Cases.Count;continue}
        if($stage.Mode -ceq 'IsolatedProcess' -and !$caseWorker){
            $counts=@{Passed=$passed;Failed=$failed}
            $batch=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Cases $stage.Cases.ToArray() -MaxConcurrency $plan.MaxConcurrency -StopOnFirstFailure:$stopOnFirst -SkipTty:($env:QUIETCLI_TEST_SKIP_TTY -ceq '1') -ExpectedRuntimeIdentifier $env:QUIETCLI_TEST_EXPECT_RID -OnCase {
                param($name,$caseState,$caseResult)
                if($caseState -ceq 'Passed'){$counts.Passed++}elseif($caseState -ceq 'Failed'){$counts.Failed++}
                if($OnProgress){& $OnProgress ('['+$caseMetadata[$name].TestKind+'] '+$name) $caseState $counts.Passed $counts.Failed}
            }
            $passed=$counts.Passed;$failed=$counts.Failed
            foreach($item in $batch.Cases){
                $item|Add-Member NoteProperty TestKind $caseMetadata[$item.Name].TestKind
                $item|Add-Member NoteProperty Dependencies @($caseMetadata[$item.Name].Dependencies)
                $results.Add($item)
            }
            $skipped+=$batch.NotStarted.Count;$batches.Add($batch)
            if($stopOnFirst -and @($batch.Cases|Where-Object State -CEQ Failed).Count){$stoppedAt="stopped at case $($passed+$failed) of $($cases.Count)"}
            continue
        }
        foreach($plannedCase in $stage.Cases){
            if($stoppedAt){$skipped++;continue}
            $name=$plannedCase.Name;$metadata=$caseMetadata[$name]
            $progressName='['+$metadata.TestKind+'] '+$name
            if($OnProgress){& $OnProgress $progressName 'Running' $passed $failed}
            $failure=$null
            try{$null=& $cases[$name];$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
            $results.Add([pscustomobject]@{Name=$name;State=$state;Error=$failure;TestKind=$metadata.TestKind;Dependencies=@($metadata.Dependencies);ExecutionMode=if($caseWorker){'CaseWorker'}else{$plannedCase.Mode}})
            if($OnProgress){& $OnProgress $progressName $state $passed $failed}
            if($state -eq 'Failed' -and $stopOnFirst){$stoppedAt="stopped at case $($passed+$failed) of $($cases.Count)"}
        }
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$casePattern;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=$skipped;TtyExcluded=($ttyExcluded+$testScope.TtyExcluded);Cases=$results.ToArray();Performance=$performance.ToArray();Gallery=$galleryEvidence.ToArray();Integration=$integration.ToArray();ExecutionPlan=$plan;ParallelBatches=$batches.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietCoreTests,Assert-QuietEqual,Invoke-QuietConformance

Export-ModuleMember -Function Compare-QuietRecallAnalysis,Export-QuietRecallFixture,Reduce-QuietRecall,Invoke-QuietRecallTests

Export-ModuleMember -Function Invoke-QuietRecallRtkComparison

Export-ModuleMember -Function Invoke-QuietRecallLargeTests
