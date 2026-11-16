#requires -Version 7.6
function Write-QuietCiPlanReport {
    <#
    .SYNOPSIS
    Saves a reviewable reason chain and publishes it in the GitHub planning check summary.
    .PARAMETER Plan
    Selective CI decision.
    .PARAMETER Base
    Baseline revision.
    .PARAMETER Revision
    Candidate revision.
    .PARAMETER Directory
    Owned output directory.
    .PARAMETER SummaryPath
    Optional GitHub step-summary path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Plan,[string]$Base,[string]$Revision,[Parameter(Mandatory)][string]$Directory,[string]$SummaryPath)
    if(!$PSCmdlet.ShouldProcess($Directory,'Save CI impact explanation')){return}
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
    [void][IO.Directory]::CreateDirectory($Directory)
    Write-WorkspaceJson ([IO.Path]::Combine($Directory,'plan.json')) @{Base=$Base;Revision=$Revision;Plan=$Plan}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('# QuietCli selective CI');$lines.Add('')
    $lines.Add('Base: '+$Base+'; candidate: '+$Revision+'.');$lines.Add('')
    $lines.Add('Full suites: '+(@($Plan.FullSuites) -join ', ')+'.')
    $lines.Add('Smoke suites: '+(@($Plan.SmokeSuites) -join ', ')+'.');$lines.Add('')
    $lines.Add('| Changed input | Package | Consumer project | Companion | Action | Reason |')
    $lines.Add('|---|---|---|---|---|---|')
    foreach($reason in $Plan.Reasons){
        $cells=@($reason.Input,$reason.Package,$reason.Project,$reason.Companion,$reason.Action,$reason.Reason)|ForEach-Object {([string]$_).Replace('|','\|').Replace([string][char]10,' ')}
        $lines.Add('| '+($cells -join ' | ')+' |')
    }
    $lines.Add('');$lines.Add('Unselected scopes were not tested. Build/cache preparation is separate from qualification.')
    $text=($lines -join [char]10)+[char]10
    [IO.File]::WriteAllText([IO.Path]::Combine($Directory,'impact.md'),$text,[Text.UTF8Encoding]::new($false))
    if($SummaryPath){[IO.File]::AppendAllText($SummaryPath,$text,[Text.UTF8Encoding]::new($false))}
}
Export-ModuleMember -Function Write-QuietCiPlanReport
