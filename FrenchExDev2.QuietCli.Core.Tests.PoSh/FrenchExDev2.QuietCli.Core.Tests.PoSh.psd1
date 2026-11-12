@{
 RootModule='FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='ebd31b05-da0f-4c36-95e5-daad4d718e7a';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietCoreTests','Assert-QuietEqual','Invoke-QuietConformance','Compare-QuietRecallAnalysis','Export-QuietRecallFixture','Reduce-QuietRecall','Invoke-QuietRecallTests','Invoke-QuietRecallRtkComparison','Invoke-QuietRecallLargeTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{TestCatalogue=@{Runner='Invoke-QuietCoreTests';Sources=@()};BuildProjects=@(
  @{Project='fixture/QuietCli.Fixture.csproj';Outputs=@{'net11.0'='lib/fixture'}}
  @{Project='engine-tests/QuietCli.Engine.Tests.csproj';Outputs=@{'net11.0'='lib/engine-tests'}}
  @{Project='recall-tools/QuietCli.Recall.Tools.csproj';Outputs=@{'net10.0'='lib/recall-tools/net10.0';'net11.0'='lib/recall-tools/net11.0'}}
 );TestExecution=@{
  SchemaVersion=1
  DefaultMode='Ordered'
  DefaultReason='Preserve existing order: engine, history and fixture dependencies are not independently isolated.'
  MaxParallelCases=2
  Cases=@{
   'security audit counterexamples are closed with independent evidence'=@{Mode='IsolatedProcess';Reason='Audit already owns child configuration, SQLite, native fixtures and synthetic package directories.';TimeoutSeconds=180}
   'fresh sessions measure inert Core import against a paired baseline'=@{Mode='Exclusive';Reason='Paired process timing measurements require no competing test campaigns.'}
   'import diagnostics retain independent first-use controls'=@{Mode='Exclusive';Reason='First-use process and engine measurements must not overlap competing test campaigns.'}
   'Core migration preserves metadata and compares local helper costs'=@{Mode='Exclusive';Reason='Engine restart and local timing measurements require exclusive test execution.'}
   'typed controls measure local JSON avoidance with identical stdin'=@{Mode='Exclusive';Reason='Paired native and serialization timing measurements require exclusive execution.'}
   'compiled framing and direct engine measure local overhead independently'=@{Mode='Exclusive';Reason='Overhead measurements must not overlap competing test campaigns.'}
   'cold engine and warm block-size measurements retain no business output'=@{Mode='Exclusive';Reason='Cold engine restart and warm timing samples require exclusive execution.'}
   'large output retains only bounded transport blocks'=@{Mode='Exclusive';Reason='Process-wide allocation measurements must not overlap other test cases.'}
   'PSGallery Core installs outside sources with its embedded engine and no Git companion'=@{Mode='Exclusive';Reason='Consumes shared build and package inputs behind the packaging barrier.'}
  }
 }}}
}
