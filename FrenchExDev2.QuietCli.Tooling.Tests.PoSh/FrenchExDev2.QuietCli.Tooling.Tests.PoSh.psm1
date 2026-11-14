#requires -Version 7.6
function Invoke-QuietToolingTests {
    <#
    .SYNOPSIS
    Qualifies repository automation independently of the Core product suite.
    .PARAMETER WorkspaceRoot
    Checkout containing the selected automation and business-package subjects.
    .PARAMETER OnProgress
    Callback receiving classified case progress and cumulative counts.
    .PARAMETER RunDirectory
    Owned reports; filtered runs remain explicitly partial.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[Parameter(Mandatory)][string]$RunDirectory)
    $toolingRoot=$PSScriptRoot
    & (Get-Module FrenchExDev2.QuietCli.Core.Tests.PoSh) {
        param($WorkspaceRoot,$OnProgress,$RunDirectory,$toolingRoot)
        $coreTestsRoot=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
        $fixture=Join-Path $coreTestsRoot 'lib/fixture/QuietCli.Fixture.dll'
        $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
        $performance=[Collections.Generic.List[object]]::new()
        $galleryEvidence=[Collections.Generic.List[object]]::new()
        $integration=[Collections.Generic.List[object]]::new()
        $testScope=@{TtyExcluded=0}
        $cases=[ordered]@{}
        $cases['CI scales by affected suites with verified merge reuse and intermediate caches']={Test-QuietCiScalability -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['test case classifications are complete explicit and fail closed before filtering']={Test-QuietCaseMetadata -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['test execution declarations preserve barriers and bounded isolated workers']={Test-QuietCaseScheduling -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI optimization preserves Core prerequisites, parallel isolation and qualified checkpoints']={Test-QuietCiOptimization -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI failure regressions reject empty Docker parents and skipped profiling uploads']={Test-QuietCiFailureRegression -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['unit byte-count parsing validates sizes without filesystem or process effects']={Test-QuietByteCountParsing}
        $cases['workspace project discovery keeps suite modes and package publication policy separate']={Test-QuietWorkspaceProjects -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['commit workspace documentation gates, script/doc drift and the -WhatIf/commit-once/no-remote contract']={Test-QuietCommitWorkspace -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['container runtime diagnosis separates image bootstrap from ABI and RID selection']={Test-QuietRuntimeDiagnosis -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['Alpine image recipe installs locked PowerShell and separates its runtime from the SDK']={Test-QuietCiImageRecipe -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI evidence preserves binary traces and rejects tampered mandatory profiles']={$performance.Add((Test-QuietEvidenceBundle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory))}
        $cases['mandatory integration receipts reject damaged evidence and targeted gate mutants']={$performance.Add((Test-QuietCoreIntegrationGate -WorkspaceRoot $WorkspaceRoot))}
        $cases['local report paths isolate workspaces and preserve CI upload contracts']={Test-QuietReportPaths -WorkspaceRoot $WorkspaceRoot}
        $cases['development workstation host properties and installer policy mutations']={Test-QuietDevelopmentWorkstation -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['workstation resources preserve active owners and reject foreign cleanup']={Test-QuietWorkstationResources -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['editor extension inventories preserve update and WhatIf contracts']={Test-QuietEditorExtensions -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['source identity includes profile helpers and excludes generated libraries']={
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/SourceIdentity.psm1') -DisableNameChecking -ErrorAction Stop
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
        $source=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts/lib/SourceIdentity.psm1') -Raw -Encoding utf8
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
        $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-QuietSourceFiles'},$true).Extent.Text
        $anchor="if(`$item.Name -eq 'lib' -and `$item.FullName -ne [IO.Path]::GetFullPath([IO.Path]::Combine(`$rootPath,'scripts/lib'))){continue}"
        if(!$function.Contains($anchor)){throw 'SourceIdentityMutationAnchorMissing'}
        foreach($replacement in @("if(`$item.Name -eq 'lib'){continue}",'')){
            $killed=$false
            try{& {param($definition) . ([scriptblock]::Create($definition)); & $oracle (Get-Command Get-QuietSourceFiles)} ($function.Replace($anchor,$replacement))}catch{$killed=$true}
            Assert-QuietEqual $killed $true 'Both omitted source helpers and included generated libraries must be detected'
        }
    }
        $cases['Gallery preserves prerelease labels and keeps numeric manifest versions separate']={
        & {
            param($scripts)
            Import-Module ([IO.Path]::Combine($scripts,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
            Import-Module ([IO.Path]::Combine($scripts,'lib/Gallery.psm1')) -DisableNameChecking -ErrorAction Stop
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
        . (Join-Path $coreTestsRoot 'GalleryPreview.Tests.ps1')
        $previewSummary=Invoke-QuietGalleryPreviewTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($previewSummary.Failed){throw ($previewSummary.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 5 -Compress)}
    }
        $cases['CI requires GA native hosts and explicitly optional next-version preview']={Assert-QuietHostMatrix $WorkspaceRoot;Test-QuietPowerShellReleasePolicy -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI failure diagnostics preserve redaction bounds and explicit local workflow selection']={Test-QuietCiDiagnostics -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['GitHub CI separates native containers, Docker fallback and workstation launchers']={Test-QuietGitHubCi -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI companion declarations separate integration suites and scale without workflow branches']={Test-QuietCiCompanions -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['GitHub CI JSON receipts create missing parents and preserve preview boundaries']={Test-QuietGitHubCiJsonReceipts -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['GitHub CI companion helpers load privately without caller profile dependencies']={Test-QuietCompanionHelperScope -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['GitHub CI container inputs include docs and restored packages without secrets or path escapes']={Test-QuietContainerInputs -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['solution build catalogue discovers new consumers and rejects malformed distributions']={Test-QuietWorkspaceBuildProjects -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['ReadyToRun builds and loads the matching RID and CLR with portable fallbacks']={Test-QuietReadyToRun -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['script layout enforces entry points libraries imports and IO paths']={
            . ([IO.Path]::Combine($toolingRoot,'ScriptLayout.Tests.ps1'))
            $null=Test-QuietScriptLayoutContract -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        }
        $cases['automation contracts require available runtimes accurate workflow graphs and safe previews']={Test-QuietAutomationContracts -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['configuration dotenv preserves literals and deterministic local GitHub presets']={Test-QuietEnvFiles -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['GitHub PR push updates preserve previews remote routing and checkpoint identity']={Test-QuietPullRequestUpdates -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['automation report streaming preserves Unicode fragments and bounded diagnostic tails']={Test-QuietReportStreaming -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['automation objective comments are inert and library loading stays silent']={Test-QuietObjectiveOutput -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['automation resource and script review gates inspect the prepared index']={Test-QuietResourceCommitChecks -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['automation commit pipeline checks staged workflow and preview contracts']={Test-QuietAutomationCommitChecks -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}
        $cases['CI process execution is independent and preserves streams failures stdin and deadlines']={
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Ci.Process.psm1') -DisableNameChecking -ErrorAction Stop
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
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Assert-PtyQualification.psm1') -DisableNameChecking -ErrorAction Stop
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
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Ci.Process.psm1') -DisableNameChecking -ErrorAction Stop
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
            foreach($job in @('WindowsResult','LinuxResult','MutationResult','PerformanceResult')){
                foreach($result in @('success','failure','cancelled','skipped','')){
                    $expectedMutation=if($skipTty -or $suite -eq 'Git'){'skipped'}else{'success'}
                    $expectedPerformance=if($suite -eq 'Git'){'skipped'}else{'success'}
                    $ready=if($job -eq 'MutationResult'){$result -ceq $expectedMutation}elseif($job -eq 'PerformanceResult'){$result -ceq $expectedPerformance}else{$result -ceq 'success'}
                    $id=[guid]::NewGuid().ToString('N')
                    $output=Join-Path $directory ($id+'.output');$receipt=Join-Path $directory ($id+'.json')
                    $arguments=@{Suite=$suite;SkipTty=$skipTty;Revision=$revision;WindowsResult='success';LinuxResult='success';MutationResult=$expectedMutation;PerformanceResult=$expectedPerformance;ReceiptPath=$receipt;OutputPath=$output}
                    $arguments[$job]=$result
                    $accepted=$false
                    try{& $script @arguments;$accepted=$true}catch{if($ready){throw}}
                    Assert-QuietEqual $accepted $ready 'Only complete required job success may pass'
                    if(Test-Path -LiteralPath $receipt){
                        $decision=Get-Content -LiteralPath $receipt -Encoding utf8 -Raw|ConvertFrom-Json
                        Assert-QuietEqual $decision.MutationRequired (!$skipTty -and $suite -ne 'Git')
                        Assert-QuietEqual $decision.PerformanceRequired ($suite -ne 'Git')
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
        $productWorkflow=$null;$toolingWorkflow=$null
        $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
        $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
        foreach($file in Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot '.github/workflows') -Filter '*.yml'){
            $reader=[IO.StringReader]::new([IO.File]::ReadAllTextAsync($file.FullName,[Text.Encoding]::UTF8).GetAwaiter().GetResult())
            try{$workflow=$parser.Deserialize($reader,[object])}finally{$reader.Dispose()}
            $jobs=$workflow['jobs']
            if($file.Name -ceq 'ci.yml'){$productWorkflow=$workflow}
            if($file.Name -ceq 'tooling-ci.yml'){$toolingWorkflow=$workflow}
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
                if($gate -notmatch '(?<!\S)-MutationResult\s+skipped(?=\s|$)' -or $gate -notmatch '(?<!\S)-SkipTty(?=\s|$)'){throw 'TtyGateExclusionNotExplicit'}
                if(@($jobs['qualification-gate']['needs']) -cnotcontains 'performance-results' -or $gate -notmatch '-PerformanceResult \$env:PERFORMANCE_RESULT'){throw 'PerformanceEvidenceMustGateQualification'}
                foreach($trigger in @('workflow_call','workflow_dispatch')){
                    $option=$workflow['on'][$trigger]['inputs']['collect_performance']
                    if(!$option -or $option['type'] -cne 'boolean' -or [string]$option['default'] -cne 'true'){throw 'PerformanceMustBeEnabledByDefault'}
                }
                $assertAggregationScope={
                    param([string]$condition)
                    $condition=$condition.Trim()
                    if($condition.StartsWith('${{') -and $condition.EndsWith('}}')){$condition=$condition.Substring(3,$condition.Length-5).Trim()}
                    if($condition -cnotmatch '(?<![\w.])always\(\)'){throw 'PerformanceAggregationFailureReportsRequired'}
                    if($condition -cnotmatch "\A(?:(?:always\(\)|inputs\.images_only|inputs\.collect_performance|needs\.linux-matrix\.outputs\.has_core|'true'|'false')|&&|\|\||==|!=|!|[()]|\s)+\z"){throw 'PerformanceAggregationConditionInvalid'}
                    $expression=$condition.Replace('always()','$true').Replace('inputs.images_only','$imagesOnly').Replace('inputs.collect_performance','$collectPerformance').Replace('needs.linux-matrix.outputs.has_core','$hasCore').Replace('&&',' -and ').Replace('||',' -or ').Replace('==',' -eq ').Replace('!=',' -ne ').Replace('!',' -not ')
                    $evaluate=[scriptblock]::Create($expression)
                    foreach($imagesOnly in @($false,$true)){foreach($collectPerformance in @($false,$true)){foreach($hasCore in @('true','false','','unknown')){
                        $expected=!$imagesOnly -and $collectPerformance -and $hasCore -ceq 'true'
                        if([bool](& $evaluate) -ne $expected){throw 'PerformanceAggregationScopeChanged'}
                    }}}
                }
                $aggregationCondition=[string]$jobs['performance-results']['if']
                & $assertAggregationScope $aggregationCondition
                $aggregationDamages=@($aggregationCondition.Replace('!inputs.images_only && ',''),$aggregationCondition.Replace('inputs.collect_performance && ',''),$aggregationCondition.Replace("needs.linux-matrix.outputs.has_core == 'true'","'true' == 'true'"),$aggregationCondition.Replace('always() && ',''))
                foreach($damaged in $aggregationDamages){
                    $rejected=$false;try{& $assertAggregationScope $damaged}catch{$rejected=$true}
                    if(!$rejected){throw 'PerformanceAggregationGuardMutantSurvived'}
                }
                Write-WorkspaceJson (Join-Path $RunDirectory 'ci-performance-aggregation-scope.json') @{ScopeProperties=16;GuardMutantsRejected=4;CachePreparationProducesQualification=$false}
                foreach($name in @('windows','linux','linux-test-driver')){
                    $runs=@($jobs[$name]['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
                    if($runs.Contains('if($env:QUIETCLI_SUITE -ne ''Git'')')){throw ('UnconditionalProfiling: '+$name)}
                    $reportSteps=@($jobs[$name]['steps']|Where-Object {$_['run'] -match 'New-CorePerformanceReport.ps1'})
                    if($reportSteps.Count -ne 1 -or [string]$reportSteps[0]['env']['QUIETCLI_COLLECT_PERFORMANCE'] -cne '${{ inputs.collect_performance }}' -or !([string]$reportSteps[0]['run']).Contains('if($env:QUIETCLI_COLLECT_PERFORMANCE -ceq ''true'' -and $env:QUIETCLI_SUITE_HAS_CORE -ceq ''true'')')){throw ('PerformanceReportNotOptIn: '+$name)}
                }
            }
        }
        if(!$productWorkflow -or !$toolingWorkflow){throw 'ProfilerQualificationWorkflowsRequired'}
        $null=Assert-QuietCiProfilerPreparation $productWorkflow $toolingWorkflow
    }
        $cases['CI images cover four native Linux targets and invalidate the cache on recipe changes']={
        & {
            param($root)
            Import-Module (Join-Path $root 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
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
            $files=@('global.json','build/ci-images.lock.json','scripts/lib/CiImages.psm1','scripts/New-CiImage.ps1','FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1')
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
        $cases['build provenance rejects changed binaries and stale source']={
        $directory=Join-Path $WorkspaceRoot ('artifacts/build-provenance/'+[guid]::NewGuid().ToString('N'))
        foreach($folder in @('FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture','FrenchExDev2.QuietCli.Core.PoSh','output')){[void][IO.Directory]::CreateDirectory((Join-Path $directory $folder))}
        $project='FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Synthetic.csproj'
        $files=@{'global.json'='{}';'Directory.Packages.props'='<Project />';'FrenchExDev2.QuietCli.Core.PoSh/protocol.json'='{}';$project='<Project />';'FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Program.cs'='// synthetic source';'output/Synthetic.dll'='synthetic binary'}
        foreach($entry in $files.GetEnumerator()){[void][IO.File]::WriteAllTextAsync((Join-Path $directory $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        & {
            param($scripts,$directory,$project)
            Import-Module ([IO.Path]::Combine($scripts,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
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
        $cases['monitor duration preserves November timestamps in French and English cultures']={
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Monitor.Time.psm1') -DisableNameChecking -ErrorAction Stop
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
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
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
    $cases['local launcher imports exact business companions and restores their lifecycle']={
        $probe=Join-Path $RunDirectory 'launcher-companions.ps1'
        $source=@'
param([string]$LauncherPath)
$ErrorActionPreference='Stop'
$beforeCompanions = @(Get-Module FrenchExDev2.QuietCli.*.PoSh -All).Count
$paths = @(& $LauncherPath -Companion Git,Vagrant -Code {
    param($runtime)
    $handlers = @(Get-QuietHandler)
    if (@($handlers | Where-Object Id -EQ 'FrenchExDev2.QuietCli.Git.PoSh').Count -ne 1 -or
        @($handlers | Where-Object Id -Like 'FrenchExDev2.QuietCli.Vagrant.PoSh.*').Count -ne 2) { throw 'LauncherCompanionHandlersMissing' }
    @('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Vagrant.PoSh') |
        ForEach-Object { (Get-Module $_ -ErrorAction Stop).Path }
})
if ($paths.Count -ne 3 -or @(Get-Module FrenchExDev2.QuietCli.*.PoSh -All).Count -ne $beforeCompanions) { throw 'LauncherCompanionLifecycleChanged' }
$invalidCompanionRejected = $false
try { & $LauncherPath -Companion Unknown -Code {} } catch { $invalidCompanionRejected = $true }
if (!$invalidCompanionRejected) { throw 'LauncherInvalidCompanionAccepted' }

'@
        [IO.File]::WriteAllText($probe,$source,[Text.UTF8Encoding]::new($false))
        $r=quiet -AsObject -Output {param($e,$r)} -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList @('-File',$probe,'-LauncherPath',(Join-Path $WorkspaceRoot 'scripts/Invoke-Quiet.ps1'))
        Assert-QuietEqual $r.Outcome Success 'Local companion launcher qualification failed'
    }
    $caseMetadata=@{
        'script layout enforces entry points libraries imports and IO paths'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI scales by affected suites with verified merge reuse and intermediate caches'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'local launcher imports exact business companions and restores their lifecycle'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'test case classifications are complete explicit and fail closed before filtering'=@{TestKind='Integration';Dependencies=@('FileSystem','ProcessEnvironment')}
        'test execution declarations preserve barriers and bounded isolated workers'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'CI optimization preserves Core prerequisites, parallel isolation and qualified checkpoints'=@{Dependencies=@('FileSystem','NativeProcess');NativeTransport='OwnedFixture';TestKind='Integration'}
        'CI failure regressions reject empty Docker parents and skipped profiling uploads'=@{Dependencies=@('FileSystem');NativeTransport='Stubbed';TestKind='Integration'}
        'unit byte-count parsing validates sizes without filesystem or process effects'=@{TestKind='Unit';Dependencies=@()}
        'workspace project discovery keeps suite modes and package publication policy separate'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'commit workspace documentation gates, script/doc drift and the -WhatIf/commit-once/no-remote contract'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'container runtime diagnosis separates image bootstrap from ABI and RID selection'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'Alpine image recipe installs locked PowerShell and separates its runtime from the SDK'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI evidence preserves binary traces and rejects tampered mandatory profiles'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'mandatory integration receipts reject damaged evidence and targeted gate mutants'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'local report paths isolate workspaces and preserve CI upload contracts'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'development workstation host properties and installer policy mutations'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'workstation resources preserve active owners and reject foreign cleanup'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'editor extension inventories preserve update and WhatIf contracts'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'source identity includes profile helpers and excludes generated libraries'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'Gallery preserves prerelease labels and keeps numeric manifest versions separate'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'Gallery previews preserve source identities, Core-only packages and offline publication boundaries'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'CI requires GA native hosts and explicitly optional next-version preview'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI failure diagnostics preserve redaction bounds and explicit local workflow selection'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI separates native containers, Docker fallback and workstation launchers'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI companion declarations separate integration suites and scale without workflow branches'=@{Dependencies=@('FileSystem');NativeTransport='Stubbed';TestKind='Integration'}
        'GitHub CI JSON receipts create missing parents and preserve preview boundaries'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI companion helpers load privately without caller profile dependencies'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'GitHub CI container inputs include docs and restored packages without secrets or path escapes'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'solution build catalogue discovers new consumers and rejects malformed distributions'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'ReadyToRun builds and loads the matching RID and CLR with portable fallbacks'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'automation contracts require available runtimes accurate workflow graphs and safe previews'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'configuration dotenv preserves literals and deterministic local GitHub presets'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub PR push updates preserve previews remote routing and checkpoint identity'=@{Dependencies=@('FileSystem');NativeTransport='Stubbed';TestKind='Integration'}
        'automation report streaming preserves Unicode fragments and bounded diagnostic tails'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'automation objective comments are inert and library loading stays silent'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'automation resource and script review gates inspect the prepared index'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'automation commit pipeline checks staged workflow and preview contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess')}
        'CI process execution is independent and preserves streams failures stdin and deadlines'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'every native property fuzz and mutation phase is mandatory for delivery'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'native mutation refuses a mismatched guest before invoking a compiler'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'release gate rejects failed skipped cancelled or incomplete required jobs'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'GitHub CI excludes native TTY campaigns and has no dangling job dependencies'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'CI images cover four native Linux targets and invalidate the cache on recipe changes'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'build provenance rejects changed binaries and stale source'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'monitor duration preserves November timestamps in French and English cultures'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'PowerShell functions have readable help and sources parse without errors'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'packaged modules verify and import outside source checkouts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
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
    $policy=Get-QuietTestExecutionPolicy -ManifestPath (Join-Path $toolingRoot 'FrenchExDev2.QuietCli.Tooling.Tests.PoSh.psd1') -CaseNames @($cases.Keys)
    $budget=1
    if($env:QUIETCLI_TEST_MAX_CONCURRENCY -and (![int]::TryParse($env:QUIETCLI_TEST_MAX_CONCURRENCY,[ref]$budget) -or $budget -lt 1 -or $budget -gt 32)){throw 'TestMaxConcurrencyInvalid'}
    $caseWorker=$env:QUIETCLI_TEST_CASE_WORKER -ceq '1'
    $plan=Get-QuietTestExecutionPlan -CaseNames $selected.ToArray() -Policy $policy -MaxConcurrency $budget
    Write-WorkspaceJson (Join-Path $RunDirectory 'tooling-execution-plan.json') $plan
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
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Tooling.Tests.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$casePattern;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=$skipped;TtyExcluded=($ttyExcluded+$testScope.TtyExcluded);Cases=$results.ToArray();Performance=$performance.ToArray();Gallery=$galleryEvidence.ToArray();Integration=$integration.ToArray();ExecutionPlan=$plan;ParallelBatches=$batches.ToArray()}
    } $WorkspaceRoot $OnProgress $RunDirectory $toolingRoot
}
Export-ModuleMember -Function Invoke-QuietToolingTests
