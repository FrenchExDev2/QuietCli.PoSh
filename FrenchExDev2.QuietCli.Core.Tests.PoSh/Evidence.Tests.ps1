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
        $missingRoot=Join-Path $root "missing-report-$iteration"
        $rejected=$false
        try{$null=& $renderer -EvidenceRoot $outputRoot -OutputDirectory $missingRoot -Revision ('a'*40) -ExpectedReports 2 -Suite Git}catch{$rejected=$_.Exception.Message -eq 'PerformanceReportEvidenceIncomplete'}
        if(!$rejected -or !(Test-Path (Join-Path $missingRoot 'PERFORMANCES_RESULTS.md'))){throw 'MissingMatrixReportWasNotPublishedAsFailure'}
        $badBytes=[byte[]]$bytes.Clone();$badBytes[0]=$badBytes[0] -bxor 255
        [void][IO.File]::WriteAllBytesAsync($trace,$badBytes).GetAwaiter().GetResult()
        $rejected=$false
        try{$null=& $builder -ReportRoot $inputRoot -OutputDirectory (Join-Path $root "damaged-$iteration") -Revision ('a'*40) -RequireProfiling}catch{$rejected=$_.Exception.Message -eq 'MandatoryProfilingEvidenceMissing'}
        if(!$rejected){throw 'ModifiedClrEvidenceAccepted'}
    }
    $rejected=$false
    try{$null=& $builder -ReportRoot $inputRoot -OutputDirectory (Join-Path $inputRoot 'nested-output') -Revision ('a'*40)}catch{$rejected=$_.Exception.Message -eq 'EvidenceDestinationMustBeOutsideReports'}
    if(!$rejected){throw 'RecursiveEvidenceDestinationAccepted'}
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
