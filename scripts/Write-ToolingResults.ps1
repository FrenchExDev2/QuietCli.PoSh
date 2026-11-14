#requires -Version 7.6
<#
.SYNOPSIS
Writes separate tooling job results to the GitHub output file, including failed or incomplete prerequisites.
.PARAMETER NeedsJson
Authoritative needs object from the always-running tooling result job.
.PARAMETER OutputPath
GitHub step output file receiving closed result strings.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][AllowEmptyString()][string]$NeedsJson,[Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($OutputPath,'Write separate tooling qualification results')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ToolingResults.psm1')) -DisableNameChecking -ErrorAction Stop
$result=Get-QuietToolingResults -NeedsJson $NeedsJson
$text="functional_result=$($result.FunctionalResult)`nmutation_result=$($result.MutationResult)`ncompletion_result=$($result.CompletionResult)`n"
[void][IO.File]::AppendAllTextAsync($OutputPath,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
$result
