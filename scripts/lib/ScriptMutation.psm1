#Objective: Pure mutation-testing model for scripts/lib: targets, mutants, classification, score and report.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutators.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietScriptMutants {
    <#
    .SYNOPSIS
    Lists the mutants of the named functions of one library source, with stable ids, in source order.
    .DESCRIPTION
    Each mutator of Get-QuietScriptMutatorCatalog runs on each function body. Duplicates (same extent and replacement) and
    no-op replacements are dropped. The id is derived from the module, function, mutator, extent and replacement only, so it
    survives edits elsewhere in the file as long as the offsets do not move.
    .PARAMETER Text
    Library source text.
    .PARAMETER Functions
    Function names to mutate; each must be defined in the source.
    .PARAMETER Module
    Library path relative to the scripts root, used in the ids and the report.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)][string[]]$Functions,[Parameter(Mandatory)][string]$Module)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "ScriptMutationSourceInvalid: $Module"}
    $definitions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $mutants=[Collections.Generic.List[object]]::new()
    foreach($name in $Functions){
        $definition=@($definitions|Where-Object {$_.Name -ceq $name})
        if($definition.Count -ne 1){throw "ScriptMutationFunctionMissing: $name"}
        foreach($mutator in Get-QuietScriptMutatorCatalog){
            foreach($candidate in & ('Find-QuietScriptMutant'+$mutator) -Ast $definition[0].Body){
                if($candidate.Original -ceq $candidate.Replacement){continue}
                $identity=$Module+[char]0x1F+$name+[char]0x1F+$candidate.Mutator+[char]0x1F+$candidate.StartOffset+[char]0x1F+$candidate.EndOffset+[char]0x1F+$candidate.Replacement
                if(!$seen.Add([string]$candidate.StartOffset+[char]0x1F+$candidate.EndOffset+[char]0x1F+$candidate.Replacement)){continue}
                $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))).Substring(0,12).ToLowerInvariant()
                $mutants.Add([pscustomobject][ordered]@{
                    Id=$hash;Module=$Module;Function=$name;Mutator=$candidate.Mutator;StartOffset=$candidate.StartOffset;EndOffset=$candidate.EndOffset
                    Line=$candidate.Line;Column=$candidate.Column;Original=$candidate.Original;Replacement=$candidate.Replacement
                })
            }
        }
    }
    $mutants|Sort-Object -Property StartOffset,EndOffset -Stable
}

function New-QuietScriptMutantSource {
    <#
    .SYNOPSIS
    Applies one mutant to the source text and reports whether the result still parses (otherwise it is a CompileError).
    .PARAMETER Text
    Original library source text.
    .PARAMETER Mutant
    Mutant from Get-QuietScriptMutants.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)]$Mutant)
    $start=[int]$Mutant.StartOffset;$end=[int]$Mutant.EndOffset
    if($start -lt 0 -or $end -lt $start -or $end -gt $Text.Length -or $Text.Substring($start,$end-$start) -cne [string]$Mutant.Original){throw "ScriptMutationOffsetMismatch: $($Mutant.Id)"}
    $mutated=$Text.Substring(0,$start)+[string]$Mutant.Replacement+$Text.Substring($end)
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseInput($mutated,[ref]$tokens,[ref]$errors)
    [pscustomobject]@{Text=$mutated;Compiles=($errors.Count -eq 0)}
}

function Get-QuietScriptMutantStatus {
    <#
    .SYNOPSIS
    Classifies one test run of a mutant: Timeout, Survived (a complete passing run) or Killed (anything else).
    .DESCRIPTION
    A failing test, a crash or a worker error all mean the mutant was detected. A run that passes with zero executed tests
    (for example everything skipped) is still Survived: nothing detected the change.
    .PARAMETER State
    Terminal state of the mutant run (Success, Failed, Crash, Timeout, Cancelled) or empty when no status was saved.
    .PARAMETER Failed
    Failed test count of the run.
    .PARAMETER TimedOut
    True when the engine itself stopped the run at its deadline.
    #>
    param([AllowNull()][AllowEmptyString()][string]$State,[int]$Failed,[switch]$TimedOut)
    if($TimedOut -or $State -ceq 'Timeout'){return 'Timeout'}
    if($State -ceq 'Success' -and $Failed -eq 0){return 'Survived'}
    'Killed'
}

