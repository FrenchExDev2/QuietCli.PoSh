# Git syntax belongs exclusively to this module.
function Get-GitInvocation {
    <#
    .SYNOPSIS
    Binds Git global options and the command without executing a binary.
    .PARAMETER Invocation
    Caller request containing the original native ArgumentList.
    #>
    param([hashtable]$Invocation)
    $arguments = @($Invocation.ArgumentList); $global = [Collections.Generic.List[string]]::new(); $globalNames = [Collections.Generic.List[string]]::new(); $position = 0; $name = $null
    $takesValue = @('-C', '-c', '--git-dir', '--work-tree', '--namespace', '--config-env', '--super-prefix', '--attr-source', '--shallow-file')
    while ($position -lt $arguments.Count) {
        $value = [string]$arguments[$position]
        if ($value -cin @('--version', '-v')) { $name = 'version'; $position++; break }
        if ($value -cin @('--help', '-h')) { $name = 'help'; $position++; break }
        if ($value -cin @('--html-path', '--man-path', '--info-path', '--exec-path') -or $value.StartsWith('--list-cmds=')) { $name = '$root'; break }
        if ($value.StartsWith('--exec-path=')) { $global.Add($value); $globalNames.Add('--exec-path='); $position++; continue }
        if (!$value.StartsWith('-')) { $name = $value; $position++; break }
        $global.Add($value); $key = ($value -split '=', 2)[0]
        $globalNames.Add($(if ($value.Contains('=')) { $key + '=' }elseif ($value -cmatch '^-(?:C|c).+') { $value.Substring(0, 2) }else { $key }))
        if ($key -cin $takesValue -and !$value.Contains('=')) {
            $position++; if ($position -ge $arguments.Count) { return @{Error = 'ArgumentsUnsupported'; Reason = "Global option $key requires a value." } }
            $global.Add([string]$arguments[$position])
        }
        elseif ($key -cnotin $takesValue -and $key -cnotin @('-p', '-P', '--paginate', '--no-pager', '--bare', '--no-replace-objects', '--no-lazy-fetch', '--no-optional-locks', '--no-advice', '--literal-pathspecs', '--no-literal-pathspecs', '--glob-pathspecs', '--noglob-pathspecs', '--icase-pathspecs') -and $value -cnotmatch '^-(?:C|c).+') {
            return @{Error = 'ArgumentsUnsupported'; Reason = "Unknown Git global option: $value" }
        }
        $position++
    }
    if (!$name) { $name = '$root' }
    $tail = @(if ($position -lt $arguments.Count) { $arguments[$position..($arguments.Count - 1)] })
    @{Name = $name; Global = $global.ToArray(); GlobalNames = $globalNames.ToArray(); Arguments = $tail; Original = @($Invocation.ArgumentList) }
}
function Get-GitNumericVersion {
    <#
    .SYNOPSIS
    Normalizes a stable Git version, including Windows package suffixes.
    .PARAMETER Version
    Observed version string; unsupported formats produce no value.
    #>
    param([string]$Version)
    if ($Version -match '^(2\.\d+\.\d+)(?:\.windows\.\d+)?$') { [version]$Matches[1] }
}
