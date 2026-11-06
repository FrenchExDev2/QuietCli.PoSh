function Assert-QuietHostMatrix {
    <#
    .SYNOPSIS
    Requires stable/preview integrated coverage on both native Windows architectures and retained isolation.
    .PARAMETER WorkspaceRoot
    Workspace containing the reusable workflow and reviewed host lock.
    #>
    param([string]$WorkspaceRoot)
    $lock=Get-Content (Join-Path $WorkspaceRoot 'build/powershell-hosts.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
    $workflow=Get-Content (Join-Path $WorkspaceRoot '.github/workflows/ci.yml') -Raw -Encoding utf8
    $windows=[regex]::Match($workflow,'(?ms)^  windows:.*?(?=^  linux-images:)').Value
    $rows=@([regex]::Matches($windows,'(?ms)^          - image:.*?(?=^          - image:|^    runs-on:)'))
    if($rows.Count -ne 6){throw 'WindowsHostMatrixCardinalityMismatch'}
    foreach($rid in @('win-x64','win-arm64')){
        foreach($channel in @('stable','preview')){
            $hostSpec=@($lock.Hosts|Where-Object {$_.Rid -ceq $rid -and $_.Channel -ceq $channel})
            if($hostSpec.Count -ne 1 -or $hostSpec[0].SHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'MatrixHostLockMissing'}
            $match=@($rows|Where-Object {$_.Value -match "(?m)^            rid: $rid\r?$" -and $_.Value -match "(?m)^            channel: $channel\r?$" -and $_.Value -match '(?m)^            mode: InProcess\r?$'})
            if($match.Count -ne 1){throw 'IntegratedHostMatrixEntryMissing'}
            $version=[regex]::Escape($hostSpec[0].Version)
            $major=if($channel -eq 'stable'){10}else{11}
            if($hostSpec[0].RuntimeMajor -ne $major -or $match[0].Value -notmatch "(?m)^            host_version: $version\r?$" -or $match[0].Value -notmatch "(?m)^            runtime_major: $major\r?$"){throw 'MatrixHostRuntimeMismatch'}
        }
        if(@($rows|Where-Object {$_.Value -match "(?m)^            rid: $rid\r?$" -and $_.Value -match '(?m)^            mode: Process\r?$'}).Count -ne 1){throw 'IsolatedHostCoverageRemoved'}
    }
    if($workflow -notmatch 'needs: \[windows, linux, pty-mutation, performance-results\]'){throw 'HostMatrixNotRequiredByQualification'}
}