function Get-QuietScriptMutantTimeout {
    <#
    .SYNOPSIS
    Per-mutant deadline in seconds: max(60, ceiling(3 x baseline + 30)).
    .PARAMETER BaselineSeconds
    Duration of the unmutated run.
    #>
    param([Parameter(Mandatory)][double]$BaselineSeconds)
    if($BaselineSeconds -lt 0 -or [double]::IsNaN($BaselineSeconds) -or [double]::IsInfinity($BaselineSeconds)){throw 'ScriptMutationBaselineDurationInvalid'}
    [int][Math]::Max(60,[Math]::Ceiling(3*$BaselineSeconds+30))
}

function Measure-QuietScriptMutationScore {
    <#
    .SYNOPSIS
    Counts mutant statuses and computes the score (Killed + Timeout) / (Killed + Timeout + Survived), as a percentage.
    .DESCRIPTION
    CompileError and declared Equivalent mutants are excluded. With no valid mutant the score is 100: nothing could survive.
    .PARAMETER Results
    Objects with a Status property.
    .PARAMETER Break
    Minimum score; Passed is Score >= Break.
    #>
    param([AllowEmptyCollection()][object[]]$Results=@(),[ValidateRange(0,100)][double]$Break=0)
    $counts=[ordered]@{Killed=0;Survived=0;Timeout=0;CompileError=0;Equivalent=0}
    foreach($result in @($Results|Where-Object {$null -ne $_})){
        $status=[string]$result.Status
        if($status -cnotin @('Killed','Survived','Timeout','CompileError','Equivalent')){throw "ScriptMutationStatusInvalid: $status"}
        $counts[$status]++
    }
    $detected=$counts.Killed+$counts.Timeout;$valid=$detected+$counts.Survived
    $score=if($valid -eq 0){100.0}else{[Math]::Round(100.0*$detected/$valid,2)}
    [pscustomobject][ordered]@{Killed=$counts.Killed;Survived=$counts.Survived;Timeout=$counts.Timeout;CompileError=$counts.CompileError;Equivalent=$counts.Equivalent;Valid=$valid;Score=$score;Break=$Break;Passed=($score -ge $Break)}
}

