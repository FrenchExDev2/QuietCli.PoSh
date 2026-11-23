#requires -Version 7.6
<#
.SYNOPSIS
Renders campaign evidence as Markdown and standalone HTML.
.PARAMETER Directory
Owned campaign output directory.
.PARAMETER Kind
Source evidence contract.
.PARAMETER Title
Human-readable campaign title.
.PARAMETER Outcome
Original outcome of the campaign step.
.PARAMETER SummaryPath
Optional Markdown job summary file.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][ValidateSet('ScriptMutation','RunProfilesMutation','Component')][string]$Kind,[Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][ValidateSet('success','failure','cancelled')][string]$Outcome,[string]$SummaryPath)
if(!$PSCmdlet.ShouldProcess($Directory,'Export campaign visualization')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CampaignReports.psm1')) -DisableNameChecking -ErrorAction Stop
Write-QuietCampaignReport -Directory $Directory -Kind $Kind -Title $Title -Outcome $Outcome -SummaryPath $SummaryPath -Confirm:$false -ErrorAction Stop
