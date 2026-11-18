#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name PerformanceStatistics
    $null=Import-QuietTestLibrary -Name PerformanceCharts
    $seed=Get-QuietTestSeed
    $row={param([string]$Host_,[string]$Workload='Events',[string]$Measure='Emit loop',[string]$Variant='-',[double[]]$Values=@(1,2,3),[bool]$Instrumented=$false)
        [pscustomobject]@{Host=$Host_;Workload=$Workload;Measure=$Measure;Variant=$Variant;Instrumented=$Instrumented;Statistics=(Get-QuietPerformanceStatistics -Values $Values)}
    }
    $chart={param([string[]]$Labels=@('linux-x64 / 7.7.0 / InProcess','win-x64 / 7.7.0 / Process'))
        @(Get-QuietPerformanceChartSeries -Workloads @(for($i=0;$i -lt $Labels.Count;$i++){& $row $Labels[$i] -Values @((1.5+$i),(2.25+$i),(4+$i))}))[0]
    }
}

Describe 'ConvertTo-QuietChartText' {
    It 'keeps ordinary labels' {
        ConvertTo-QuietChartText 'linux-musl-x64 / 7.6.10 / InProcess'|Should -BeExactly 'linux-musl-x64 / 7.6.10 / InProcess'
        ConvertTo-QuietChartText 'Events · Emit loop · listeners=4, collect=on'|Should -BeExactly 'Events · Emit loop · listeners=4, collect=on'
    }

    It 'replaces quotes, brackets, markup and control characters' {
        ConvertTo-QuietChartText 'a"b]c<d>e`f'|Should -BeExactly 'a_b_c_d_e_f'
        ConvertTo-QuietChartText "x`ny"|Should -BeExactly 'x_y'
        ConvertTo-QuietChartText $null|Should -BeExactly '-'
        ConvertTo-QuietChartText '   '|Should -BeExactly '-'
    }

    It 'shortens long labels with an ellipsis' {
        $text=ConvertTo-QuietChartText ('x'*100) 10
        $text|Should -BeExactly ('x'*9+'…')
        ConvertTo-QuietChartText ('y'*10) 10|Should -BeExactly ('y'*10)
        ConvertTo-QuietChartText ('z'*11) 10|Should -BeExactly ('z'*9+'…')
    }

    It 'only emits safe characters within the length limit (fuzz)' {
        Invoke-QuietProperty -Name 'chart text charset' -Seed $seed -Count 400 -Generator {param([Random]$Random)
            @{Text=-join @(1..$Random.Next(0,90)|ForEach-Object {[char]$Random.Next(0,0x3000)});Max=$Random.Next(4,80)}
        } -Property {param($case)
            $text=ConvertTo-QuietChartText $case.Text $case.Max
            $text.Length -le $case.Max -and $text -cmatch '^[A-Za-z0-9 ._=,:/+()\-·–×…]+$' -and $text -notmatch '["\[\]<>{}]'
        }|Should -Be 400
    }
}

Describe 'ConvertTo-QuietChartXml' {
    It 'escapes markup and drops control characters' {
        ConvertTo-QuietChartXml '<script>&"''x'|Should -BeExactly '&lt;script&gt;&amp;&quot;&apos;x'
        ConvertTo-QuietChartXml ("a"+[char]1+"b")|Should -BeExactly 'a b'
        ConvertTo-QuietChartXml $null|Should -BeExactly '-'
    }
}