function Read-QuietScriptMutationTargets {
    <#
    .SYNOPSIS
    Validates mutation.targets.psd1 and returns its targets with resolved paths.
    .DESCRIPTION
    Each target is @{Name; Module; Functions; UnitTestFiles; Break; Inputs?; Equivalent?}. Module is relative to the
    scripts root (lib/*.psm1), UnitTestFiles are relative to the tests root and must lie under unit/. Inputs (optional)
    lists the repository files or globs (* within a segment, ** across segments) that the unit tests read, for the
    incremental cache key. Equivalent (optional) declares mutants that no test can kill because the mutated code behaves
    the same: @{Function; Mutator; Original; Replacement; Reason; Platform?}, where Function is one of Functions, Mutator
    is a catalog mutator, Original is non-empty, Reason says why the behavior is unchanged (at least 20 characters) and
    Platform (Windows, Linux or MacOS) limits the entry to the runs on that platform. Errors:
    ScriptMutationTargetsMissing and
    ScriptMutationTargetsInvalid: syntax|shape|name|duplicate|module|functions|tests|break|inputs|equivalent.
    .PARAMETER Path
    Targets file.
    .PARAMETER ScriptsRoot
    Scripts root the modules are resolved against.
    .PARAMETER TestsRoot
    Tests root the unit test files are resolved against.
    #>
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$TestsRoot)
    if(![IO.File]::Exists($Path)){throw 'ScriptMutationTargetsMissing'}
    try{$data=Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop}catch{throw 'ScriptMutationTargetsInvalid: syntax'}
    if(@($data.Keys).Count -ne 1 -or !$data.ContainsKey('Targets') -or @($data.Targets).Count -eq 0){throw 'ScriptMutationTargetsInvalid: shape'}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($target in @($data.Targets)){
        if($target -isnot [hashtable]){throw 'ScriptMutationTargetsInvalid: shape'}
        foreach($key in $target.Keys){if($key -cnotin @('Name','Module','Functions','UnitTestFiles','Break','Inputs','Equivalent')){throw 'ScriptMutationTargetsInvalid: shape'}}
        $name=[string]$target.Name
        if($name -cnotmatch '^[A-Za-z][A-Za-z0-9.-]{0,63}$'){throw 'ScriptMutationTargetsInvalid: name'}
        if(!$names.Add($name)){throw 'ScriptMutationTargetsInvalid: duplicate'}
        $module=[string]$target.Module
        if($module -cnotmatch '^lib/[A-Za-z0-9][A-Za-z0-9.-]*\.psm1$'){throw 'ScriptMutationTargetsInvalid: module'}
        $modulePath=[IO.Path]::GetFullPath([IO.Path]::Combine($ScriptsRoot,$module))
        if(![IO.File]::Exists($modulePath)){throw 'ScriptMutationTargetsInvalid: module'}
        $functions=@($target.Functions|ForEach-Object {[string]$_})
        if($functions.Count -eq 0 -or @($functions|Where-Object {$_ -cnotmatch '^[A-Za-z][A-Za-z0-9-]*$'}).Count -or @($functions|Sort-Object -Unique -CaseSensitive).Count -ne $functions.Count){throw 'ScriptMutationTargetsInvalid: functions'}
        $tests=@($target.UnitTestFiles|ForEach-Object {[string]$_})
        if($tests.Count -eq 0){throw 'ScriptMutationTargetsInvalid: tests'}
        foreach($test in $tests){
            if($test -cnotmatch '^unit/([A-Za-z0-9][A-Za-z0-9.-]*/)*[A-Za-z0-9][A-Za-z0-9.-]*\.Tests\.ps1$' -or ![IO.File]::Exists([IO.Path]::Combine($TestsRoot,$test))){throw 'ScriptMutationTargetsInvalid: tests'}
        }
        $break=$target.Break
        if($break -isnot [int] -or $break -lt 0 -or $break -gt 100){throw 'ScriptMutationTargetsInvalid: break'}
        $inputs=@(if($target.ContainsKey('Inputs')){$target.Inputs})
        if($target.ContainsKey('Inputs') -and ($inputs.Count -eq 0 -or @($inputs|Where-Object {$_ -isnot [string] -or $_ -cnotmatch '^[A-Za-z0-9._*-]+(/[A-Za-z0-9._*-]+)*$' -or $_ -cmatch '(^|/)\.\.?(/|$)'}).Count -or @($inputs|Sort-Object -Unique -CaseSensitive).Count -ne $inputs.Count)){throw 'ScriptMutationTargetsInvalid: inputs'}
        $declared=@(if($target.ContainsKey('Equivalent')){$target.Equivalent})
        if($target.ContainsKey('Equivalent') -and $declared.Count -eq 0){throw 'ScriptMutationTargetsInvalid: equivalent'}
        $identities=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $equivalent=foreach($entry in $declared){
            if($entry -isnot [hashtable] -or @($entry.Keys|Where-Object {$_ -cnotin @('Function','Mutator','Original','Replacement','Reason','Platform')}).Count){throw 'ScriptMutationTargetsInvalid: equivalent'}
            $platform=[string]$entry['Platform']  # an absent platform reads as the empty string
            if($entry.Function -isnot [string] -or $entry.Function -cnotin $functions -or $entry.Mutator -isnot [string] -or $entry.Mutator -cnotin @(Get-QuietScriptMutatorCatalog) -or $entry.Original -isnot [string] -or !$entry.Original -or $entry.Replacement -isnot [string] -or
                $entry.Reason -isnot [string] -or $entry.Reason.Trim().Length -lt 20 -or ($entry.ContainsKey('Platform') -and $platform -cnotin @('Windows','Linux','MacOS'))){throw 'ScriptMutationTargetsInvalid: equivalent'}
            if(!$identities.Add($entry.Function+[char]0x1F+$entry.Mutator+[char]0x1F+$entry.Original+[char]0x1F+$entry.Replacement+[char]0x1F+$platform)){throw 'ScriptMutationTargetsInvalid: equivalent'}
            [pscustomobject][ordered]@{Function=$entry.Function;Mutator=$entry.Mutator;Original=$entry.Original;Replacement=$entry.Replacement;Reason=$entry.Reason.Trim();Platform=$platform}
        }
        [pscustomobject][ordered]@{Name=$name;Module=$module;ModulePath=$modulePath;Functions=[string[]]$functions;UnitTestFiles=[string[]]$tests;Break=[int]$break;Inputs=[string[]]$inputs;Equivalent=@($equivalent)}
    }
}

