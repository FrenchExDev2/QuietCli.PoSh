#requires -Version 7.6
#requires -PSEdition Core
Set-StrictMode -Version Latest
$script:QuietRoot=$PSScriptRoot
$script:QuietSession=[guid]::NewGuid().ToString('N')
$script:QuietEngine=$null
$script:QuietManagedAssembly=$null
$script:QuietHandlers=[ordered]@{}
$script:QuietProbeCache=@{}
$script:QuietStack=[Collections.Generic.Stack[object]]::new()
$script:QuietRecallDepth=0
$script:QuietConfiguration=$null
$script:QuietTokenizers=@{}
$script:QuietUtf8=[Text.UTF8Encoding]::new($false,$true)
foreach($source in @('Contracts','Dependencies','Protocol','Configuration','Runtime','Invoke','Delivery','Registry','Gain','Scaffold','Recall','Agent')){. ([IO.Path]::Combine($PSScriptRoot,"src/$source.ps1"))}
$script:QuietProtocol=Read-QuietProtocolSpecification ([IO.Path]::Combine($PSScriptRoot,'protocol.json'))
[void]$ExecutionContext.SessionState.InvokeProvider.Item.Set('Alias:quiet','Invoke-QuietCli')
$ExecutionContext.SessionState.Module.OnRemove={Stop-QuietEngine}
Export-ModuleMember -Function Invoke-QuietCli,Out-QuietResult,ConvertTo-QuietJson,Get-QuietCliGain,Repair-QuietCliMeasurementPrivacy,Register-QuietHandler,Get-QuietHandler,Unregister-QuietHandler,New-QuietModule,New-QuietByteRecordFramer,Stop-QuietEngine,Get-QuietEngine -Alias quiet
Export-ModuleMember -Function Get-QuietRecall,Invoke-QuietRecall,New-QuietRecallReference,Export-QuietRecall,Import-QuietRecall
Export-ModuleMember -Function Save-QuietRecall,Get-QuietSavedRecall
Export-ModuleMember -Function Get-QuietCliConfiguration,Test-QuietCliConfiguration,Import-QuietCliConfiguration,New-QuietCliConfiguration,ConvertTo-QuietYaml
Export-ModuleMember -Function Get-QuietAgentInstruction,Add-QuietAgentInstruction
