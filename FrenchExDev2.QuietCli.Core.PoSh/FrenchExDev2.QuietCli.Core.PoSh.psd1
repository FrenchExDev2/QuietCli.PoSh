@{
 RootModule='FrenchExDev2.QuietCli.Core.PoSh.psm1'
 ModuleVersion='0.2.0'
 GUID='41464c2f-3715-4bf6-9a08-3a90c3d7aeda'
 Author='Stéphane Erard'
 Description='Streaming QuietCli2 facade with automatic integrated .NET 10/11 hosting and optional isolated .NET 11 engine.'
 PowerShellVersion='7.6'
 CompatiblePSEditions=@('Core')
 FunctionsToExport=@('Invoke-QuietCli','Get-QuietCliGain','Repair-QuietCliMeasurementPrivacy','Register-QuietHandler','Get-QuietHandler','Unregister-QuietHandler','New-QuietModule','Invoke-QuietRecall','Get-QuietAgentInstruction','Add-QuietAgentInstruction')
 AliasesToExport=@('quiet')
 CmdletsToExport=@('Out-QuietResult','ConvertTo-QuietJson','ConvertTo-QuietYaml','New-QuietByteRecordFramer','Get-QuietCliConfiguration','Test-QuietCliConfiguration','Import-QuietCliConfiguration','New-QuietCliConfiguration','Get-QuietRecall','New-QuietRecallReference','Export-QuietRecall','Import-QuietRecall','Save-QuietRecall','Get-QuietSavedRecall','Stop-QuietEngine','Get-QuietEngine')
 VariablesToExport=@()
 PrivateData=@{
  PSData=@{Prerelease='preview';Tags=@('QuietCli','AI','CLI','Windows','Linux','ARM64');LicenseUri='https://opensource.org/license/mit';ProjectUri='https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh';ReleaseNotes='Preview of automatic integrated .NET 10/11 hosting and compiled record framing. Optional isolated .NET 11 RC engine. Native platform qualification is reported separately.'}
  QuietCli=@{ProtocolVersion=1;TestsModule='FrenchExDev2.QuietCli.Core.Tests.PoSh'}
 }
}
