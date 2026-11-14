function Test-QuietCiDiagnostics {
    <#
    .SYNOPSIS
    Checks credential redaction, bounded failure exports, malformed inputs and local workflow selection.
    .PARAMETER WorkspaceRoot
    Checkout providing the independently exercised diagnostic scripts.
    .PARAMETER RunDirectory
    Owned directory for synthetic evidence and campaign results.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
    $seed=20261110;$random=[Random]::new($seed)
    for($i=0;$i -lt 128;$i++){
        $token='synthetic-'+[Convert]::ToHexString([byte[]]@(1..24|ForEach-Object {$random.Next(0,256)}))
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($token))
        $basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('fixture:'+ $token))
        $message="denied é漢 $token $encoded $basic"
        $redacted=ConvertTo-QuietCiRegistryDiagnostic $message $token fixture
        if($redacted.Contains($token) -or $redacted.Contains($encoded) -or $redacted.Contains($basic) -or !$redacted.StartsWith('denied é漢 ')){throw 'RegistryDiagnosticCredentialPropertyFailed'}
    }
    foreach($malformed in @('',"`0`n`r`e[31mdenied",('x'*10000),'ghs_syntheticToken123456789')){
        $text=ConvertTo-QuietCiRegistryDiagnostic $malformed '' fixture
        if($text.Length -gt 2048 -or $text -match '[\x00-\x1F\x7F]' -or $text -match 'ghs_synthetic'){throw 'RegistryDiagnosticBoundaryFailed'}
    }
    $functionSource=(Get-Command ConvertTo-QuietCiRegistryDiagnostic).ScriptBlock.ToString()
    $mutations=@(
        @{Name='redaction removed';From="`$Text.Replace(`$secret,'[REDACTED]')";To="`$Text.Replace('never-match','[REDACTED]')";Input='synthetic-credential';Token='synthetic-credential'},
        @{Name='bound removed';From='if($Text.Length -gt 2048)';To='if($false)';Input=('x'*10000);Token=''}
    )
    foreach($mutation in $mutations){
        if(!$functionSource.Contains($mutation.From)){throw 'RegistryDiagnosticInvalidMutant'}
        $mutant=[scriptblock]::Create($functionSource.Replace($mutation.From,$mutation.To))
        $observed=& $mutant -Text $mutation.Input -Token $mutation.Token -Actor fixture
        if($observed.Length -le 2048 -and (!$mutation.Token -or !$observed.Contains($mutation.Token))){throw 'RegistryDiagnosticMutantSurvived'}
    }
    $cases=@(1..12|ForEach-Object {[pscustomobject]@{Name="fixture-$_";State='Failed';Error=('diagnostic-é'+('x'*3000))}})
    $summary=[pscustomobject]@{State=[pscustomobject]@{State='Failed';Failed=12};Suites=@([pscustomobject]@{Cases=$cases})}
    $printed=@(& {Write-WorkspaceFailureDiagnostics -Summary $summary -RunDirectory 'fixture-reports'} 6>&1|ForEach-Object {"$_"})
    if(@($printed|Where-Object {$_ -like 'CI failed case:*'}).Count -ne 8 -or @($printed|Where-Object Length -GT 2100).Count){throw 'FailureConsoleDiagnosticBoundsChanged'}
    foreach($workflowName in @('ci.yml','publish-psgallery.yml')){
        $workflow=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot ".github/workflows/$workflowName"),[Text.Encoding]::UTF8)
        if(!$workflow.Contains('run: ./scripts/Export-CiFailureDiagnostics.ps1') -or !$workflow.Contains('path: artifacts/failure-diagnostics')){throw 'RedactedFailureArtifactWiringMissing'}
    }
    $fixture=Join-Path $RunDirectory 'failure-export-fixture'
    $reports=Join-Path $fixture 'artifacts/tests/run'
    [void][IO.Directory]::CreateDirectory($reports)
    $previous=$env:QUIETCLI_DIAGNOSTIC_TEST_TOKEN
    $token='ghs_syntheticExportCredential0123456789'
    $env:QUIETCLI_DIAGNOSTIC_TEST_TOKEN=$token
    try{
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($token))
        $lines=@("expected é漢 diagnostic",$token,$encoded,'Authorization: Bearer unknown-credential','password=unknown-password')
        [void][IO.File]::WriteAllTextAsync((Join-Path $reports 'worker.stderr.log'),($lines -join "`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        Write-WorkspaceJson (Join-Path $reports 'core-suite.json') @{Cases=@(@{Name='retained-assertion';State='Failed';Error='synthetic assertion diagnostic'});Performance=@(1..256)}
        foreach($name in @('.env','auth.json')){[void][IO.File]::WriteAllTextAsync((Join-Path $reports $name),'private-file-sentinel',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        [void][IO.File]::WriteAllTextAsync((Join-Path $reports 'worker.stdout.log'),('x'*1048577),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $result=& (Join-Path $WorkspaceRoot 'scripts/Export-CiFailureDiagnostics.ps1') -WorkspaceRoot $fixture
        $all=@(Get-ChildItem -LiteralPath $result.Directory -Recurse -File|ForEach-Object {[IO.File]::ReadAllText($_.FullName,[Text.Encoding]::UTF8)}) -join "`n"
        foreach($secret in @($token,$encoded,'unknown-credential','unknown-password','private-file-sentinel')){if($all.Contains($secret)){throw 'FailureExportCredentialOrPrivateFileLeaked'}}
        if(!$all.Contains('expected é漢 diagnostic') -or !$all.Contains('ExcludedOversized') -or !$all.Contains('retained-assertion')){throw 'FailureExportLostDiagnosticOrBounds'}
    }finally{$env:QUIETCLI_DIAGNOSTIC_TEST_TOKEN=$previous}
    $launcher=Join-Path $WorkspaceRoot 'scripts/Invoke-LocalWorkflow.ps1'
    $unused=Join-Path $RunDirectory 'whatif-must-not-exist'
    & $launcher -WorkspaceRoot $WorkspaceRoot -WrkflwPath 'absent-wrkflw' -Mode Run -Job core -RunDirectory $unused -WhatIf
    if(Test-Path -LiteralPath $unused){throw 'LocalWorkflowWhatIfWroteReports'}
    foreach($bad in @('../escape.yml','.github/workflows/../release.yml',"bad`nworkflow.yml")){
        $rejected=$false
        try{& $launcher -WorkspaceRoot $WorkspaceRoot -WrkflwPath absent -Workflow $bad -WhatIf}catch{$rejected=$true}
        if(!$rejected){throw 'LocalWorkflowMalformedPathAccepted'}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory 'ci-diagnostics-campaign.json') @{Seed=$seed;RegistryProperties=128;RegistryBoundaryCases=4;MutantsKilled=2;ExportFixtures=1;ConsoleFailureCases=12;MalformedWorkflowPaths=3;LocalWorkflowWhatIf='No execution or report directory';RealRegistryAccess=$false}
}
