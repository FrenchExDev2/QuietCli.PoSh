#Objective: Pure planning, Pester configuration, report and status functions for the scripts test runner.
#requires -Version 7.6

function Get-QuietScriptsTestPlan {
    <#
    .SYNOPSIS
    Discovers the *.Tests.ps1 files selected by kind, paths and filters, in ordinal order.
    .PARAMETER TestsRoot
    Existing tests root containing unit/ and integration/.
    .PARAMETER Kind
    Unit, Integration or All.
    .PARAMETER Path
    Optional file or directory selectors inside TestsRoot; any selector makes the run partial.
    .PARAMETER FullNameFilter
    Optional Pester full-name filters; makes the run partial.
    .PARAMETER Tag
    Optional Pester tags to include; makes the run partial.
    .PARAMETER ExcludeTag
    Optional Pester tags to exclude; makes the run partial.
    #>
    param([Parameter(Mandatory)][string]$TestsRoot,[ValidateSet('Unit','Integration','All')][string]$Kind='All',[string[]]$Path=@(),[string[]]$FullNameFilter=@(),[string[]]$Tag=@(),[string[]]$ExcludeTag=@())
    try{$root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($TestsRoot))}catch{throw 'ScriptsTestPathInvalid: tests-root-unresolvable'}
    if(![IO.Directory]::Exists($root) -or [IO.DirectoryInfo]::new($root).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'ScriptsTestPathInvalid: tests-root'}
    $kinds=switch($Kind){'Unit'{@('unit')}'Integration'{@('integration')}default{@('unit','integration')}}
    $options=[IO.EnumerationOptions]::new();$options.RecurseSubdirectories=$true;$options.AttributesToSkip=[IO.FileAttributes]::ReparsePoint;$options.MatchCasing=[IO.MatchCasing]::CaseInsensitive
    $discovered=[Collections.Generic.List[string]]::new()
    foreach($name in $kinds){
        $directory=[IO.Path]::Combine($root,$name)
        if(![IO.Directory]::Exists($directory) -or [IO.DirectoryInfo]::new($directory).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){continue}
        foreach($file in [IO.Directory]::EnumerateFiles($directory,'*.Tests.ps1',$options)){$discovered.Add([IO.Path]::GetFullPath($file))}
    }
    $selectors=@(foreach($entry in @($Path|Where-Object {$null -ne $_})){Resolve-QuietScriptsTestPath -Path $entry -TestsRoot $root})
    $files=[Collections.Generic.List[string]]::new()
    foreach($file in $discovered){
        $selected=$selectors.Count -eq 0
        foreach($selector in $selectors){if(Test-QuietScriptsPathWithin -Path $file -Root $selector){$selected=$true}}
        if($selected){$files.Add($file)}
    }
    if($files.Count -eq 0){throw 'ScriptsTestSelectionEmpty'}
    $sorted=[string[]]$files.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    $clean={param($values)@(@($values)|Where-Object {![string]::IsNullOrWhiteSpace($_)})}
    $nameFilters=[string[]](& $clean $FullNameFilter);$tags=[string[]](& $clean $Tag);$excluded=[string[]](& $clean $ExcludeTag)
    [pscustomobject][ordered]@{
        Kind=$Kind;TestsRoot=$root;Files=$sorted
        FullNameFilter=$nameFilters;Tag=$tags;ExcludeTag=$excluded
        Partial=[bool]($selectors.Count -gt 0 -or $nameFilters.Count -gt 0 -or $tags.Count -gt 0 -or $excluded.Count -gt 0)
    }
}

