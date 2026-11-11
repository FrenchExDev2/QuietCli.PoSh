#requires -Version 7.6
<#
.SYNOPSIS
Checks library placement, import preservation and the engine-independent native boundary.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Run .NET script layout properties, malformed initializers and targeted mutants')){return}
$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('quiet-dotnet-layout-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$assertions=0
function Assert-DotNetLayout {
    <#
    .SYNOPSIS
    Enforces the layout and native-boundary contract independently of its implementation.
    #>
    param([bool]$Condition,[string]$Message)
    $script:assertions++
    if(!$Condition){throw "Assertion failed: $Message"}
}
function Test-DotNetNativeBoundary {
    <#
    .SYNOPSIS
    Uses a process adapter fixture to check exact arguments and failure propagation.
    #>
    param([string]$ModulePath)
    $module=Import-Module $ModulePath -Force -PassThru
    try {
        & $module {
            $script:NativeOutcome='Success';$script:NativeExit=0;$script:MalformedNative=$false
            function script:Import-DotNetProcessHelper {
                <#
                .SYNOPSIS
                Prevents loading the real process helper during adapter unit assertions.
                #>
                param($QuietCliRoot)
            }
            function script:Invoke-CiProcess {
                <#
                .SYNOPSIS
                Models the existing helper's callbacks, exit code and timeout outcome.
                #>
                param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds,$State,$OnOutput)
                $script:NativeArguments=$ArgumentList
                $text=if($script:MalformedNative){'unrecognized record'}elseif($ArgumentList[0] -eq '--list-sdks'){'11.0.100 [C:/SDK path]'}elseif($ArgumentList[0] -eq '--list-runtimes'){'Microsoft.NETCore.App 11.0.0 [C:/runtime path]'}else{'sha256:'+('a'*64)}
                $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text=$text}) $State
                [pscustomobject]@{Outcome=$script:NativeOutcome;ExitCode=$script:NativeExit}
            }
        }
        $inventory=Get-DotNetInstallation -Confirm:$false
        Assert-DotNetLayout ($inventory.Sdk.Success -and $inventory.Runtime.Success -and $inventory.Sdk.Records[0].Version -eq '11.0.100') 'Independent process records produce typed SDK and runtime inventories.'
        & $module {$script:NativeOutcome='Failed';$script:NativeExit=1}
        $inventory=Get-DotNetInstallation -Confirm:$false
        Assert-DotNetLayout (!$inventory.Sdk.Success -and !$inventory.Runtime.Success) 'Nonzero native results never establish readiness.'
        & $module {$script:NativeOutcome='Timeout';$script:NativeExit=-1}
        Assert-DotNetLayout (!(Get-DotNetInstallation -Confirm:$false).Sdk.Success) 'Native timeouts invalidate retained records.'
        & $module {$script:NativeOutcome='Success';$script:NativeExit=0;$script:MalformedNative=$true}
        $rejected=$false
        try{$null=Get-DotNetInstallation -Confirm:$false}catch{$rejected=$true}
        Assert-DotNetLayout $rejected 'Parser failure propagates rather than returning incomplete success.'
        & $module {$script:MalformedNative=$false}
        $pull=Invoke-DotNetContainerPull -ContainerRuntime podman -Image 'mcr.microsoft.com/dotnet/sdk:11.0' -Platform linux/arm64 -Confirm:$false
        $arguments=& $module {,$script:NativeArguments}
        Assert-DotNetLayout ($pull.Status -eq 'Pulled' -and ($arguments -join '|') -eq 'pull|--quiet|--platform|linux/arm64|--retry=0|mcr.microsoft.com/dotnet/sdk:11.0') 'Pull uses explicit image/platform arguments with Podman retries disabled.'
        & $module {$script:NativeOutcome='Failed';$script:NativeExit=1}
        $rejected=$false
        try{$null=Invoke-DotNetContainerPull -ContainerRuntime docker -Image 'mcr.microsoft.com/dotnet/runtime:11.0' -Confirm:$false}catch{$rejected=$true}
        Assert-DotNetLayout $rejected 'Failed image pulls propagate to the installer.'
    }finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
