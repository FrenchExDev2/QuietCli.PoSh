#requires -Version 7.6
Set-StrictMode -Version Latest

function ConvertTo-QuietChartText {
    <#
    .SYNOPSIS
    Reduces untrusted metadata to a conservative character set that is safe inside Mermaid quoted strings.
    .PARAMETER Value
    Text to sanitize; null becomes '-'.
    .PARAMETER MaxLength
    Longest kept text; longer text ends with an ellipsis.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()]$Value,[ValidateRange(4,512)][int]$MaxLength=64)
    if($null -eq $Value){return '-'}
    $text=[regex]::Replace([string]$Value,'[^A-Za-z0-9 ._=,:/+()\-·–×]','_').Trim()
    if(!$text){return '-'}
    if($text.Length -gt $MaxLength){$text=$text.Substring(0,$MaxLength-1)+'…'}
    $text
}

function ConvertTo-QuietChartXml {
    <#
    .SYNOPSIS
    Escapes text for an SVG text node or attribute value.
    .PARAMETER Value
    Text to escape; null becomes '-'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()]$Value)
    if($null -eq $Value){return '-'}
    [Security.SecurityElement]::Escape([regex]::Replace([string]$Value,'[\x00-\x08\x0B\x0C\x0E-\x1F]',' '))
}

function Format-QuietChartNumber {
    <#
    .SYNOPSIS
    Formats a finite number with the invariant culture and at most two decimals.
    .PARAMETER Value
    Finite number.
    .PARAMETER Format
    .NET numeric format string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][double]$Value,[string]$Format='0.00')
    $Value.ToString($Format,[Globalization.CultureInfo]::InvariantCulture)
}

function Get-QuietPerformanceChartSeries {
    <#
    .SYNOPSIS
    Groups workload rows into one chart per workload, measure and variant, with one bar per environment.
    .DESCRIPTION
    Keeps the first-seen order of the rows, which follows the workload catalog. Environments without
    observations are listed in Missing instead of becoming zero-length bars. A chart without any
    observation is dropped.
    .PARAMETER Workloads
    Rows from Get-QuietPerformanceWorkloadRows (Host, Workload, Measure, Variant, Instrumented, Statistics).
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Workloads)
    $charts=[ordered]@{}
    foreach($row in @($Workloads)){
        if($null -eq $row){continue}
        $key=[string]$row.Workload+"`n"+[string]$row.Measure+"`n"+[string]$row.Variant
        if(!$charts.Contains($key)){
            $charts[$key]=[pscustomobject]@{Workload=[string]$row.Workload;Measure=[string]$row.Measure;Variant=[string]$row.Variant;Instrumented=[bool]$row.Instrumented;Bars=[Collections.Generic.List[object]]::new();Missing=[Collections.Generic.List[string]]::new()}
        }
        if($null -eq $row.Statistics){$charts[$key].Missing.Add([string]$row.Host)}
        else{$charts[$key].Bars.Add([pscustomobject]@{Label=[string]$row.Host;Statistics=$row.Statistics})}
    }
    foreach($chart in $charts.Values){if($chart.Bars.Count){$chart}}
}

function Get-QuietPerformanceChartTitle {
    <#
    .SYNOPSIS
    Names a chart from its workload, measure and variant.
    .PARAMETER Chart
    Get-QuietPerformanceChartSeries item.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Chart)
    $title=$Chart.Workload+' · '+$Chart.Measure
    if($Chart.Variant -and $Chart.Variant -cne '-'){$title+=' · '+$Chart.Variant}
    $title+' (median ms)'
}

function ConvertTo-QuietPerformanceMermaidChart {
    <#
    .SYNOPSIS
    Renders one chart as a horizontal Mermaid xychart of median milliseconds, one bar per environment.
    .PARAMETER Chart
    Get-QuietPerformanceChartSeries item with at least one bar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Chart)
    $labels=@($Chart.Bars|ForEach-Object {'"'+(ConvertTo-QuietChartText $_.Label 48)+'"'})
    $values=@($Chart.Bars|ForEach-Object {Format-QuietChartNumber $_.Statistics.Median '0.##'})
    $top=[Math]::Max(1,[Math]::Ceiling((($Chart.Bars|ForEach-Object {[double]$_.Statistics.Median}|Measure-Object -Maximum).Maximum)*1.1))
    $text=[Text.StringBuilder]::new()
    [void]$text.AppendLine('```mermaid')
    [void]$text.AppendLine('%%{init: {"xyChart": {"showDataLabel": true}}}%%')
    [void]$text.AppendLine('xychart-beta horizontal')
    [void]$text.AppendLine('    title "'+(ConvertTo-QuietChartText (Get-QuietPerformanceChartTitle $Chart) 120)+'"')
    [void]$text.AppendLine('    x-axis ['+($labels -join ', ')+']')
    [void]$text.AppendLine('    y-axis "Median ms" 0 --> '+(Format-QuietChartNumber $top '0'))
    [void]$text.AppendLine('    bar ['+($values -join ', ')+']')
    [void]$text.Append('```')
    $text.ToString().Replace("`r`n","`n")
}