function Select-QuietScriptMutationEquivalents {
    <#
    .SYNOPSIS
    Splits the mutants of one target into those to run and those its declared Equivalent entries cover.
    .DESCRIPTION
    An entry covers every mutant with the same Function, Mutator, Original and Replacement (line endings normalized), on
    every platform or only on its Platform. An entry that applies here and covers no mutant is stale: the code changed and
    the declaration must be reviewed (ScriptMutationEquivalentStale). Covered mutants carry the entry's Reason.
    .PARAMETER Mutants
    Mutants from Get-QuietScriptMutants.
    .PARAMETER Equivalent
    Equivalent entries of the target from Read-QuietScriptMutationTargets.
    .PARAMETER Platform
    Current platform: Windows, Linux or MacOS.
    .PARAMETER Target
    Target name, for the stale error.
    #>
    param([AllowEmptyCollection()][object[]]$Mutants=@(),[AllowEmptyCollection()][object[]]$Equivalent=@(),[Parameter(Mandatory)][ValidateSet('Windows','Linux','MacOS')][string]$Platform,[Parameter(Mandatory)][string]$Target)
    $lf={param($Value)([string]$Value).Replace("`r`n","`n")}
    $entries=@($Equivalent|Where-Object {$null -ne $_ -and (!$_.Platform -or $_.Platform -ceq $Platform)})
    $used=[bool[]]::new($entries.Count)
    $run=[Collections.Generic.List[object]]::new();$covered=[Collections.Generic.List[object]]::new()
    foreach($mutant in @($Mutants|Where-Object {$null -ne $_})){
        $match=-1
        for($index=0;$index -lt $entries.Count;$index++){
            $entry=$entries[$index]
            if($entry.Function -ceq $mutant.Function -and $entry.Mutator -ceq $mutant.Mutator -and (& $lf $entry.Original) -ceq (& $lf $mutant.Original) -and (& $lf $entry.Replacement) -ceq (& $lf $mutant.Replacement)){$match=$index;break}
        }
        if($match -lt 0){$run.Add($mutant);continue}
        $used[$match]=$true
        $copy=[ordered]@{};foreach($property in $mutant.PSObject.Properties){$copy[$property.Name]=$property.Value}
        $copy.Reason=$entries[$match].Reason
        $covered.Add([pscustomobject]$copy)
    }
    $stale=@(for($index=0;$index -lt $entries.Count;$index++){if(!$used[$index]){'{0} {1} {2} -> {3}{4}' -f $entries[$index].Function,$entries[$index].Mutator,$entries[$index].Original,$entries[$index].Replacement,$(if($entries[$index].Platform){' on '+$entries[$index].Platform})}})
    if($stale.Count){throw ("ScriptMutationEquivalentStale: $Target`: "+($stale -join '; '))}
    [pscustomobject]@{Run=$run.ToArray();Equivalent=$covered.ToArray()}
}

function New-QuietScriptMutationReport {
    <#
    .SYNOPSIS
    Builds the run report: one entry per target with its score, break, verdict, survivors and declared equivalents, plus the overall verdict.
    .DESCRIPTION
    A campaign that stopped passes Crash and only the targets it finished: the report is then Incomplete, never Passed,
    and Crash names the target it stopped in (empty outside any target), the error and the targets it never started.
    .PARAMETER Targets
    Targets from Read-QuietScriptMutationTargets; with Crash, only the finished ones (possibly none).
    .PARAMETER Results
    Mutant results: mutant fields plus Target, Status, Reason for an Equivalent and, for a reused outcome, Cached = true.
    .PARAMETER Seed
    Test seed shared by every mutant run.
    .PARAMETER Crash
    {Target, Error, NotRun} of a campaign that stopped before its end.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Targets,[AllowEmptyCollection()][object[]]$Results=@(),[int]$Seed,$Crash)
    $entries=foreach($target in $Targets){
        $own=@($Results|Where-Object {$null -ne $_ -and [string]$_.Target -ceq $target.Name})
        $score=Measure-QuietScriptMutationScore -Results $own -Break $target.Break
        [pscustomobject][ordered]@{
            Name=$target.Name;Module=$target.Module;Functions=$target.Functions.Count;Mutants=$own.Count
            Killed=$score.Killed;Survived=$score.Survived;Timeout=$score.Timeout;CompileError=$score.CompileError;Equivalent=$score.Equivalent;Cached=@($own|Where-Object {$_.PSObject.Properties['Cached'] -and $_.Cached -is [bool] -and $_.Cached}).Count;Score=$score.Score;Break=$score.Break;Passed=$score.Passed
            Survivors=@($own|Where-Object Status -CEQ 'Survived'|ForEach-Object {[pscustomobject][ordered]@{Id=$_.Id;Function=$_.Function;Mutator=$_.Mutator;Line=$_.Line;Column=$_.Column;Original=$_.Original;Replacement=$_.Replacement}})
            Equivalents=@($own|Where-Object Status -CEQ 'Equivalent'|ForEach-Object {[pscustomobject][ordered]@{Id=$_.Id;Function=$_.Function;Mutator=$_.Mutator;Line=$_.Line;Column=$_.Column;Original=$_.Original;Replacement=$_.Replacement;Reason=$_.Reason}})
        }
    }
    $entries=@($entries)
    $stop=if($null -ne $Crash){[pscustomobject][ordered]@{Target=[string]$Crash.Target;Error=[string]$Crash.Error;NotRun=[string[]]@($Crash.NotRun|Where-Object {$_})}}
    [pscustomobject][ordered]@{SchemaVersion=1;Seed=$Seed;Passed=($null -eq $stop -and @($entries|Where-Object {!$_.Passed}).Count -eq 0);Incomplete=($null -ne $stop);Crash=$stop;Targets=$entries}
}

