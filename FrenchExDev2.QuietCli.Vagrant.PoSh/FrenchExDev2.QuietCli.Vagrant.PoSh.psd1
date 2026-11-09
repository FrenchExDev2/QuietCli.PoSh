@{
 RootModule='FrenchExDev2.QuietCli.Vagrant.PoSh.psm1';ModuleVersion='0.1.0';GUID='7f3b2c1a-9e4d-4a8f-b3c6-2d5e8f1a4c70';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh';ModuleVersion='0.2.0'})
 Description='Streaming Vagrant handlers for QuietCli2 (up/provision via --machine-readable). Qualification against a real vagrant binary remains partial.'
 FunctionsToExport=@();AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{
  PSData=@{Prerelease='preview';Tags=@('QuietCli','Vagrant','AI','Windows','Linux');LicenseUri='https://opensource.org/license/mit';ProjectUri='https://github.com/FrenchExDev2/QuietCli.PoSh';ReleaseNotes='Initial preview: up/provision handlers over --machine-readable, -Listeners/-UI integration.'}
  QuietCli=@{Binary='vagrant';TestsModule='FrenchExDev2.QuietCli.Vagrant.Tests.PoSh';Qualification='Partial';Publishable=$false}
 }
}
