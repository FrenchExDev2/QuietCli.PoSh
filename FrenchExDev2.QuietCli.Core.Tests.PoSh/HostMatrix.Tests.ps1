function Assert-QuietHostMatrix {
    <#
    .SYNOPSIS
    Requires GA integrated/isolated coverage on both native architectures and opt-in future preview.
    .PARAMETER WorkspaceRoot
    Workspace containing the reusable workflow and reviewed host lock.
    #>
    param([string]$WorkspaceRoot)
    $lock=Get-Content (Join-Path $WorkspaceRoot 'build/powershell-hosts.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
    $workflow=Get-Content (Join-Path $WorkspaceRoot '.github/workflows/ci.yml') -Raw -Encoding utf8
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/GitHubCi.psm1') -DisableNameChecking -ErrorAction Stop
    $selection=Get-GitHubCiWindowsMatrix $lock
    $rows=@($selection.Matrix.include)
    if($rows.Count -ne 4 -or $selection.ExpectedReports -ne 8){throw 'WindowsHostMatrixCardinalityMismatch'}
    if(!$workflow.Contains('matrix: ${{ fromJson(needs.linux-matrix.outputs.windows_matrix) }}') -or !$workflow.Contains('EXPECTED_REPORTS: ${{ needs.linux-matrix.outputs.expected_reports }}') -or !$workflow.Contains('-ExpectedReports ([int]$env:EXPECTED_REPORTS)')){throw 'WindowsHostMatrixPlanNotConsumed'}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $parsed=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize($workflow)
    foreach($trigger in @('workflow_call','workflow_dispatch')){
        $option=$parsed['on'][$trigger]['inputs']['run_preview']
        if(!$option -or $option['type'] -cne 'boolean' -or [string]$option['default'] -cne 'false'){throw 'PowerShellPreviewMustBeOptIn'}
    }
    foreach($rid in @('win-x64','win-arm64')){
        $hostSpec=@($lock.Hosts|Where-Object {$_.Rid -ceq $rid -and $_.Channel -ceq 'stable'})
        if($hostSpec.Count -ne 1 -or $hostSpec[0].SHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'MatrixHostLockMissing'}
        foreach($mode in @('Process','InProcess')){
            $match=@($rows|Where-Object {$_.rid -ceq $rid -and $_.channel -ceq 'stable' -and $_.mode -ceq $mode})
            if($match.Count -ne 1){throw 'ProductionHostMatrixEntryMissing'}
            if($match[0].host_version -cne $lock.StableVersion -or $match[0].runtime_major -ne $hostSpec[0].RuntimeMajor){throw 'MatrixHostRuntimeMismatch'}
        }
    }
    $gate=[regex]::Match($workflow,'(?ms)^  qualification-gate:.*?(?=^  [a-z][a-z-]*:|\z)').Value
    Assert-QuietHostQualificationDependencies $gate
    # Dependency order and additional prerequisites do not remove host coverage.
    $random=[Random]::new(611112)
    foreach($round in 1..32){
        $names=@('windows','linux-result','linux-matrix','performance-results','future-evidence')|Sort-Object {$random.Next()}
        Assert-QuietHostQualificationDependencies ('    needs: ['+($names -join ', ')+']')
    }
    foreach($removed in @('windows','linux-result','linux-matrix','performance-results')){
        $names=@('windows','linux-result','linux-matrix','performance-results')|Where-Object {$_ -cne $removed}
        $rejected=$false
        try{Assert-QuietHostQualificationDependencies ('    needs: ['+($names -join ', ')+']')}catch{$rejected=$_.Exception.Message -ceq 'HostMatrixNotRequiredByQualification'}
        if(!$rejected){throw ('HostQualificationDependencyRemovalAccepted: '+$removed)}
    }
}

function Assert-QuietHostQualificationDependencies {
    <#
    .SYNOPSIS
    Requires all matrix and profiling prerequisites regardless of ordering or additional gates.
    .PARAMETER Workflow
    Qualification job text containing one literal inline dependency list.
    #>
    param([string]$Workflow)
    $match=[regex]::Matches($Workflow,'(?m)^    needs: \[([^\]\r\n]+)\]\s*$')
    if($match.Count -ne 1){throw 'HostMatrixNotRequiredByQualification'}
    $needs=@($match[0].Groups[1].Value.Split(',')|ForEach-Object {$_.Trim()})
    if(@($needs|Select-Object -Unique).Count -ne $needs.Count){throw 'HostMatrixNotRequiredByQualification'}
    foreach($required in @('windows','linux-result','linux-matrix','performance-results')){
        if($required -cnotin $needs){throw 'HostMatrixNotRequiredByQualification'}
    }
}