function Get-QuietScriptsTestValue {
    <#
    .SYNOPSIS
    Reads one property or dictionary entry without throwing on null, scalar or malformed input.
    .PARAMETER InputObject
    Any object, dictionary or null.
    .PARAMETER Name
    Property or key name.
    #>
    param($InputObject,[Parameter(Mandatory)][string]$Name)
    $value=$null
    # The interface cast reaches Contains on dictionaries that implement it explicitly (Dictionary<TKey,TValue>).
    if($InputObject -is [Collections.IDictionary]){if(([Collections.IDictionary]$InputObject).Contains($Name)){$value=$InputObject[$Name]}}
    elseif($null -ne $InputObject){
        $property=$InputObject.PSObject.Properties[$Name]
        # PowerShell reads a throwing getter's Value as null instead of raising, so no try/catch is needed.
        if($null -ne $property){$value=$property.Value}
    }
    return $value
}

function Test-QuietScriptsPathWithin {
    <#
    .SYNOPSIS
    Returns whether a full path equals or is contained in a full root path (case-insensitive on Windows).
    .PARAMETER Path
    Full candidate path.
    .PARAMETER Root
    Full root directory.
    #>
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
    # One expression rather than if/else, so coverage sees one command on every platform.
    $comparison=$IsWindows ? [StringComparison]::OrdinalIgnoreCase : [StringComparison]::Ordinal
    $root=[IO.Path]::TrimEndingDirectorySeparator($Root)
    $candidate=[IO.Path]::TrimEndingDirectorySeparator($Path)
    if([string]::Equals($candidate,$root,$comparison)){return $true}
    return $candidate.StartsWith($root+[IO.Path]::DirectorySeparatorChar,$comparison)
}

function Resolve-QuietScriptsTestPath {
    <#
    .SYNOPSIS
    Validates one -Path selector and returns its full path inside the tests root.
    .DESCRIPTION
    Rejects empty values, control or invalid characters, '..' segments, paths outside the root, missing
    targets, links on the way from the root, and files that are not *.Tests.ps1. Every rejection throws
    ScriptsTestPathInvalid with a reason code; the offending value is never echoed.
    .PARAMETER Path
    Selector, relative to TestsRoot or absolute inside it.
    .PARAMETER TestsRoot
    Full, existing tests root.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Path,[Parameter(Mandatory)][string]$TestsRoot)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'ScriptsTestPathInvalid: empty'}
    foreach($character in $Path.ToCharArray()){if([char]::IsControl($character)){throw 'ScriptsTestPathInvalid: control-character'}}
    if($Path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0){throw 'ScriptsTestPathInvalid: invalid-character'}
    if(@($Path -split '[\\/]') -contains '..'){throw 'ScriptsTestPathInvalid: parent-segment'}
    # Combine returns a rooted selector unchanged; empty and NUL-bearing values, the only ones GetFullPath rejects, are refused above.
    $full=[IO.Path]::GetFullPath([IO.Path]::Combine($TestsRoot,$Path))
    if(!(Test-QuietScriptsPathWithin -Path $full -Root $TestsRoot)){throw 'ScriptsTestPathInvalid: outside-root'}
    $isFile=[IO.File]::Exists($full);$isDirectory=[IO.Directory]::Exists($full)
    if(!$isFile -and !$isDirectory){throw 'ScriptsTestPathInvalid: missing'}
    $cursor=$TestsRoot
    $relative=[IO.Path]::GetRelativePath($TestsRoot,$full)
    foreach($segment in ($relative.Split([IO.Path]::DirectorySeparatorChar) | Where-Object {$_ -cne '.'})){
        $cursor=[IO.Path]::Combine($cursor,$segment)
        if([IO.File]::GetAttributes($cursor).HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'ScriptsTestPathInvalid: link'}
    }
    if($isFile -and !$full.EndsWith('.Tests.ps1',[StringComparison]::OrdinalIgnoreCase)){throw 'ScriptsTestPathInvalid: not-a-test-file'}
    return $full
}