Describe 'Get-QuietPerformanceChartSeries' {
    It 'makes one chart per workload, measure and variant in first-seen order, one bar per environment' {
        $rows=@(
            & $row 'h1' -Workload 'ImportFirstCall' -Measure 'Fresh-process import'
            & $row 'h1' -Variant 'listeners=0, collect=off'
            & $row 'h2' -Workload 'ImportFirstCall' -Measure 'Fresh-process import'
            & $row 'h2' -Variant 'listeners=4, collect=on'
        )
        $series=@(Get-QuietPerformanceChartSeries -Workloads $rows)
        $series.Count|Should -Be 3
        $series[0].Workload|Should -BeExactly 'ImportFirstCall'
        $series[0].Bars.Label|Should -Be @('h1','h2')
        $series[1].Variant|Should -BeExactly 'listeners=0, collect=off'
    }

    It 'lists environments without observations as missing and drops a chart with no observation' {
        $rows=@(
            & $row 'h1'
            [pscustomobject]@{Host='h2';Workload='Events';Measure='Emit loop';Variant='-';Instrumented=$false;Statistics=$null}
            [pscustomobject]@{Host='h1';Workload='Framing';Measure='1 MiB framing';Variant='-';Instrumented=$false;Statistics=$null}
            $null
        )
        $series=@(Get-QuietPerformanceChartSeries -Workloads $rows)
        $series.Count|Should -Be 1
        $series[0].Bars.Count|Should -Be 1
        $series[0].Missing|Should -Be @('h2')
        @(Get-QuietPerformanceChartSeries -Workloads @()).Count|Should -Be 0
    }

    It 'keeps measures apart even when their names concatenate alike' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @((& $row 'h1' -Measure 'ab' -Variant 'c'),(& $row 'h1' -Measure 'a' -Variant 'bc')))
        $series.Count|Should -Be 2
    }
}

Describe 'Get-QuietPerformanceChartTitle and caption' {
    It 'names the variant only when there is one' {
        Get-QuietPerformanceChartTitle ([pscustomobject]@{Workload='W';Measure='M';Variant='-'})|Should -BeExactly 'W · M (median ms)'
        Get-QuietPerformanceChartTitle ([pscustomobject]@{Workload='W';Measure='M';Variant='v'})|Should -BeExactly 'W · M · v (median ms)'
    }

    It 'states median, quartiles, N, p95 with (max) and missing environments' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @((& $row 'h1' -Values @(1,2,3,4,5,6,7)),[pscustomobject]@{Host='h2';Workload='Events';Measure='Emit loop';Variant='-';Instrumented=$false;Statistics=$null}))
        Get-QuietPerformanceChartCaption $series[0]|Should -BeExactly 'h1: 4.00 ms, Q1–Q3 2.00–6.00, N=7, p95 7.00 (max); no observation: h2'
    }

    It 'prints a plain p95 from 20 observations and no missing clause when every environment has data' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @(& $row 'h1' -Values ([double[]](1..20))))
        Get-QuietPerformanceChartCaption $series[0]|Should -BeExactly 'h1: 10.50 ms, Q1–Q3 5.00–15.00, N=20, p95 19.00'
    }
}