function ConvertTo-QuietScriptMutationMarkdown {
    <#
    .SYNOPSIS
    Renders a mutation report as Markdown: a score table, then each survivor with file:line, mutator and before/after,
    then each declared equivalent with its reason. An incomplete report names where it stopped, the error and the
    targets never run; its table holds only the finished targets.
    .PARAMETER Report
    Result of New-QuietScriptMutationReport.
    #>
    param([Parameter(Mandatory)]$Report)
    $escape={param([string]$Value)$Value.Replace('|','\|').Replace("`r",' ').Replace("`n",' ').Replace('`',"'")}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('# Script mutation report');$lines.Add('')
    $incomplete=$true -eq $Report.PSObject.Properties['Incomplete']?.Value
    $lines.Add('Verdict: **'+$(if($incomplete){'incomplete'}elseif($Report.Passed){'passed'}else{'failed'})+'**. Seed: '+$Report.Seed+'.');$lines.Add('')
    if($incomplete){
        $crash=$Report.Crash
        $lines.Add(('Stopped {0} with `{1}`. Not run: {2}. Only the finished targets are scored below.' -f $(if($crash.Target){'in target `'+(& $escape $crash.Target)+'`'}else{'outside any target'}),(& $escape $crash.Error),$(if(@($crash.NotRun).Count){(@($crash.NotRun|ForEach-Object {'`'+(& $escape $_)+'`'}) -join ', ')}else{'none'})))
        $lines.Add('')
    }
    $lines.Add('| Target | Module | Mutants | Killed | Timeout | Survived | Compile errors | Equivalent | Cached | Score | Break | Verdict |')
    $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    foreach($target in @($Report.Targets)){
        $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9:0.##} % | {10} % | {11} |' -f $target.Name,$target.Module,$target.Mutants,$target.Killed,$target.Timeout,$target.Survived,$target.CompileError,[int]$target.Equivalent,[int]$target.Cached,[double]$target.Score,$target.Break,$(if($target.Passed){'passed'}else{'failed'})))
    }
    $sections=@(
        @{Property='Survivors';Title='Survivors';Header='| Location | Function | Mutator | Before | After |';Rule='| --- | --- | --- | --- | --- |'}
        @{Property='Equivalents';Title='Equivalent mutants';Header='| Location | Function | Mutator | Before | After | Reason |';Rule='| --- | --- | --- | --- | --- | --- |'}
    )
    foreach($section in $sections){
        foreach($target in @($Report.Targets|Where-Object {$_.PSObject.Properties[$section.Property] -and @($_.($section.Property)).Count})){
            $lines.Add('');$lines.Add('## '+$section.Title+': '+$target.Name);$lines.Add('')
            $lines.Add($section.Header);$lines.Add($section.Rule)
            foreach($row in @($target.($section.Property))){
                $reason=if($row.PSObject.Properties['Reason']){' '+(& $escape $row.Reason)+' |'}
                $lines.Add(('| `{0}:{1}:{2}` | {3} | {4} | `{5}` | `{6}` |{7}' -f $target.Module,$row.Line,$row.Column,$row.Function,$row.Mutator,(& $escape $row.Original),(& $escape $row.Replacement),$reason))
            }
        }
    }
    ($lines -join "`n")+"`n"
}