function Get-QuietScriptsCoverageTargets {
    <#
    .SYNOPSIS
    Reads coverage.targets.psd1 ({Threshold; Paths relative to the scripts root}) and resolves the targets.
    .PARAMETER TestsRoot
    Tests root containing coverage.targets.psd1.
    .PARAMETER ScriptsRoot
    Scripts root against which target paths are resolved (a mutated copy is allowed).
    #>
    param([Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$ScriptsRoot)
    $file=[IO.Path]::Combine($TestsRoot,'coverage.targets.psd1')
    if(![IO.File]::Exists($file)){throw 'ScriptsTestCoverageTargetsMissing'}
    try{$data=Import-PowerShellDataFile -LiteralPath $file -ErrorAction Stop}catch{throw 'ScriptsTestCoverageTargetsInvalid: syntax'}
    $threshold=$data['Threshold']
    if($threshold -isnot [int] -and $threshold -isnot [double] -and $threshold -isnot [decimal]){throw 'ScriptsTestCoverageTargetsInvalid: threshold'}
    if([double]$threshold -lt 0 -or [double]$threshold -gt 100){throw 'ScriptsTestCoverageTargetsInvalid: threshold'}
    $relative=@($data['Paths'])
    if($relative.Count -eq 0){throw 'ScriptsTestCoverageTargetsInvalid: paths'}
    $scripts=[IO.Path]::GetFullPath($ScriptsRoot)
    $paths=foreach($item in $relative){
        if($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item) -or [IO.Path]::IsPathRooted($item) -or @($item -split '[\\/]') -contains '..'){throw 'ScriptsTestCoverageTargetsInvalid: path'}
        $full=[IO.Path]::GetFullPath([IO.Path]::Combine($scripts,$item))
        if(![IO.File]::Exists($full)){throw 'ScriptsTestCoverageTargetsInvalid: missing-target'}
        $full
    }
    [pscustomobject][ordered]@{Threshold=[double]$threshold;Paths=[string[]]@($paths)}
}

function New-QuietScriptsPesterConfiguration {
    <#
    .SYNOPSIS
    Returns a JSON-serializable hashtable accepted by New-PesterConfiguration -Hashtable for one plan.
    .PARAMETER Plan
    Result of Get-QuietScriptsTestPlan.
    .PARAMETER RunDirectory
    Run directory receiving results.junit.xml and coverage.xml.
    .PARAMETER CoverageTargets
    Optional result of Get-QuietScriptsCoverageTargets; enables JaCoCo coverage with its threshold.
    #>
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$RunDirectory,$CoverageTargets)
    $files=[string[]]@(Get-QuietScriptsTestValue $Plan 'Files')
    if($files.Count -eq 0){throw 'ScriptsTestSelectionEmpty'}
    $filter=[ordered]@{}
    foreach($name in @('FullNameFilter','Tag','ExcludeTag')){
        $values=[string[]]@(@(Get-QuietScriptsTestValue $Plan $name)|Where-Object {![string]::IsNullOrWhiteSpace($_)})
        if($values.Count -gt 0){$filter[$(if($name -ceq 'FullNameFilter'){'FullName'}else{$name})]=$values}
    }
    $configuration=[ordered]@{
        Run=[ordered]@{Path=$files;PassThru=$true;Exit=$false;Throw=$false}
        Filter=$filter
        Output=[ordered]@{Verbosity='Detailed';StackTraceVerbosity='Filtered';RenderMode='Plaintext'}
        TestResult=[ordered]@{Enabled=$true;OutputFormat='JUnitXml';OutputPath=[IO.Path]::Combine($RunDirectory,'results.junit.xml')}
        Should=[ordered]@{ErrorAction='Stop'}
    }
    if($null -ne $CoverageTargets){
        $configuration.CodeCoverage=[ordered]@{Enabled=$true;Path=[string[]]@($CoverageTargets.Paths);OutputFormat='JaCoCo';OutputPath=[IO.Path]::Combine($RunDirectory,'coverage.xml');CoveragePercentTarget=[double]$CoverageTargets.Threshold}
    }
    return $configuration
}

