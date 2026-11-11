# Vagrant test companion

This companion owns its `Invoke-QuietVagrantTests` runner and the complete literal `$caseMetadata` table in its own `.psm1`. Its manifest declares its RootModule, TestCatalogue runner/helper sources and TestExecution policy. Shared infrastructure discovers and validates these declarations without importing the product; Core.Tests does not own Vagrant's case catalogue.

There are 14 declared cases: six Unit parser/property cases and eight Integration cases, including the optional parser mutation campaign. The mutation case declares `EnabledWhen=QUIETCLI_VAGRANT_PARSER_MUTATION=1`, independently checked against its registration guard. Without that request, 13 cases are active; an omitted active case fails metadata validation.

The manifest cap is two. The six pure parser cases opt into IsolatedProcess execution; environment, handler and native-fixture cases remain Ordered. Each isolated case receives a private configuration/report directory and one internal slot. Cases use the owned Core fixture rather than installing Vagrant or contacting a provider. Real-provider qualification remains separate.

```powershell
./scripts/Test-TestCaseMetadata.ps1 -Suite Vagrant -Plan -MaxConcurrency 2
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild -Case '[Ca]*line*' -MaxConcurrency 2
```

The second command is a partial, monitored development run selecting three pure parser cases. Case filters and stop-on-first-failure retain explicit Partial/Incomplete scope. See [classification and concurrency](../docs/README-test-classification-and-concurrency.md) and [qualification](../README-qualification-when-where-how.md). License attribution is recorded in [CREDITS.md](../CREDITS.md).

FragmentedTranscripts/MalformedInputs report completed campaign counts only after their corresponding fuzz case succeeds; they remain null for unexecuted or incomplete campaigns. A filtered parser run must not claim the full native fuzz corpus ran.
