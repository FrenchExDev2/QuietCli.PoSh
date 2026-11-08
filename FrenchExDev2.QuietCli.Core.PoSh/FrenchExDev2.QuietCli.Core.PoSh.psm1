#requires -Version 7.6
#requires -PSEdition Core
Set-StrictMode -Version Latest
$script:QuietRoot=$PSScriptRoot
$script:QuietSession=[guid]::NewGuid().ToString('N')
$script:QuietManagedAssembly=$null
$script:QuietUtf8=[Text.UTF8Encoding]::new($false,$true)
foreach($source in @('Protocol','Invoke')){. ([IO.Path]::Combine($PSScriptRoot,"src/$source.ps1"))}
$script:QuietProtocol=Read-QuietProtocolSpecification ([IO.Path]::Combine($PSScriptRoot,'protocol.json'))
# The verified engine assembly also carries the compiled cmdlets; importing it here avoids compiling their scripts.
Import-QuietManagedEngine
[FrenchExDev2.QuietCli.QuietSession]::Initialize($PSScriptRoot)
Import-Module -Assembly $script:QuietManagedAssembly
$script:QuietSession=[FrenchExDev2.QuietCli.QuietSession]::SessionId
$script:QuietMetadataAdapter=[FrenchExDev2.QuietCli.MetadataAdapter]::Instance
[void]$ExecutionContext.SessionState.InvokeProvider.Item.Set('Alias:quiet','Invoke-QuietCli')
$ExecutionContext.SessionState.Module.OnRemove={Stop-QuietEngine}
Export-ModuleMember -Function Invoke-QuietCli -Alias quiet
Export-ModuleMember -Cmdlet New-QuietModule,Get-QuietAgentInstruction,Add-QuietAgentInstruction,Register-QuietHandler,Get-QuietHandler,Unregister-QuietHandler,Out-QuietResult,ConvertTo-QuietJson,ConvertTo-QuietYaml,New-QuietByteRecordFramer,Get-QuietCliConfiguration,Test-QuietCliConfiguration,Import-QuietCliConfiguration,New-QuietCliConfiguration,Invoke-QuietRecall,Get-QuietRecall,New-QuietRecallReference,Export-QuietRecall,Import-QuietRecall,Save-QuietRecall,Get-QuietSavedRecall,Stop-QuietEngine,Get-QuietEngine,Get-QuietCliGain,Repair-QuietCliMeasurementPrivacy