function ConvertTo-QuietScriptsTestCount {
    <#
    .SYNOPSIS
    Converts one reported count to a non-negative integer, or -1 when it is absent or malformed.
    .DESCRIPTION
    Null, booleans ('True'), fractions and non-numeric text all fail the invariant integer parse.
    .PARAMETER Value
    Raw count.
    #>
    param($Value)
    $number=0L
    if(![long]::TryParse([string]$Value,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or $number -lt 0 -or $number -gt [int]::MaxValue){return -1}
    return [int]$number
}

function ConvertTo-QuietScriptsTestReport {
    <#
    .SYNOPSIS
    Maps a Pester run result (or any malformed object) to the repository test report without throwing.
    .DESCRIPTION
    Failed includes failed tests, blocks and containers. Passed + Failed + Skipped = Total always holds.
    A missing or malformed result, zero executed tests or missing requested coverage marks the report
    Incomplete; Success requires a complete report, no failure and, when requested, the coverage threshold.
    .PARAMETER Result
    Pester result object (PassThru), or anything else.
    .PARAMETER Plan
    Result of Get-QuietScriptsTestPlan.
    .PARAMETER Seed
    Seed exported to the run as QUIETCLI_TEST_SEED.
    .PARAMETER CoverageTarget
    Required coverage percentage when coverage was requested; omit otherwise.
    #>
    param($Result,[Parameter(Mandatory)]$Plan,[int]$Seed,[Nullable[double]]$CoverageTarget)
    $incomplete=$null -eq $Result
    $counts=@{}
    foreach($name in @('PassedCount','FailedCount','SkippedCount','NotRunCount','FailedBlocksCount','FailedContainersCount')){
        $raw=Get-QuietScriptsTestValue $Result $name
        $value=ConvertTo-QuietScriptsTestCount $raw
        if($value -lt 0){$value=0;if($name -in @('PassedCount','FailedCount','SkippedCount')){$incomplete=$true}}
        $counts[$name]=$value
    }
    $passed=$counts.PassedCount;$skipped=$counts.SkippedCount
    $failed=[int][Math]::Min([long][int]::MaxValue,[long]$counts.FailedCount+$counts.FailedBlocksCount+$counts.FailedContainersCount)
    $outcome=[string](Get-QuietScriptsTestValue $Result 'Result')
    if($outcome -notin @('Passed','Failed')){$incomplete=$true}
    if($passed+$failed+$skipped -eq 0){$incomplete=$true}
    $cases=[Collections.Generic.List[object]]::new()
    foreach($test in @(Get-QuietScriptsTestValue $Result 'Tests')){
        if($null -eq $test){continue}
        $name=Get-QuietScriptsTestValue $test 'ExpandedPath';if([string]::IsNullOrEmpty($name)){$name=Get-QuietScriptsTestValue $test 'Name'}
        $block=Get-QuietScriptsTestValue $test 'ScriptBlock'
        $duration=Get-QuietScriptsTestValue $test 'Duration'
        $cases.Add([ordered]@{Name=[string]$name;Result=[string](Get-QuietScriptsTestValue $test 'Result');File=[string](Get-QuietScriptsTestValue $block 'File');DurationMs=$(if($duration -is [TimeSpan]){[Math]::Round($duration.TotalMilliseconds,1)})})
    }
    $coverage=$null
    if($null -ne $CoverageTarget){
        $percent=Get-QuietScriptsTestValue (Get-QuietScriptsTestValue $Result 'CodeCoverage') 'CoveragePercent'
        $number=0.0
        # Null ('') and booleans ('True') fail the invariant parse, as in ConvertTo-QuietScriptsTestCount.
        if(![double]::TryParse([string]$percent,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number)){$incomplete=$true;$coverage=[ordered]@{Percent=$null;Target=[double]$CoverageTarget;Met=$false}}
        else{$coverage=[ordered]@{Percent=[Math]::Round($number,2);Target=[double]$CoverageTarget;Met=[bool]($number -ge [double]$CoverageTarget)}}
    }
    $success=!$incomplete -and $failed -eq 0 -and ($null -eq $coverage -or $coverage.Met)
    [ordered]@{
        Project='Scripts.Tests';Kind=[string](Get-QuietScriptsTestValue $Plan 'Kind');State=$(if($success){'Success'}else{'Failed'})
        Passed=$passed;Failed=$failed;Skipped=$skipped;NotRun=$counts.NotRunCount;Total=$passed+$failed+$skipped
        Partial=[bool](Get-QuietScriptsTestValue $Plan 'Partial');Incomplete=[bool]$incomplete;Seed=$Seed
        Files=[string[]]@(Get-QuietScriptsTestValue $Plan 'Files');Coverage=$coverage;Cases=$cases.ToArray()
    }
}

function ConvertTo-QuietScriptsXmlText {
    <#
    .SYNOPSIS
    Returns a text an XML 1.0 document can hold: ANSI escape sequences removed, every other forbidden character written as U+XXXX.
    .DESCRIPTION
    A null text yields the empty string. A lone surrogate becomes U+FFFD. Characters outside the Basic Multilingual Plane
    are kept.
    .PARAMETER Text
    Any text, such as a failure message captured from a child process.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $builder=[Text.StringBuilder]::new()
    foreach($rune in ([regex]::Replace($Text,'\x1B\[[0-?]*[ -/]*[@-~]','')).EnumerateRunes()){
        if($rune.IsBmp -and ![Xml.XmlConvert]::IsXmlChar([char]$rune.Value)){[void]$builder.AppendFormat('U+{0:X4}',$rune.Value)}else{[void]$builder.Append($rune.ToString())}
    }
    $builder.ToString()
}

function Protect-QuietScriptsTestResult {
    <#
    .SYNOPSIS
    Makes every text of a Pester result that the JUnit report holds XML-safe, in place, and returns how many it changed.
    .DESCRIPTION
    Pester writes test paths, failure messages and stack traces into the report as they are. A colored error captured
    from a child process, or a control character in a data-driven test name, would otherwise make the whole export fail
    and the run incomplete. Covers the ExpandedPath of each test and the DisplayErrorMessage and DisplayStackTrace of
    every error record of the tests and containers. Values that are not strings are left alone.
    .PARAMETER Result
    Pester run result (Run.PassThru).
    #>
    param([Parameter(Mandatory)]$Result)
    $fields=[Collections.Generic.List[object[]]]::new()
    foreach($test in $Result.Tests){$fields.Add(@($test,'ExpandedPath'))}
    foreach($owner in @($Result.Tests)+@($Result.Containers)){
        foreach($record in $owner.ErrorRecord){$fields.Add(@($record,'DisplayErrorMessage'));$fields.Add(@($record,'DisplayStackTrace'))}
    }
    $changed=0
    foreach($field in $fields){
        $text=$field[0].($field[1])
        if($text -isnot [string]){continue}
        $safe=ConvertTo-QuietScriptsXmlText -Text $text
        if($safe -cne $text){$field[0].($field[1])=$safe;$changed++}
    }
    $changed
}

function New-QuietScriptsTestStatus {
    <#
    .SYNOPSIS
    Builds the initial Running status read by Watch-Tests.ps1 and Wait-WorkspaceWorker.
    .PARAMETER WorkspaceRoot
    Source workspace.
    .PARAMETER Plan
    Result of Get-QuietScriptsTestPlan.
    .PARAMETER ProcessId
    Worker process id.
    .PARAMETER StartedUtc
    Worker start time.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)]$Plan,[int]$ProcessId,[DateTimeOffset]$StartedUtc=[DateTimeOffset]::UtcNow)
    $files=@(Get-QuietScriptsTestValue $Plan 'Files')
    [ordered]@{
        Project='FrenchExDev2.QuietCli.Scripts.Tests';Task=('Tests scripts ('+[string](Get-QuietScriptsTestValue $Plan 'Kind')+')')
        Workspace=$WorkspaceRoot;ProjectDirectory=[string](Get-QuietScriptsTestValue $Plan 'TestsRoot')
        Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;StartedUtc=$StartedUtc.ToString('o');ProcessId=$ProcessId
        Passed=0;Failed=0;State='Running';Case=('Running '+$files.Count+' test file(s)');Error=$null;FinishedUtc=$null
    }
}