function Get-QuietPerformanceChartCaption {
    <#
    .SYNOPSIS
    States the numbers behind a chart as plain text: median, Q1–Q3, N and p95 per environment, and missing environments.
    .PARAMETER Chart
    Get-QuietPerformanceChartSeries item.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Chart)
    $parts=@(foreach($bar in $Chart.Bars){
        $s=$bar.Statistics
        $p95=Format-QuietChartNumber $s.P95
        if($s.P95IsMax){$p95+=' (max)'}
        $bar.Label+': '+(Format-QuietChartNumber $s.Median)+' ms, Q1–Q3 '+(Format-QuietChartNumber $s.Q1)+'–'+(Format-QuietChartNumber $s.Q3)+', N='+$s.Count+', p95 '+$p95
    })
    if($Chart.Missing.Count){$parts+='no observation: '+($Chart.Missing -join ', ')}
    $parts -join '; '
}

function ConvertTo-QuietPerformanceSvgChart {
    <#
    .SYNOPSIS
    Renders one chart as a self-contained, script-free horizontal bar SVG with values, N and Q1–Q3 whiskers.
    .DESCRIPTION
    Bars show the median, a thin whisker shows Q1–Q3 and the value at the tip states the median and N.
    Each row carries an SVG title with every statistic for a native tooltip. Colors come from CSS
    classes (qc-*) so the page can switch light and dark themes.
    .PARAMETER Chart
    Get-QuietPerformanceChartSeries item with at least one bar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Chart)
    $width=760;$labelWidth=290;$plotLeft=300;$plotWidth=300;$pitch=28;$barHeight=16;$top=34
    $height=$top+$Chart.Bars.Count*$pitch+8
    $scale=[double](($Chart.Bars|ForEach-Object {[Math]::Max([double]$_.Statistics.Median,[double]$_.Statistics.Q3)}|Measure-Object -Maximum).Maximum)
    if(!($scale -gt 0)){$scale=1}
    $title=ConvertTo-QuietChartXml (Get-QuietPerformanceChartTitle $Chart)
    $svg=[Text.StringBuilder]::new()
    [void]$svg.Append('<svg class="qc" role="img" viewBox="0 0 '+$width+' '+$height+'" width="100%" style="max-width:'+$width+'px" xmlns="http://www.w3.org/2000/svg"><title>'+$title+'</title>')
    [void]$svg.Append('<text class="qc-title" x="0" y="16">'+$title+'</text>')
    [void]$svg.Append('<text class="qc-key" x="'+$width+'" y="16" text-anchor="end">bar = median · line = Q1–Q3</text>')
    [void]$svg.Append('<line class="qc-axis" x1="'+$plotLeft+'" x2="'+$plotLeft+'" y1="'+($top-4)+'" y2="'+($height-4)+'"/>')
    $index=0
    foreach($bar in $Chart.Bars){
        $s=$bar.Statistics
        $y=$top+$index*$pitch;$mid=$y+$barHeight/2
        $w=[Math]::Max(1,$plotWidth*[double]$s.Median/$scale)
        $q1=$plotLeft+$plotWidth*[double]$s.Q1/$scale;$q3=$plotLeft+$plotWidth*[double]$s.Q3/$scale
        $p95=Format-QuietChartNumber $s.P95
        if($s.P95IsMax){$p95+=' (max)'}
        $label=ConvertTo-QuietChartText $bar.Label 44
        $tip=ConvertTo-QuietChartXml ($bar.Label+': median '+(Format-QuietChartNumber $s.Median)+' ms, Q1–Q3 '+(Format-QuietChartNumber $s.Q1)+'–'+(Format-QuietChartNumber $s.Q3)+', min–max '+(Format-QuietChartNumber $s.Min)+'–'+(Format-QuietChartNumber $s.Max)+', p95 '+$p95+', N='+$s.Count)
        $f={param([double]$v)Format-QuietChartNumber $v '0.##'}
        $path=if($w -gt 4){'M'+(& $f $plotLeft)+' '+(& $f $y)+'h'+(& $f ($w-4))+'a4 4 0 0 1 4 4v'+(& $f ($barHeight-8))+'a4 4 0 0 1 -4 4h'+(& $f (4-$w))+'z'}else{'M'+(& $f $plotLeft)+' '+(& $f $y)+'h'+(& $f $w)+'v'+$barHeight+'h'+(& $f (-$w))+'z'}
        [void]$svg.Append('<g class="qc-row"><title>'+$tip+'</title>')
        [void]$svg.Append('<rect class="qc-hit" x="0" y="'+($y-5)+'" width="'+$width+'" height="'+$pitch+'"/>')
        [void]$svg.Append('<text class="qc-label" x="'+$labelWidth+'" y="'+(& $f ($mid+4))+'" text-anchor="end">'+(ConvertTo-QuietChartXml $label)+'</text>')
        [void]$svg.Append('<path class="qc-bar" d="'+$path+'"/>')
        [void]$svg.Append('<line class="qc-whisker" x1="'+(& $f $q1)+'" x2="'+(& $f $q3)+'" y1="'+(& $f $mid)+'" y2="'+(& $f $mid)+'"/>')
        [void]$svg.Append('<line class="qc-whisker" x1="'+(& $f $q1)+'" x2="'+(& $f $q1)+'" y1="'+(& $f ($mid-4))+'" y2="'+(& $f ($mid+4))+'"/><line class="qc-whisker" x1="'+(& $f $q3)+'" x2="'+(& $f $q3)+'" y1="'+(& $f ($mid-4))+'" y2="'+(& $f ($mid+4))+'"/>')
        $valueX=[Math]::Max($plotLeft+$w,$q3)+6
        [void]$svg.Append('<text class="qc-value" x="'+(& $f $valueX)+'" y="'+(& $f ($mid+4))+'">'+(Format-QuietChartNumber $s.Median)+' ms <tspan class="qc-n">N='+$s.Count+'</tspan></text></g>')
        $index++
    }
    [void]$svg.Append('</svg>')
    $svg.ToString().Replace("`r`n","`n")
}

