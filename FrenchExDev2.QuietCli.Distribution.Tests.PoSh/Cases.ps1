function Test-QuietEmbeddedDistributions {
    <#
    .SYNOPSIS
    Validates all six embedded engines have matching native and managed architectures.
    .PARAMETER WorkspaceRoot
    Selected verified source checkout.
    .PARAMETER RunDirectory
    Owned evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)

        & {
            param($root)
            Import-Module (Join-Path $root 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
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

function Test-QuietCoreGalleryDistribution {
    <#
    .SYNOPSIS
    Validates PSGallery Core installs outside sources with its embedded engine and no Git companion.
    .PARAMETER WorkspaceRoot
    Selected verified source checkout.
    .PARAMETER RunDirectory
    Owned evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)

        $root=Join-Path $WorkspaceRoot ('artifacts/gallery-tests/'+[guid]::NewGuid().ToString('N'))
        $packages=Join-Path $root packages
        $sourceIdentity=& (Join-Path $WorkspaceRoot scripts/Get-ModulePackageName.ps1) -Path (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1') -AsObject -RequireManifest
        $prepared=& (Join-Path $WorkspaceRoot 'scripts/New-QuietGalleryPackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $packages -Version $sourceIdentity.Version
        Assert-QuietEqual $prepared.Version $sourceIdentity.Version
        & {
            param($scripts,$packages,$expectedVersion)
            Import-Module ([IO.Path]::Combine($scripts,'lib','Common.psm1')) -DisableNameChecking -ErrorAction Stop
            Import-Module ([IO.Path]::Combine($scripts,'lib','Gallery.psm1')) -DisableNameChecking -ErrorAction Stop
            foreach($wrong in @('0.0.0-invalid','999.999.999-invalid','0.0.0')|Where-Object {$_ -cne $expectedVersion}){
                $rejected=$false
                try{$null=Test-QuietGalleryPackageSet $packages -Version $wrong}catch{$rejected=$_.Exception.Message -eq 'GalleryReleaseVersionMismatch'}
                if(!$rejected){throw 'Wrong or stripped prerelease version was accepted'}
            }
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version $expectedVersion -ValidateOnly
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version $expectedVersion -WhatIf
            $plan=Test-QuietGalleryPackageSet $packages -Version $expectedVersion
            if(@($plan.Packages).Count -ne 1 -or $plan.Packages[0].Module -cne 'FrenchExDev2.QuietCli.Core.PoSh'){throw 'GalleryCoreOnlyRequired'}
        } (Join-Path $WorkspaceRoot scripts) $packages $sourceIdentity.Version
        $probe=Join-Path (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh') audit/Probe-GalleryInstall.ps1
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -NoProfile -File $probe -PackageDirectory $packages -InstallationDirectory (Join-Path $root installed)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Installed $true
        Assert-QuietEqual $r.Data.CoreLoadedFromPackage $true
        Assert-QuietEqual $r.Data.GitModuleLoaded $false
        Assert-QuietEqual $r.Data.NativeExecution Success
        Assert-QuietEqual $r.Data.PackageVersion $sourceIdentity.Version
        $galleryEvidence.Add(@{Packages=$prepared.Packages;Targets=$prepared.Targets;Installation=$r.Data;ExternalPublication=$false})

}

function Test-QuietRecallDistribution {
    <#
    .SYNOPSIS
    Validates Recall companion development tools work in source-free packages.
    .PARAMETER WorkspaceRoot
    Selected verified source checkout.
    .PARAMETER RunDirectory
    Owned evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)

        $packages=Join-Path $RunDirectory 'recall-packages'
        $null=& (Join-Path $WorkspaceRoot 'scripts/New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $packages -Module FrenchExDev2.QuietCli.Core.PoSh,FrenchExDev2.QuietCli.Core.Tests.PoSh
        Assert-QuietEqual (Test-Path (Join-Path $packages 'FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools')) $false
        $worker=Join-Path $RunDirectory 'package-recall.ps1'
        $code=@'
<#
.SYNOPSIS
Checks packaged offline tools without source or orchestration helpers.
.PARAMETER PackageRoot
Extracted four-module package root.
#>
param([string]$PackageRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -DisableNameChecking
$r=quiet -AsObject -Recall -Output {} pwsh -Command "'fixture'"
if($r.Outcome -ne 'Success'){throw 'PackagedCaptureFailed'}
$comparison=Compare-QuietRecallAnalysis $r -First @{Complete={1}} -Second @{Complete={1}}
$reduction=Reduce-QuietRecall $r -FailurePredicate {param($c)$c.RetainedBytes -gt 0} -MaxAttempts 5
if(!$comparison.Equal -or $reduction.Capture.RetainedBytes -lt 1){throw 'PackagedToolsFailed'}
[pscustomobject]@{Equal=$comparison.Equal;ProvenMinimal=$reduction.ProvenMinimal}|ConvertTo-Json -Compress
'@
        [void][IO.File]::WriteAllTextAsync($worker,$code.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -PackageRoot $packages
        Assert-QuietEqual $r.Outcome Success (($r.Error|ConvertTo-Json -Compress))
        Assert-QuietEqual $r.Data.Equal $true
        $framework=if([Environment]::Version.Major -ge 11){'net11.0'}else{'net10.0'}
        $binary=Join-Path $packages ('FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/recall-tools/'+$framework+'/QuietCli.Recall.Tools.dll')
        $bytes=[IO.File]::ReadAllBytesAsync($binary).GetAwaiter().GetResult();$bytes[-1]=$bytes[-1] -bxor 1
        [void][IO.File]::WriteAllBytesAsync($binary,$bytes).GetAwaiter().GetResult()
        $broken=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)[void]$r.Data.Append($e.Text)} -Complete {param($r)$r.Data.ToString()} pwsh -File $worker -PackageRoot $packages
        Assert-QuietEqual $broken.Outcome Failed
        Assert-QuietEqual $broken.Data.Contains('RecallToolsBinaryIntegrityFailed') $true

}
