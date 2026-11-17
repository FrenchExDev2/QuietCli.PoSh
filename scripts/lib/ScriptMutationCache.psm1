#Objective: Incremental mutation cache: content-addressed keys per mutant over everything its tests can observe, and validated documents.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietScriptMutationSha256 {
    <#
    .SYNOPSIS
    Lowercase hex SHA-256 of a UTF-8 string.
    .PARAMETER Text
    Text to hash.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Get-QuietScriptMutationFilesDigest {
    <#
    .SYNOPSIS
    Hashes a set of files as their paths relative to Root plus the SHA-256 of their bytes, in ordinal order.
    .PARAMETER Root
    Directory the recorded paths are relative to.
    .PARAMETER Paths
    Full file paths; duplicates count once.
    #>
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
    $lines=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in $Paths){[void]$lines.Add([IO.Path]::GetRelativePath($Root,$path).Replace('\','/')+[char]0x1F+(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)}
    Get-QuietScriptMutationSha256 (@($lines) -join "`n")
}

function Get-QuietScriptMutationTreeFiles {
    <#
    .SYNOPSIS
    Lists the files under a directory, skipping links; nothing when it does not exist.
    .PARAMETER Directory
    Directory to walk.
    #>
    param([Parameter(Mandatory)][string]$Directory)
    if(![IO.Directory]::Exists($Directory)){return}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Directory)
    while($pending.Count){
        foreach($entry in [IO.DirectoryInfo]::new($pending.Pop()).EnumerateFileSystemInfos()){
            if($entry.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){continue}
            if($entry -is [IO.DirectoryInfo]){$pending.Push($entry.FullName)}else{$entry.FullName}
        }
    }
}

function Get-QuietScriptMutationTestFingerprint {
    <#
    .SYNOPSIS
    Hashes the test side of a target: its unit test files plus every tests-root file outside unit/ and integration/.
    .DESCRIPTION
    That covers support modules, analyzer rules and settings. README.md, mutation.targets.psd1, coverage.inventory.json
    and ScriptAnalyzer.baseline.json at the tests root are left out: they are bookkeeping no unit test reads. Any edit,
    addition, removal or rename of a covered file changes the fingerprint. Links are skipped.
    .PARAMETER TestsRoot
    Tests root.
    .PARAMETER UnitTestFiles
    Unit test files of the target, relative to the tests root.
    #>
    param([Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string[]]$UnitTestFiles)
    $TestsRoot=[IO.Path]::GetFullPath($TestsRoot)
    # Test-root files that no unit test reads: bookkeeping that changes often and would otherwise invalidate every target.
    $bookkeeping=@('README.md','mutation.targets.psd1','coverage.inventory.json','ScriptAnalyzer.baseline.json')
    $files=[Collections.Generic.List[string]]::new()
    foreach($relative in $UnitTestFiles){
        $path=[IO.Path]::GetFullPath([IO.Path]::Combine($TestsRoot,$relative))
        if(![IO.File]::Exists($path)){throw "ScriptMutationCacheTestMissing: $relative"}
        $files.Add($path)
    }
    foreach($path in Get-QuietScriptMutationTreeFiles $TestsRoot){
        $relative=[IO.Path]::GetRelativePath($TestsRoot,$path).Replace('\','/')
        if($relative -cmatch '^(unit|integration)/' -or $relative -cin $bookkeeping){continue}
        $files.Add($path)
    }
    Get-QuietScriptMutationFilesDigest -Root $TestsRoot -Paths $files.ToArray()
}

function Get-QuietScriptMutationSourceFingerprint {
    <#
    .SYNOPSIS
    Hashes the scripts side of a target: its module plus every scripts file reachable from it or from its tests.
    .DESCRIPTION
    Digest of Get-QuietScriptMutationSourceFiles, with paths relative to the scripts root.
    .PARAMETER ScriptsRoot
    Unmutated scripts root.
    .PARAMETER Module
    Target module, relative to the scripts root.
    .PARAMETER TestsRoot
    Tests root.
    .PARAMETER UnitTestFiles
    Unit test files of the target, relative to the tests root.
    #>
    param([Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$Module,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string[]]$UnitTestFiles)
    Get-QuietScriptMutationFilesDigest -Root ([IO.Path]::GetFullPath($ScriptsRoot)) -Paths @(Get-QuietScriptMutationSourceFiles -ScriptsRoot $ScriptsRoot -Module $Module -TestsRoot $TestsRoot -UnitTestFiles $UnitTestFiles)
}

function Get-QuietScriptMutationSourceFiles {
    <#
    .SYNOPSIS
    Returns, as full paths in ordinal order, the module plus every scripts file reachable from it or from the given tests.
    .DESCRIPTION
    The closure starts from the module, the libraries the given test files and the support modules name, then follows
    every '<name>.psm1' or '<name>.ps1' file name that ends a quoted literal (with or without a path before it) and every
    Import-QuietTestLibrary name found in the included files,
    resolved under lib/ and the scripts root. Over-inclusion only costs reuse; a dependency the scan cannot see (a name
    built at run time) is the one way to miss an edit, so libraries import each other by literal file name.
    .PARAMETER ScriptsRoot
    Unmutated scripts root.
    .PARAMETER Module
    Starting script or module, relative to the scripts root; empty starts from the test files alone.
    .PARAMETER TestsRoot
    Tests root.
    .PARAMETER UnitTestFiles
    Test files whose references join the closure, relative to the tests root; may be empty.
    #>
    param([Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][AllowEmptyString()][string]$Module,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$UnitTestFiles)
    $ScriptsRoot=[IO.Path]::GetFullPath($ScriptsRoot);$TestsRoot=[IO.Path]::GetFullPath($TestsRoot)
    $modulePath=if($Module){[IO.Path]::GetFullPath([IO.Path]::Combine($ScriptsRoot,$Module))}
    if($Module -and ![IO.File]::Exists($modulePath)){throw "ScriptMutationCacheModuleMissing: $Module"}
    # A file name ends a quoted literal and starts it or follows a path separator: 'A.psm1', "../B.ps1", "$PSScriptRoot/C.psm1".
    $pattern=[regex]::new('[''"/\\]([A-Za-z0-9][A-Za-z0-9._-]*)\.(psm1|ps1)[''"]|Import-QuietTestLibrary\s+(?:-Name\s+)?[''"]?([A-Za-z0-9][A-Za-z0-9._-]*)')
    $referenced={param([string]$Path)
        foreach($match in $pattern.Matches([IO.File]::ReadAllText($Path))){
            $names=if($match.Groups[3].Success){@($match.Groups[3].Value+'.psm1')}else{@($match.Groups[1].Value+'.'+$match.Groups[2].Value)}
            foreach($name in $names){
                foreach($candidate in [IO.Path]::Combine($ScriptsRoot,'lib',$name),[IO.Path]::Combine($ScriptsRoot,$name)){if([IO.File]::Exists($candidate)){[IO.Path]::GetFullPath($candidate)}}
            }
        }
    }
    $included=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pending=[Collections.Generic.Queue[string]]::new()
    if($modulePath){[void]$included.Add($modulePath);$pending.Enqueue($modulePath)}
    $roots=@(foreach($relative in $UnitTestFiles){
        $path=[IO.Path]::GetFullPath([IO.Path]::Combine($TestsRoot,$relative))
        if(![IO.File]::Exists($path)){throw "ScriptMutationCacheTestMissing: $relative"}
        $path
    })+@(Get-QuietScriptMutationTreeFiles ([IO.Path]::Combine($TestsRoot,'support')))
    foreach($root in $roots){foreach($path in & $referenced $root){if($included.Add($path)){$pending.Enqueue($path)}}}
    while($pending.Count){foreach($path in & $referenced $pending.Dequeue()){if($included.Add($path)){$pending.Enqueue($path)}}}
    $files=[string[]]@($included);[Array]::Sort($files,[StringComparer]::Ordinal)
    $files
}

function Get-QuietScriptMutationInputsFingerprint {
    <#
    .SYNOPSIS
    Hashes the repository files a target's unit tests read, named by the target's Inputs globs.
    .DESCRIPTION
    Digest of Get-QuietScriptMutationInputFiles. A pattern without a match still contributes its text, so adding the
    first matching file changes the fingerprint.
    .PARAMETER WorkspaceRoot
    Repository root the patterns are relative to.
    .PARAMETER Inputs
    Validated patterns from the targets file.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[AllowEmptyCollection()][string[]]$Inputs=@())
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot)
    $files=@(Get-QuietScriptMutationInputFiles -WorkspaceRoot $WorkspaceRoot -Inputs $Inputs)
    Get-QuietScriptMutationSha256 ((@($Inputs|Sort-Object -CaseSensitive) -join "`n")+[char]0x1E+(Get-QuietScriptMutationFilesDigest -Root $WorkspaceRoot -Paths $files))
}