function Assert-QuietScriptMutationShards {
    <#
    .SYNOPSIS
    Accepts sharded mutation reports only when together they cover every configured target exactly once, each passing its unlowered break.
    .DESCRIPTION
    Every report must be a SchemaVersion 1 report from New-QuietScriptMutationReport. A target missing from every
    report, reported twice, unknown to the targets file, reported for another module or function count, reported with
    a lower break, without mutants or below its break is an issue, and so is an Incomplete report of a campaign that
    stopped (ScriptMutationShardIncomplete: <target it stopped in>). All issues are reported together
    (ScriptMutationShardReportsMissing, ScriptMutationShardReportInvalid, ScriptMutationShardIncomplete, ScriptMutationShardUnknown,
    ScriptMutationShardDuplicate, ScriptMutationShardMissing, ScriptMutationShardStale, ScriptMutationShardBreakLowered,
    ScriptMutationShardFailed). Returns the completion receipt {SchemaVersion, Passed, Targets}.
    .PARAMETER Targets
    Authoritative targets from Read-QuietScriptMutationTargets.
    .PARAMETER Reports
    Parsed report.json documents, one per shard.
    #>
    param([Parameter(Mandatory)][object[]]$Targets,[AllowEmptyCollection()][AllowNull()][object[]]$Reports=@())
    $issues=[Collections.Generic.List[string]]::new()
    $seen=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $known=[Collections.Generic.HashSet[string]]::new([string[]]@($Targets|ForEach-Object {[string]$_.Name}),[StringComparer]::Ordinal)
    $documents=@($Reports|Where-Object {$null -ne $_})
    if(!$documents.Count){$issues.Add('ScriptMutationShardReportsMissing')}
    foreach($report in $documents){
        $version=$report.PSObject.Properties['SchemaVersion']
        $entries=$report.PSObject.Properties['Targets']
        if(!$version -or [string]$version.Value -cne '1' -or !$entries){$issues.Add('ScriptMutationShardReportInvalid');continue}
        # A stopped campaign's finished targets still count; the target it stopped in is then missing too.
        if($true -eq $report.PSObject.Properties['Incomplete']?.Value){$issues.Add('ScriptMutationShardIncomplete: '+[string]$report.PSObject.Properties['Crash']?.Value?.Target)}
        elseif(@($entries.Value).Count -eq 0){$issues.Add('ScriptMutationShardReportInvalid')}
        foreach($entry in @($entries.Value)){
            $name=if($null -ne $entry -and $entry.PSObject.Properties['Name']){[string]$entry.Name}  # a nameless entry reports an empty name
            if(!$known.Contains($name)){$issues.Add('ScriptMutationShardUnknown: '+$name);continue}
            if($seen.ContainsKey($name)){$issues.Add('ScriptMutationShardDuplicate: '+$name);continue}
            $seen.Add($name,$entry)
        }
    }
    $rows=foreach($target in $Targets){
        $name=[string]$target.Name
        if(!$seen.ContainsKey($name)){$issues.Add('ScriptMutationShardMissing: '+$name);continue}
        $entry=$seen[$name]
        $number={param([string]$Property)$value=$entry.PSObject.Properties[$Property];$parsed=0.0;if($value -and [double]::TryParse([string]$value.Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)){$parsed}else{[double]::NaN}}
        $break=& $number 'Break';$score=& $number 'Score';$mutants=& $number 'Mutants';$functions=& $number 'Functions'
        $module=$entry.PSObject.Properties['Module']
        if(!$module -or [string]$module.Value -cne [string]$target.Module -or $functions -ne @($target.Functions).Count){$issues.Add('ScriptMutationShardStale: '+$name);continue}
        if([double]::IsNaN($break) -or $break -lt [int]$target.Break){$issues.Add('ScriptMutationShardBreakLowered: '+$name);continue}
        $passed=$entry.PSObject.Properties['Passed']
        if(!$passed -or $passed.Value -isnot [bool] -or !$passed.Value -or [double]::IsNaN($score) -or $score -lt $break -or [double]::IsNaN($mutants) -or $mutants -lt 1){$issues.Add('ScriptMutationShardFailed: '+$name);continue}
        [pscustomobject][ordered]@{Name=$name;Module=[string]$target.Module;Mutants=[int]$mutants;Score=$score;Break=[int]$target.Break}
    }
    if($issues.Count){throw ($issues -join '; ')}
    [pscustomobject][ordered]@{SchemaVersion=1;Passed=$true;Targets=@($rows)}
}

Export-ModuleMember -Function Get-QuietScriptMutants,New-QuietScriptMutantSource,Get-QuietScriptMutantStatus,Get-QuietScriptMutantTimeout,Measure-QuietScriptMutationScore,Read-QuietScriptMutationTargets,Select-QuietScriptMutationEquivalents,New-QuietScriptMutationReport,ConvertTo-QuietScriptMutationMarkdown,Assert-QuietScriptMutationShards