Describe 'Golden renderings' {
    # Exact outputs, reviewed by hand: scale 15 = max(median, Q3); 6 ms -> 120 px; Q1 4 -> x 380; Q3 15 -> x 600;
    # the value starts 6 px after the bar or the whisker, whichever ends later.
    BeforeAll {
        $golden=@(Get-QuietPerformanceChartSeries -Workloads @(
            (& $row 'h<1>' -Variant 'listeners=1, collect=on' -Values @(2,4,6,8,40))
            (& $row 'h2' -Variant 'listeners=1, collect=on' -Values ([double[]](1..20)))
            [pscustomobject]@{Host='h3';Workload='Events';Measure='Emit loop';Variant='listeners=1, collect=on';Instrumented=$false;Statistics=$null}
        ))[0]
        $goldenCoverage=@(Get-QuietPerformanceWorkloadCoverage -Catalog @([pscustomobject]@{Workload='ImportFirstCall'},[pscustomobject]@{Workload='Events'}) -Workloads @(
            (& $row 'h1' -Workload 'ImportFirstCall' -Measure 'Fresh-process import' -Values @(1,2,3))
            (& $row 'h1' -Workload 'Events' -Measure 'Instrumented iteration' -Instrumented $true -Values @(5,6))
        ))
    }

    It 'renders the Mermaid bar chart exactly' {
        ConvertTo-QuietPerformanceMermaidChart $golden|Should -BeExactly (@(
            '```mermaid'
            '%%{init: {"xyChart": {"showDataLabel": true}}}%%'
            'xychart-beta horizontal'
            '    title "Events · Emit loop · listeners=1, collect=on (median ms)"'
            '    x-axis ["h_1_", "h2"]'
            '    y-axis "Median ms" 0 --> 12'
            '    bar [6, 10.5]'
            '```'
        ) -join "`n")
    }

    It 'renders the SVG bar chart exactly' {
        ConvertTo-QuietPerformanceSvgChart $golden|Should -BeExactly (@(
            '<svg class="qc" role="img" viewBox="0 0 760 98" width="100%" style="max-width:760px" xmlns="http://www.w3.org/2000/svg"><title>Events · Emit loop · listeners=1, collect=on (median ms)</title>'
            '<text class="qc-title" x="0" y="16">Events · Emit loop · listeners=1, collect=on (median ms)</text>'
            '<text class="qc-key" x="760" y="16" text-anchor="end">bar = median · line = Q1–Q3</text>'
            '<line class="qc-axis" x1="300" x2="300" y1="30" y2="94"/>'
            '<g class="qc-row"><title>h&lt;1&gt;: median 6.00 ms, Q1–Q3 4.00–8.00, min–max 2.00–40.00, p95 40.00 (max), N=5</title>'
            '<rect class="qc-hit" x="0" y="29" width="760" height="28"/>'
            '<text class="qc-label" x="290" y="46" text-anchor="end">h_1_</text>'
            '<path class="qc-bar" d="M300 34h116a4 4 0 0 1 4 4v8a4 4 0 0 1 -4 4h-116z"/>'
            '<line class="qc-whisker" x1="380" x2="460" y1="42" y2="42"/>'
            '<line class="qc-whisker" x1="380" x2="380" y1="38" y2="46"/><line class="qc-whisker" x1="460" x2="460" y1="38" y2="46"/>'
            '<text class="qc-value" x="466" y="46">6.00 ms <tspan class="qc-n">N=5</tspan></text></g>'
            '<g class="qc-row"><title>h2: median 10.50 ms, Q1–Q3 5.00–15.00, min–max 1.00–20.00, p95 19.00, N=20</title>'
            '<rect class="qc-hit" x="0" y="57" width="760" height="28"/>'
            '<text class="qc-label" x="290" y="74" text-anchor="end">h2</text>'
            '<path class="qc-bar" d="M300 62h206a4 4 0 0 1 4 4v8a4 4 0 0 1 -4 4h-206z"/>'
            '<line class="qc-whisker" x1="400" x2="600" y1="70" y2="70"/>'
            '<line class="qc-whisker" x1="400" x2="400" y1="66" y2="74"/><line class="qc-whisker" x1="600" x2="600" y1="66" y2="74"/>'
            '<text class="qc-value" x="606" y="74">10.50 ms <tspan class="qc-n">N=20</tspan></text></g>'
            '</svg>'
        ) -join '')
    }

    It 'renders the Mermaid overview exactly' {
        ConvertTo-QuietPerformanceMermaidOverview $goldenCoverage|Should -BeExactly (@(
            '```mermaid'
            'flowchart LR'
            '    subgraph U["Uninstrumented timing (Core tests)"]'
            '        direction TB'
            '        U0["<b>ImportFirstCall</b><br/>3 obs · 1 env · 1 series"]'
            '        U1["<b>Events</b><br/>no observation"]'
            '        class U1 gap'
            '    end'
            '    subgraph P["Instrumented (Profiler 4.3.0 + dotnet-trace)"]'
            '        direction TB'
            '        P0["<b>ImportFirstCall</b><br/>not profiled (collectors attach after import)"]'
            '        class P0 gap'
            '        P1["<b>Events</b><br/>2 obs · 1 env · 1 series"]'
            '    end'
            '    U -. "same workloads, separate processes" .-> P'
            '    classDef gap stroke-dasharray: 4 3'
            '```'
        ) -join "`n")
    }

    It 'renders the SVG overview exactly' {
        ConvertTo-QuietPerformanceSvgOverview $goldenCoverage|Should -BeExactly (@(
            '<svg class="qc" role="img" viewBox="0 0 480 176" width="100%" style="max-width:480px" xmlns="http://www.w3.org/2000/svg"><title>Workload coverage: observations and environments per workload</title>'
            '<text class="qc-title" x="0" y="16">Uninstrumented timing (Core tests)</text>'
            '<g><title>ImportFirstCall: 3 obs · 1 env · 1 series</title><rect class="qc-box" x="0" y="24" width="148" height="54" rx="6"/>'
            '<text class="qc-box-name" x="10" y="45">ImportFirstCall</text><text class="qc-box-detail" x="10" y="64">3 obs · 1 env</text></g>'
            '<g><title>Events: no observation</title><rect class="qc-box qc-gap" x="158" y="24" width="148" height="54" rx="6"/>'
            '<text class="qc-box-name" x="168" y="45">Events</text><text class="qc-box-detail" x="168" y="64">no observation</text></g>'
            '<text class="qc-title" x="0" y="104">Instrumented (Profiler 4.3.0 + dotnet-trace)</text>'
            '<g><title>ImportFirstCall: not profiled (collectors attach after import)</title><rect class="qc-box qc-gap" x="0" y="112" width="148" height="54" rx="6"/>'
            '<text class="qc-box-name" x="10" y="133">ImportFirstCall</text><text class="qc-box-detail" x="10" y="152">not profiled</text></g>'
            '<g><title>Events: 2 obs · 1 env · 1 series</title><rect class="qc-box" x="158" y="112" width="148" height="54" rx="6"/>'
            '<text class="qc-box-name" x="168" y="133">Events</text><text class="qc-box-detail" x="168" y="152">2 obs · 1 env</text></g>'
            '</svg>'
        ) -join '')
    }

    It 'widens the overview beyond 480 px for many workloads' {
        $wide=@(foreach($i in 1..5){[pscustomobject]@{Workload="W$i";Instrumented=$false;Hosts=1;Observations=1;Measures=1}})
        ConvertTo-QuietPerformanceSvgOverview $wide|Should -Match 'viewBox="0 0 780 176" width="100%" style="max-width:780px"'
        ConvertTo-QuietPerformanceSvgOverview @()|Should -Match 'viewBox="0 0 480 176"'
    }
}