function Update-QuietScriptsTestStatus {
    <#
    .SYNOPSIS
    Moves a Running status to its single terminal state from a report or a crash message.
    .PARAMETER Status
    Current status; only Running may transition.
    .PARAMETER Report
    Result of ConvertTo-QuietScriptsTestReport.
    .PARAMETER ErrorMessage
    Crash message when the run could not produce a report.
    .PARAMETER FinishedUtc
    Terminal time.
    #>
    [CmdletBinding(DefaultParameterSetName='Report')]
    param([Parameter(Mandatory)][Collections.IDictionary]$Status,[Parameter(Mandatory,ParameterSetName='Report')][Collections.IDictionary]$Report,[Parameter(Mandatory,ParameterSetName='Crash')][string]$ErrorMessage,[DateTimeOffset]$FinishedUtc=[DateTimeOffset]::UtcNow)
    if([string]$Status['State'] -cne 'Running'){throw 'ScriptsTestStatusTransitionInvalid'}
    $next=[ordered]@{};foreach($entry in $Status.GetEnumerator()){$next[$entry.Key]=$entry.Value}
    $next.FinishedUtc=$FinishedUtc.ToString('o')
    if($PSCmdlet.ParameterSetName -ceq 'Crash'){
        $next.State='Crash';$next.Failed=[int]$next.Failed+1;$next.Case='Worker failed before a complete report';$next.Error=$ErrorMessage
        return $next
    }
    $state=[string]$Report['State'];if($state -cnotin @('Success','Failed','Crash','Timeout','Cancelled')){throw 'ScriptsTestStatusTransitionInvalid'}
    $next.State=$state;$next.Passed=[int]$Report['Passed'];$next.Failed=[int]$Report['Failed']
    $next.Case=('{0} passed, {1} failed, {2} skipped{3}{4}' -f $Report['Passed'],$Report['Failed'],$Report['Skipped'],$(if($Report['Partial']){' (partial)'}),$(if($Report['Incomplete']){' (incomplete)'}))
    $next.Error=$null
    return $next
}

