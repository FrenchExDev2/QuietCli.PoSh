#Objective: Inventories scripts/lib exports against the script tests that reference them and enforces a shrink-only list of untested exports.
#requires -Version 7.6

function Get-QuietScriptsLibraryExports {
    <#
    .SYNOPSIS
    Returns {Key, Library, Name} for every function a scripts/lib module exports through its single literal Export-ModuleMember.
    .PARAMETER ScriptsRoot
    Scripts directory whose lib/*.psm1 files are read.
    #>
    param([Parameter(Mandatory)][string]$ScriptsRoot)
    $lib=[IO.Path]::Combine([IO.Path]::GetFullPath($ScriptsRoot),'lib')
    if(![IO.Directory]::Exists($lib)){throw 'ScriptsInventoryPathInvalid: scripts-root'}
    foreach($file in @(Get-ChildItem -LiteralPath $lib -Filter '*.psm1' -File|Sort-Object Name)){
        $library='lib/'+$file.Name
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ('ScriptsInventoryExportsInvalid: '+$library+' does not parse')}
        $exports=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Export-ModuleMember'},$true))
        if($exports.Count -ne 1){throw ('ScriptsInventoryExportsInvalid: '+$library+' has '+$exports.Count+' Export-ModuleMember')}
        $elements=$exports[0].CommandElements
        # The last -Function parameter wins, as in the binder; its list is the next element (absent when it ends the command).
        $index=0
        foreach($element in $elements){if($element -is [Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -ieq 'Function'){$index=$elements.IndexOf($element)+1}}
        if(!$index -or $index -ge $elements.Count){throw ('ScriptsInventoryExportsInvalid: '+$library+' exports no -Function list')}
        $value=$elements[$index]
        $names=if($value -is [Management.Automation.Language.ArrayLiteralAst]){@($value.Elements)}else{@($value)}
        foreach($name in $names){
            if($name -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $name.Value -cnotmatch '\A[A-Za-z][A-Za-z0-9]*-[A-Za-z0-9]+\z'){throw ('ScriptsInventoryExportsInvalid: '+$library+' exports '+$name.Extent.Text)}
            [pscustomobject]@{Key=$library+'::'+$name.Value;Library=$library;Name=$name.Value}
        }
    }
}

function Get-QuietScriptsTestInventory {
    <#
    .SYNOPSIS
    Returns {Key, Library, Name, Tests} for every export; Tests lists the *.Tests.ps1 files (relative to TestsRoot) that name it as a command word.
    .PARAMETER ScriptsRoot
    Scripts directory under inventory.
    .PARAMETER TestsRoot
    test/scripts directory searched recursively.
    #>
    param([Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$TestsRoot)
    $TestsRoot=[IO.Path]::GetFullPath($TestsRoot)
    if(![IO.Directory]::Exists($TestsRoot)){throw 'ScriptsInventoryPathInvalid: tests-root'}
    $files=@(Get-ChildItem -LiteralPath $TestsRoot -Filter '*.Tests.ps1' -File -Recurse|Sort-Object FullName|ForEach-Object {
        [pscustomobject]@{Path=[IO.Path]::GetRelativePath($TestsRoot,$_.FullName).Replace('\','/');Text=[IO.File]::ReadAllText($_.FullName)}
    })
    foreach($export in @(Get-QuietScriptsLibraryExports -ScriptsRoot $ScriptsRoot)){
        $pattern='(?<![A-Za-z0-9_-])'+[regex]::Escape($export.Name)+'(?![A-Za-z0-9_-])'
        $tests=@($files|Where-Object {[regex]::IsMatch($_.Text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)}|ForEach-Object Path)
        [pscustomobject]@{Key=$export.Key;Library=$export.Library;Name=$export.Name;Tests=[string[]]$tests}
    }
}

function Read-QuietScriptsTestInventoryBaseline {
    <#
    .SYNOPSIS
    Reads {SchemaVersion=1, Untested=[sorted unique 'lib/<File>.psm1::<Function>' keys]} and rejects any other shape.
    .PARAMETER Path
    coverage.inventory.json.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if(![IO.File]::Exists($Path)){throw 'ScriptsInventoryBaselineMissing'}
    try{$document=[IO.File]::ReadAllText($Path,[Text.Encoding]::GetEncoding('utf-8',[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback))|ConvertFrom-Json -AsHashtable}catch{throw 'ScriptsInventoryBaselineInvalid: syntax'}
    if($document -isnot [Collections.IDictionary] -or $document.Count -ne 2 -or !$document.ContainsKey('SchemaVersion') -or $document['SchemaVersion'] -isnot [long] -or $document['SchemaVersion'] -ne 1 -or !$document.ContainsKey('Untested')){throw 'ScriptsInventoryBaselineInvalid: shape'}
    $untested=@($document['Untested'])
    foreach($key in $untested){if($key -isnot [string] -or $key -cnotmatch '\Alib/[A-Za-z0-9][A-Za-z0-9.-]*\.psm1::[A-Za-z][A-Za-z0-9]*-[A-Za-z0-9]+\z'){throw 'ScriptsInventoryBaselineInvalid: key'}}
    $sorted=[string[]]@($untested|Sort-Object -Unique -CaseSensitive)
    if(($sorted -join "`n") -cne ($untested -join "`n")){throw 'ScriptsInventoryBaselineInvalid: order'}
    [pscustomobject]@{SchemaVersion=1;Untested=$sorted}
}

function Compare-QuietScriptsTestInventory {
    <#
    .SYNOPSIS
    Returns {Passed, Exports, Tested, Baselined, New, Stale, Pruned}: New are untested exports missing from the baseline, Stale are baseline keys now tested or no longer exported.
    .PARAMETER Inventory
    Get-QuietScriptsTestInventory rows.
    .PARAMETER Baseline
    Read-QuietScriptsTestInventoryBaseline result.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Inventory,[Parameter(Mandatory)]$Baseline)
    $listed=[Collections.Generic.HashSet[string]]::new([string[]]@($Baseline.Untested),[StringComparer]::Ordinal)
    $untested=@($Inventory|Where-Object {@($_.Tests).Count -eq 0}|ForEach-Object Key)
    $current=[Collections.Generic.HashSet[string]]::new([string[]]$untested,[StringComparer]::Ordinal)
    $new=[string[]]@($untested|Where-Object {!$listed.Contains($_)}|Sort-Object -CaseSensitive)
    $stale=[string[]]@($Baseline.Untested|Where-Object {!$current.Contains($_)})
    $kept=[string[]]@($Baseline.Untested|Where-Object {$current.Contains($_)})
    [pscustomobject][ordered]@{
        Passed=($new.Count -eq 0 -and $stale.Count -eq 0);Exports=$Inventory.Count;Tested=$Inventory.Count-$untested.Count;Baselined=$kept.Count
        New=$new;Stale=$stale;Pruned=[pscustomobject][ordered]@{SchemaVersion=1;Untested=$kept}
    }
}

Export-ModuleMember -Function Get-QuietScriptsLibraryExports,Get-QuietScriptsTestInventory,Read-QuietScriptsTestInventoryBaseline,Compare-QuietScriptsTestInventory
