#requires -Version 7.6
<#
.SYNOPSIS
Publishes/consumes fixture previews using the real PSResourceGet client in an isolated user environment.
.PARAMETER Uri
Explicit fixture feed endpoint; no public fallback is queried.
.PARAMETER RunDirectory
Owned client output directory.
.PARAMETER Publish
Publishes fixture packages before consuming, for the Windows producer/client.
.PARAMETER DependencyStrategy
Explicit automatic resolution or separately restored pinned preview closure.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][uri]$Uri,[Parameter(Mandatory)][string]$RunDirectory,[switch]$Publish,
    [ValidateSet('Automatic','PinnedClosure')][string]$DependencyStrategy='Automatic')
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($Uri,'Publish or restore fixture packages and register an isolated client repository')){return}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$result=[ordered]@{Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';DependencyStrategy=$DependencyStrategy;AutomaticDependencyResolution=if($DependencyStrategy -eq 'Automatic'){'UnderTest'}else{'NotQualified'};Uri=[string]$Uri;PowerShell=[string]$PSVersionTable.PSVersion;Client=$null;Value=$null;Draft=$null;Modules=@();Error=$null}
try{
    Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction Stop
    $result.Client=[string](Get-Module Microsoft.PowerShell.PSResourceGet).Version
    Register-PSResourceRepository -Name OwnedProbe -Uri $Uri.AbsoluteUri -ApiVersion V3 -ErrorAction Stop
    if($Publish){
        $env:PSModulePath=(Join-Path $RunDirectory 'packages')+[IO.Path]::PathSeparator+$env:PSModulePath
        foreach($definition in @(
            @{Name='DevDependency';Label='dev1';Body="function Get-DevDependencyValue { 21 }`nExport-ModuleMember -Function Get-DevDependencyValue";Functions=@('Get-DevDependencyValue');Required=@()},
            @{Name='DevConsumer';Label='dev1';Body="function Get-DevConsumerValue { 2 * (Get-DevDependencyValue) }`nExport-ModuleMember -Function Get-DevConsumerValue";Functions=@('Get-DevConsumerValue');Required=@(@{ModuleName='DevDependency';ModuleVersion='0.0.1'})},
            @{Name='DraftWitness';Label='draft1';Body="function Get-DraftWitnessValue { 'draft1' }`nExport-ModuleMember -Function Get-DraftWitnessValue";Functions=@('Get-DraftWitnessValue');Required=@()}
        )){
            $directory=Join-Path $RunDirectory ('packages/'+$definition.Name)
            [void][IO.Directory]::CreateDirectory($directory)
            [void][IO.File]::WriteAllTextAsync((Join-Path $directory ($definition.Name+'.psm1')),$definition.Body,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            New-ModuleManifest -Path (Join-Path $directory ($definition.Name+'.psd1')) -RootModule ($definition.Name+'.psm1') -ModuleVersion '0.0.1' -Author 'Owned fixture' -Description 'Local gallery compatibility fixture' -FunctionsToExport $definition.Functions -RequiredModules $definition.Required -Prerelease $definition.Label -ErrorAction Stop
            $publishArguments=@{Path=$directory;Repository='OwnedProbe';ApiKey='OwnedFixtureOnly';ErrorAction='Stop'}
            if($DependencyStrategy -eq 'PinnedClosure'){$publishArguments.SkipDependenciesCheck=$true}
            Publish-PSResource @publishArguments
        }
    }
    $found=Find-PSResource -Name DevConsumer -Version '0.0.1-dev1' -Prerelease -Repository OwnedProbe -ErrorAction Stop
    if(!$found){throw 'FixturePreviewNotFound'}
    $save=Join-Path $RunDirectory 'modules'
    [void][IO.Directory]::CreateDirectory($save)
    if($DependencyStrategy -eq 'PinnedClosure'){
        Save-PSResource -Name DevDependency -Version '0.0.1-dev1' -Prerelease -Repository OwnedProbe -Path $save -TrustRepository -AcceptLicense -ErrorAction Stop
        Save-PSResource -Name DevConsumer -Version '0.0.1-dev1' -Prerelease -Repository OwnedProbe -Path $save -TrustRepository -AcceptLicense -SkipDependencyCheck -ErrorAction Stop
    }else{
        Save-PSResource -Name DevConsumer -Version '0.0.1-dev1' -Prerelease -Repository OwnedProbe -Path $save -TrustRepository -AcceptLicense -ErrorAction Stop
        $result.AutomaticDependencyResolution='Passed'
    }
    Save-PSResource -Name DraftWitness -Version '0.0.1-draft1' -Prerelease -Repository OwnedProbe -Path $save -TrustRepository -AcceptLicense -ErrorAction Stop
    $env:PSModulePath=$save+[IO.Path]::PathSeparator+$env:PSModulePath
    Import-Module DevConsumer -ErrorAction Stop
    Import-Module DraftWitness -ErrorAction Stop
    $result.Value=Get-DevConsumerValue
    $result.Draft=Get-DraftWitnessValue
    if($result.Value -ne 42 -or $result.Draft -cne 'draft1'){throw 'FixtureBehaviorMismatch'}
    $result.Modules=@(Get-Module DevConsumer,DevDependency,DraftWitness | ForEach-Object {[pscustomobject]@{Name=$_.Name;Version=[string]$_.Version;Path=$_.Path;Sha256=(Get-FileHash -LiteralPath $_.Path).Hash;Exports=@($_.ExportedFunctions.Keys)}})
    if($result.Modules.Count -ne 3){throw 'FixtureDependencyNotImported'}
    $result.State='Success'
}catch{$result.State='Failed';$result.Error=$_.Exception.Message}
finally{
    $json=(ConvertTo-Json $result -Depth 12).Replace("`r`n","`n")+"`n"
    [void][IO.File]::WriteAllTextAsync((Join-Path $RunDirectory 'client-summary.json'),$json,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
if($result.State -ne 'Success'){exit 1}
