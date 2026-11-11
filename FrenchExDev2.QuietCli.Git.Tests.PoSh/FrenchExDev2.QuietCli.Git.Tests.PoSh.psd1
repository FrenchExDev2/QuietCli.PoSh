@{
 RootModule='FrenchExDev2.QuietCli.Git.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='ff6d693b-d16a-4098-b783-24dffb366cc9';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Git.PoSh';ModuleVersion='0.1.0'},@{ModuleName='FrenchExDev2.QuietCli.Core.Tests.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietGitTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{
 TestCatalogue=@{Runner='Invoke-QuietGitTests';Sources=@('IndexOperations.Tests.ps1','Revisions.Tests.ps1','PathQueries.Tests.ps1','Attribution.Tests.ps1','Queries.Tests.ps1','RepositoryCommands.Tests.ps1','Semantic.Tests.ps1','CiImages.Tests.ps1')}
 TestExecution=@{SchemaVersion=1;DefaultMode='Ordered';DefaultReason='Cases mutate shared synthetic Git repositories, handlers and probe history; preserve their prerequisites.';MaxParallelCases=2;Cases=@{
  'compiled Git parsers preserve migration vectors and measure local costs'=@{Mode='Exclusive';Reason='Paired parser cost measurements require exclusive execution within this companion.'}
 }}
 BuildProjects=@(
  @{Project='parser-tests/QuietCli.Git.Parser.Tests.csproj';Outputs=@{'net11.0'='lib/parser-tests'}}
 )}}
}