try {
    . (Join-Path $workspace 'scripts/ScriptShouldProcess.ps1')
    $fixture=Join-Path $root 'policy'
    $null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts/lib'))
    $null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'build'))
    [IO.File]::WriteAllText((Join-Path $fixture 'build/script-shouldprocess.json'),'{"SchemaVersion":1,"LegacyPaths":[],"ReadOnlyExceptions":[]}',[Text.UTF8Encoding]::new($false))
    $sample=Join-Path $fixture 'scripts/lib/Sample.psm1'
    $random=[Random]::new(110104)
    foreach($case in 1..80){
        $name='Value'+$random.Next()
        $text="Set-StrictMode -Version Latest`nfunction Get-$name { 'é-$case' }`nExport-ModuleMember -Function Get-$name`n"
        [IO.File]::WriteAllText($sample,$text,[Text.UTF8Encoding]::new($false))
        Assert-DotNetLayout ((Get-QuietScriptShouldProcess $sample) -eq 'Library') "Generated declarative module seed 110104 case $case."
    }
    $valid=$text
    $policyResult=Test-QuietScriptShouldProcessPolicy $fixture
    Assert-DotNetLayout ($policyResult.Libraries -eq 1) 'Dependent modules are admitted under scripts/lib.'
    foreach($initialization in @('Write-Output unexpected','$x=Get-Date','Set-Content forbidden.txt bad','Export-ModuleMember -Function (Get-Date)','Import-Module unreviewed-module')){
        [IO.File]::WriteAllText($sample,($valid+$initialization+"`n"),[Text.UTF8Encoding]::new($false))
        Assert-DotNetLayout ((Get-QuietScriptShouldProcess $sample) -eq 'Unclassified') 'Executable library initializers are not silently qualified.'
    }
    foreach($case in 1..64){
        [IO.File]::WriteAllText($sample,($valid+"`n`$value = "+$random.Next()+"`n"),[Text.UTF8Encoding]::new($false))
        Assert-DotNetLayout ((Get-QuietScriptShouldProcess $sample) -eq 'Unclassified') "Generated executable initializer seed 110104 case $case."
    }
    [IO.File]::WriteAllText($sample,$valid,[Text.UTF8Encoding]::new($false))
    $misplaced=Join-Path $fixture 'scripts/Misplaced.psm1'
    [IO.File]::WriteAllText($misplaced,$valid,[Text.UTF8Encoding]::new($false))
    $rejected=$false
    try{$null=Test-QuietScriptShouldProcessPolicy $fixture}catch{$rejected=$_.Exception.Message -like 'ScriptLibraryLocationRequired:*'}
    Assert-DotNetLayout $rejected 'A module beside executable entry points is rejected.'
    Remove-Item -LiteralPath $misplaced
    foreach($name in @('DotNetReadiness','DotNetProvisioning')){
        $path=Join-Path $workspace "scripts/lib/$name.psm1"
        Assert-DotNetLayout ((Get-QuietScriptShouldProcess $path) -eq 'Library') "Imported $name module has a declarative initializer."
    }
    $importer=Join-Path $workspace 'scripts/Import-DotNetTooling.ps1'
    $destination=Join-Path $root 'import'
    # The one-time importer accepts a source tree, not an installed workspace dependency.
    $fixtureSource=Join-Path $root 'source'
    foreach($relative in @('scripts/Test-DotNetReadiness.ps1','scripts/Install-DotNet.ps1','scripts/Update-DotNetGlobalJson.ps1','scripts/DotNetReadiness.psm1','scripts/DotNetProvisioning.psm1','scripts/tests/DotNetReadiness.Tests.ps1','scripts/tests/DotNetProvisioning.Tests.ps1','scripts/tests/Invoke-DotNetReadinessTests.ps1','scripts/tests/Watch-DotNetReadinessTests.ps1','Doc/Net/DotNetReadiness.md','Doc/Net/DotNetProvisioning.md')){
        $path=Join-Path $fixtureSource $relative
        $null=[IO.Directory]::CreateDirectory((Split-Path $path -Parent))
        [IO.File]::WriteAllText($path,'# initial é',[Text.UTF8Encoding]::new($false))
    }
    $null=& $importer -SourceWorkspace $fixtureSource -DestinationRoot $destination -WhatIf
    Assert-DotNetLayout (!(Test-Path $destination)) 'Import preview creates no destination directories.'
    $copied=@(& $importer -SourceWorkspace $fixtureSource -DestinationRoot $destination -Confirm:$false)
    Assert-DotNetLayout ($copied.Count -eq 11 -and @(Get-ChildItem (Join-Path $destination 'scripts') -Filter '*.psm1' -File).Count -eq 0) 'The importer places libraries below scripts/lib and copies all declared sources.'
    $maintained=Join-Path $destination 'scripts/lib/DotNetReadiness.psm1'
    [IO.File]::WriteAllText($maintained,'# maintained copy',[Text.UTF8Encoding]::new($false))
    $null=& $importer -SourceWorkspace $fixtureSource -DestinationRoot $destination -Confirm:$false
    Assert-DotNetLayout ((Get-Content $maintained -Raw -Encoding utf8) -eq '# maintained copy') 'A subsequent import preserves repository-specific integrations.'
    Test-DotNetNativeBoundary -ModulePath (Join-Path $workspace 'scripts/lib/DotNetReadiness.psm1')
    $baselineAssertions=$assertions
    $policySource=Get-Content (Join-Path $workspace 'scripts/ScriptShouldProcess.ps1') -Raw -Encoding utf8
    $changed=$policySource.Replace("`$relative -notlike 'scripts/lib/*'",'$false')
    if($changed -ceq $policySource){throw 'LayoutMutationAnchorMissing'}
    $policyMutant=Join-Path $root 'PolicyMutant.ps1'
    [IO.File]::WriteAllText($policyMutant,$changed,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($misplaced,$valid,[Text.UTF8Encoding]::new($false))
    . $policyMutant
    $rejected=$false;try{$null=Test-QuietScriptShouldProcessPolicy $fixture}catch{$rejected=$true}
    Assert-DotNetLayout (!$rejected) 'Removing the placement guard changes the accepted module layout.'
    $nativeSource=Get-Content (Join-Path $workspace 'scripts/lib/DotNetReadiness.psm1') -Raw -Encoding utf8
    $nativeMutant=Join-Path $root 'NativeMutant.psm1'
    $changed=$nativeSource.Replace("`$ok = `$result.Outcome -eq 'Success' -and `$result.ExitCode -eq 0",'$ok = $true')
    if($changed -ceq $nativeSource){throw 'NativeMutationAnchorMissing'}
    [IO.File]::WriteAllText($nativeMutant,$changed,[Text.UTF8Encoding]::new($false))
    $detected=$false
    try{Test-DotNetNativeBoundary -ModulePath $nativeMutant}catch{
        if($_.Exception.Message -notlike 'Assertion failed:*'){throw}
        $detected=$true
    }
    if(!$detected){throw 'NativeFailureMutantSurvived'}
    $assertions=$baselineAssertions
    [pscustomobject]@{State='Passed';Assertions=$assertions;PropertyCases=80;FuzzCases=69;MutantsKilled=2;Seed=110104}
}finally{
    $resolved=[IO.Path]::GetFullPath($root)
    $temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path $resolved -Parent) -ne $temporaryRoot -or (Split-Path $resolved -Leaf) -notmatch '^quiet-dotnet-layout-[a-f0-9]{32}$'){throw 'Unsafe layout fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
