#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PerformanceCharts.psm1')) -DisableNameChecking -ErrorAction Stop

function Read-QuietCampaignEvidence {
    <# .SYNOPSIS
    Reads one JSON file from the selected campaign directory when present.
    .PARAMETER Path
    Expected evidence file.
    #>
    param([string]$Path)
    if([IO.File]::Exists($Path)){
        $encoding=[Text.Encoding]::GetEncoding('utf-8',[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
        [IO.File]::ReadAllText($Path,$encoding) | ConvertFrom-Json
    }
}

function Get-QuietCampaignCharts {
    <# .SYNOPSIS
    Projects known evidence files into independent mutation and profiling series.
    .PARAMETER Directory
    Campaign output directory.
    .PARAMETER Kind
    Evidence contract for the selected campaign.
    #>
    param([string]$Directory,[string]$Kind)
    if($Kind -eq 'ScriptMutation'){
        $evidence=Read-QuietCampaignEvidence ([IO.Path]::Combine($Directory,'report.json'))
        foreach($target in $evidence.Targets){
            $counts=[ordered]@{Killed=$target.Killed;Survived=$target.Survived;Timeout=$target.Timeout;'Compile error'=$target.CompileError;Equivalent=$target.Equivalent}
            [pscustomobject]@{Heading=$target.Name;Unit='Mutants';Rows=@(foreach($key in $counts.Keys){[pscustomobject]@{Label=$key;Value=$counts[$key]}})}
        }
        return
    }
    $profiles=Read-QuietCampaignEvidence ([IO.Path]::Combine($Directory,'run-profiles-mutation.json'))
    if($profiles){
        $label=if($profiles.Partial){"Run profiles (shard $($profiles.ShardIndex + 1)/$($profiles.ShardCount))"}else{'Run profiles'}
        [pscustomobject]@{Heading=$label;Unit='Mutants';Rows=@($profiles.Results|Group-Object Outcome|ForEach-Object {[pscustomobject]@{Label=$_.Name;Value=$_.Count}})}
    }
    foreach($file in Get-ChildItem -LiteralPath ([IO.Path]::Combine($Directory,'mutation-evidence')) -Filter '*.json' -File -ErrorAction SilentlyContinue){
        $evidence=Read-QuietCampaignEvidence $file.FullName
        $outcomes=if($evidence.Results){$evidence.Results.State}else{$evidence.Cases.Outcome}
        $rows=@($outcomes|Group-Object|ForEach-Object {[pscustomobject]@{Label=$_.Name;Value=$_.Count}})
        if($evidence.Selected -gt $evidence.Completed){$rows+=[pscustomobject]@{Label='Pending';Value=$evidence.Selected-$evidence.Completed}}
        [pscustomobject]@{Heading=$file.BaseName;Unit='Mutants';Rows=$rows}
    }
    foreach($file in Get-ChildItem -LiteralPath ([IO.Path]::Combine($Directory,'profiling')) -Filter '*.profile.json' -File -ErrorAction SilentlyContinue){
        $trace=Read-QuietCampaignEvidence $file.FullName
        foreach($series in @(@{Title='Top functions';Rows=$trace.TopFunctionsBySelfDuration},@{Title='Top lines';Rows=$trace.TopLinesBySelfDuration})){
            $rows=@(foreach($row in $series.Rows|Select-Object -First 8){
                $label=if($series.Title -ceq 'Top functions' -and $row.Function){$row.Function}else{[IO.Path]::GetFileName($row.File)+':'+$row.Line}
                [pscustomobject]@{Label=$label;Value=$row.SelfMs}
            })
            [pscustomobject]@{Heading=$series.Title;Unit='Self time (ms)';Rows=$rows}
        }
    }
}

function Write-QuietCampaignReport {
    <# .SYNOPSIS
    Writes a Mermaid report, a standalone HTML view and an optional GitHub job summary.
    .PARAMETER Directory
    Owned directory for this campaign.
    .PARAMETER Kind
    Source evidence contract.
    .PARAMETER Title
    Human-readable campaign title.
    .PARAMETER Outcome
    Outcome of the campaign step, independent of the report content.
    .PARAMETER SummaryPath
    Optional GitHub Markdown summary file to append to.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][ValidateSet('ScriptMutation','RunProfilesMutation','Component')][string]$Kind,[Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][ValidateSet('success','failure','cancelled')][string]$Outcome,[string]$SummaryPath)
    if(!$PSCmdlet.ShouldProcess($Directory,'Write campaign reports')){return}
    $directoryPath=[IO.Path]::GetFullPath($Directory,(Get-Location).ProviderPath)
    $charts=@(Get-QuietCampaignCharts -Directory $directoryPath -Kind $Kind)
    $titleText=ConvertTo-QuietChartText $Title 120
    $markdown=[Collections.Generic.List[string]]::new()
    $markdown.AddRange([string[]]@("# $titleText",'',"Campaign outcome **$Outcome**.",''))
    $html=[Collections.Generic.List[string]]::new()
    $html.AddRange([string[]]@('<!doctype html>',('<html lang="en"><meta charset="utf-8"><title>{0}</title>' -f (ConvertTo-QuietChartXml $titleText)),
        '<style>body{font:1rem system-ui;max-width:60rem;margin:2rem auto;padding:0 1rem}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:.4rem;border-bottom:1px solid #888}meter{width:100%}</style>',
        ('<h1>{0}</h1><p>Campaign outcome <strong>{1}</strong>.</p>' -f (ConvertTo-QuietChartXml $titleText),$Outcome)))
    if(!@($charts|Where-Object {$_.Rows.Count}).Count){
        $markdown.Add('No campaign measurements were produced.');$markdown.Add('')
        $html.Add('<p>No campaign measurements were produced.</p>')
    }
    foreach($chart in $charts){
        $rows=@($chart.Rows|Where-Object {$null -ne $_.Value -and [double]::IsFinite([double]$_.Value) -and $_.Value -ge 0})
        if(!$rows.Count){continue}
        $heading=ConvertTo-QuietChartText $chart.Heading 100
        $values=@($rows|ForEach-Object {([double]$_.Value).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)})
        $labels=@(for($index=0;$index -lt $rows.Count;$index++){'"'+($index+1)+'. '+(ConvertTo-QuietChartText $rows[$index].Label 48)+'"'})
        $max=[Math]::Max(1.0,[Math]::Ceiling(($rows.Value|Measure-Object -Maximum).Maximum))
        $bound=$max.ToString([Globalization.CultureInfo]::InvariantCulture)
        $markdown.AddRange([string[]]@("## $heading",'','```mermaid','xychart-beta horizontal',
            ('    x-axis ['+($labels -join ', ')+']'),('    y-axis "'+$chart.Unit+'" 0 --> '+$bound),('    bar ['+($values -join ', ')+']'),'```','',
            ('| Item | '+$chart.Unit+' |'),'| --- | ---: |'))
        $html.Add(('<h2>{0}</h2><table><thead><tr><th>Item</th><th>{1}</th><th>Chart</th></tr></thead><tbody>' -f (ConvertTo-QuietChartXml $heading),(ConvertTo-QuietChartXml $chart.Unit)))
        for($i=0;$i -lt $rows.Count;$i++){
            $markdown.Add(('| {0} | {1} |' -f (ConvertTo-QuietChartText $rows[$i].Label 100),$values[$i]))
            $html.Add(('<tr><th scope="row">{0}</th><td>{1}</td><td><meter min="0" max="{2}" value="{1}">{1}</meter></td></tr>' -f (ConvertTo-QuietChartXml $rows[$i].Label),$values[$i],$bound))
        }
        $markdown.Add('');$html.Add('</tbody></table>')
    }
    $html.Add('</html>')
    $short=($markdown -join "`n")+"`n"
    $details=''
    if($Kind -eq 'ScriptMutation' -and ($evidence=Read-QuietCampaignEvidence ([IO.Path]::Combine($directoryPath,'report.json')))){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutation.psm1')) -DisableNameChecking -ErrorAction Stop
        $details="`n"+(ConvertTo-QuietScriptMutationMarkdown $evidence)
    }
    $encoding=[Text.UTF8Encoding]::new($false)
    [void][IO.Directory]::CreateDirectory($directoryPath)
    [IO.File]::WriteAllText([IO.Path]::Combine($directoryPath,'report.md'),$short+$details,$encoding)
    [IO.File]::WriteAllText([IO.Path]::Combine($directoryPath,'report.html'),($html -join "`n")+"`n",$encoding)
    if($SummaryPath){[IO.File]::AppendAllText([IO.Path]::GetFullPath($SummaryPath,(Get-Location).ProviderPath),$short,$encoding)}
}

Export-ModuleMember -Function Write-QuietCampaignReport
