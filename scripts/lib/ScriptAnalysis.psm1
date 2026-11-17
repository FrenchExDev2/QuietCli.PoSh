#Objective: Pure settings, finding, cache-key and baseline logic behind Test-ScriptAnalysis.ps1.
#requires -Version 7.6

function Compare-QuietScriptAnalysisBaseline {
    <#
    .SYNOPSIS
    Compares analyzer findings with the checked-in baseline; new violations and stale entries fail the check.
    .PARAMETER Findings
    Findings from ConvertTo-QuietScriptAnalysisFinding.
    .PARAMETER Baseline
    Baseline from Read-QuietScriptAnalysisBaseline.
    .OUTPUTS
    {Passed, New, Stale, Baselined, Pruned}. Pruned is the baseline with every count lowered to what still occurs; it never gains an entry.
    #>
    param([AllowEmptyCollection()][object[]]$Findings=@(),[Parameter(Mandatory)][object]$Baseline)
    $actual=[Collections.Generic.Dictionary[string,Collections.Generic.List[object]]]::new([StringComparer]::Ordinal)
    foreach($finding in @($Findings|Where-Object {$null -ne $_})){
        $key=Get-QuietScriptAnalysisFindingKey $finding
        if(!$actual.ContainsKey($key)){$actual[$key]=[Collections.Generic.List[object]]::new()}
        $actual[$key].Add($finding)
    }
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($entry in @($Baseline.Entries)){$expected[(Get-QuietScriptAnalysisFindingKey $entry)]=$entry}
    $new=[Collections.Generic.List[object]]::new();$stale=[Collections.Generic.List[object]]::new();$kept=[Collections.Generic.List[object]]::new();$baselined=0
    foreach($key in @($actual.Keys|Sort-Object -Culture ([cultureinfo]::InvariantCulture) -CaseSensitive)){
        $items=$actual[$key]
        $allowed=if($expected.ContainsKey($key)){[int]$expected[$key].Count}else{0}
        $baselined+=[Math]::Min($allowed,$items.Count)
        for($index=$allowed;$index -lt $items.Count;$index++){$new.Add($items[$index])}
    }
    foreach($entry in @($Baseline.Entries)){
        $key=Get-QuietScriptAnalysisFindingKey $entry
        $count=if($actual.ContainsKey($key)){$actual[$key].Count}else{0}
        if($count -lt [int]$entry.Count){$stale.Add([pscustomobject][ordered]@{Rule=$entry.Rule;Path=$entry.Path;Function=$entry.Function;ExtentSHA256=$entry.ExtentSHA256;Expected=[int]$entry.Count;Actual=$count})}
        $remaining=[Math]::Min($count,[int]$entry.Count)
        if($remaining -gt 0){$kept.Add([pscustomobject][ordered]@{Rule=$entry.Rule;Path=$entry.Path;Function=$entry.Function;ExtentSHA256=$entry.ExtentSHA256;Count=$remaining})}
    }
    [pscustomobject][ordered]@{
        Passed=($new.Count -eq 0 -and $stale.Count -eq 0);New=$new.ToArray();Stale=$stale.ToArray();Baselined=$baselined
        Pruned=[pscustomobject][ordered]@{SchemaVersion=1;Analyzer=[string]$Baseline.Analyzer;Entries=$kept.ToArray()}
    }
}

function Get-QuietScriptAnalysisFindingKey {
    <#
    .SYNOPSIS
    Returns the ordinal baseline key (rule, path, function, extent hash) of a finding or baseline entry.
    .PARAMETER Item
    Finding or baseline entry.
    #>
    param([Parameter(Mandatory)][object]$Item)
    ([string]$Item.Rule)+[char]0x1F+([string]$Item.Path)+[char]0x1F+([string]$Item.Function)+[char]0x1F+([string]$Item.ExtentSHA256)
}

function Get-QuietScriptAnalysisSha256 {
    <#
    .SYNOPSIS
    Returns the uppercase SHA-256 of a text after CRLF and CR are normalized to LF.
    .PARAMETER Text
    Text to hash; null hashes as empty.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $normalized=([string]$Text).Replace("`r`n","`n").Replace("`r","`n")
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($normalized)))
}

function Get-QuietScriptAnalysisFunctionName {
    <#
    .SYNOPSIS
    Returns the innermost function that contains an extent, or an empty string at file level.
    .PARAMETER Ast
    Parsed file.
    .PARAMETER StartOffset
    Extent start offset.
    .PARAMETER EndOffset
    Extent end offset.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast,[int]$StartOffset,[int]$EndOffset)
    $best=$null
    foreach($function in $Ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
        # FindAll walks the tree in preorder, and enclosing functions nest: the last one found is the innermost.
        if($function.Extent.StartOffset -le $StartOffset -and $function.Extent.EndOffset -ge $EndOffset){$best=$function}
    }
    if($best){$best.Name}else{''}
}