function Get-QuietScriptsTestExitCode {
    <#
    .SYNOPSIS
    Returns 0 for a Success state and 1 for every other state.
    .PARAMETER State
    Terminal state.
    #>
    param([AllowNull()][AllowEmptyString()][string]$State)
    if($State -ceq 'Success'){return 0}
    return 1
}

function Test-QuietScriptsTestsApplicable {
    <#
    .SYNOPSIS
    Tells whether a workspace's script-test checks apply: true when test/scripts exists, false for a flat fixture without it.
    .DESCRIPTION
    A grouped workspace (one with src/) must ship test/scripts; it fails with ScriptsTestsRootMissing, so deleting
    the test tree never turns the checks off. Isolated commit fixtures declare neither and are not applicable.
    .PARAMETER WorkspaceRoot
    Workspace (working tree or exported snapshot) to inspect.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    if([IO.Directory]::Exists([IO.Path]::Combine($WorkspaceRoot,'test','scripts'))){return $true}
    if([IO.Directory]::Exists([IO.Path]::Combine($WorkspaceRoot,'src'))){throw 'ScriptsTestsRootMissing: test/scripts'}
    return $false
}

Export-ModuleMember -Function ConvertTo-QuietScriptsXmlText,Protect-QuietScriptsTestResult,Get-QuietScriptsTestPlan,Resolve-QuietScriptsTestPath,Get-QuietScriptsCoverageTargets,New-QuietScriptsPesterConfiguration,ConvertTo-QuietScriptsTestReport,New-QuietScriptsTestStatus,Update-QuietScriptsTestStatus,Get-QuietScriptsTestExitCode,Test-QuietScriptsTestsApplicable