function Get-QuietScriptMutationInputFiles {
    <#
    .SYNOPSIS
    Returns the full paths of the repository files that a target's Inputs globs name.
    .DESCRIPTION
    '*' matches within one path segment and '**' across segments. Each pattern only walks the directory before its
    first wildcard. Links are skipped.
    .PARAMETER WorkspaceRoot
    Repository root the patterns are relative to.
    .PARAMETER Inputs
    Validated patterns from the targets file.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[AllowEmptyCollection()][string[]]$Inputs=@())
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot)
    $files=[Collections.Generic.List[string]]::new()
    foreach($glob in $Inputs){
        $segments=$glob.Split('/')
        $fixed=[Collections.Generic.List[string]]::new()
        foreach($segment in $segments){if($segment.Contains('*')){break};$fixed.Add($segment)}
        # [string[]]: an object[] argument would bind Combine(string) and stringify the array.
        $base=[IO.Path]::Combine([string[]](@($WorkspaceRoot)+$fixed.ToArray()))
        $builder=[Text.StringBuilder]::new('^')
        for($index=0;$index -lt $segments.Count;$index++){
            $last=$index -eq $segments.Count-1
            if($segments[$index] -ceq '**'){[void]$builder.Append($(if($last){'.*'}else{'(?:[^/]+/)*'}))}
            else{[void]$builder.Append([regex]::Escape($segments[$index]).Replace('\*','[^/]*'));if(!$last){[void]$builder.Append('/')}}
        }
        [void]$builder.Append('$')
        $regex=[regex]::new($builder.ToString())
        $candidates=if($fixed.Count -eq $segments.Count){if([IO.File]::Exists($base)){$base}}else{Get-QuietScriptMutationTreeFiles $base}
        foreach($path in $candidates){if($regex.IsMatch([IO.Path]::GetRelativePath($WorkspaceRoot,$path).Replace('\','/'))){$files.Add($path)}}
    }
    $files.ToArray()
}

function Get-QuietScriptMutationTargetFingerprint {
    <#
    .SYNOPSIS
    Combines the source, test and repository-input fingerprints of one target.
    .PARAMETER ScriptsRoot
    Unmutated scripts root.
    .PARAMETER TestsRoot
    Tests root.
    .PARAMETER WorkspaceRoot
    Repository root of the Inputs patterns.
    .PARAMETER Target
    Target with Module, UnitTestFiles and optional Inputs.
    #>
    param([Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)]$Target)
    $files=[string[]]@($Target.UnitTestFiles)
    $inputs=[string[]]@(if($Target -is [Collections.IDictionary]){if($Target.Contains('Inputs')){$Target.Inputs}}elseif($Target.PSObject.Properties['Inputs']){$Target.Inputs})
    $parts=@(
        (Get-QuietScriptMutationSourceFingerprint -ScriptsRoot $ScriptsRoot -Module ([string]$Target.Module) -TestsRoot $TestsRoot -UnitTestFiles $files)
        (Get-QuietScriptMutationTestFingerprint -TestsRoot $TestsRoot -UnitTestFiles $files)
        (Get-QuietScriptMutationInputsFingerprint -WorkspaceRoot $WorkspaceRoot -Inputs @($inputs|Where-Object {$_}))
    )
    Get-QuietScriptMutationSha256 ($parts -join [char]0x1F)
}

function Get-QuietScriptMutantCacheKeys {
    <#
    .SYNOPSIS
    Returns a dictionary from mutant id to its cache key.
    .DESCRIPTION
    A key hashes the cache schema, the engine fingerprint (Pester, PowerShell, platform), the target fingerprint and
    the mutant itself (module, mutator, offsets, replacement). Any edit that the target's tests could observe changes
    the target fingerprint and so every key of the target.
    .PARAMETER Mutants
    Mutants from Get-QuietScriptMutants.
    .PARAMETER TargetFingerprint
    Result of Get-QuietScriptMutationTargetFingerprint.
    .PARAMETER EngineFingerprint
    Identifies the test runtime, for example 'Pester=6.2.0;PowerShell=7.6.0;Platform=win-x64'.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Mutants,[Parameter(Mandatory)][string]$TargetFingerprint,[Parameter(Mandatory)][string]$EngineFingerprint)
    $keys=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($mutant in $Mutants){
        $identity=@('2',$EngineFingerprint,$TargetFingerprint,[string]$mutant.Module,[string]$mutant.Function,[string]$mutant.Mutator,[string]$mutant.StartOffset,[string]$mutant.EndOffset,[string]$mutant.Replacement) -join [char]0x1F
        $keys[[string]$mutant.Id]=Get-QuietScriptMutationSha256 $identity
    }
    $keys
}

function Get-QuietScriptMutantCachePath {
    <#
    .SYNOPSIS
    Path of one cache document: <Directory>/<first two key characters>/<key>.json.
    .PARAMETER Directory
    Cache root.
    .PARAMETER Key
    64-character lowercase hex key.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Key)
    if($Key -cnotmatch '^[0-9a-f]{64}$'){throw 'ScriptMutationCacheKeyInvalid'}
    [IO.Path]::Combine($Directory,$Key.Substring(0,2),$Key+'.json')
}

