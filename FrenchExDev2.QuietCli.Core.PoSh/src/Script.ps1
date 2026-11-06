function Initialize-QuietCallFactories {
    <#
    .SYNOPSIS
    Creates invocation-local business values before engine initialization.
    .PARAMETER Request
    Validated options, copied before evaluating zero-argument factories.
    #>
    param([hashtable]$Request)
    $copy = $Request.Clone()
    foreach ($name in @('Data', 'State')) {
        $factory = $name + 'Factory'
        if (!$copy.ContainsKey($factory)) { continue }
        $values = @(& $copy[$factory])
        if ($values.Count -ne 1) { throw "QuietFactoryMustReturnOneValue: $factory" }
        if ($name -eq 'State' -and $values[0] -isnot [hashtable]) { throw 'QuietStateFactoryMustReturnHashtable' }
        $copy[$name] = $values[0]
        $copy.Remove($factory)
    }
    return $copy
}

function ConvertTo-QuietScriptLiteral {
    <#
    .SYNOPSIS
    Emits bounded PowerShell literals without evaluating arbitrary objects.
    .PARAMETER Value
    A primitive, array, hashtable or ordered dictionary.
    .PARAMETER Budget
    Shared node budget and ancestor references for cycle detection.
    .PARAMETER Depth
    Current nesting depth, limited to 32.
    #>
    param([AllowNull()]$Value, [hashtable]$Budget = @{ Nodes = 0; Characters = 0; Ancestors = [Collections.Generic.List[object]]::new() }, [int]$Depth = 0)
    $Budget.Nodes++
    if ($Depth -gt 32 -or $Budget.Nodes -gt 10000) { throw 'QuietScriptLiteralLimit' }
    if ($null -eq $Value) { return '$null' }
    $type = $Value.GetType()
    if ($type -eq [string] -or $type -eq [char]) {
        $text = [string]$Value
        $Budget.Characters += $text.Length
        if ($Budget.Characters -gt 1048576) { throw 'QuietScriptLiteralLimit' }
        $literal = "'" + $text.Replace("'", "''").Replace("`r", "' + [char]13 + '").Replace("`n", "' + [char]10 + '") + "'"
        if ($type -eq [char]) { return "[char]($literal)" }
        return "($literal)"
    }
    if ($type -eq [bool]) { if ($Value) { return '$true' }; return '$false' }
    $numbers = @('System.Byte','System.SByte','System.Int16','System.UInt16','System.Int32','System.UInt32','System.Int64','System.UInt64','System.Single','System.Double','System.Decimal')
    if ($type.FullName -in $numbers) {
        if (($type -eq [double] -and ![double]::IsFinite($Value)) -or ($type -eq [single] -and ![single]::IsFinite($Value))) { throw 'QuietScriptNonFiniteNumber' }
        $format = if ($type -in @([single], [double])) { 'R' } else { $null }
        $text = $Value.ToString($format, [Globalization.CultureInfo]::InvariantCulture)
        return "[$($type.FullName)]::Parse('$text', [Globalization.CultureInfo]::InvariantCulture)"
    }
    if ($Value -isnot [array] -and $type -ne [hashtable] -and $type -ne [Collections.Specialized.OrderedDictionary]) {
        throw "QuietScriptUnsupportedValue: $($type.FullName). Use DataFactory or StateFactory for complex business values."
    }
    foreach ($ancestor in $Budget.Ancestors) { if ([object]::ReferenceEquals($ancestor, $Value)) { throw 'QuietScriptCyclicValue' } }
    $Budget.Ancestors.Add($Value)
    try {
        $parts = [Collections.Generic.List[string]]::new()
        if ($Value -is [array]) {
            if ($Value.Rank -ne 1) { throw 'QuietScriptMultidimensionalArray' }
            $element = $type.GetElementType()
            if ($element.FullName -notin ($numbers + @('System.Object','System.String','System.Char','System.Boolean'))) { throw 'QuietScriptUnsupportedArrayType' }
            foreach ($item in $Value) { $parts.Add((ConvertTo-QuietScriptLiteral -Value $item -Budget $Budget -Depth ($Depth + 1))) }
            return "[$($element.FullName)[]]@(" + ($parts -join ', ') + ')'
        }
        foreach ($key in $Value.Keys) {
            $keyLiteral = ConvertTo-QuietScriptLiteral -Value $key -Budget $Budget -Depth ($Depth + 1)
            $itemLiteral = ConvertTo-QuietScriptLiteral -Value $Value[$key] -Budget $Budget -Depth ($Depth + 1)
            $parts.Add("$keyLiteral = $itemLiteral")
        }
        $prefix = if ($type -eq [hashtable]) { '@{' } else { '[ordered]@{' }
        return $prefix + ($parts -join '; ') + '}'
    }
    finally { $Budget.Ancestors.RemoveAt($Budget.Ancestors.Count - 1) }
}

