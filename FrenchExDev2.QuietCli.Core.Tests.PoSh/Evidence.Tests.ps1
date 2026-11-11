function Test-QuietEvidenceBundle {
    <#
    .SYNOPSIS
    Verifies byte-preserving evidence copies, exclusions, integrity failures and a checksum-gate mutant.
    .PARAMETER WorkspaceRoot
    Local monorepo containing the actual bundle builder.
    .PARAMETER RunDirectory
    Owned run directory retaining explicitly labeled synthetic integrity fixtures.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    $builder=Join-Path $WorkspaceRoot 'scripts/New-CoreEvidenceBundle.ps1'
    $root=Join-Path $RunDirectory 'evidence-unit'
    [void][IO.Directory]::CreateDirectory($root)
    $random=[Random]::new(73597)
    foreach($iteration in 1..4){
        $inputRoot=Join-Path $root "input-$iteration";$profileEvidence=Join-Path $inputRoot 'profiling'
        [void][IO.Directory]::CreateDirectory($profileEvidence)
        $bytes=[byte[]]::new($random.Next(128,4096));$random.NextBytes($bytes)
        $trace=Join-Path $profileEvidence 'synthetic.nettrace'
        [void][IO.File]::WriteAllBytesAsync($trace,$bytes).GetAwaiter().GetResult()
        foreach($name in @('powershell-lines.json','powershell.speedscope.json','synthetic.speedscope.json')){Write-WorkspaceJson (Join-Path $profileEvidence $name) @{SyntheticIntegrityFixture=$true}}
        Write-WorkspaceJson (Join-Path $profileEvidence 'summary.json') @{SyntheticIntegrityFixture=$true;State='Success';ProfilerVersion='4.3.0';ClrProfilerVersion='10.0.750501';TargetIdentity=@{EngineMode='InProcess'};Collectors=@(@{Trace='synthetic.nettrace';Speedscope='synthetic.speedscope.json';SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})}
        Write-WorkspaceJson (Join-Path $inputRoot 'summary.json') @{SyntheticIntegrityFixture=$true;State=@{State='Success';Platform='synthetic-rid';Passed=1;Failed=0};Suites=@();Profiling=$null;EngineIdentity=@{Mode='InProcess'};PowerShellVersion='synthetic';HostRuntime='synthetic'}
        [void][IO.Directory]::CreateDirectory((Join-Path $inputRoot 'workspace'))
        Write-WorkspaceJson (Join-Path $inputRoot 'workspace/excluded.json') @{Sentinel='excluded staged workspace'}
        $outputRoot=Join-Path $root "output-$iteration"
        $null=& $builder -ReportRoot $inputRoot -OutputDirectory $outputRoot -Revision ('a'*40) -RequireProfiling
        $manifest=Get-Content (Join-Path $outputRoot 'evidence-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
        if($manifest.EvidenceGaps.Count -or $manifest.SuccessfulProfilingReports -ne 1 -or (Test-Path (Join-Path $outputRoot 'workspace'))){throw 'EvidenceCopyOrExclusionChanged: seed 73597'}
        $copied=[IO.File]::ReadAllBytesAsync((Join-Path $outputRoot 'profiling/synthetic.nettrace')).GetAwaiter().GetResult()
        if([Convert]::ToHexString($copied) -cne [Convert]::ToHexString($bytes)){throw 'BinaryEvidenceChanged'}
        foreach($file in $manifest.Files){if((Get-FileHash (Join-Path $outputRoot $file.Path) -Algorithm SHA256).Hash -cne $file.SHA256){throw 'EvidenceManifestHashMismatch'}}
        $renderer=Join-Path $WorkspaceRoot 'scripts/New-CorePerformanceReport.ps1'
        $null=& $renderer -EvidenceRoot $outputRoot -OutputDirectory $outputRoot -Revision ('a'*40) -ExpectedReports 1 -Suite Git
        $reportText=[IO.File]::ReadAllTextAsync((Join-Path $outputRoot 'PERFORMANCES_RESULTS.md'),[Text.Encoding]::UTF8).GetAwaiter().GetResult()
        if(!$reportText.Contains('COMPLETE') -or !$reportText.Contains('synthetic-rid') -or !$reportText.Contains('Git-only')){throw 'ReadableEvidenceSummaryMissing'}
        $htmlPath=Join-Path $outputRoot 'PERFORMANCES_RESULTS.html'
        $html=[IO.File]::ReadAllText($htmlPath,[Text.Encoding]::UTF8)
        if(!$html.Contains('<!doctype html>') -or !$html.Contains('synthetic-rid') -or !$html.Contains('Content-Security-Policy')){throw 'StandaloneHtmlEvidenceMissing'}
        $published=Get-Content (Join-Path $outputRoot evidence-manifest.json) -Raw -Encoding utf8|ConvertFrom-Json
        $htmlReceipt=@($published.Files|Where-Object Path -CEQ 'PERFORMANCES_RESULTS.html')
        if($htmlReceipt.Count -ne 1 -or $htmlReceipt[0].SHA256 -cne (Get-FileHash $htmlPath).Hash){throw 'HtmlEvidenceChecksumMissing'}
        $missingRoot=Join-Path $root "missing-report-$iteration"
        $rejected=$false
        try{$null=& $renderer -EvidenceRoot $outputRoot -OutputDirectory $missingRoot -Revision ('a'*40) -ExpectedReports 2 -Suite Git}catch{$rejected=$_.Exception.Message -eq 'PerformanceReportEvidenceIncomplete'}
        if(!$rejected -or !(Test-Path (Join-Path $missingRoot 'PERFORMANCES_RESULTS.md')) -or !(Test-Path (Join-Path $missingRoot 'PERFORMANCES_RESULTS.html'))){throw 'MissingMatrixReportWasNotPublishedAsFailure'}
        $badBytes=[byte[]]$bytes.Clone();$badBytes[0]=$badBytes[0] -bxor 255
        [void][IO.File]::WriteAllBytesAsync($trace,$badBytes).GetAwaiter().GetResult()
        $rejected=$false
        try{$null=& $builder -ReportRoot $inputRoot -OutputDirectory (Join-Path $root "damaged-$iteration") -Revision ('a'*40) -RequireProfiling}catch{$rejected=$_.Exception.Message -eq 'MandatoryProfilingEvidenceMissing'}
        if(!$rejected){throw 'ModifiedClrEvidenceAccepted'}
    }
    $linkedRoot=Join-Path $root 'linked-input';$linkedOutside=Join-Path $root 'linked-outside';$linkedOutput=Join-Path $root 'linked-output'
    [void][IO.Directory]::CreateDirectory($linkedRoot);[void][IO.Directory]::CreateDirectory($linkedOutside)
    Write-WorkspaceJson (Join-Path $linkedRoot summary.json) @{State=@{State='Failed';Passed=1;Failed=1};Suites=@()}
    Write-WorkspaceJson (Join-Path $linkedOutside secret.json) @{MustNotBeCollected=$true}
    $link=Join-Path $linkedRoot unsafe-link
    $null=New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $link -Target $linkedOutside
    try{
        $rejected=$false
        try{$null=& $builder -ReportRoot $linkedRoot -OutputDirectory $linkedOutput -Revision ('a'*40)}catch{$rejected=$_.Exception.Message -eq 'EvidenceCollectionIncomplete'}
        $partial=Get-Content (Join-Path $linkedOutput evidence-manifest.json) -Raw -Encoding utf8|ConvertFrom-Json
        if(!$rejected -or !@($partial.EvidenceGaps|Where-Object {$_ -like 'EvidenceSourceLinkRejected:*'}).Count -or 'summary.json' -cnotin $partial.Files.Path -or (Test-Path (Join-Path $linkedOutput unsafe-link/secret.json))){throw 'LinkedEvidenceLostFailureManifestOrFollowedTarget'}
    }finally{[IO.Directory]::Delete($link)}
    $rejected=$false
    try{$null=& $builder -ReportRoot $inputRoot -OutputDirectory (Join-Path $inputRoot 'nested-output') -Revision ('a'*40)}catch{$rejected=$_.Exception.Message -eq 'EvidenceDestinationMustBeOutsideReports'}
    if(!$rejected){throw 'RecursiveEvidenceDestinationAccepted'}
    Test-QuietMatrixHtmlEvidence -WorkspaceRoot $WorkspaceRoot -RunDirectory $root
    $source=[IO.File]::ReadAllTextAsync($builder,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $anchor='(Get-FileHash $trace -Algorithm SHA256).Hash -cne $collector.SHA256'
    if(!$source.Contains($anchor)){throw 'EvidenceIntegrityMutantInvalid'}
    $common=(Join-Path $WorkspaceRoot 'scripts/Common.ps1').Replace("'","''")
    $mutantSource=$source.Replace($anchor,'$false').Replace(". (Join-Path `$PSScriptRoot 'Common.ps1')",(". '"+$common+"'"))
    $mutant=[scriptblock]::Create($mutantSource)
    $survived=$true
    try{$null=& $mutant -ReportRoot $inputRoot -OutputDirectory (Join-Path $root 'mutant') -Revision ('a'*40) -RequireProfiling}catch{$survived=$false}
    if(!$survived){throw 'EvidenceIntegrityMutantDidNotExposeMissingCheck'}
    # The independent damaged-input assertion above rejects this accepted mutant result.
    $result=[pscustomobject]@{Seed=73597;BinaryCases=4;DamagedCases=4;ReadableReportCases=4;MissingMatrixCases=4;BoundaryCases=1;Mutations=@(@{Name='IgnoreClrTraceChecksum';State='Killed';DetectedBy='ModifiedClrEvidenceAccepted invariant'});SyntheticFixtureDirectory=$root}
    Write-WorkspaceJson (Join-Path $RunDirectory 'evidence-validation.json') $result
    $result
}

function Test-QuietMatrixHtmlEvidence {
    <#
    .SYNOPSIS
    Verifies standalone HTML and detailed profiling tables with ten explicitly synthetic matrix subjects.
    .PARAMETER WorkspaceRoot
    Checkout containing the real evidence collector and report renderer.
    .PARAMETER RunDirectory
    Owned synthetic fixtures; these are renderer assertions, never hosted profiling qualification.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $inputRoot=Join-Path $RunDirectory synthetic-matrix-input
    $bundle=Join-Path $RunDirectory synthetic-matrix-bundle
    $builder=Join-Path $WorkspaceRoot scripts/New-CoreEvidenceBundle.ps1
    $renderer=Join-Path $WorkspaceRoot scripts/New-CorePerformanceReport.ps1
    $targets=@(
        @('win-x64','7.6.7','InProcess'),@('win-arm64','7.6.7','InProcess'),
        @('win-x64','7.7.0-preview.5','InProcess'),@('win-arm64','7.7.0-preview.5','InProcess'),
        @('win-x64','7.6.7','Process'),@('win-arm64','7.6.7','Process'),
        @('linux-x64','7.6.7','InProcess'),@('linux-arm64','7.6.7','InProcess'),
        @('linux-musl-x64','7.6.7','InProcess'),@('linux-musl-arm64','7.6.7','InProcess')
    )
    $revision='c'*40;$index=0
    foreach($target in $targets){
        $job=Join-Path $inputRoot ('job-'+$index);$profiles=Join-Path $job profiling
        [void][IO.Directory]::CreateDirectory($profiles)
        $collectors=@(foreach($number in 1..$(if($target[2] -ceq 'Process'){2}else{1})){
            $name='synthetic-'+$number+'.nettrace';$bytes=[Text.Encoding]::UTF8.GetBytes('Explicit synthetic trace fixture '+$index+' '+$number)
            [IO.File]::WriteAllBytes((Join-Path $profiles $name),$bytes)
            Write-WorkspaceJson (Join-Path $profiles ($name+'.speedscope.json')) @{SyntheticIntegrityFixture=$true}
            @{TargetProcessId=(1000+$index*2+$number);Trace=$name;Speedscope=($name+'.speedscope.json');TraceBytes=$bytes.Length;SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));ObservedFrameNames=@{CoreCSharp=3;PowerShellRuntime=2;DotNetLibraries=4;OtherOrUnresolved=1}}
        })
        $syntheticProfile=@{SyntheticIntegrityFixture=$true;State='Success';ProfilerVersion='4.3.0';ClrProfilerVersion='10.0.750501';TargetIdentity=@{EngineMode=$target[2]};Collectors=$collectors}
        Write-WorkspaceJson (Join-Path $profiles summary.json) $syntheticProfile
        Write-WorkspaceJson (Join-Path $profiles powershell.speedscope.json) @{SyntheticIntegrityFixture=$true}
        Write-WorkspaceJson (Join-Path $profiles powershell-lines.json) @{SyntheticIntegrityFixture=$true;Lines=@(
            @{Category='CorePowerShellFacade';Path='synthetic<script>alert(1)</script>.ps1';Line=17;Hits=7;SelfMs=1.25;InclusiveMs=2.5},
            @{Category='UserCallbacksAndWorkload';Path='synthetic-workload.ps1';Line=3;Hits=2;SelfMs=0.25;InclusiveMs=0.5}
        )}
        $scenarios=@(foreach($scenario in 1..8){@{Name=('Synthetic '+$scenario);Human=@{Samples=@(@{Kind='First';InvocationMs=4;ReferenceMs=2;CallbackMs=1},@{Kind='WarmEngine';InvocationMs=3;ReferenceMs=2;CallbackMs=1})};Samples=@(1,2)}})
        $core=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Performance=@(@{Kind='FreshSessionImport';Statistics=@{ElapsedMs=@{Import=@{Median=2;P95=3}};AllocatedBytes=@{PairedDelta=@{Median=1024}}}});Integration=@(@{Kind='ControlledGitStatus';Scenarios=$scenarios})}
        Write-WorkspaceJson (Join-Path $job summary.json) @{SyntheticIntegrityFixture=$true;State=@{State='Success';Platform=$target[0];Passed=1;Failed=0};Suites=@($core);Profiling=$syntheticProfile;EngineIdentity=@{Mode=$target[2]};PowerShellVersion=$target[1];HostRuntime='10.0.14'}
        $index++
    }
    $null=& $builder -ReportRoot $inputRoot -OutputDirectory $bundle -Revision $revision -RequireProfiling
    $output=Join-Path $RunDirectory synthetic-matrix-html
    $result=& $renderer -EvidenceRoot $bundle -OutputDirectory $output -Revision $revision -ExpectedReports 10 -Suite All
    Assert-QuietEqual $result.Rows 10
    Assert-QuietEqual $result.Gaps 0
    $data=Get-Content (Join-Path $output PERFORMANCES_RESULTS.json) -Raw -Encoding utf8|ConvertFrom-Json
    Assert-QuietEqual $data.ProfilingLines.Count 20
    Assert-QuietEqual $data.Collectors.Count 12 'Isolated hosts retain both CLR collectors'
    $html=[IO.File]::ReadAllText($result.Html,[Text.Encoding]::UTF8)
    foreach($needle in @('PowerShell line hotspots','CLR trace provenance','linux-musl-arm64','CorePowerShellFacade','1.25','7.7.0-preview.5','Content-Security-Policy','&lt;script&gt;')){if(!$html.Contains($needle)){throw ('MatrixHtmlDetailMissing: '+$needle)}}
    if($html.Contains('<script>') -or $html -match '<(?:script|link|img)\b'){throw 'MatrixHtmlAllowsActiveOrExternalContent'}
    # Copying the same successful subject ten times must never pass cardinality as a complete matrix.
    $job0=Get-Content (Join-Path $inputRoot job-0/summary.json) -Raw -Encoding utf8|ConvertFrom-Json
    Write-WorkspaceJson (Join-Path $inputRoot job-1/summary.json) $job0
    $duplicate=Join-Path $RunDirectory synthetic-duplicate-bundle
    $null=& $builder -ReportRoot $inputRoot -OutputDirectory $duplicate -Revision $revision -RequireProfiling
    $rejected=$false;$badOutput=Join-Path $RunDirectory synthetic-duplicate-html
    try{$null=& $renderer -EvidenceRoot $duplicate -OutputDirectory $badOutput -Revision $revision -ExpectedReports 10 -Suite All}catch{$rejected=$_.Exception.Message -ceq 'PerformanceReportEvidenceIncomplete'}
    Assert-QuietEqual $rejected $true 'Duplicate environments cannot replace missing targets'
    if(![IO.File]::ReadAllText((Join-Path $badOutput PERFORMANCES_RESULTS.html),[Text.Encoding]::UTF8).Contains('INCOMPLETE')){throw 'DuplicateMatrixFailureHtmlMissing'}
    $job0.Profiling=$null
    Write-WorkspaceJson (Join-Path $inputRoot job-0/summary.json) $job0
    $missing=Join-Path $RunDirectory synthetic-missing-profile-bundle
    $null=& $builder -ReportRoot $inputRoot -OutputDirectory $missing -Revision $revision -RequireProfiling
    $rejected=$false
    try{$null=& $renderer -EvidenceRoot $missing -OutputDirectory (Join-Path $RunDirectory synthetic-missing-profile-html) -Revision $revision -ExpectedReports 10 -Suite All}catch{$rejected=$_.Exception.Message -ceq 'PerformanceReportEvidenceIncomplete'}
    Assert-QuietEqual $rejected $true 'Functional success cannot substitute for absent profiling'
    $preview=Join-Path $RunDirectory html-preview-must-not-exist
    $null=& $renderer -EvidenceRoot $bundle -OutputDirectory $preview -Revision $revision -ExpectedReports 10 -WhatIf
    Assert-QuietEqual (Test-Path $preview) $false
    Write-WorkspaceJson (Join-Path $RunDirectory synthetic-matrix-validation.json) @{SyntheticIntegrityFixture=$true;Rows=10;PowerShellLines=20;ClrCollectors=12;DuplicateRejected=$true;MissingProfilingRejected=$true;HtmlEscaping=$true;PreviewNoWrites=$true;HostedProfilingExecuted=$false}
}
