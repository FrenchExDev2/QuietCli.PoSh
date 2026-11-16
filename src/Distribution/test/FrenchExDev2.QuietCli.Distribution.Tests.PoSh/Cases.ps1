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
                $output='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$target.Rid
                $manifest=Test-QuietBuildManifest $root $output
                if($manifest.RuntimeIdentifier -cne $target.Rid -or $manifest.PlatformTarget -cne $target.PlatformTarget){throw 'Compiler target metadata mismatch'}
                Assert-QuietRuntimePublication (Join-Path $root $output) $target
                $configuration=Get-Content -LiteralPath (Join-Path (Join-Path $root $output) 'QuietCli.Engine.runtimeconfig.json') -Encoding utf8 -Raw|ConvertFrom-Json
                [xml]$runtimeProject=Get-Content (Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj') -Raw -Encoding utf8
                $expectedRuntime=@($runtimeProject.SelectNodes('//RuntimeFrameworkVersion')|Where-Object {$_.GetAttribute('Condition') -match 'net11\.0'})
                if($expectedRuntime.Count -ne 1 -or $configuration.runtimeOptions.framework.version -cne $expectedRuntime[0].InnerText){throw 'Published engine runtime does not match its source pin'}
            }
        } $WorkspaceRoot
        $identity=Get-QuietEngine
        $hostRid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        $expected=$hostRid
        if($identity.Mode -eq 'InProcess'){
            $directory=if([Environment]::Version.Major -ge 11){'lib/engine'}else{'lib/inprocess'}
            $build=Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/'+$directory+'/build-manifest.json')) -Raw -Encoding utf8|ConvertFrom-Json
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
        $sourceIdentity=& (Join-Path $WorkspaceRoot scripts/Get-ModulePackageName.ps1) -Path (Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1') -AsObject -RequireManifest
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
        $probe=Join-Path (Join-Path $WorkspaceRoot 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh') audit/Probe-GalleryInstall.ps1
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

        $shadow=[IO.Path]::Combine($RunDirectory,'source-lookalike-é漢')
        $helpers=[IO.Path]::Combine($shadow,'scripts/lib')
        [void][IO.Directory]::CreateDirectory($helpers)
        foreach($name in @('Common','TestCaseMetadata','TestCaseScheduling')){
            [IO.File]::WriteAllText([IO.Path]::Combine($helpers,($name+'.psm1')),"throw 'PackagedRecallImportedSourceHelpers'`n",[Text.UTF8Encoding]::new($false))
        }
        # Match the hosted artifact depth, where four parents previously selected the real checkout.
        $packages=[IO.Path]::Combine($shadow,'artifacts/component/recall-packages')
        $moduleName='FrenchExDev2.QuietCli.Core.Tests.PoSh'
        foreach($index in 0..31){
            $module=if($index -eq 0){[IO.Path]::Combine($packages,$moduleName)}else{[IO.Path]::Combine($shadow,('nested-'+$index),$moduleName)}
            Assert-QuietEqual (Get-QuietTestSourceWorkspace -ModuleRoot $module) $null
        }
        Assert-QuietEqual (Get-QuietTestSourceWorkspace -ModuleRoot (Resolve-QuietWorkspacePath $WorkspaceRoot $moduleName)) ([IO.Path]::GetFullPath($WorkspaceRoot))
        foreach($index in 0..31){
            $resolved=$null
            try{$resolved=Get-QuietTestSourceWorkspace -ModuleRoot ($shadow+[char]0+$index)}catch{}
            if($null -ne $resolved){throw 'MalformedRecallWorkspaceAccepted'}
        }
        $guard='if(![string]::Equals($module,$expected,$comparison)){return $null}'
        $source=(Get-Command Get-QuietTestSourceWorkspace).ScriptBlock.Ast.Extent.Text
        if(([regex]::Matches($source,[regex]::Escape($guard))).Count -ne 1){throw 'RecallWorkspaceGuardMutationAnchorInvalid'}
        $mutant=New-Module -ScriptBlock ([scriptblock]::Create($source.Replace($guard,'')))
        $observed=& $mutant {param($root) Get-QuietTestSourceWorkspace -ModuleRoot $root} ([IO.Path]::Combine($packages,$moduleName))
        if($null -eq $observed){throw 'RecallWorkspaceGuardMutantSurvived'}
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
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
try{
Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -DisableNameChecking
$r=quiet -AsObject -Recall -Output {} -FilePath ([Environment]::ProcessPath) -ArgumentList @('-Command',"'fixture'")
if($r.Outcome -ne 'Success'){throw 'PackagedCaptureFailed'}
$comparison=Compare-QuietRecallAnalysis $r -First @{Complete={1}} -Second @{Complete={1}}
$reduction=Reduce-QuietRecall $r -FailurePredicate {param($c)$c.RetainedBytes -gt 0} -MaxAttempts 5
if(!$comparison.Equal -or $reduction.Capture.RetainedBytes -lt 1){throw 'PackagedToolsFailed'}
[pscustomobject]@{State='Success';Equal=$comparison.Equal;ProvenMinimal=$reduction.ProvenMinimal;RuntimeMajor=[Environment]::Version.Major;OutputEncoding=[Console]::OutputEncoding.WebName}|ConvertTo-Json -Compress
}catch{
    [pscustomobject]@{State='Failed';ErrorId=$_.FullyQualifiedErrorId;ErrorMessage=$_.Exception.Message;RuntimeMajor=[Environment]::Version.Major;OutputEncoding=[Console]::OutputEncoding.WebName}|ConvertTo-Json -Compress
    exit 1
}
'@
        [void][IO.File]::WriteAllTextAsync($worker,$code.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $runner=[Environment]::ProcessPath
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-File',$worker,'-PackageRoot',$packages)
        Assert-QuietEqual $r.Outcome Success (($r.Error|ConvertTo-Json -Compress))
        Assert-QuietEqual $r.Completeness.Source $true
        Assert-QuietEqual $r.Completeness.Analysis $true
        Assert-QuietEqual $r.Data.State Success
        Assert-QuietEqual $r.Data.OutputEncoding 'utf-8'
        Assert-QuietEqual $r.Data.Equal $true
        Assert-QuietEqual $r.Data.RuntimeMajor ([Environment]::Version.Major)
        $framework=if([Environment]::Version.Major -ge 11){'net11.0'}else{'net10.0'}
        $binary=Join-Path $packages ('FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/recall-tools/'+$framework+'/QuietCli.Recall.Tools.dll')
        $bytes=[IO.File]::ReadAllBytesAsync($binary).GetAwaiter().GetResult();$bytes[-1]=$bytes[-1] -bxor 1
        [void][IO.File]::WriteAllBytesAsync($binary,$bytes).GetAwaiter().GetResult()
        $broken=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-File',$worker,'-PackageRoot',$packages)
        $diagnostic=$broken.Error|ConvertTo-Json -Depth 8 -Compress
        Assert-QuietEqual $broken.Outcome Failed $diagnostic
        Assert-QuietEqual $broken.Completeness.Source $true $diagnostic
        Assert-QuietEqual $broken.Completeness.Analysis $true $diagnostic
        Assert-QuietEqual $broken.Execution.Native.ExitCode 1
        Assert-QuietEqual $broken.Data.State Failed
        Assert-QuietEqual $broken.Data.OutputEncoding 'utf-8'
        Assert-QuietEqual $broken.Data.RuntimeMajor ([Environment]::Version.Major)
        Assert-QuietEqual $broken.Data.ErrorMessage 'RecallToolsBinaryIntegrityFailed'
        Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'packaged-recall-integrity.json')) @{SourceWorkspaceProperties=33;MalformedRoots=32;WorkspaceGuardMutantsKilled=1;SourceHelperImports=0;Framework=$framework;TamperedPackageRejected=$true;RuntimeMajor=$r.Data.RuntimeMajor;AnalysisComplete=$broken.Completeness.Analysis;Rejection=$broken.Data}

}
