@{
 RootModule='FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psm1';ModuleVersion='0.1.0';GUID='3a9c7e21-6b4f-4d2a-9c1e-8f5b2d6a7e30';Author='Stéphane Erard';PowerShellVersion='7.6';CompatiblePSEditions=@('Core')
 RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Vagrant.PoSh';ModuleVersion='0.1.0'},@{ModuleName='FrenchExDev2.QuietCli.Core.Tests.PoSh';ModuleVersion='0.1.0'})
 FunctionsToExport=@('Invoke-QuietVagrantTests');AliasesToExport=@();CmdletsToExport=@();VariablesToExport=@()
 PrivateData=@{QuietCli=@{
  TestCatalogue=@{Runner='Invoke-QuietVagrantTests';Sources=@('VagrantLine.Tests.ps1','VagrantFuzz.Tests.ps1')}
  TestExecution=@{SchemaVersion=1;DefaultMode='Ordered';DefaultReason='Preserve shared process environment, loaded handlers and native fixture assumptions until isolated-case qualification.';MaxParallelCases=2;Cases=@{
   'ConvertFrom-QuietVagrantMachineReadableLine matches the independent oracle on interleaved web/db lines'=@{Mode='IsolatedProcess';Reason='Pure string parser and independent oracle; all inputs and state are owned by the case.'}
   'a ui/info Running provisioner line is recognized as the ProvisionerStarted trigger shape'=@{Mode='IsolatedProcess';Reason='Pure parsing and trigger-shape assertions with case-local strings and matches.'}
   'real provisioner prefixes preserve exact machine identity across generated names and malformed messages'=@{Mode='IsolatedProcess';Reason='Seeded in-memory event vectors; no shared environment, handlers or native process effects.'}
   'an escaped comma in Vagrant data is correctly un-escaped'=@{Mode='IsolatedProcess';Reason='Pure in-memory escaping and independent-oracle assertions with owned strings.'}
   'a malformed or truncated line is dropped without throwing'=@{Mode='IsolatedProcess';Reason='Pure bounded malformed strings; no external state or process effects.'}
   'bounded malformed timestamps and missing fields are rejected without partial events'=@{Mode='IsolatedProcess';Reason='Seeded in-memory malformed parsing assertions with case-local data.'}
  }}
 }}
}
