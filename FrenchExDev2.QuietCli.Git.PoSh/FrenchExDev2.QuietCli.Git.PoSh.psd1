@{
 RootModule='FrenchExDev2.QuietCli.Git.PoSh.psm1';ModuleVersion='0.1.0';GUID='fb86bdbe-f964-461c-b144-a655e42df279';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh';ModuleVersion='0.1.0'})
 Description='Streaming Git handlers for QuietCli2. Fourteen command families; full Git inventory qualification remains incomplete.'
 FunctionsToExport=@('Get-QuietGitCoverage','Remove-QuietGitArtifact');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{
  PSData=@{Tags=@('QuietCli','Git','AI','Windows','Linux','ARM64');LicenseUri='https://opensource.org/license/mit';ProjectUri='https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh';ReleaseNotes='Initial Git handlers with an explicit Core dependency. Full command/version qualification remains incomplete.'}
  QuietCli=@{Binary='git';TestsModule='FrenchExDev2.QuietCli.Git.Tests.PoSh';Qualification='Partial'}
 }
}