Describe 'ConvertTo-QuietPerformanceMermaidChart' {
    It 'renders a horizontal xychart with one label and one value per bar' {
        $text=ConvertTo-QuietPerformanceMermaidChart (& $chart)
        $text.StartsWith('```mermaid'+"`n")|Should -BeTrue
        $text.EndsWith("`n"+'```')|Should -BeTrue
        # The report is LF-only on every OS; StringBuilder.AppendLine would add CR on Windows.
        $text.Contains("`r")|Should -BeFalse
        $text|Should -Match 'xychart-beta horizontal'
        $text|Should -Match 'x-axis \["linux-x64 / 7.7.0 / InProcess", "win-x64 / 7.7.0 / Process"\]'
        $text|Should -Match 'bar \[2\.25, 3\.25\]'
        $text|Should -Match 'y-axis "Median ms" 0 --> 4'
    }

    It 'writes invariant numbers under a comma-decimal culture' {
        $previous=[Globalization.CultureInfo]::CurrentCulture
        try{
            [Globalization.CultureInfo]::CurrentCulture='fr-FR'
            $text=ConvertTo-QuietPerformanceMermaidChart (& $chart)
            $svg=ConvertTo-QuietPerformanceSvgChart (& $chart)
        }finally{[Globalization.CultureInfo]::CurrentCulture=$previous}
        $text|Should -Match 'bar \[2\.25, 3\.25\]'
        $svg|Should -Match '2\.25 ms'
        $svg|Should -Not -Match '\d,\d'
    }

    It 'cannot be broken out of by a hostile environment label (fuzz)' {
        Invoke-QuietProperty -Name 'mermaid label injection' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            @{Labels=@(1..$Random.Next(1,4)|ForEach-Object {-join @(1..$Random.Next(1,40)|ForEach-Object {@('"',']','[','`',"`n",'<','>','}','{','a','/',';','%')[$Random.Next(13)]})})}
        } -Property {param($case)
            $text=ConvertTo-QuietPerformanceMermaidChart (& $chart $case.Labels)
            $lines=$text -split "`n"
            $axis=@($lines|Where-Object {$_ -like '    x-axis*'})
            $axis.Count -eq 1 -and $lines.Count -eq 8 -and ([regex]::Matches($axis[0],'"').Count -eq 2*$case.Labels.Count)
        }|Should -Be 200
    }
}

