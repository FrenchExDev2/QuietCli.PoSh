#Requires -Version 7.6
<#
.SYNOPSIS
Runs deterministic offline regression, property, fuzz and mutation checks.
.PARAMETER ModulePath
Readiness module under test.
.PARAMETER NoMutations
Runs assertions only, used for isolated mutants.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$ModulePath = (Join-Path $PSScriptRoot '../scripts/lib/DotNetReadiness.psm1'), [switch]$NoMutations)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Run offline .NET readiness fixtures and bounded mutations')){return}
$ErrorActionPreference = 'Stop'
$module = Import-Module $ModulePath -Force -PassThru
$assertions = 0
function Assert-Readiness {
    <#
    .SYNOPSIS
    Fails when an independently specified observable invariant is false.
    #>
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (!$Condition) { throw "Assertion failed: $Message" }
}
try {
    & $module {
        $script:HttpCalls = 0
        $script:LocalCalls = 0
        $script:HttpStatus = 200
        $script:BadBody = $false
        $script:SingleManifest = $false
        $script:ArchiveStatus = 200
        $script:LocalSuccess = $true
        $script:LocalVersion = '11.0.100'
        $script:Versions = @('11.0.100-rc.10.1','11.0.100-rc.2.1','11.0.100','11.0.101')
        $script:TransportFailure = $false
        function script:New-FixtureMetadata {
            <#
            .SYNOPSIS
            Creates release evidence independent of selection logic.
            #>
            @{ 'channel-version' = '11.0'; releases = @(foreach ($v in $script:Versions) {
                @{ 'release-version' = '11.0.0'; 'release-date' = '2026-11-10'; sdk = @{version=$v;files=@(@{
                    name='dotnet-sdk-linux-x64.tar.gz';rid='linux-x64';url='https://builds.dotnet.microsoft.com/dotnet/Sdk/test.tar.gz';hash=('a'*128)
                })}}
            }) }
        }
        function script:Invoke-DotNetReadinessHttp {
            <#
            .SYNOPSIS
            Supplies deterministic public endpoint responses without I/O.
            #>
            param($Uri,$Method='GET',$TimeoutSeconds)
            $script:HttpCalls++
            if ($script:TransportFailure) { throw 'Synthetic TLS failure.' }
            if ($Method -eq 'HEAD') { return [pscustomobject]@{StatusCode=$script:ArchiveStatus;Body='';Digest=$null} }
            if ([string]$Uri -like '*/releases.json') {
                return [pscustomobject]@{StatusCode=200;Body=(New-FixtureMetadata | ConvertTo-Json -Depth 15);Digest=$null}
            }
            $data = if ([string]$Uri -like '*/blobs/*') { @{os='linux';architecture='amd64'} }
                elseif ($script:SingleManifest) { @{schemaVersion=2;config=@{digest=('sha256:'+('b'*64))}} }
                else { @{schemaVersion=2;manifests=@(
                    @{digest=('sha256:'+('c'*64));platform=@{os='linux';architecture='amd64'}},
                    @{digest=('sha256:'+('d'*64));platform=@{os='linux';architecture='arm64'}}
                )} }
            [pscustomobject]@{StatusCode=$script:HttpStatus;Body=$(if($script:BadBody){'malformed{'}else{$data|ConvertTo-Json -Depth 10});Digest=('sha256:'+('e'*64))}
        }
        function script:Get-DotNetReadinessLocal {
            <#
            .SYNOPSIS
            Models independent SDK/runtime command outcomes.
            #>
            param($ProjectPath,$QuietCliRoot)
            $script:LocalCalls++
            $r=@{}
            foreach($kind in @('Sdk','Runtime','Selected')) {
                $version=if($kind -eq 'Runtime'){'11.0.0'}else{$script:LocalVersion}
                $r[$kind]=@{Success=$script:LocalSuccess;Records=@([pscustomobject]@{Version=$version;Name=$(if($kind -eq 'Runtime'){'Microsoft.NETCore.App'}else{'SDK'})})}
            }
            $r
        }
    }
    $options = @{ Rid = @('linux-x64'); ProjectPath = $PSScriptRoot; Confirm = $false }
    $report = Get-DotNetReadiness @options
    Assert-Readiness ($report.Ready -and $report.SelectedSdk -eq '11.0.101') 'Successful evidence establishes readiness and selects latest patch.'
    Assert-Readiness ($report.Checks.Count -eq 9) 'Report contains publication, archive, four images, three local checks.'
    $release=Get-DotNetSdkRelease -Channel 11.0 -Confirm:$false
    Assert-Readiness ($release.Version -eq '11.0.101') 'Shared release lookup selects the latest stable SDK.'
    $release=Get-DotNetSdkRelease -Channel 11.0 -Version 11.0.100 -Confirm:$false
    Assert-Readiness ($release.Version -eq '11.0.100') 'Explicit SDK lookup preserves an exact older published patch.'
    $release=Get-DotNetSdkRelease -Channel 11.0 -Version 11.0.100-rc.2.1 -Preleases -Confirm:$false
    Assert-Readiness ($release.Version -eq '11.0.100-rc.2.1') 'Exact RC lookup requires and honors the prerelease policy.'
    $failed=$false
    try{$null=Get-DotNetSdkRelease -Channel 11.0 -Version 12.0.100 -Confirm:$false}catch{$failed=$true}
    Assert-Readiness $failed 'Shared release lookup rejects versions from another channel.'
    $before=& $module {@($script:HttpCalls,$script:LocalCalls)}
    $null=Get-DotNetSdkRelease -WhatIf
    $null=Get-DotNetInstallation -WhatIf
    $null=Invoke-DotNetContainerPull -ContainerRuntime docker -Image 'mcr.microsoft.com/dotnet/sdk:11.0' -WhatIf
    $after=& $module {@($script:HttpCalls,$script:LocalCalls)}
    Assert-Readiness (($before -join ',') -eq ($after -join ',')) 'Shared helper previews perform no HTTP/native probes.'
    $report = Get-DotNetReadiness @options -SkipLocal
    Assert-Readiness ($report.PublicationReady -and !$report.Ready -and !$report.LocalReady) 'Publication alone never proves local readiness.'
    & $module { $script:Versions=@('11.0.100-rc.2.1','11.0.100-rc.10.1') }
    $report = Get-DotNetReadiness @options
    Assert-Readiness (!$report.SelectedSdk -and !$report.PublicationReady) 'Stable policy rejects every prerelease.'
    $report = Get-DotNetReadiness @options -Preleases
    Assert-Readiness ($report.SelectedSdk -eq '11.0.100-rc.10.1') 'RC numeric precedence is semantic, not lexical.'
    Assert-Readiness (@($report.Checks | Where-Object { $_.Category -eq 'Image' -and $_.Target -like '*:11.0-preview' }).Count -eq 4) 'RC images use official preview tag convention.'
    & $module { $script:Versions=@('11.0.100-rc.10.1','11.0.100') }
    Assert-Readiness ((Get-DotNetReadiness @options -Preleases).SelectedSdk -eq '11.0.100') 'GA supersedes RC when prereleases are included.'
    foreach ($status in @(401,403,408,429,500,502,503)) {
        & $module { param($s) $script:HttpStatus=$s } $status
        $report=Get-DotNetReadiness @options
        Assert-Readiness (@($report.Checks|Where-Object {$_.Category -eq 'Image' -and $_.Status -eq 'Unknown'}).Count -eq 4 -and !$report.Ready) "HTTP $status remains unknown."
    }
    & $module { $script:HttpStatus=404 }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (@($report.Checks|Where-Object {$_.Category -eq 'Image' -and $_.Status -eq 'Missing'}).Count -eq 4) 'Only explicit registry 404 proves missing tag.'
    & $module { $script:HttpStatus=200; $script:BadBody=$true }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (!$report.Ready -and @($report.Checks|Where-Object Status -eq Unknown).Count -eq 4) 'Malformed manifests cannot pass.'
    & $module { $script:BadBody=$false; $script:SingleManifest=$true }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (!$report.PublicationReady -and @($report.Checks|Where-Object {$_.Category -eq 'Image' -and $_.Status -eq 'Missing'}).Count -eq 4) 'Single image config cannot satisfy missing arm64.'
    $report=Get-DotNetReadiness @options -Platform linux/amd64
    Assert-Readiness ($report.PublicationReady) 'Single manifest config proves its actual platform.'
    & $module { $script:SingleManifest=$false; $script:ArchiveStatus=403 }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (!$report.Ready -and @($report.Checks|Where-Object {$_.Category -eq 'SdkArchive' -and $_.Status -eq 'Unknown'}).Count -eq 1) 'Archive auth error cannot mean available or absent.'
    & $module { $script:ArchiveStatus=404 }
    Assert-Readiness (@((Get-DotNetReadiness @options).Checks|Where-Object {$_.Category -eq 'SdkArchive' -and $_.Status -eq 'Missing'}).Count -eq 1) 'Missing archive prevents readiness.'
    & $module { $script:ArchiveStatus=200; $script:LocalSuccess=$false }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (!$report.LocalReady -and @($report.Checks|Where-Object Status -eq Unknown).Count -eq 3) 'Failed native execution invalidates otherwise valid records.'
    & $module { $script:LocalSuccess=$true; $script:LocalVersion='11.0.100-rc.3.1' }
    Assert-Readiness (!(Get-DotNetReadiness @options).LocalReady) 'Installed RC does not establish stable readiness.'
    & $module { $script:TransportFailure=$true }
    $report=Get-DotNetReadiness @options
    Assert-Readiness (!$report.PublicationReady -and $report.Checks[0].Status -eq 'Unknown') 'TLS failure is not absence.'
    & $module { $script:TransportFailure=$false }
    $previewPath=Join-Path ([IO.Path]::GetTempPath()) ('readiness-preview-'+[guid]::NewGuid()+'.json')
    $before=& $module { @($script:HttpCalls,$script:LocalCalls) }
    $report=Get-DotNetReadiness @options -WhatIf -ReportPath $previewPath
    $after=& $module { @($script:HttpCalls,$script:LocalCalls) }
    Assert-Readiness (($before -join ',') -eq ($after -join ',') -and !(Test-Path $previewPath)) 'WhatIf performs no probes and creates no file.'
    Assert-Readiness (!$report.Ready -and @($report.Checks|Where-Object Status -ne NotChecked).Count -eq 0) 'Preview never reports availability.'
    [IO.File]::WriteAllText($previewPath,'preserve é',[Text.UTF8Encoding]::new($false))
    $null=Get-DotNetReadiness @options -WhatIf -ReportPath $previewPath
    Assert-Readiness ((Get-Content $previewPath -Raw -Encoding utf8) -eq 'preserve é') 'Preview preserves an existing report.'
    try {
        $objects=@(Get-DotNetReadiness @options -SkipLocal -ReportPath $previewPath)
        $saved=Get-Content $previewPath -Raw -Encoding utf8
        Assert-Readiness ($objects.Count -eq 1 -and ($saved|ConvertFrom-Json).SchemaVersion -eq 1 -and !$saved.Contains("`r")) 'Report write returns exactly one object and UTF-8/LF JSON.'
    } finally { Remove-Item -LiteralPath $previewPath -Force }
    # Generated independent maximum oracle, with reproducible seed and shuffled order.
    $random=[Random]::new(110100)
    foreach ($case in 1..80) {
        $patches=@(1..12|ForEach-Object {$random.Next(100,400)})
        $versions=@($patches|ForEach-Object {"11.0.$_"})
        & $module { param($v) $script:Versions=$v } $versions
        $selected=& $module { Select-DotNetReadinessSdk -Metadata (New-FixtureMetadata) -Channel '11.0' }
        Assert-Readiness ($selected.Version -eq "11.0.$(($patches|Measure-Object -Maximum).Maximum)") "Generated stable maximum seed 110100 case $case."
    }
    foreach ($bad in @('','garbage','11','11.0','11.0.100 bad','11.0.100 [','Microsoft.NETCore.App bogus [/tmp]','11.0.100 [ok] extra',"bad`n11.0.100")) {
        foreach ($kind in @('Sdk','Runtime','Selected')) {
            $failed=$false
            try { $parsed=& $module {param($text,$k) ConvertFrom-DotNetReadinessRecord -Text $text -Kind $k} $bad $kind; $failed=$null -eq $parsed } catch { $failed=$true }
            Assert-Readiness $failed "Malformed $kind discovery cannot create evidence."
        }
    }
    foreach ($ending in @('',"`r","`n","`r`n")) {
        $parsed=& $module {param($t) ConvertFrom-DotNetReadinessRecord -Text $t -Kind Sdk} "11.0.100 [C:\Program Files\dotnet\sdk]$ending"
        Assert-Readiness ($parsed.Version -eq '11.0.100') 'Native discovery accepts documented records with CRLF/LF.'
    }
    $fuzzRandom=[Random]::new(110101)
    $alphabet='abcdefghijklmnopqrstuvwxyz0123456789éà中#%'
    foreach($case in 1..100) {
        $pathText=-join @(1..($fuzzRandom.Next(1,40))|ForEach-Object {$alphabet[$fuzzRandom.Next($alphabet.Length)]})
        $patch=$fuzzRandom.Next(100,1000)
        $invalid=switch($fuzzRandom.Next(4)) {
            0 { 'fault:11.0.{0} [{1}]' -f $patch,$pathText }
            1 { '11.0.{0} [{1}] extra' -f $patch,$pathText }
            2 { '11.0.-{0} [{1}]' -f $patch,$pathText }
            3 { '11.0.{0} [{1}' -f $patch,$pathText }
        }
        $rejected=$false
        try{$null=& $module {param($t) ConvertFrom-DotNetReadinessRecord -Text $t -Kind Sdk} $invalid}catch{$rejected=$true}
        Assert-Readiness $rejected "Generated malformed SDK record seed 110101 case $case."
    }
    foreach($badChannel in @('11','../11.0','11.0/../../x','11.0?foo','0.0')) {
        $failed=$false
        try {$null=Get-DotNetReadiness -Channel $badChannel -WhatIf} catch {$failed=$true}
        Assert-Readiness $failed 'Malformed channels cannot enter URL construction.'
    }
    $killed=0
    if (!$NoMutations) {
        $source=Get-Content $ModulePath -Raw -Encoding utf8
        $mutations=@(
            @('stable-filter','if (!$Preleases -and $version.PreReleaseLabel) { continue }','if ($false) { continue }'),
            @('semantic-order','Sort-Object SemanticVersion -Descending','Sort-Object SemanticVersion'),
            @('platform-check',"if (`$missing.Count) { 'Missing' } else { 'Available' }","if (`$false) { 'Missing' } else { 'Available' }"),
            @('registry-absence','if ($response.StatusCode -eq 404)', 'if ($response.StatusCode -eq 403)'),
            @('preview-probes',"if (`$PSCmdlet.ShouldProcess(`".NET `$Channel (`$metadataUrl)`", 'Read release metadata, HEAD SDK archives and query MCR manifests'))",'if ($true)'),
            @('archive-success',"if (`$head.StatusCode -ge 200 -and `$head.StatusCode -lt 300)","if (`$head.StatusCode -ge 200 -and `$head.StatusCode -lt 500)"),
            @('local-evidence',"`$localReady = `$localChecks.Count -eq 3 -and @(`$localChecks | Where-Object Status -ne Available).Count -eq 0",'$localReady = $true')
        )
        foreach($mutation in $mutations) {
            if(!$source.Contains($mutation[1])) { throw "Invalid mutation anchor: $($mutation[0])" }
            $directory=Join-Path ([IO.Path]::GetTempPath()) ('readiness-mutant-'+[guid]::NewGuid())
            $null=[IO.Directory]::CreateDirectory($directory)
            $mutant=Join-Path $directory 'DotNetReadiness.psm1'
            try {
                [IO.File]::WriteAllText($mutant,$source.Replace($mutation[1],$mutation[2]),[Text.UTF8Encoding]::new($false))
                $detected=$false
                try { $null=& $PSCommandPath -ModulePath $mutant -NoMutations } catch {
                    if ($_.Exception.Message -notlike 'Assertion failed:*') { throw "Invalid/crashed mutant $($mutation[0]): $($_.Exception.Message)" }
                    $detected=$true
                }
                if(!$detected) { throw "Surviving mutant: $($mutation[0])" }
                $killed++
                Write-Output "Killed mutant: $($mutation[0])"
            } finally { Remove-Item -LiteralPath $mutant -Force; Remove-Item -LiteralPath $directory -Force }
        }
    }
    [pscustomobject]@{State='Passed';Assertions=$assertions;PropertyCases=80;FuzzCases=132;MutantsKilled=$killed;Seed=110100;FuzzSeed=110101}
} finally { Remove-Module $module -Force -ErrorAction SilentlyContinue }
