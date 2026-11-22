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
    Owned output directory for the JSON and Markdown bundle.
    .PARAMETER MarkdownPath
    Destination for a standalone Markdown plan.
    .PARAMETER SummaryPath
    Optional GitHub step-summary path.
    #>
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Bundle')]
    param(
        [Parameter(Mandatory)]$Plan,[string]$Base,[string]$Revision,
        [Parameter(Mandatory,ParameterSetName='Bundle')][string]$Directory,
        [Parameter(Mandatory,ParameterSetName='Markdown')][string]$MarkdownPath,
        [Parameter(ParameterSetName='Bundle')][string]$SummaryPath
    )
    if($Directory){$MarkdownPath=[IO.Path]::Combine($Directory,'impact.md')}
    $MarkdownPath=[IO.Path]::GetFullPath($MarkdownPath,$PWD.ProviderPath)
    if(!$PSCmdlet.ShouldProcess($MarkdownPath,'Save CI impact explanation')){return}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($MarkdownPath))
    if($Directory){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
        Write-WorkspaceJson ([IO.Path]::Combine($Directory,'plan.json')) @{Base=$Base;Revision=$Revision;Plan=$Plan}
    }
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('# QuietCli selective CI');$lines.Add('')
    $lines.Add('Base: '+$Base+'; candidate: '+$Revision+'.');$lines.Add('')
    $lines.Add('Full suites: '+(@($Plan.FullSuites) -join ', ')+'.')
    $lines.Add('Smoke suites: '+(@($Plan.SmokeSuites) -join ', ')+'.')
    if($Plan.PSObject.Properties['ToolingScope']){$lines.Add('Tooling: '+$Plan.ToolingScope+'.')}
    if($Plan.PSObject.Properties['RunLayout']){
        $lines.Add('Layout tests: '+$Plan.RunLayout+'.')
        $lines.Add('Distribution: '+$Plan.RunDistribution+'.')
        $lines.Add('Script test files: '+$Plan.ScriptTests.Count+'.')
        $lines.Add('Script tests require a Core/Git build: '+$Plan.ScriptTestsRequireBuild+'.')
        $lines.Add('Script mutation targets: '+(@($Plan.ScriptMutationTargets) -join ', ')+'.')
    }
    $lines.Add('')
    $lines.Add('| Changed input | Package | Consumer project | Companion | Action | Reason |')
    $lines.Add('|---|---|---|---|---|---|')
    foreach($reason in $Plan.Reasons){
        $cells=@($reason.Input,$reason.Package,$reason.Project,$reason.Companion,$reason.Action,$reason.Reason)|ForEach-Object {([string]$_).Replace('|','\|').Replace([string][char]10,' ')}
        $lines.Add('| '+($cells -join ' | ')+' |')
    }
    $lines.Add('');$lines.Add('Unselected scopes were not tested. Build/cache preparation is separate from qualification.')
    $text=($lines -join [char]10)+[char]10
    $temporary=$MarkdownPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,$text,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$MarkdownPath,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    if($SummaryPath){[IO.File]::AppendAllText($SummaryPath,$text,[Text.UTF8Encoding]::new($false))}
}
Export-ModuleMember -Function Write-QuietCiPlanReport