function Get-QuietPerformanceWorkloadCoverage {
    <#
    .SYNOPSIS
    Counts, per workload, the environments with observations and the observations they hold, split by instrumented or not.
    .PARAMETER Workloads
    Rows from Get-QuietPerformanceWorkloadRows.
    .PARAMETER Catalog
    Workload catalog, used to keep the catalog order and to list workloads without data.
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Workloads,[AllowEmptyCollection()][object[]]$Catalog)
    $names=[Collections.Generic.List[string]]::new()
    foreach($name in @(@($Catalog|ForEach-Object {[string]$_.Workload})+@($Workloads|Where-Object {$null -ne $_}|ForEach-Object {[string]$_.Workload}))){if(!$names.Contains($name)){$names.Add($name)}}
    foreach($instrumented in @($false,$true)){
        foreach($name in $names){
            $rows=@($Workloads|Where-Object {$null -ne $_ -and [string]$_.Workload -ceq $name -and [bool]$_.Instrumented -eq $instrumented -and $null -ne $_.Statistics})
            [pscustomobject]@{
                Workload=$name;Instrumented=$instrumented
                Hosts=@($rows|ForEach-Object {[string]$_.Host}|Sort-Object -Unique).Count
                Observations=[int](($rows|ForEach-Object {[int]$_.Statistics.Count}|Measure-Object -Sum).Sum)
                Measures=@($rows|ForEach-Object {[string]$_.Measure+"`n"+[string]$_.Variant}|Sort-Object -Unique).Count
            }
        }
    }
}

function Get-QuietCoverageText {
    <#
    .SYNOPSIS
    Describes one coverage cell in a few words.
    .PARAMETER Coverage
    Get-QuietPerformanceWorkloadCoverage item.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Coverage)
    if($Coverage.Instrumented -and $Coverage.Workload -ceq 'ImportFirstCall'){return 'not profiled (collectors attach after import)'}
    if(!$Coverage.Observations){return 'no observation'}
    [string]$Coverage.Observations+' obs · '+$Coverage.Hosts+' env · '+$Coverage.Measures+' series'
}

