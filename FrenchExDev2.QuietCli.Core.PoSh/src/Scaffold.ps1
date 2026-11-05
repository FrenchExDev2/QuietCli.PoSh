function New-QuietModule {
    <#
.SYNOPSIS
Generates a business module and an independent companion test module.
    .PARAMETER Name
    Full module name without the Tests component.
    .PARAMETER Binary
    Executable name handled by the module.
    .PARAMETER OutputPath
    Parent workspace directory; existing destinations are never overwritten.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9.]+$')][string]$Name,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')][string]$Binary,[Parameter(Mandatory)][string]$OutputPath)
    $testName=$Name -replace '\.PoSh$','.Tests.PoSh';if($testName -eq $Name){$testName=$Name+'.Tests'}
    $target=Join-Path $OutputPath $Name;$tests=Join-Path $OutputPath $testName
    if((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $tests)){throw 'ModuleDestinationExists'}
    foreach($path in @($target,$tests,(Join-Path $target 'src'))){[void][IO.Directory]::CreateDirectory($path)}
    $module=@'
#requires -Version 7.6
. (Join-Path $PSScriptRoot 'src/Handler.ps1')
$ExecutionContext.SessionState.Module.OnRemove={Unregister-QuietHandler -Id '__MODULE__'}
Export-ModuleMember -Function @()
'@
    $module=$module.Replace('__MODULE__',$Name)
    $handler=@'
# Registering this catalogue never executes a binary. Configure the four callbacks before use.
Register-QuietHandler -Id '__MODULE__' -Definition @{
    Binary='__BINARY__'
    ModuleVersion='0.1.0'
    VersionRange='Unconfigured'
    Qualification='NotImplemented'
    Documentation=@()
    SupportedForms=@()
    Probe={
        param($runtime)
        # Use quiet -AsObject -Role Probe with explicit Output/Complete callbacks.
        # Return exactly one observed version. Keep native version rules in this module.
        throw 'ConfigureDocumentedVersionProbe'
    }
    TestVersion={param($version) $false}
    Match={param($request,$version) $false}
    Execute={
        param($runtime)
        # Use quiet -AsObject with explicit Output/Complete callbacks for native work.
        # Preserve request arguments, environment, input and cancellation deliberately.
        # Retain only business data; return that data to the enclosing invocation.
        throw 'ImplementBusinessHandler'
    }
}
'@
    $handler=$handler.Replace('__MODULE__',$Name).Replace('__BINARY__',$Binary)
    [void][IO.File]::WriteAllTextAsync((Join-Path $target ($Name+'.psm1')),$module,$script:QuietUtf8).GetAwaiter().GetResult()
    [void][IO.File]::WriteAllTextAsync((Join-Path $target 'src/Handler.ps1'),$handler,$script:QuietUtf8).GetAwaiter().GetResult()
    New-ModuleManifest -Path (Join-Path $target ($Name+'.psd1')) -RootModule ($Name+'.psm1') -ModuleVersion '0.1.0' -PowerShellVersion '7.6' -RequiredModules @(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh';ModuleVersion='0.1.0'}) -FunctionsToExport @() -AliasesToExport @() -PrivateData @{QuietCli=@{Binary=$Binary;TestsModule=$testName;Qualification='NotImplemented'}}
    $testSource=@'
function Invoke-ModuleTests {
    <#
    .SYNOPSIS
    Rejects an unimplemented module instead of certifying an empty test set.
    #>
    [CmdletBinding()]param()
    throw 'Write independent business assertions and enable the shared conformance suite.'
}
Export-ModuleMember -Function Invoke-ModuleTests
'@
    [void][IO.File]::WriteAllTextAsync((Join-Path $tests ($testName+'.psm1')),$testSource,$script:QuietUtf8).GetAwaiter().GetResult()
    New-ModuleManifest -Path (Join-Path $tests ($testName+'.psd1')) -RootModule ($testName+'.psm1') -ModuleVersion '0.1.0' -PowerShellVersion '7.6' -RequiredModules @(@{ModuleName=$Name;ModuleVersion='0.1.0'},@{ModuleName='FrenchExDev2.QuietCli.Core.Tests.PoSh';ModuleVersion='0.1.0'}) -FunctionsToExport Invoke-ModuleTests -AliasesToExport @()
    foreach($entry in @(@{Path=$target;Text="# $Name`n`nHandler for $Binary. Qualification: not implemented. Import registers an inert catalogue. Edit src/Handler.ps1: document the official sources, implement Probe and TestVersion, declare supported forms in Match, then implement Execute with explicit quiet callbacks. Keep business data local; never gather raw output for accounting. Add schemas, examples and qualification limits before general use."},@{Path=$tests;Text="# $testName`n`nIndependent tests for $Name. An empty generated suite fails explicitly. Keep fixtures and assertions in this repository. Use Invoke-QuietConformance for shared envelope invariants and independently authored assertions for business effects. The business module must never depend on this companion."})){
        [void][IO.File]::WriteAllTextAsync((Join-Path $entry.Path 'README.md'),$entry.Text,$script:QuietUtf8).GetAwaiter().GetResult()
    }
    [pscustomobject]@{Module=$target;Tests=$tests;Qualification='NotImplemented'}
}
