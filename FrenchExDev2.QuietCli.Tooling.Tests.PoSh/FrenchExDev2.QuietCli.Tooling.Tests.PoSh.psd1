@{
 RootModule='FrenchExDev2.QuietCli.Tooling.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='f6edbd29-12f6-47eb-b317-f2b662385b29';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.Tests.PoSh';ModuleVersion='0.1.0'},@{ModuleName='FrenchExDev2.QuietCli.Git.PoSh';ModuleVersion='0.1.0'},@{ModuleName='FrenchExDev2.QuietCli.Vagrant.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietToolingTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{Publishable=$false;TestCatalogue=@{Runner='Invoke-QuietToolingTests';Sources=@()};TestExecution=@{SchemaVersion=1;DefaultMode='Ordered';DefaultReason='Automation fixtures have explicit source-lock and package prerequisites.';MaxParallelCases=2;Cases=@{}}}}
}