function ConvertTo-QuietPerformanceMermaidOverview {
    <#
    .SYNOPSIS
    Renders the workload coverage as a Mermaid flowchart with two lanes: uninstrumented timing and line-profiled runs.
    .PARAMETER Coverage
    Get-QuietPerformanceWorkloadCoverage output.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()][object[]]$Coverage)
    $text=[Text.StringBuilder]::new()
    [void]$text.AppendLine('```mermaid')
    [void]$text.AppendLine('flowchart LR')
    $lanes=@(@{Id='U';Instrumented=$false;Title='Uninstrumented timing (Core tests)'},@{Id='P';Instrumented=$true;Title='Diagnostics and profiling'})
    foreach($lane in $lanes){
        [void]$text.AppendLine('    subgraph '+$lane.Id+'["'+$lane.Title+'"]')
        [void]$text.AppendLine('        direction TB')
        $index=0
        foreach($item in @($Coverage|Where-Object {[bool]$_.Instrumented -eq $lane.Instrumented})){
            [void]$text.AppendLine('        '+$lane.Id+$index+'["<b>'+(ConvertTo-QuietChartText $item.Workload 40)+'</b><br/>'+(ConvertTo-QuietChartText (Get-QuietCoverageText $item) 80)+'"]')
            if(!$item.Observations){[void]$text.AppendLine('        class '+$lane.Id+$index+' gap')}
            $index++
        }
        [void]$text.AppendLine('    end')
    }
    [void]$text.AppendLine('    U -. "same workloads, separate processes" .-> P')
    [void]$text.AppendLine('    classDef gap stroke-dasharray: 4 3')
    [void]$text.Append('```')
    $text.ToString().Replace("`r`n","`n")
}

function ConvertTo-QuietPerformanceSvgOverview {
    <#
    .SYNOPSIS
    Renders the workload coverage as a script-free SVG: one lane per measurement kind, one box per workload.
    .PARAMETER Coverage
    Get-QuietPerformanceWorkloadCoverage output.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()][object[]]$Coverage)
    $lanes=@(@{Instrumented=$false;Title='Uninstrumented timing (Core tests)'},@{Instrumented=$true;Title='Diagnostics and profiling'})
    $columns=[Math]::Max(1,[Math]::Max(@($Coverage|Where-Object {!$_.Instrumented}).Count,@($Coverage|Where-Object {$_.Instrumented}).Count))
    $boxWidth=148;$gap=10;$boxHeight=54;$laneHeight=$boxHeight+34
    $width=[Math]::Max(480,$columns*($boxWidth+$gap)-$gap);$height=$lanes.Count*$laneHeight
    $svg=[Text.StringBuilder]::new()
    [void]$svg.Append('<svg class="qc" role="img" viewBox="0 0 '+$width+' '+$height+'" width="100%" style="max-width:'+$width+'px" xmlns="http://www.w3.org/2000/svg"><title>Workload coverage: observations and environments per workload</title>')
    $laneIndex=0
    foreach($lane in $lanes){
        $y=$laneIndex*$laneHeight
        [void]$svg.Append('<text class="qc-title" x="0" y="'+($y+16)+'">'+(ConvertTo-QuietChartXml $lane.Title)+'</text>')
        $index=0
        foreach($item in @($Coverage|Where-Object {[bool]$_.Instrumented -eq $lane.Instrumented})){
            $x=$index*($boxWidth+$gap);$boxY=$y+24
            $class=if($item.Observations){'qc-box'}else{'qc-box qc-gap'}
            $detail=Get-QuietCoverageText $item
            [void]$svg.Append('<g><title>'+(ConvertTo-QuietChartXml ($item.Workload+': '+$detail))+'</title><rect class="'+$class+'" x="'+$x+'" y="'+$boxY+'" width="'+$boxWidth+'" height="'+$boxHeight+'" rx="6"/>')
            [void]$svg.Append('<text class="qc-box-name" x="'+($x+10)+'" y="'+($boxY+21)+'">'+(ConvertTo-QuietChartXml (ConvertTo-QuietChartText $item.Workload 20))+'</text>')
            $short=if($item.Observations){[string]$item.Observations+' obs · '+$item.Hosts+' env'}elseif($item.Instrumented -and $item.Workload -ceq 'ImportFirstCall'){'not profiled'}else{'no observation'}
            [void]$svg.Append('<text class="qc-box-detail" x="'+($x+10)+'" y="'+($boxY+40)+'">'+(ConvertTo-QuietChartXml $short)+'</text></g>')
            $index++
        }
        $laneIndex++
    }
    [void]$svg.Append('</svg>')
    $svg.ToString().Replace("`r`n","`n")
}

Export-ModuleMember -Function 'ConvertTo-QuietChartText','ConvertTo-QuietChartXml','Get-QuietPerformanceChartSeries','Get-QuietPerformanceChartTitle','ConvertTo-QuietPerformanceMermaidChart','Get-QuietPerformanceChartCaption','ConvertTo-QuietPerformanceSvgChart','Get-QuietPerformanceWorkloadCoverage','ConvertTo-QuietPerformanceMermaidOverview','ConvertTo-QuietPerformanceSvgOverview'