function ConvertTo-QuietScriptAnalysisFinding {
    <#
    .SYNOPSIS
    Maps one analyzer record to a stable finding keyed by rule, relative path, function and extent hash.
    .PARAMETER Record
    DiagnosticRecord, or any object with RuleName, Extent, Line, Column, Severity and Message.
    .PARAMETER RelativePath
    Workspace-relative path with forward slashes.
    .PARAMETER Ast
    Parsed file used to name the enclosing function.
    #>
    param([Parameter(Mandatory)][object]$Record,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    $extent=$Record.Extent
    $text='';$function=''
    if($extent){$text=[string]$extent.Text;$function=Get-QuietScriptAnalysisFunctionName -Ast $Ast -StartOffset ([int]$extent.StartOffset) -EndOffset ([int]$extent.EndOffset)}
    [pscustomobject][ordered]@{
        Rule=[string]$Record.RuleName;Path=$RelativePath.Replace('\','/');Function=$function;ExtentSHA256=(Get-QuietScriptAnalysisSha256 $text)
        Line=[int]$Record.Line;Column=[int]$Record.Column;Severity=[string]$Record.Severity;Message=[string]$Record.Message
    }
}

function ConvertTo-QuietScriptAnalysisBaseline {
    <#
    .SYNOPSIS
    Builds a baseline document from findings: one entry per key with its count, sorted in ordinal order.
    .PARAMETER Findings
    Findings to accept.
    .PARAMETER Analyzer
    Analyzer name and version recorded in the document.
    #>
    param([AllowEmptyCollection()][object[]]$Findings=@(),[Parameter(Mandatory)][string]$Analyzer)
    $groups=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($finding in @($Findings|Where-Object {$null -ne $_})){
        $key=Get-QuietScriptAnalysisFindingKey $finding
        if($groups.ContainsKey($key)){$groups[$key].Count++}
        else{$groups[$key]=[pscustomobject][ordered]@{Rule=[string]$finding.Rule;Path=[string]$finding.Path;Function=[string]$finding.Function;ExtentSHA256=[string]$finding.ExtentSHA256;Count=1}}
    }
    [pscustomobject][ordered]@{SchemaVersion=1;Analyzer=$Analyzer;Entries=@($groups.Values)}
}

function Read-QuietScriptAnalysisBaseline {
    <#
    .SYNOPSIS
    Reads and validates ScriptAnalyzer.baseline.json.
    .PARAMETER Path
    Baseline path.
    .OUTPUTS
    {SchemaVersion, Analyzer, Entries}. Errors: ScriptAnalysisBaselineMissing and ScriptAnalysisBaselineInvalid: <reason>.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if(![IO.File]::Exists($Path)){throw 'ScriptAnalysisBaselineMissing'}
    try{$document=[IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop}catch{throw 'ScriptAnalysisBaselineInvalid: syntax'}
    if($document -isnot [pscustomobject] -or $document.SchemaVersion -ne 1){throw 'ScriptAnalysisBaselineInvalid: schema'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $entries=[Collections.Generic.List[object]]::new()
    foreach($entry in @($document.Entries)){
        if($entry -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$entry.Rule) -or [string]::IsNullOrWhiteSpace([string]$entry.Path) -or $null -eq $entry.Function){throw 'ScriptAnalysisBaselineInvalid: entry'}
        if([string]$entry.Path -match '(^/|\\|^[A-Za-z]:|(^|/)\.\.(/|$))'){throw 'ScriptAnalysisBaselineInvalid: path'}
        if([string]$entry.ExtentSHA256 -cnotmatch '^[A-F0-9]{64}$'){throw 'ScriptAnalysisBaselineInvalid: hash'}
        if($entry.Count -isnot [long] -and $entry.Count -isnot [int] -or [long]$entry.Count -lt 1){throw 'ScriptAnalysisBaselineInvalid: count'}
        if(!$seen.Add((Get-QuietScriptAnalysisFindingKey $entry))){throw 'ScriptAnalysisBaselineInvalid: duplicate'}
        $entries.Add($entry)
    }
    [pscustomobject][ordered]@{SchemaVersion=1;Analyzer=[string]$document.Analyzer;Entries=$entries.ToArray()}
}

function Read-QuietScriptAnalysisSettings {
    <#
    .SYNOPSIS
    Reads ScriptAnalyzerSettings.psd1 and requires a reason for every excluded rule.
    .PARAMETER Path
    Settings path.
    .OUTPUTS
    {Settings, TestSettings, Reasons, SHA256}. Settings and TestSettings hold only Severity and ExcludeRules, for Invoke-ScriptAnalyzer -Settings; TestSettings adds TestExcludeRules and applies to test containers only. Errors: ScriptAnalysisSettingsMissing and ScriptAnalysisSettingsInvalid: <reason>.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if(![IO.File]::Exists($Path)){throw 'ScriptAnalysisSettingsMissing'}
    try{$data=Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop}catch{throw 'ScriptAnalysisSettingsInvalid: syntax'}
    foreach($key in $data.Keys){if($key -cnotin @('Severity','ExcludeRules','TestExcludeRules','ExclusionReasons')){throw 'ScriptAnalysisSettingsInvalid: key'}}
    $severity=@($data.Severity|Where-Object {$null -ne $_}|ForEach-Object {[string]$_})
    if(!$severity.Count -or @($severity|Where-Object {$_ -cnotin @('Error','Warning','Information')}).Count){throw 'ScriptAnalysisSettingsInvalid: severity'}
    $exclude=@($data.ExcludeRules|Where-Object {$null -ne $_}|ForEach-Object {[string]$_})
    $testExclude=@($data.TestExcludeRules|Where-Object {$null -ne $_}|ForEach-Object {[string]$_})
    $reasons=if($data.ExclusionReasons -is [hashtable]){$data.ExclusionReasons}elseif($null -eq $data.ExclusionReasons){@{}}else{throw 'ScriptAnalysisSettingsInvalid: reasons'}
    $all=@($exclude)+@($testExclude)
    if(@($all|Select-Object -Unique).Count -ne $all.Count){throw 'ScriptAnalysisSettingsInvalid: duplicate'}
    foreach($rule in $all){if([string]::IsNullOrWhiteSpace($rule) -or !$reasons.ContainsKey($rule) -or ([string]$reasons[$rule]).Trim().Length -lt 20){throw 'ScriptAnalysisSettingsInvalid: reason'}}
    foreach($rule in $reasons.Keys){if($rule -cnotin $all){throw 'ScriptAnalysisSettingsInvalid: orphan-reason'}}
    $canonical=[ordered]@{Severity=@($severity|Sort-Object -CaseSensitive);ExcludeRules=@($exclude|Sort-Object -CaseSensitive);TestExcludeRules=@($testExclude|Sort-Object -CaseSensitive)}
    [pscustomobject][ordered]@{
        Settings=@{Severity=$canonical.Severity;ExcludeRules=$canonical.ExcludeRules}
        TestSettings=@{Severity=$canonical.Severity;ExcludeRules=@($canonical.ExcludeRules+$canonical.TestExcludeRules|Sort-Object -CaseSensitive)}
        Reasons=$reasons;SHA256=(Get-QuietScriptAnalysisSha256 ($canonical|ConvertTo-Json -Compress))
    }
}

function Test-QuietScriptAnalysisTestContainer {
    <#
    .SYNOPSIS
    Returns true for a Pester container (test/scripts/**/*.Tests.ps1), which is analyzed with TestSettings.
    .PARAMETER RelativePath
    Workspace-relative path.
    #>
    param([Parameter(Mandatory)][string]$RelativePath)
    $normalized=$RelativePath.Replace('\','/')
    $normalized.StartsWith('test/scripts/',[StringComparison]::Ordinal) -and $normalized.EndsWith('.Tests.ps1',[StringComparison]::Ordinal)
}

function Get-QuietScriptAnalysisFiles {
    <#
    .SYNOPSIS
    Lists the .ps1 and .psm1 files under scripts/ and test/scripts/, skipping links, as sorted relative paths.
    .PARAMETER WorkspaceRoot
    Workspace to analyze.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $options=[IO.EnumerationOptions]::new();$options.RecurseSubdirectories=$true;$options.AttributesToSkip=[IO.FileAttributes]::ReparsePoint;$options.IgnoreInaccessible=$false
    $files=[Collections.Generic.List[string]]::new()
    foreach($area in @('scripts','test/scripts')){
        $directory=[IO.Path]::Combine($root,$area)
        if(![IO.Directory]::Exists($directory)){continue}
        foreach($file in [IO.Directory]::EnumerateFiles($directory,'*',$options)){
            if([IO.Path]::GetExtension($file) -cnotin @('.ps1','.psm1')){continue}
            $files.Add([IO.Path]::GetRelativePath($root,$file).Replace('\','/'))
        }
    }
    $sorted=$files.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    $sorted
}

function Get-QuietScriptAnalysisCacheKey {
    <#
    .SYNOPSIS
    Returns the per-file cache key: relative path, content hash and configuration hash.
    .PARAMETER RelativePath
    Workspace-relative path; part of the key because a rule can depend on the location.
    .PARAMETER ContentSHA256
    SHA-256 of the file bytes.
    .PARAMETER ConfigurationSHA256
    Hash of the analyzer version, the settings and the custom rules.
    #>
    param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$ContentSHA256,[Parameter(Mandatory)][string]$ConfigurationSHA256)
    Get-QuietScriptAnalysisSha256 ('v1'+[char]0x1F+$RelativePath.Replace('\','/')+[char]0x1F+$ContentSHA256.ToUpperInvariant()+[char]0x1F+$ConfigurationSHA256.ToUpperInvariant())
}

Export-ModuleMember -Function Compare-QuietScriptAnalysisBaseline,Get-QuietScriptAnalysisFindingKey,Get-QuietScriptAnalysisSha256,Get-QuietScriptAnalysisFunctionName,ConvertTo-QuietScriptAnalysisFinding,ConvertTo-QuietScriptAnalysisBaseline,Read-QuietScriptAnalysisBaseline,Read-QuietScriptAnalysisSettings,Test-QuietScriptAnalysisTestContainer,Get-QuietScriptAnalysisFiles,Get-QuietScriptAnalysisCacheKey
