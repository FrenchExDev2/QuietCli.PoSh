@{
 RootModule='FrenchExDev2.QuietCli.Core.PoSh.psm1'
 ModuleVersion='0.1.0'
 GUID='41464c2f-3715-4bf6-9a08-3a90c3d7aeda'
 Author='Stéphane Erard'
 Description='Streaming QuietCli2 facade for the separate .NET 11 RC engine.'
 PowerShellVersion='7.6'
 CompatiblePSEditions=@('Core')
 FunctionsToExport=@('Invoke-QuietCli','Out-QuietResult','ConvertTo-QuietJson','Get-QuietCliGain','Repair-QuietCliMeasurementPrivacy','Register-QuietHandler','Get-QuietHandler','Unregister-QuietHandler','New-QuietModule','Stop-QuietEngine','Get-QuietEngine')
 AliasesToExport=@('quiet')
 CmdletsToExport=@()
 VariablesToExport=@()
 PrivateData=@{
  PSData=@{Tags=@('QuietCli','AI','CLI','Windows','Linux','ARM64');LicenseUri='https://opensource.org/license/mit';ProjectUri='https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh';ReleaseNotes='Initial streaming engine. Requires PowerShell 7.6+ and .NET 11 RC. Includes Windows and Linux x64/ARM64 engines, including musl. ARM64 binaries are cross-compiled; native platform qualification is reported separately.'}
  QuietCli=@{ProtocolVersion=1;TestsModule='FrenchExDev2.QuietCli.Core.Tests.PoSh'}
 }
}
