@{
 RootModule='FrenchExDev2.QuietCli.Distribution.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='ca0c2322-016d-48b9-9e83-13695770ccf5';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.Tests.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietDistributionTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{Publishable=$false;TestCatalogue=@{Runner='Invoke-QuietDistributionTests';Sources=@()};TestExecution=@{SchemaVersion=1;DefaultMode='Ordered';DefaultReason='Distribution checks consume the verified six-RID build behind one packaging barrier.';MaxParallelCases=2;Cases=@{}}}}
}
