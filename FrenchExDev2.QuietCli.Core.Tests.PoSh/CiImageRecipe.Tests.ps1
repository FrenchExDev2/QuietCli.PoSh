function Test-QuietCiImageRecipe {
    <#
    .SYNOPSIS
    Verifies locked image dependencies, separate host/SDK roots, generated versions and rejection boundaries.
    .PARAMETER WorkspaceRoot
    Source workspace containing the declared module recipe and shared renderer.
    .PARAMETER RunDirectory
    Owned property/fuzz/mutation evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
    $sourcePath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1'
    $source=[IO.File]::ReadAllTextAsync($sourcePath,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $fixture=Join-Path $RunDirectory 'ci-image-recipe'
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'build'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture '.github/containers'))
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'global.json') -Destination $fixture
    $lockText=[IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'build/ci-images.lock.json'),[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $lockPath=Join-Path $fixture 'build/ci-images.lock.json'
    [void][IO.File]::WriteAllTextAsync($lockPath,$lockText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    function Assert-RecipeContract {
        <# .SYNOPSIS
        Asserts observable final-stage requirements independently from how the recipe constructs them.
        .PARAMETER Declaration
        Returned stage declaration.
        .PARAMETER Version
        Independently selected locked Alpine package version.
        .PARAMETER Alpine
        Selects the musl host/SDK separation contract.
        #>
        param($Declaration,[string]$Version,[bool]$Alpine)
        $final=@($Declaration.Containerfile.Stages | Where-Object Name -eq ci)[0]
        if($Alpine){
            if($Declaration.Arguments.POWERSHELL_URL -notmatch '/powershell-7\.[6-9]\.\d+-linux-(x64|arm64)\.tar\.gz\z' -or $Declaration.Arguments.POWERSHELL_SHA256 -cnotmatch '\A[a-f0-9]{64}\z'){throw 'AlpinePSResourceGetDonorNotPinned'}
            if(@($final.Copy|Where-Object Spec -CEQ '/opt/powershell/Modules/Microsoft.PowerShell.PSResourceGet /usr/local/share/powershell/Modules/Microsoft.PowerShell.PSResourceGet').Count -ne 1){throw 'AlpinePSResourceGetNotCopied'}
            if(($final.Run -join ' ') -notmatch 'Get-Command Compress-PSResource -ErrorAction Stop'){throw 'AlpinePackagingCapabilityNotChecked'}
            if('powershell=$POWERSHELL_PACKAGE' -cnotin @($final.Packages -split '\s+')){throw 'AlpinePowerShellNotInstalled'}
            if(('POWERSHELL_PACKAGE='+$Version) -cnotin @($final.Args) -or $Declaration.Arguments.POWERSHELL_PACKAGE -cne $Version){throw 'AlpinePowerShellVersionNotLocked'}
            if($final.Env.DOTNET_ROOT -cne '/opt/pwsh-runtime'){throw 'AlpinePowerShellRuntimeRootIncorrect'}
            if($Declaration.Arguments.RUNTIME_URL -notmatch '/Runtime/10\.0\.\d+/dotnet-runtime-10\.0\.\d+-linux-musl-(x64|arm64)\.tar\.gz\z' -or $Declaration.Arguments.RUNTIME_SHA512 -cnotmatch '\A[a-f0-9]{128}\z' -or @($final.Copy|Where-Object Spec -CEQ '/opt/pwsh-runtime /opt/pwsh-runtime').Count -ne 1){throw 'AlpinePortableRuntimeNotPinnedOrCopied'}
        }elseif($final.Env.DOTNET_ROOT -cne '/usr/share/dotnet'){throw 'DebianRuntimeRootChanged'}
        if(($final.Env.PATH -split ':')[0] -cne '/usr/share/dotnet'){throw 'PinnedSdkNotFirstOnPath'}
        if(($final.Entrypoint -join ' ') -cne 'pwsh'){throw 'PowerShellEntrypointMissing'}
        $rendered=Get-QuietModuleContainerfile -Platform $Declaration.Containerfile.Platform -Objective $Declaration.Containerfile.Objective -Stages $Declaration.Containerfile.Stages
        if($Alpine -and ($rendered -notmatch 'apk add[^\n]*powershell=\$POWERSHELL_PACKAGE' -or $rendered.IndexOf('ARG POWERSHELL_PACKAGE=') -gt $rendered.LastIndexOf('apk add'))){throw 'AlpinePackageNotRenderedAfterItsArgument'}
    }
    $originalLock=$lockText|ConvertFrom-Json
    foreach($rid in 'linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'){
        $declaration=& $sourcePath -WorkspaceRoot $fixture -RuntimeIdentifier $rid
        Assert-RecipeContract $declaration $originalLock.AlpinePowerShellPackage $rid.Contains('-musl-')
    }
    $seed=20261109;$random=[Random]::new($seed)
    foreach($index in 1..100){
        $version='7.'+$random.Next(6,10)+'.'+$random.Next(0,50)+'-r'+$random.Next(0,10)
        $lock=$lockText|ConvertFrom-Json;$lock.AlpinePowerShellPackage=$version
        Write-WorkspaceJson $lockPath $lock
        foreach($rid in 'linux-musl-x64','linux-musl-arm64'){
            $declaration=& $sourcePath -WorkspaceRoot $fixture -RuntimeIdentifier $rid
            Assert-RecipeContract $declaration $version $true
        }
    }
    $malformed=@('','latest','7.5.9-r0','7.10.0-r0','7.6.9','7.6.9-r0;echo injected',"7.6.9-r0`nnext", "7.6.9-r0`n",'7.6.9-r999999999999999999999999999999999999999x')
    foreach($version in $malformed){
        $lock=$lockText|ConvertFrom-Json;$lock.AlpinePowerShellPackage=$version;Write-WorkspaceJson $lockPath $lock
        $rejected=$false
        try{$null=& $sourcePath -WorkspaceRoot $fixture -RuntimeIdentifier linux-musl-x64}catch{$rejected=$_.Exception.Message -match 'CiImagePowerShellLockInvalid'}
        if(!$rejected){throw 'MalformedPowerShellPackageAccepted'}
    }
    [void][IO.File]::WriteAllTextAsync($lockPath,$lockText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $mutants=@(
        @{Name='psresourceget-copy-removed';From="`$ciStage.Copy+=[pscustomobject]@{Stage='tools';Spec='/opt/powershell/Modules/Microsoft.PowerShell.PSResourceGet /usr/local/share/powershell/Modules/Microsoft.PowerShell.PSResourceGet'}";To=''},
        @{Name='powershell-installation-removed';From="if(`$platform -ceq 'alpine'){`$ciPackages+=' powershell=`$POWERSHELL_PACKAGE'}";To=''},
        @{Name='powershell-package-unpinned';From=' powershell=$POWERSHELL_PACKAGE';To=' powershell'},
        @{Name='alpine-host-root-points-at-sdk';From="DOTNET_ROOT='/opt/pwsh-runtime'";To="DOTNET_ROOT='/usr/share/dotnet'"},
        @{Name='alpine-sdk-path-shadowed';From="PATH='/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'";To="PATH='/usr/bin:/bin'"},
        @{Name='package-final-newline-accepted';From='\A7\.[6-9]\.\d+-r\d+\z';To='^7\.[6-9]\.\d+-r\d+$'}
    )
    $outcomes=@(foreach($mutant in $mutants){
        if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw ('CiRecipeMutationAnchorInvalid: '+$mutant.Name)}
        $path=Join-Path $fixture ($mutant.Name+'.ps1')
        [void][IO.File]::WriteAllTextAsync($path,$source.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $killed=$false
        if($mutant.Name -eq 'package-final-newline-accepted'){
            $lock=$lockText|ConvertFrom-Json;$lock.AlpinePowerShellPackage=$originalLock.AlpinePowerShellPackage+"`n";Write-WorkspaceJson $lockPath $lock
            try{$null=& $path -WorkspaceRoot $fixture -RuntimeIdentifier linux-musl-x64;$killed=$true}catch{$killed=$false}
            [void][IO.File]::WriteAllTextAsync($lockPath,$lockText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }else{
            $declaration=& $path -WorkspaceRoot $fixture -RuntimeIdentifier linux-musl-x64
            try{Assert-RecipeContract $declaration $originalLock.AlpinePowerShellPackage $true}catch{$killed=$true}
        }
        if(!$killed){throw ('CiImageRecipeMutantSurvived: '+$mutant.Name)}
        @{Name=$mutant.Name;Outcome='Killed'}
    })
    Write-WorkspaceJson (Join-Path $fixture 'summary.json') @{Seed=$seed;TargetExamples=4;GeneratedPlans=200;MalformedInputs=$malformed.Count;Mutations=$outcomes;SourceSHA256=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash}
}