function Read-QuietScriptMutationCacheDocument {
    <#
    .SYNOPSIS
    Returns the JSON object stored at a path, or nothing when the file is missing, unreadable, not UTF-8 or not an object.
    .PARAMETER Path
    Cache document path.
    #>
    param([Parameter(Mandatory)][string]$Path)
    # Strict UTF-8: an invalid byte fails the read instead of decoding to U+FFFD.
    $strict=[Text.Encoding]::GetEncoding('utf-8',[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
    $document=try{[IO.File]::ReadAllText($Path,$strict)|ConvertFrom-Json -ErrorAction Stop}catch{$null}
    # [pscustomobject] tests [psobject], which every JSON value wrapped by ConvertFrom-Json is; only an object qualifies.
    if($document -is [Management.Automation.PSCustomObject]){$document}
}

function Get-QuietScriptMutationCacheValue {
    <#
    .SYNOPSIS
    Returns one property of a cache document, or nothing when it is absent.
    .PARAMETER Document
    Object from Read-QuietScriptMutationCacheDocument.
    .PARAMETER Name
    Property name.
    #>
    param([Parameter(Mandatory)]$Document,[Parameter(Mandatory)][string]$Name)
    $property=$Document.PSObject.Properties[$Name]
    if($property){$property.Value}
}

function Read-QuietScriptMutantCache {
    <#
    .SYNOPSIS
    Returns the cached {Status, Seconds, Seed} of a key, or $null on a miss or an unusable document.
    .DESCRIPTION
    Only Killed and Survived are ever cached. A document that does not parse, carries another schema, another key or
    another status is treated as a miss and is overwritten by the next run.
    .PARAMETER Directory
    Cache root.
    .PARAMETER Key
    Cache key.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Key)
    $document=Read-QuietScriptMutationCacheDocument (Get-QuietScriptMutantCachePath -Directory $Directory -Key $Key)
    if($null -eq $document){return}
    if([string](Get-QuietScriptMutationCacheValue $document 'SchemaVersion') -cne '1' -or [string](Get-QuietScriptMutationCacheValue $document 'Key') -cne $Key -or [string](Get-QuietScriptMutationCacheValue $document 'Status') -cnotin @('Killed','Survived')){return}
    $seconds=0.0
    if(![double]::TryParse([string](Get-QuietScriptMutationCacheValue $document 'Seconds'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -or $seconds -lt 0){return}
    [pscustomobject][ordered]@{Status=[string](Get-QuietScriptMutationCacheValue $document 'Status');Seconds=$seconds;Seed=[int](Get-QuietScriptMutationCacheValue $document 'Seed')}
}

function Write-QuietScriptMutantCache {
    <#
    .SYNOPSIS
    Records a Killed or Survived outcome; Timeout and CompileError are never cached. Returns true when written.
    .DESCRIPTION
    A timeout depends on machine load and a compile error is recomputed from the text for free, so neither is stored.
    .PARAMETER Directory
    Cache root.
    .PARAMETER Key
    Cache key.
    .PARAMETER Status
    Mutant status.
    .PARAMETER Seconds
    Run duration.
    .PARAMETER Seed
    Test seed of the run, kept for diagnosis only.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][AllowEmptyString()][string]$Status,[double]$Seconds,[int]$Seed)
    $path=Get-QuietScriptMutantCachePath -Directory $Directory -Key $Key
    if($Status -cnotin @('Killed','Survived')){return $false}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    # 0.0, not 0: an integer literal makes PowerShell pick Math.Max(int,int) and truncate the duration.
    Write-WorkspaceJson $path ([ordered]@{SchemaVersion=1;Key=$Key;Status=$Status;Seconds=[Math]::Round([Math]::Max(0.0,$Seconds),1);Seed=$Seed})
    $true
}

function Get-QuietScriptMutationBaselineKey {
    <#
    .SYNOPSIS
    Cache key of a target's baseline on one machine.
    .DESCRIPTION
    A baseline duration depends on the machine that measured it, so the key hashes the machine identity next to the
    engine and target fingerprints: a cache restored on another machine never reuses it, and the baseline runs again.
    .PARAMETER TargetFingerprint
    Result of Get-QuietScriptMutationTargetFingerprint.
    .PARAMETER EngineFingerprint
    Engine fingerprint of the campaign.
    .PARAMETER Machine
    Machine identity, for example the host name and the processor count.
    #>
    param([Parameter(Mandatory)][string]$TargetFingerprint,[Parameter(Mandatory)][string]$EngineFingerprint,[Parameter(Mandatory)][string]$Machine)
    Get-QuietScriptMutationSha256 (@('baseline','1',$EngineFingerprint,$TargetFingerprint,$Machine) -join [char]0x1F)
}

function Read-QuietScriptMutationBaseline {
    <#
    .SYNOPSIS
    Returns the recorded baseline {Passed, Seconds, Focus} of a key, or nothing on a miss or an unusable document.
    .DESCRIPTION
    Focus lists the functions whose focused split was proven on the baseline; it is empty when the document has none,
    and a Focus that is not a list of names makes the document unusable.
    .PARAMETER Directory
    Cache root.
    .PARAMETER Key
    Key from Get-QuietScriptMutationBaselineKey.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Key)
    $document=Read-QuietScriptMutationCacheDocument (Get-QuietScriptMutantCachePath -Directory $Directory -Key $Key)
    if($null -eq $document){return}
    if([string](Get-QuietScriptMutationCacheValue $document 'SchemaVersion') -cne '1' -or [string](Get-QuietScriptMutationCacheValue $document 'Kind') -cne 'Baseline' -or [string](Get-QuietScriptMutationCacheValue $document 'Key') -cne $Key){return}
    $passed=0;$seconds=0.0
    if(![int]::TryParse([string](Get-QuietScriptMutationCacheValue $document 'Passed'),[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$passed) -or $passed -lt 1){return}
    if(![double]::TryParse([string](Get-QuietScriptMutationCacheValue $document 'Seconds'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -or ![double]::IsFinite($seconds) -or $seconds -lt 0){return}
    $focus=@(Get-QuietScriptMutationCacheValue $document 'Focus')
    if(@($focus|Where-Object {$_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_)}).Count){return}
    [pscustomobject][ordered]@{Passed=$passed;Seconds=$seconds;Focus=[string[]]$focus}
}

function Write-QuietScriptMutationBaseline {
    <#
    .SYNOPSIS
    Records a passing baseline (test count, duration and proven focused functions) and returns true when written.
    .DESCRIPTION
    Only a baseline with at least one passed test and a finite, non-negative duration is stored: anything else would
    let a later campaign skip a baseline that never proved its tests pass.
    .PARAMETER Directory
    Cache root.
    .PARAMETER Key
    Key from Get-QuietScriptMutationBaselineKey.
    .PARAMETER Passed
    Passed test count of the baseline.
    .PARAMETER Seconds
    Baseline duration, which sets the mutant timeout.
    .PARAMETER Focus
    Functions whose focused split (Get-QuietScriptMutationFocus) passed with the baseline's test count.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][int]$Passed,[Parameter(Mandatory)][double]$Seconds,[AllowEmptyCollection()][string[]]$Focus=@())
    $path=Get-QuietScriptMutantCachePath -Directory $Directory -Key $Key
    if($Passed -lt 1 -or ![double]::IsFinite($Seconds) -or $Seconds -lt 0){return $false}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    Write-WorkspaceJson $path ([ordered]@{SchemaVersion=1;Kind='Baseline';Key=$Key;Passed=$Passed;Seconds=[Math]::Round($Seconds,1);Focus=[string[]]@($Focus)})
    $true
}

function Remove-QuietScriptMutantCacheUnused {
    <#
    .SYNOPSIS
    Deletes the cache documents whose key is not in Keys and returns how many were deleted.
    .DESCRIPTION
    Only <Directory>/<two hex>/<64 hex>.json documents are considered; any other file is left alone. Shard directories
    left empty are removed. A campaign calls this with every key it computed, so the cache keeps exactly the outcomes
    of the current sources and does not grow with each edit.
    .PARAMETER Directory
    Cache root; nothing happens when it does not exist.
    .PARAMETER Keys
    Keys to keep.
    #>
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Keys)
    if(![IO.Directory]::Exists($Directory)){return 0}
    $keep=[Collections.Generic.HashSet[string]]::new([string[]]$Keys,[StringComparer]::Ordinal)
    $removed=0
    foreach($shard in [IO.DirectoryInfo]::new($Directory).EnumerateDirectories()){
        if($shard.Name -cnotmatch '^[0-9a-f]{2}$' -or $shard.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){continue}
        foreach($file in $shard.EnumerateFiles('*.json')){
            $key=[IO.Path]::GetFileNameWithoutExtension($file.Name)
            if($key -cnotmatch '^[0-9a-f]{64}$' -or !$key.StartsWith($shard.Name,[StringComparison]::Ordinal) -or $keep.Contains($key)){continue}
            $file.Delete();$removed++
        }
        if(!$shard.EnumerateFileSystemInfos().GetEnumerator().MoveNext()){$shard.Delete()}
    }
    $removed
}

Export-ModuleMember -Function Get-QuietScriptMutationSha256,Get-QuietScriptMutationTreeFiles,Get-QuietScriptMutationTestFingerprint,Get-QuietScriptMutationSourceFingerprint,Get-QuietScriptMutationSourceFiles,Get-QuietScriptMutationInputsFingerprint,Get-QuietScriptMutationInputFiles,Get-QuietScriptMutationTargetFingerprint,Get-QuietScriptMutantCacheKeys,Get-QuietScriptMutantCachePath,Read-QuietScriptMutantCache,Write-QuietScriptMutantCache,Get-QuietScriptMutationBaselineKey,Read-QuietScriptMutationBaseline,Write-QuietScriptMutationBaseline,Remove-QuietScriptMutantCacheUnused