Describe 'ConvertTo-QuietPerformanceSvgChart' {
    It 'is well-formed XML with one row, bar and value per environment, and no active content' {
        $svg=ConvertTo-QuietPerformanceSvgChart (& $chart @('a','b','c'))
        $svg.Contains("`r")|Should -BeFalse
        $xml=[xml]$svg
        $xml.DocumentElement.LocalName|Should -BeExactly 'svg'
        ([regex]::Matches($svg,'class="qc-row"')).Count|Should -Be 3
        ([regex]::Matches($svg,'class="qc-bar"')).Count|Should -Be 3
        $svg|Should -Match '2\.25 ms <tspan class="qc-n">N=3</tspan>'
        $svg|Should -Not -Match '<script|<foreignObject|on\w+='
    }

    It 'gives the longest bar the full plot width and keeps tiny bars visible' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @((& $row 'big' -Values @(100)),(& $row 'tiny' -Values @(0))))
        $svg=ConvertTo-QuietPerformanceSvgChart $series[0]
        $svg|Should -Match 'M300 34h296a4 4 0 0 1 4 4'
        $svg|Should -Match 'M300 62h1v16h-1z'
    }

    It 'scales on the widest whisker, and never divides by a zero scale' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @(& $row 'w' -Values @(1,2,10)))
        # Median 2, Q3 10: the whisker, not the bar, sets the full width.
        ConvertTo-QuietPerformanceSvgChart $series[0]|Should -Match 'M300 34h56a4 4 0 0 1 4 4.*x2="600"'
        $zero=@(Get-QuietPerformanceChartSeries -Workloads @(& $row 'z' -Values @(0,0)))
        $svg=ConvertTo-QuietPerformanceSvgChart $zero[0]
        $svg|Should -Not -Match 'NaN|Infinity'
        $svg|Should -Match 'M300 34h1v16h-1z'
    }

    It 'rounds Mermaid values to two decimals' {
        $series=@(Get-QuietPerformanceChartSeries -Workloads @(& $row 'r' -Values @((1/3))))
        ConvertTo-QuietPerformanceMermaidChart $series[0]|Should -Match '(?m)^    bar \[0\.33\]$'
        ConvertTo-QuietPerformanceMermaidChart $series[0]|Should -Match '(?m)^    y-axis "Median ms" 0 --> 1$'
    }

    It 'escapes hostile labels and stays well-formed (fuzz)' {
        Invoke-QuietProperty -Name 'svg escaping' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            @{Labels=@(1..$Random.Next(1,4)|ForEach-Object {-join @(1..$Random.Next(1,30)|ForEach-Object {[char]$Random.Next(1,0x2100)})})}
        } -Property {param($case)
            $svg=ConvertTo-QuietPerformanceSvgChart (& $chart $case.Labels)
            $null=[xml]$svg
            $svg -notmatch '<script'
        }|Should -Be 200
    }
}

