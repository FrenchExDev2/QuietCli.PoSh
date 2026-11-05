#requires -Version 7.6
#requires -PSEdition Core
Set-StrictMode -Version Latest
$script:QuietRoot=$PSScriptRoot
$script:QuietSession=[guid]::NewGuid().ToString('N')
$script:QuietEngine=$null
$script:QuietHandlers=[ordered]@{}
$script:QuietProbeCache=@{}
$script:QuietStack=[Collections.Generic.Stack[object]]::new()
$script:QuietUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:QuietProtocol=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'protocol.json') -Encoding utf8 -Raw|ConvertFrom-Json
if($script:QuietProtocol.Version -ne 1 -or $script:QuietProtocol.BlockSize -gt 16384 -or $script:QuietProtocol.BlockSize -lt 1024 -or $script:QuietProtocol.HeaderLimit -gt 1048576 -or $script:QuietProtocol.HeaderLimit -lt 65536){throw 'UnsafeProtocolSpecification'}
foreach($source in @('Contracts','Dependencies','Protocol','Runtime','Invoke','Delivery','Registry','Gain','Scaffold')){. (Join-Path $PSScriptRoot "src/$source.ps1")}
Set-Alias -Name quiet -Value Invoke-QuietCli
$ExecutionContext.SessionState.Module.OnRemove={Stop-QuietEngine}
Export-ModuleMember -Function Invoke-QuietCli,Out-QuietResult,ConvertTo-QuietJson,Get-QuietCliGain,Repair-QuietCliMeasurementPrivacy,Register-QuietHandler,Get-QuietHandler,Unregister-QuietHandler,New-QuietModule,Stop-QuietEngine,Get-QuietEngine -Alias quiet
