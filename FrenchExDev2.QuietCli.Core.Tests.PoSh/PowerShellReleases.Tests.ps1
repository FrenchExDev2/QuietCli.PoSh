function Test-QuietPowerShellReleasePolicy {
    <#
    .SYNOPSIS
    Checks independent GA/preview matrices, resource rejection and no-effect previews without network.
    .PARAMETER WorkspaceRoot
    Checkout containing resource and matrix subjects.
    .PARAMETER RunDirectory
    Owned property and fixture report root.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/PowerShellReleases.psm1') -Force
    . (Join-Path $WorkspaceRoot 'scripts/GitHubCi.ps1')
    $base=Get-Content (Join-Path $WorkspaceRoot 'build/ci-images.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
    $evidence=[pscustomobject]@{Stable='7.7.0';RuntimeMajor=11;AutomationPackage=@{Version='7.7.0';Available=$true;Status=200};Assets=@(foreach($rid in @('win-x64','win-arm64','linux-x64','linux-arm64')){
        $name=if($rid.StartsWith('win-')){"PowerShell-7.7.0-$rid.zip"}else{"powershell-7.7.0-$rid.tar.gz"}
        [pscustomobject]@{Name=$name;Available=$true;Status=200;SHA256=('a'*64);Url=('https://github.com/PowerShell/PowerShell/releases/download/v7.7.0/'+$name)}
    });Alpine=@([pscustomobject]@{Architecture='x86_64';Available=$true;Version=$base.AlpinePowerShellPackage},[pscustomobject]@{Architecture='aarch64';Available=$true;Version=$base.AlpinePowerShellPackage});NextPreview=[pscustomobject]@{Version='7.8.0-preview.1';Available=$false;RuntimeMajor=$null;Release=$null}}
    $refused=$false;try{$null=New-QuietPowerShellResourcePlan $evidence $base}catch{$refused=$_.Exception.Message -like 'AlpinePowerShellGaUnavailable*'}
    Assert-QuietEqual $refused $true 'Alpine lag requires an explicit exception'
    $plan=New-QuietPowerShellResourcePlan $evidence $base -AllowAlpineVersionLag
    Assert-QuietEqual $plan.ImageLock.SDK $base.SDK
    Assert-QuietEqual $plan.ImageLock.AlpineRuntime $base.AlpineRuntime
    Assert-QuietEqual ($plan.ImageLock.Platforms.Base -join '|') ($base.Platforms.Base -join '|')
    Assert-QuietEqual $plan.AlpineException $true
    Assert-QuietEqual (@($plan.HostLock.Hosts|Where-Object Channel -EQ preview).Count) 0 'Never invent an unavailable preview hash'
    $selection=Get-GitHubCiWindowsMatrix $plan.HostLock
    Assert-QuietEqual $selection.WindowsTargets 4
    Assert-QuietEqual $selection.ExpectedReports 8
    Assert-QuietEqual (@($selection.Matrix.include|Where-Object channel -NE stable).Count) 0
    $refused=$false;try{$null=Get-GitHubCiWindowsMatrix $plan.HostLock $true}catch{$refused=$_.Exception.Message -like 'PowerShellPreviewNotPublished*'}
    Assert-QuietEqual $refused $true
    $serialized=$evidence|ConvertTo-Json -Depth 12
    $damages=@(
        {param($r)$r.Assets[0].Available=$false},
        {param($r)$r.Assets[1].Status=404},
        {param($r)$r.Assets[2].SHA256='a'*63},
        {param($r)$r.Assets[3].Url='https://example.invalid/asset'},
        {param($r)$r.AutomationPackage.Available=$false},
        {param($r)$r.AutomationPackage.Version='7.6.9'},
        {param($r)$r.NextPreview.Version='7.7.0-preview.5'},
        {param($r)$r.Alpine[1].Architecture='x86_64'},
        {param($r)$r.Alpine[1].Available=$false},
        {param($r)$r.Alpine[1].Version='7.6.8-r0'}
    )
    foreach($damage in $damages){$bad=ConvertFrom-Json $serialized;& $damage $bad;$refused=$false;try{$null=New-QuietPowerShellResourcePlan $bad $base -AllowAlpineVersionLag}catch{$refused=$true};Assert-QuietEqual $refused $true 'Malformed availability must fail before lock writes'}
    $future=ConvertFrom-Json $serialized;$future.NextPreview.Available=$true;$future.NextPreview.RuntimeMajor=11
    $future.NextPreview.Release=[pscustomobject]@{assets=@(foreach($rid in @('win-x64','win-arm64')){[pscustomobject]@{name="PowerShell-7.8.0-preview.1-$rid.zip";browser_download_url="https://github.com/PowerShell/PowerShell/releases/download/v7.8.0-preview.1/PowerShell-7.8.0-preview.1-$rid.zip";digest=('sha256:'+('b'*64))}})}
    $futurePlan=New-QuietPowerShellResourcePlan $future $base -AllowAlpineVersionLag
    Assert-QuietEqual (Get-GitHubCiWindowsMatrix $futurePlan.HostLock).WindowsTargets 4 'A published preview still requires opt-in'
    $selected=Get-GitHubCiWindowsMatrix $futurePlan.HostLock $true
    Assert-QuietEqual $selected.WindowsTargets 6
    Assert-QuietEqual $selected.ExpectedReports 10
    Assert-QuietEqual (@($selected.Matrix.include|Where-Object {$_.channel -ceq 'preview' -and $_.mode -ceq 'InProcess'}).Count) 2
    $seed=20261112;$random=[Random]::new($seed);$properties=0
    foreach($round in 1..64){
        $lock=$futurePlan.HostLock|ConvertTo-Json -Depth 10|ConvertFrom-Json
        $lock.Hosts=@($lock.Hosts|Sort-Object {$random.Next()})
        $include=[bool]($round%2)
        $matrix=Get-GitHubCiWindowsMatrix $lock $include
        $expected=@('win-x64:stable:Process','win-x64:stable:InProcess','win-arm64:stable:Process','win-arm64:stable:InProcess')
        if($include){$expected+=@('win-x64:preview:InProcess','win-arm64:preview:InProcess')}
        $observed=@($matrix.Matrix.include|ForEach-Object {$_.rid+':'+$_.channel+':'+$_.mode})
        Assert-QuietEqual (($observed|Sort-Object) -join '|') (($expected|Sort-Object) -join '|')
        Assert-QuietEqual $matrix.ExpectedReports ($expected.Count+4)
        $properties+=2
    }
    $root=Join-Path $RunDirectory 'powershell-preview-no-effects'
    foreach($script in @('Test-PowerShellReleaseAvailability.ps1','Update-PowerShellCiLock.ps1')){$null=& (Join-Path $WorkspaceRoot ('scripts/'+$script)) -WhatIf}
    $null=& (Join-Path $WorkspaceRoot 'scripts/Select-PowerShellCiMatrix.ps1') -WorkspaceRoot $root -IncludePreview -OutputPath (Join-Path $root 'output') -WhatIf
    $null=& (Join-Path $WorkspaceRoot 'scripts/Initialize-PowerShellHost.ps1') -Channel preview -RuntimeIdentifier win-x64 -OutputDirectory $root -WhatIf
    Assert-QuietEqual (Test-Path $root) $false
    $unpublished=Join-Path $RunDirectory 'unpublished-host'
    $refused=$false
    try{$null=& (Join-Path $WorkspaceRoot 'scripts/Initialize-PowerShellHost.ps1') -Channel preview -RuntimeIdentifier win-x64 -OutputDirectory $unpublished}catch{$refused=$_.Exception.Message -like 'PowerShellPreviewNotPublished*'}
    Assert-QuietEqual $refused $true
    Assert-QuietEqual (Test-Path $unpublished) $false 'Unavailable Preview creates no extraction directory'
    $hostRoot=Join-Path $RunDirectory 'linux-host-archive'
    $inputDirectory=Join-Path $hostRoot input
    [void][IO.Directory]::CreateDirectory($inputDirectory)
    [IO.File]::WriteAllText((Join-Path $inputDirectory pwsh),'owned Linux archive',[Text.UTF8Encoding]::new($false))
    $archive=Join-Path $hostRoot fixture.tar.gz
    $file=[IO.File]::Create($archive)
    $gzip=[IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionLevel]::Optimal)
    try{[void][System.Formats.Tar.TarFile]::CreateFromDirectoryAsync($inputDirectory,$gzip,$false,[Threading.CancellationToken]::None).GetAwaiter().GetResult()}finally{$gzip.Dispose();$file.Dispose()}
    $hash=(Get-FileHash $archive -Algorithm SHA256).Hash
    Write-WorkspaceJson (Join-Path $hostRoot 'build/powershell-hosts.lock.json') @{SchemaVersion=1;Hosts=@(@{Channel='stable';Rid='linux-x64';Version='7.7.0';RuntimeMajor=11;SHA256=$hash})}
    $cache=Join-Path $hostRoot '.cache/powershell-hosts'
    [void][IO.Directory]::CreateDirectory($cache)
    Copy-Item -LiteralPath $archive -Destination (Join-Path $cache ($hash+'.tar.gz'))
    foreach($index in 1..2){
        $hostInfo=& (Join-Path $WorkspaceRoot 'scripts/Initialize-PowerShellHost.ps1') -Channel stable -RuntimeIdentifier linux-x64 -WorkspaceRoot $hostRoot -OutputDirectory (Join-Path $hostRoot ('output-'+$index))
        Assert-QuietEqual ([IO.File]::ReadAllText($hostInfo.Executable,[Text.Encoding]::UTF8)) 'owned Linux archive'
        Assert-QuietEqual $hostInfo.ArchiveSHA256 $hash
    }
    [IO.File]::WriteAllText((Join-Path $cache ($hash+'.tar.gz')),'tampered',[Text.UTF8Encoding]::new($false))
    $refused=$false
    try{$null=& (Join-Path $WorkspaceRoot 'scripts/Initialize-PowerShellHost.ps1') -Channel stable -RuntimeIdentifier linux-x64 -WorkspaceRoot $hostRoot -OutputDirectory (Join-Path $hostRoot damaged)}catch{$refused=$_.Exception.Message -ceq 'PowerShellHostCacheChecksumMismatch'}
    Assert-QuietEqual $refused $true 'A corrupt Linux archive must never be extracted'
    $matrixCode=(Get-Command Get-GitHubCiWindowsMatrix).ScriptBlock.ToString()
    $mutants=@(
        @{From='$IncludePreview=$false';To='$IncludePreview=$true'},
        @{From="@('Process','InProcess')";To="@('InProcess')"},
        @{From='($rows.Count+4)';To='($rows.Count+3)'}
    )
    foreach($mutant in $mutants){
        Assert-QuietEqual ($matrixCode.Contains($mutant.From)) $true
        $subject=[scriptblock]::Create($matrixCode.Replace($mutant.From,$mutant.To));$detected=$false
        try{$observed=& $subject $plan.HostLock;if($observed.WindowsTargets -ne 4 -or $observed.ExpectedReports -ne 8){$detected=$true}}catch{$detected=$true}
        Assert-QuietEqual $detected $true 'A matrix policy mutant must change independently asserted behavior'
    }
    Write-WorkspaceJson (Join-Path $RunDirectory 'powershell-release-policy.json') @{Seed=$seed;MatrixProperties=$properties;MalformedEvidence=$damages.Count;GuardMutantsDetected=$mutants.Count;ProductionTargets=8;OptionalPreviewTargets=2;AlpineLagExplicit=$true;PreviewNoEffects=$true;LinuxArchiveCacheHits=2;CorruptLinuxArchiveRejected=$true;NetworkUsed=$false}
}
