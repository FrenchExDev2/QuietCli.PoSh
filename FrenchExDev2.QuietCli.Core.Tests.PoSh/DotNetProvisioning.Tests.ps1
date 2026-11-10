#Requires -Version 7.6
<#
.SYNOPSIS
Exercises provisioning and SDK pin policies using isolated offline fixtures.
.PARAMETER ModulePath
Provisioning module under test.
.PARAMETER NoMutations
Run regressions, properties and fuzz cases without recursively generating mutants.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$ModulePath=(Join-Path $PSScriptRoot '../scripts/lib/DotNetProvisioning.psm1'),[switch]$NoMutations)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Run offline .NET provisioning fixtures and bounded mutations')){return}
$ErrorActionPreference='Stop'
$module=Import-Module $ModulePath -Force -PassThru
$assertions=0
$root=Join-Path ([IO.Path]::GetTempPath()) ('dotnet-provisioning-fixtures-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$oldPath=$env:PATH;$oldDotnetRoot=$env:DOTNET_ROOT
function Assert-Provisioning {
    <# .SYNOPSIS Enforces business invariants independently of implementation branches. #>
    param([bool]$Condition,[string]$Message)
    $script:assertions++
    if(!$Condition){throw "Assertion failed: $Message"}
}
function Assert-ProvisioningThrows {
    <# .SYNOPSIS Requires an operation to reject invalid evidence or policy. #>
    param([scriptblock]$Operation,[string]$Message)
    $rejected=$false
    try{$null=& $Operation}catch{$rejected=$true}
    Assert-Provisioning $rejected $Message
}
try {
    $fixtureDirectory=Join-Path $root 'archive-fixture'
    $null=[IO.Directory]::CreateDirectory($fixtureDirectory)
    [IO.File]::WriteAllText((Join-Path $fixtureDirectory 'dotnet.exe'),'fixture',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $fixtureDirectory 'dotnet'),'fixture',[Text.UTF8Encoding]::new($false))
    $fixtureZip=Join-Path $root 'fixture.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($fixtureDirectory,$fixtureZip)
    $fixtureHash=(Get-FileHash $fixtureZip -Algorithm SHA512).Hash
    & $module {
        param($zip,$hash,$fixtureRoot,$commonPath)
        $script:FixtureZip=$zip;$script:FixtureHash=$hash
        $script:FixtureRoot=$fixtureRoot;$script:CommonPath=$commonPath;$script:RuntimeResolveCalls=0
        $script:ResolutionCalls=0;$script:InventoryCalls=0;$script:DownloadCalls=0;$script:PullCalls=0
        $script:SdkPresent=$true;$script:RuntimeComplete=$true;$script:CorruptHash=$false;$script:PullFailure=$false
        function script:Get-DotNetSdkRelease {
            <# .SYNOPSIS Supplies a deterministic release with a real fixture archive hash. #>
            param($Channel,$Version,$Preleases,$Confirm)
            $script:ResolutionCalls++
            $rid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
            @{Version='11.0.100';RuntimeVersion='11.0.0';Files=@(@{rid=$rid;name='dotnet-sdk.zip';url='https://builds.dotnet.microsoft.com/dotnet/fixture.zip';hash=$(if($script:CorruptHash){'0'*128}else{$script:FixtureHash})})}
        }
        function script:Get-DotNetInstallation {
            <# .SYNOPSIS Supplies independent complete/incomplete SDK and runtime inventories. #>
            param($DotNetPath,$QuietCliRoot,$Confirm)
            $script:InventoryCalls++
            @{Sdk=@{Success=$script:SdkPresent;Records=@(@{Name='SDK';Version='11.0.100'})};Runtime=@{Success=$script:RuntimeComplete;Records=@(
                @{Name='Microsoft.NETCore.App';Version='11.0.0'},
                @{Name='Microsoft.AspNetCore.App';Version='11.0.0'},
                @{Name='Microsoft.WindowsDesktop.App';Version='11.0.0'}
            )}}
        }
        function script:Save-DotNetSdkArchive {
            <# .SYNOPSIS Copies the local zip fixture instead of performing a network download. #>
            param($Uri,$Destination,$TimeoutSeconds)
            $script:DownloadCalls++
            Copy-Item -LiteralPath $script:FixtureZip -Destination $Destination
        }
        function script:Invoke-DotNetContainerPull {
            <# .SYNOPSIS Models an explicit image pull without native calls. #>
            param($ContainerRuntime,$Image,$Platform,$QuietCliRoot,$Confirm)
            $script:PullCalls++
            if($script:PullFailure){throw 'Synthetic image pull failure.'}
            [pscustomobject]@{Image=$Image;Platform=$Platform;Status='Pulled'}
        }
        function script:Resolve-DotNetContainerRuntime {
            <# .SYNOPSIS Exercises the actual shared resolver against owned dotenv and discovery fixtures. #>
            param($ContainerRuntime,$WorkspaceRoot)
            $script:RuntimeResolveCalls++
            . $script:CommonPath
            function Get-Command {
                <# .SYNOPSIS Models installed clients without starting either client or a daemon. #>
                param($Name,$CommandType,$ErrorAction)
                if($Name -in @('docker','podman')){[pscustomobject]@{Name=$Name;CommandType='Application'}}
            }
            Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -Available -WorkspaceRoot $script:FixtureRoot
        }
    } $fixtureZip $fixtureHash $root (Join-Path $PSScriptRoot '../scripts/Common.ps1')
    $pin=Join-Path $root 'global.json'
    $original=@'
{
  // Preserve all unrelated values, including the Aspire pin.
  "sdk": { "version": "11.0.100-rc.3.1", "rollForward": "patch", "allowPrerelease": true },
  "msbuild-sdks": { "Aspire.AppHost.Sdk": "13.6.0" },
  "test": { "runner": "Microsoft.Testing.Platform" },
  "custom": { "unicode": "été 中", "values": [1, false, null] }
}
'@
    [IO.File]::WriteAllText($pin,$original,[Text.UTF8Encoding]::new($false))
    $originalHash=(Get-FileHash $pin -Algorithm SHA256).Hash
    $before=& $module {@($script:ResolutionCalls,$script:InventoryCalls,$script:DownloadCalls,$script:PullCalls)}
    $previewError=$null
    try{$null=Update-DotNetGlobalJson -Path $pin -Version 11.0.100 -WhatIf}catch{$previewError=$_}
    $after=& $module {@($script:ResolutionCalls,$script:InventoryCalls,$script:DownloadCalls,$script:PullCalls)}
    Assert-Provisioning (!$previewError -and ($before -join ',') -eq ($after -join ',') -and (Get-FileHash $pin -Algorithm SHA256).Hash -eq $originalHash) 'Pin preview succeeds without probes or writes.'
    Assert-Provisioning (@(Get-ChildItem $root -Filter '*.bak-*').Count -eq 0) 'Preview creates no backup.'
    $null=Update-DotNetGlobalJson -Path $pin -WhatIf
    Assert-Provisioning ((& $module {$script:ResolutionCalls}) -eq 0) 'Latest-version preview does not resolve metadata.'
    $result=Update-DotNetGlobalJson -Path $pin -Version 11.0.100 -SdkDirectory (Join-Path $root 'local SDK/11.0.100') -Confirm:$false
    $saved=Get-Content $pin -Raw -Encoding utf8
    $data=$saved|ConvertFrom-Json -AsHashtable
    Assert-Provisioning ($result.Status -eq 'Updated' -and $data.sdk.version -eq '11.0.100' -and !$data.sdk.allowPrerelease) 'Stable update changes version and disables prereleases.'
    Assert-Provisioning ($data.sdk.rollForward -eq 'patch' -and $data['msbuild-sdks']['Aspire.AppHost.Sdk'] -eq '13.6.0' -and $data.test.runner -eq 'Microsoft.Testing.Platform' -and $data.custom.unicode -eq 'été 中') 'Unrelated values and existing rollForward survive.'
    Assert-Provisioning ($data.sdk.paths[0] -eq 'local SDK/11.0.100' -and $data.sdk.paths[-1] -eq '$host$') 'Portable SDK paths are relative with host fallback.'
    Assert-Provisioning ((Get-FileHash $result.BackupPath -Algorithm SHA256).Hash -eq $originalHash) 'Backup preserves exact original bytes.'
    $bytes=[IO.File]::ReadAllBytes($pin)
    Assert-Provisioning (!$saved.Contains("`r") -and !($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'Updated documents are UTF-8/LF without BOM.'
    $count=@(Get-ChildItem $root -Filter '*.bak-*').Count
    $unchanged=Update-DotNetGlobalJson -Path $pin -Version 11.0.100 -Confirm:$false
    Assert-Provisioning ($unchanged.Status -eq 'Unchanged' -and @(Get-ChildItem $root -Filter '*.bak-*').Count -eq $count) 'Idempotent pin update makes no backup or rewrite.'
    Push-Location $root
    try {
        $relativePlan=Get-DotNetGlobalJsonPlan -Path './global.json' -Version 11.0.100
        Assert-Provisioning ($relativePlan.Path -eq $pin) 'Relative pin paths follow PowerShell location, independently of the process directory.'
        $relativeInstall=Install-DotNetEnvironment -InstallRoot './relative-install' -WhatIf
        Assert-Provisioning ($relativeInstall.InstallRoot -eq (Join-Path $root 'relative-install')) 'Relative install paths follow PowerShell location.'
    }finally{Pop-Location}
    Assert-ProvisioningThrows {Update-DotNetGlobalJson -Path $pin -Version 11.0.99 -SkipInstalledCheck -Confirm:$false} 'Downgrades require explicit permission.'
    Assert-ProvisioningThrows {Update-DotNetGlobalJson -Path $pin -Version 11.0.101 -Confirm:$false} 'Unavailable exact SDK cannot be pinned by default.'
    Assert-ProvisioningThrows {Update-DotNetGlobalJson -Path $pin -Version 11.0.100-rc.3.1 -Confirm:$false} 'Explicit prerelease requires Preleases.'
    $preview=Join-Path $root 'preview-install'
    $before=& $module {@($script:ResolutionCalls,$script:InventoryCalls,$script:DownloadCalls,$script:PullCalls)}
    $null=Install-DotNetEnvironment -InstallRoot $preview -UpdateGlobalJson -GlobalJsonPath $pin -PullImages -ContainerRuntime podman -ActivateSession -WhatIf
    $after=& $module {@($script:ResolutionCalls,$script:InventoryCalls,$script:DownloadCalls,$script:PullCalls)}
    Assert-Provisioning (!(Test-Path $preview) -and ($before -join ',') -eq ($after -join ',') -and $env:PATH -eq $oldPath -and $env:DOTNET_ROOT -eq $oldDotnetRoot) 'Install preview creates no directories, probes, pulls or session edits.'
    Assert-ProvisioningThrows {Install-DotNetEnvironment -InstallRoot $preview -PullImages -ContainerRuntime invalid -WhatIf} 'Unknown explicit container clients are rejected.'
    $invalidDirectory=Join-Path $root 'invalid'
    $null=[IO.Directory]::CreateDirectory($invalidDirectory)
    $invalid=Join-Path $invalidDirectory 'global.json'
    [IO.File]::WriteAllText($invalid,'{"sdk":null}',[Text.UTF8Encoding]::new($false))
    $beforeHash=(Get-FileHash $pin -Algorithm SHA256).Hash
    Assert-ProvisioningThrows {Update-DotNetGlobalJson -Path @($pin,$invalid) -Version 11.0.101 -SkipInstalledCheck -Confirm:$false} 'All target documents are validated before any write.'
    Assert-Provisioning ((Get-FileHash $pin -Algorithm SHA256).Hash -eq $beforeHash) 'Invalid batch leaves previously valid file unchanged.'
    $createDirectory=Join-Path $root 'create'
    $null=[IO.Directory]::CreateDirectory($createDirectory)
    $createdPin=Join-Path $createDirectory 'global.json'
    Assert-ProvisioningThrows {Update-DotNetGlobalJson -Path $createdPin -Version 11.0.100 -Confirm:$false} 'Missing files require Create.'
    $created=Update-DotNetGlobalJson -Path $createdPin -Version 11.0.100 -Create -Confirm:$false
    Assert-Provisioning ($created.Status -eq 'Updated' -and !$created.BackupPath -and (Get-Content $createdPin -Raw -Encoding utf8|ConvertFrom-Json).sdk.rollForward -eq 'latestFeature') 'Explicit creation initializes the SDK policy.'
    $plan=Get-DotNetGlobalJsonPlan -Path $createdPin -Version 11.0.101
    [IO.File]::WriteAllText($createdPin,'{"custom":"concurrent"}',[Text.UTF8Encoding]::new($false))
    Assert-ProvisioningThrows {& $module {param($p) Write-DotNetGlobalJsonPlan -Plan $p} $plan} 'Concurrent source changes invalidate the prepared update.'
    Assert-Provisioning ((Get-Content $createdPin -Raw -Encoding utf8) -eq '{"custom":"concurrent"}') 'Concurrent content survives rejection.'
    # Independent preservation oracle across varied valid JSON documents.
    $random=[Random]::new(110102)
    foreach($case in 1..60) {
        $unknown=@{Name="été-$case";Number=$random.Next();Nested=@{Enabled=($case%2 -eq 0);Values=@($case,$null,"中-$case")}}
        $fixture=@{sdk=@{version='11.0.100';rollForward='latestPatch';allowPrerelease=$true};custom=$unknown}
        [IO.File]::WriteAllText($invalid,($fixture|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        $planned=Get-DotNetGlobalJsonPlan -Path $invalid -Version 11.0.101
        $actual=($planned.Json|ConvertFrom-Json -AsHashtable).custom
        Assert-Provisioning (($actual|ConvertTo-Json -Depth 10 -Compress) -eq ($unknown|ConvertTo-Json -Depth 10 -Compress)) "Generated preservation property seed 110102 case $case."
    }
    $badCorpus=@('null','[]','{"sdk":[]}','{"sdk":null}','{"sdk":{"version":"11.0.100","version":"11.0.101"}}','{"x":{"a":1,"a":2}}','{"sdk":','{"sdk":{"version":true}}')
    foreach($bad in $badCorpus) {
        [IO.File]::WriteAllText($invalid,$bad,[Text.UTF8Encoding]::new($false))
        Assert-ProvisioningThrows {Get-DotNetGlobalJsonPlan -Path $invalid -Version 11.0.101} 'Malformed or lossy JSON cannot be rewritten.'
    }
    $fuzz=[Random]::new(110103)
    foreach($case in 1..100) {
        $bad='{"sdk":{"version":"11.0.100"},"random":'+$fuzz.Next()+'BROKEN'+$fuzz.Next()
        [IO.File]::WriteAllText($invalid,$bad,[Text.UTF8Encoding]::new($false))
        Assert-ProvisioningThrows {Get-DotNetGlobalJsonPlan -Path $invalid -Version 11.0.101} "Generated invalid JSON seed 110103 case $case."
    }
    $installRoot=Join-Path $root 'installed'
    & $module {$script:CorruptHash=$true}
    $beforeNative=& $module {$script:InventoryCalls}
    Assert-ProvisioningThrows {Install-DotNetEnvironment -InstallRoot $installRoot -Confirm:$false} 'A bad SHA-512 prevents extraction and promotion.'
    Assert-Provisioning (!(Test-Path (Join-Path $installRoot '11.0.100')) -and (& $module {$script:InventoryCalls}) -eq $beforeNative) 'Corrupt archive is never executed or promoted.'
    Assert-Provisioning (@(Get-ChildItem $installRoot -Directory -Force).Count -eq 0) 'Failed archive staging is cleaned without deleting existing SDKs.'
    & $module {$script:CorruptHash=$false;$script:RuntimeComplete=$false}
    Assert-ProvisioningThrows {Install-DotNetEnvironment -InstallRoot $installRoot -Confirm:$false} 'Incomplete runtime inventory prevents SDK promotion.'
    Assert-Provisioning (!(Test-Path (Join-Path $installRoot '11.0.100'))) 'Unverified payload remains unavailable.'
    & $module {$script:RuntimeComplete=$true}
    $installed=Install-DotNetEnvironment -InstallRoot $installRoot -Confirm:$false
    Assert-Provisioning ($installed.Status -eq 'Installed' -and (Test-Path (Join-Path $installed.SdkDirectory 'frenchexdev-install.json'))) 'Verified SDK is promoted with its archive receipt.'
    $downloads=& $module {$script:DownloadCalls}
    $again=Install-DotNetEnvironment -InstallRoot ($installRoot+[IO.Path]::DirectorySeparatorChar) -Confirm:$false
    Assert-Provisioning ($again.Status -eq 'AlreadyInstalled' -and (& $module {$script:DownloadCalls}) -eq $downloads) 'An existing complete SDK is verified and reused without downloading.'
    $pinHash=(Get-FileHash $pin -Algorithm SHA256).Hash
    & $module {$script:PullFailure=$true}
    Assert-ProvisioningThrows {Install-DotNetEnvironment -InstallRoot $installRoot -UpdateGlobalJson -GlobalJsonPath $pin -PullImages -ContainerRuntime docker -Confirm:$false} 'Failed requested image pull stops pin updates.'
    Assert-Provisioning ((Get-FileHash $pin -Algorithm SHA256).Hash -eq $pinHash -and (Test-Path $installed.SdkDirectory)) 'Image failure preserves pins and keeps the verified SDK.'
    & $module {$script:PullFailure=$false;$script:PullCalls=0}
    $all=Install-DotNetEnvironment -InstallRoot $installRoot -UpdateGlobalJson -GlobalJsonPath $pin -PullImages -ContainerRuntime podman -Platform linux/amd64,linux/arm64 -ActivateSession -Confirm:$false
    Assert-Provisioning ($all.Images.Count -eq 8 -and $all.GlobalJson.Count -eq 1 -and $env:DOTNET_ROOT -eq $all.SdkDirectory -and $env:PATH.StartsWith($all.SdkDirectory)) 'Explicit full setup pulls every requested image/platform, pins SDK and activates only this process.'
    $discovered=Install-DotNetEnvironment -InstallRoot $installRoot -PullImages -Confirm:$false
    Assert-Provisioning ($discovered.ContainerRuntime -eq 'podman') 'The shared resolver prefers Podman when no setting is supplied.'
    $dotenv=Join-Path $root '.env'
    [IO.File]::WriteAllText($dotenv,"QUIET_CONTAINER_RUNTIME=docker`n",[Text.UTF8Encoding]::new($false))
    $configured=Install-DotNetEnvironment -InstallRoot $installRoot -PullImages -Confirm:$false
    Assert-Provisioning ($configured.ContainerRuntime -eq 'docker') 'Checkout dotenv overrides discovery.'
    $explicit=Install-DotNetEnvironment -InstallRoot $installRoot -PullImages -ContainerRuntime podman -Confirm:$false
    Assert-Provisioning ($explicit.ContainerRuntime -eq 'podman') 'Explicit selection overrides checkout dotenv, including GitHub Docker presets.'
    foreach($malformed in @("QUIET_CONTAINER_RUNTIME=`n","QUIET_CONTAINER_RUNTIME=invalid`n","QUIET_CONTAINER_RUNTIME=docker`nQUIET_CONTAINER_RUNTIME=podman`n")){
        [IO.File]::WriteAllText($dotenv,$malformed,[Text.UTF8Encoding]::new($false))
        Assert-ProvisioningThrows {Install-DotNetEnvironment -InstallRoot $installRoot -PullImages -Confirm:$false} 'Malformed runtime configuration fails instead of falling back.'
        $calls=& $module {$script:RuntimeResolveCalls}
        $null=Install-DotNetEnvironment -InstallRoot $installRoot -PullImages -WhatIf
        Assert-Provisioning ((& $module {$script:RuntimeResolveCalls}) -eq $calls) 'Preview does not read or resolve malformed runtime configuration.'
    }
    Remove-Item -LiteralPath $dotenv
    $killed=0
    if(!$NoMutations) {
        $source=Get-Content $ModulePath -Raw -Encoding utf8
        $mutations=@(
            @('checksum',"if((Get-FileHash -LiteralPath `$archive -Algorithm SHA512).Hash -ine `$archiveInfo.hash)",'if($false)'),
            @('downgrade',"if(!`$AllowDowngrade -and [System.Management.Automation.SemanticVersion]`$Version -lt `$old)",'if($false)'),
            @('preservation','$data=ConvertFrom-Json -InputObject $original -AsHashtable -Depth 64 -ErrorAction Stop','$data=[ordered]@{}'),
            @('preview',"if(!`$PSCmdlet.ShouldProcess((`$Path -join ', '),`"Verify SDK `$(if(`$Version){`$Version}else{`"latest eligible `$Channel`"}); back up and update global.json`"))",'if($false)'),
            @('runtime-verification',"if(!`$inventory.Sdk.Success -or !`$inventory.Runtime.Success -or `$Version -notin @(`$inventory.Sdk.Records|ForEach-Object Version))",'if($false)'),
            @('installed-pin','if(!$SkipInstalledCheck)','if($false)')
        )
        foreach($mutation in $mutations) {
            if(!$source.Contains($mutation[1])){throw "Invalid mutation anchor: $($mutation[0])"}
            $mutantRoot=Join-Path $root ('mutant-'+$mutation[0])
            $null=[IO.Directory]::CreateDirectory($mutantRoot)
            $mutantPath=Join-Path $mutantRoot 'DotNetProvisioning.psm1'
            Copy-Item -LiteralPath (Join-Path (Split-Path $ModulePath -Parent) 'DotNetReadiness.psm1') -Destination (Join-Path $mutantRoot 'DotNetReadiness.psm1')
            [IO.File]::WriteAllText($mutantPath,$source.Replace($mutation[1],$mutation[2]),[Text.UTF8Encoding]::new($false))
            $detected=$false
            try{$null=& $PSCommandPath -ModulePath $mutantPath -NoMutations}catch{
                if($_.Exception.Message -notlike 'Assertion failed:*'){throw "Invalid/crashed mutant $($mutation[0]): $($_.Exception.Message)"}
                $detected=$true
            }
            if(!$detected){throw "Surviving mutant: $($mutation[0])"}
            $killed++
            Write-Output "Killed provisioning mutant: $($mutation[0])"
        }
    }
    [pscustomobject]@{State='Passed';Assertions=$assertions;PropertyCases=60;FuzzCases=108;MutantsKilled=$killed;Seed=110102;FuzzSeed=110103}
}
finally {
    $env:PATH=$oldPath;$env:DOTNET_ROOT=$oldDotnetRoot
    Remove-Module $module -Force -ErrorAction SilentlyContinue
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path $resolved -Parent) -ne $temp -or (Split-Path $resolved -Leaf) -notmatch '^dotnet-provisioning-fixtures-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup target.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
