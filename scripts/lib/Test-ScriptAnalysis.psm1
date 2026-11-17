#Objective: Runs the pinned PSScriptAnalyzer on scripts/ and test/scripts/ through a per-file cache and enforces the baseline.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptAnalysis.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptTestScriptAnalysis {
    <#
    .SYNOPSIS
    Analyzes scripts/ and test/scripts/ with the pinned PSScriptAnalyzer and fails on any finding outside the baseline or any stale baseline entry.
    .PARAMETER WorkspaceRoot
    Workspace to analyze (working tree or exported snapshot). Settings, custom rules and baseline are read from it.
    .PARAMETER ToolRoot
    Trusted repository that owns the pinned tool cache (.cache/test-tools).
    .PARAMETER CacheDirectory
    Per-file analysis cache; defaults to <ToolRoot>/.cache/script-analysis.
    .PARAMETER UpdateBaseline
    Writes the baseline pruned of stale entries. It never adds an entry, so new findings still fail.
    .PARAMETER Offline
    Requires the pinned PSScriptAnalyzer to be cached already.
    .PARAMETER TimeoutSeconds
    Wall-clock limit for the analyzer worker.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$ToolRoot,[string]$CacheDirectory,[switch]$UpdateBaseline,[switch]$Offline,[int]$TimeoutSeconds=900)
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot);$ToolRoot=[IO.Path]::GetFullPath($ToolRoot)
    if(!(Test-QuietScriptsTestsApplicable -WorkspaceRoot $WorkspaceRoot)){return [pscustomobject][ordered]@{Check='ScriptAnalyzer';Applicable=$false}}
    $testsRoot=[IO.Path]::Combine($WorkspaceRoot,'test','scripts')
    $settings=Read-QuietScriptAnalysisSettings ([IO.Path]::Combine($testsRoot,'ScriptAnalyzerSettings.psd1'))
    $baselinePath=[IO.Path]::Combine($testsRoot,'ScriptAnalyzer.baseline.json')
    $baseline=Read-QuietScriptAnalysisBaseline $baselinePath
    $rulesPath=[IO.Path]::Combine($testsRoot,'analyzer','QuietCliRules.psm1')
    if(![IO.File]::Exists($rulesPath)){throw 'ScriptAnalysisRulesMissing'}
    $package=@(Get-RunTestToolPackages -Tool scriptanalyzer)[0]
    $analyzer='PSScriptAnalyzer '+$package.Version
    $configuration=Get-QuietScriptAnalysisSha256 ($analyzer+'|'+$settings.SHA256+'|'+(Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash)
    if([string]::IsNullOrWhiteSpace($CacheDirectory)){$CacheDirectory=[IO.Path]::Combine($ToolRoot,'.cache','script-analysis')}
    $CacheDirectory=[IO.Path]::GetFullPath($CacheDirectory)
    [void][IO.Directory]::CreateDirectory($CacheDirectory)
    $files=@(Get-QuietScriptAnalysisFiles $WorkspaceRoot)
    $entries=foreach($relative in $files){
        $full=[IO.Path]::Combine($WorkspaceRoot,$relative)
        $key=Get-QuietScriptAnalysisCacheKey -RelativePath $relative -ContentSHA256 (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ConfigurationSHA256 $configuration
        [pscustomobject]@{Path=$full;RelativePath=$relative;Test=(Test-QuietScriptAnalysisTestContainer $relative);CachePath=[IO.Path]::Combine($CacheDirectory,$key+'.json')}
    }
    $misses=@($entries|Where-Object {![IO.File]::Exists($_.CachePath)})
    Write-Host ("Progress: Analyze PowerShell sources | files=$($files.Count) cached=$($files.Count-$misses.Count) to analyze=$($misses.Count)")
    if($misses.Count){
        $tools=Initialize-QuietTestTools -WorkspaceRoot $ToolRoot -Tool scriptanalyzer -Offline:$Offline
        Invoke-QuietScriptAnalysisProcess -AnalyzerModulePath $tools.ScriptAnalyzerModulePath -Version $package.Version -Settings $settings.Settings -TestSettings $settings.TestSettings -RulesPath $rulesPath -Files $misses -CacheDirectory $CacheDirectory -TimeoutSeconds $TimeoutSeconds
    }
    $findings=foreach($entry in $entries){
        if(![IO.File]::Exists($entry.CachePath)){throw ('ScriptAnalysisCacheMissing: '+$entry.RelativePath)}
        @((Get-Content -LiteralPath $entry.CachePath -Raw -Encoding utf8|ConvertFrom-Json).Findings)|Where-Object {$null -ne $_}
    }
    $comparison=Compare-QuietScriptAnalysisBaseline -Findings @($findings) -Baseline $baseline
    foreach($finding in $comparison.New){Write-Host ('New finding: '+$finding.Path+':'+$finding.Line+' '+$finding.Rule+' '+$finding.Message)}
    foreach($entry in $comparison.Stale){Write-Host ('Stale baseline entry: '+$entry.Path+' '+$entry.Rule+' function='+$entry.Function+' expected='+$entry.Expected+' actual='+$entry.Actual)}
    $pruned=$false
    if($UpdateBaseline -and $comparison.Stale.Count){
        Write-WorkspaceJson $baselinePath ([pscustomobject][ordered]@{SchemaVersion=1;Analyzer=$analyzer;Entries=$comparison.Pruned.Entries})
        $pruned=$true
    }
    $result=[pscustomobject][ordered]@{
        Check='ScriptAnalyzer';Analyzer=$analyzer;Files=$files.Count;Analyzed=$misses.Count;Cached=$files.Count-$misses.Count
        Findings=@($findings).Count;Baselined=$comparison.Baselined;New=$comparison.New.Count;Stale=$comparison.Stale.Count;Pruned=$pruned
    }
    if($comparison.New.Count){throw ('ScriptAnalysisNewViolations: '+$comparison.New.Count+'; fix them. The baseline only records legacy findings and never grows.')}
    if($comparison.Stale.Count -and !$pruned){throw ('ScriptAnalysisBaselineStale: '+$comparison.Stale.Count+'; run ./scripts/Test-ScriptAnalysis.ps1 -UpdateBaseline to prune it.')}
    $result
}

function Invoke-QuietScriptAnalysisProcess {
    <#
    .SYNOPSIS
    Runs the analyzer worker in a child pwsh so the pinned PSScriptAnalyzer never meets another loaded copy.
    .PARAMETER AnalyzerModulePath
    Pinned PSScriptAnalyzer.psd1.
    .PARAMETER Version
    Required analyzer version.
    .PARAMETER Settings
    Invoke-ScriptAnalyzer settings hashtable.
    .PARAMETER TestSettings
    Settings applied to Pester containers.
    .PARAMETER RulesPath
    Custom rules module.
    .PARAMETER Files
    Entries {Path, RelativePath, CachePath} to analyze.
    .PARAMETER CacheDirectory
    Cache directory that also holds the request and the worker logs.
    .PARAMETER TimeoutSeconds
    Wall-clock limit for the worker.
    #>
    param([Parameter(Mandatory)][string]$AnalyzerModulePath,[Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][hashtable]$Settings,[Parameter(Mandatory)][hashtable]$TestSettings,[Parameter(Mandatory)][string]$RulesPath,[Parameter(Mandatory)][object[]]$Files,[Parameter(Mandatory)][string]$CacheDirectory,[int]$TimeoutSeconds=900)
    $run=[IO.Path]::Combine($CacheDirectory,'runs',([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
    [void][IO.Directory]::CreateDirectory($run)
    $requestPath=[IO.Path]::Combine($run,'request.json')
    Write-WorkspaceJson $requestPath ([ordered]@{AnalyzerModulePath=$AnalyzerModulePath;Version=$Version;Settings=$Settings;TestSettings=$TestSettings;RulesPath=$RulesPath;Files=@($Files)})
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $command="Import-Module '"+([IO.Path]::Combine($PSScriptRoot,'Test-ScriptAnalysis.psm1')).Replace("'","''")+"' -DisableNameChecking -ErrorAction Stop; Invoke-QuietScriptAnalysisWorker -RequestPath '"+$requestPath.Replace("'","''")+"'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $stdout=[IO.Path]::Combine($run,'worker.stdout.log');$stderr=[IO.Path]::Combine($run,'worker.stderr.log')
    $options=@{FilePath=$runner;ArgumentList=@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);PassThru=$true;RedirectStandardOutput=$stdout;RedirectStandardError=$stderr}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $worker=Start-Process @options
    if(!$worker.WaitForExit($TimeoutSeconds*1000)){
        try{$worker.Kill($true)}catch{Write-Verbose ('Analyzer worker already stopped: '+$_.Exception.Message)}
        throw ('ScriptAnalysisTimeout: '+$TimeoutSeconds+'s; see '+$run)
    }
    $worker.WaitForExit()
    if($worker.ExitCode -ne 0){
        $tail=if([IO.File]::Exists($stderr)){(@(Get-Content -LiteralPath $stderr -Tail 5 -Encoding utf8) -join ' ')}else{''}
        throw ('ScriptAnalysisWorkerFailed: exit '+$worker.ExitCode+'; see '+$run+'; '+$tail)
    }
    [IO.Directory]::Delete($run,$true)
}

function Invoke-QuietScriptAnalysisWorker {
    <#
    .SYNOPSIS
    Worker body: imports the pinned analyzer, analyzes each requested file and writes one cache document per file.
    .PARAMETER RequestPath
    request.json written by Invoke-QuietScriptAnalysisProcess.
    #>
    param([Parameter(Mandatory)][string]$RequestPath)
    $ErrorActionPreference='Stop'
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    Import-Module $request.AnalyzerModulePath -Force -DisableNameChecking -ErrorAction Stop
    $loaded=@(Get-Module PSScriptAnalyzer)
    if($loaded.Count -ne 1 -or $loaded[0].Version -ne [version]$request.Version){throw 'ScriptAnalysisAnalyzerVersionMismatch'}
    $settings=@{Severity=@($request.Settings.Severity);ExcludeRules=@($request.Settings.ExcludeRules)}
    $testSettings=@{Severity=@($request.TestSettings.Severity);ExcludeRules=@($request.TestSettings.ExcludeRules)}
    foreach($file in $request.Files){
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file.Path,[ref]$tokens,[ref]$errors)
        $records=@(Invoke-ScriptAnalyzer -Path $file.Path -Settings $(if($file.Test){$testSettings}else{$settings}) -CustomRulePath $request.RulesPath -IncludeDefaultRules)
        $findings=@($records|ForEach-Object {ConvertTo-QuietScriptAnalysisFinding -Record $_ -RelativePath $file.RelativePath -Ast $ast})
        Write-WorkspaceJson $file.CachePath ([ordered]@{RelativePath=$file.RelativePath;Findings=$findings})
        Write-Host ('Analyzed: '+$file.RelativePath+' findings='+$findings.Count)
    }
}

Export-ModuleMember -Function Invoke-QuietScriptTestScriptAnalysis,Invoke-QuietScriptAnalysisProcess,Invoke-QuietScriptAnalysisWorker