function Export-QuietCallScript {
    <#
    .SYNOPSIS
    Writes an explicit call definition without executing callbacks or native code.
    .PARAMETER Request
    Explicit facade options before configuration defaults are applied.
    #>
    param([hashtable]$Request)
    if (!$Request.ContainsKey('Output') -and !$Request.ContainsKey('Complete')) { throw 'QuietScriptCallbackRequired' }
    foreach ($key in $Request.Keys) {
        if ($key -match 'Recall|^(SaveRecall|Zip|Compress|AllowPartial|CancellationToken)$') { throw "QuietScriptUnsupportedOption: $key" }
    }
    $path = [IO.Path]::GetFullPath([string]$Request.Script, (Get-Location).Path)
    if ([IO.Path]::GetExtension($path) -ine '.ps1') { throw 'QuietScriptExtensionRequired' }
    if (![IO.Directory]::Exists([IO.Path]::GetDirectoryName($path))) { throw 'QuietScriptParentMissing' }
    if ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) { throw 'QuietScriptAlreadyExists' }
    $budget = @{ Nodes = 0; Characters = 0; Ancestors = [Collections.Generic.List[object]]::new() }
    $binary = ConvertTo-QuietScriptLiteral -Value $Request.FilePath -Budget $budget
    $arguments = ConvertTo-QuietScriptLiteral -Value ([string[]]$Request.ArgumentList) -Budget $budget
    $directory = if ($Request.ContainsKey('WorkingDirectory')) { [IO.Path]::GetFullPath([string]$Request.WorkingDirectory, (Get-Location).Path) } else { (Get-Location).Path }
    $working = ConvertTo-QuietScriptLiteral -Value $directory -Budget $budget
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add(@'
#requires -Version 7.6
#requires -PSEdition Core
<#
.SYNOPSIS
Executes a reusable QuietCli call with fresh business initialization.
.DESCRIPTION
External variables, functions and modules used by callbacks must be supplied explicitly.
Closures are not captured. Explicit option values, including environment values, are stored here.
Unspecified options use the active QuietCli configuration when this script executes.
.PARAMETER FilePath
Native executable, resolved only when executing this script.
.PARAMETER ArgumentList
Exact native arguments.
.PARAMETER WorkingDirectory
Native working directory; defaults to the directory selected during generation.
#>
'@)
    $lines.Add("param([string]`$FilePath = $binary, [string[]]`$ArgumentList = $arguments, [string]`$WorkingDirectory = $working)")
    $lines.Add(@'
if (!(Get-Module -Name FrenchExDev2.QuietCli.Core.PoSh)) {
    Import-Module FrenchExDev2.QuietCli.Core.PoSh -MinimumVersion 0.2.0 -ErrorAction Stop
}
$quietArguments = [Collections.Generic.List[object]]::new()
'@)
    foreach ($key in @($Request.Keys | Sort-Object)) {
        if ($key -in @('Script','FilePath','ArgumentList','WorkingDirectory')) { continue }
        $value = $Request[$key]
        if ($key -in @('Output','Complete','DataFactory','StateFactory','Interaction')) {
            if ($value -isnot [scriptblock]) { throw "QuietScriptCallbackMustBeScriptBlock: $key" }
            $literal = "{`n" + $value.ToString() + "`n}"
        }
        else { $literal = ConvertTo-QuietScriptLiteral -Value $value -Budget $budget }
        $switches = @('AsObject','AsJson','AsYaml')
        if ($key -in $switches) {
            $lines.Add("`$quietArguments.Add('-${key}:$([bool]$value)')")
        }
        else {
            $lines.Add("`$quietArguments.Add('-$key')")
            $lines.Add("`$quietArguments.Add(($literal))")
        }
    }
    $lines.Add(@'
$quietArguments.Add('-WorkingDirectory')
$quietArguments.Add($WorkingDirectory)
$quietArguments.Add('-FilePath')
$quietArguments.Add($FilePath)
$quietArguments.Add('-ArgumentList')
$quietArguments.Add($ArgumentList)
$callArguments = $quietArguments.ToArray()
FrenchExDev2.QuietCli.Core.PoSh\Invoke-QuietCli @callArguments
'@)
    $source = (($lines -join "`n").Replace("`r`n", "`n").Replace("`r", "`n")) + "`n"
    if ($source.Length -gt 2097152) { throw 'QuietScriptSourceLimit' }
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ('QuietScriptInvalidSource: ' + $errors[0].Message) }
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, $true)
        $bytes = $script:QuietUtf8.GetBytes($source)
        [void]$stream.WriteAsync($bytes, 0, $bytes.Length).GetAwaiter().GetResult()
        $stream.Dispose(); $stream = $null
    }
    catch {
        if ($null -ne $stream) { $stream.Dispose(); [IO.File]::Delete($path) }
        throw
    }
    return [IO.FileInfo]::new($path)
}