Describe 'Workload coverage and overview' {
    BeforeAll {
        $rows=@(
            & $row 'h1' -Workload 'ImportFirstCall' -Measure 'Fresh-process import' -Values @(1,2,3,4,5,6,7)
            & $row 'h2' -Workload 'ImportFirstCall' -Measure 'Fresh-process import' -Values @(1,2,3,4,5,6,7)
            & $row 'h1' -Workload 'Events' -Variant 'a' -Values @(1,2)
            & $row 'h1' -Workload 'Events' -Variant 'b' -Values @(1)
            & $row 'h1' -Workload 'Events' -Measure 'Instrumented iteration' -Instrumented $true -Values @(5,6,7,8)
        )
        $catalog=@([pscustomobject]@{Workload='ImportFirstCall'},[pscustomobject]@{Workload='Framing'},[pscustomobject]@{Workload='Events'})
        $coverage=@(Get-QuietPerformanceWorkloadCoverage -Workloads $rows -Catalog $catalog)
    }

    It 'counts observations, environments and series per workload and lane, in catalog order' {
        $coverage.Count|Should -Be 6
        $plain=@($coverage|Where-Object {!$_.Instrumented})
        $plain.Workload|Should -Be @('ImportFirstCall','Framing','Events')
        @($plain[0].Observations,$plain[0].Hosts,$plain[0].Measures)|Should -Be @(14,2,1)
        @($plain[1].Observations,$plain[1].Hosts)|Should -Be @(0,0)
        @($plain[2].Observations,$plain[2].Hosts,$plain[2].Measures)|Should -Be @(3,1,2)
        $instrumented=@($coverage|Where-Object Instrumented)
        $instrumented[2].Observations|Should -Be 4
        $instrumented[0].Observations|Should -Be 0
    }

    It 'appends workloads absent from the catalog and counts measure/variant pairs exactly' {
        $extra=@(
            & $row 'h1' -Workload 'Ui' -Measure 'ab' -Variant 'c'
            & $row 'h1' -Workload 'Ui' -Measure 'a' -Variant 'bc'
        )
        $result=@(Get-QuietPerformanceWorkloadCoverage -Workloads $extra -Catalog @([pscustomobject]@{Workload='Events'}))
        @($result|Where-Object {!$_.Instrumented}).Workload|Should -Be @('Events','Ui')
        @($result|Where-Object {!$_.Instrumented -and $_.Workload -ceq 'Ui'})[0].Measures|Should -Be 2
    }

    It 'renders a Mermaid flowchart with numbers and a dashed gap for missing data' {
        $text=ConvertTo-QuietPerformanceMermaidOverview $coverage
        $text.Contains("`r")|Should -BeFalse
        $text|Should -Match 'flowchart LR'
        $text|Should -Match 'U0\["<b>ImportFirstCall</b><br/>14 obs · 2 env · 1 series"\]'
        $text|Should -Match 'P0\["<b>ImportFirstCall</b><br/>not profiled \(collectors attach after import\)"\]'
        $text|Should -Match 'class U1 gap'
        $text|Should -Match 'P2\["<b>Events</b><br/>4 obs · 1 env · 1 series"\]'
    }

    It 'renders a well-formed SVG with one box per workload and lane' {
        $svg=ConvertTo-QuietPerformanceSvgOverview $coverage
        $svg.Contains("`r")|Should -BeFalse
        $null=[xml]$svg
        ([regex]::Matches($svg,'<rect class="qc-box')).Count|Should -Be 6
        ([regex]::Matches($svg,'qc-gap')).Count|Should -Be 3
        $svg|Should -Match '14 obs · 2 env'
        $svg|Should -Match 'not profiled'
    }
}
