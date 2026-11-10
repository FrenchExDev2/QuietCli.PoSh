@{
 RootModule='FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='ebd31b05-da0f-4c36-95e5-daad4d718e7a';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietCoreTests','Assert-QuietEqual','Invoke-QuietConformance','Compare-QuietRecallAnalysis','Export-QuietRecallFixture','Reduce-QuietRecall','Invoke-QuietRecallTests','Invoke-QuietRecallRtkComparison','Invoke-QuietRecallLargeTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{BuildProjects=@(
  @{Project='fixture/QuietCli.Fixture.csproj';Outputs=@{'net11.0'='lib/fixture'}}
  @{Project='engine-tests/QuietCli.Engine.Tests.csproj';Outputs=@{'net11.0'='lib/engine-tests'}}
  @{Project='recall-tools/QuietCli.Recall.Tools.csproj';Outputs=@{'net10.0'='lib/recall-tools/net10.0';'net11.0'='lib/recall-tools/net11.0'}}
 )}}
}
