#Objective: Standard for run profiles: named, data-only PowerShell files that bind a script to a set of default arguments.
#requires -Version 7.6
<#
.SYNOPSIS
Standard for run profiles: named, data-only PowerShell files that bind a script to a set of default arguments.

.DESCRIPTION
A profile is `<Name>.profile.psd1` holding one hashtable literal (SchemaVersion, Name, Description, Script, Parameters).
Files are parsed in restricted language mode (no commands, no variables other than $true/$false/$null), so a profile
can never run code. Creating a profile means writing that file; running one means merging caller arguments over its
parameters and invoking the target script.
#>
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunFormat.psm1')), ([IO.Path]::Combine($PSScriptRoot,'RunEncoding.psm1')) -DisableNameChecking

$script:SchemaVersion = 1
$script:NamePattern = '^[a-z0-9][a-z0-9-]{0,63}\z'
$script:ScriptPattern = '^[A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z'
$script:ParameterPattern = '^[A-Za-z_][A-Za-z0-9_]*\z'
$script:AllowedKeys = @('SchemaVersion', 'Name', 'Description', 'Script', 'Parameters')

function Get-RunProfileDirectory {
    <#
    .SYNOPSIS
    Resolves the directory holding profile files; defaults to scripts/RunProfiles.
    .PARAMETER Directory
    Optional override.
    #>
    param([string]$Directory)
    if ($Directory) { return [IO.Path]::GetFullPath($Directory) }
    return [IO.Path]::GetFullPath(([IO.Path]::Combine($PSScriptRoot,'../RunProfiles')))
}

function Get-RunScriptDirectory {
    <#
    .SYNOPSIS
    Resolves the directory holding target scripts; defaults to scripts/.
    .PARAMETER Directory
    Optional override.
    #>
    param([string]$Directory)
    if ($Directory) { return [IO.Path]::GetFullPath($Directory) }
    return [IO.Path]::GetFullPath(([IO.Path]::Combine($PSScriptRoot,'..')))
}

function Test-RunProfileName {
    <#
    .SYNOPSIS
    Tells whether a name is a valid profile name (lowercase letters, digits and hyphens, at most 64 characters).
    .PARAMETER Name
    Candidate name.
    #>
    param([AllowNull()][string]$Name)
    return $null -ne $Name -and $Name -cmatch $script:NamePattern
}

function Get-RunProfilePath {
    <#
    .SYNOPSIS
    Returns the file path of a named profile after validating the name.
    .PARAMETER Name
    Profile name.
    .PARAMETER Directory
    Profile directory override.
    #>
    param([Parameter(Mandatory)][string]$Name, [string]$Directory)
    if (-not (Test-RunProfileName $Name)) { throw "RunProfileInvalidName: '$Name'" }
    return [IO.Path]::Combine((Get-RunProfileDirectory $Directory),"$Name.profile.psd1")
}

function Get-RunProfileNames {
    <#
    .SYNOPSIS
    Lists the names of the profiles present in a directory, in ordinal order.
    .PARAMETER Directory
    Profile directory override.
    #>
    param([string]$Directory)
    $root = Get-RunProfileDirectory $Directory
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $names = foreach ($file in [IO.Directory]::EnumerateFiles($root, '*.profile.psd1')) {
        $name = [IO.Path]::GetFileName($file).Substring(0, [IO.Path]::GetFileName($file).Length - '.profile.psd1'.Length)
        if (Test-RunProfileName $name) { $name }
    }
    return @($names | Sort-Object -CaseSensitive)
}

function Test-RunProfileValue {
    <#
    .SYNOPSIS
    Tells whether a parameter value is representable in a profile: string, integer, double, boolean or arrays of them.
    .PARAMETER Value
    Candidate value.
    #>
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long]) { return $true }
    if ($Value -is [double]) { return -not ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) }
    if ($Value -is [Array]) { foreach ($item in $Value) { if (-not (Test-RunProfileValue $item)) { return $false } }; return $true }
    return $false
}

function Assert-RunProfile {
    <#
    .SYNOPSIS
    Validates a profile hashtable against the schema and throws a coded error on the first violation.
    .PARAMETER Profile
    Profile data.
    .PARAMETER ExpectedName
    When given, the profile Name must equal it (the file name).
    #>
    param([Parameter(Mandatory)]$Profile, [string]$ExpectedName)
    if ($Profile -isnot [hashtable]) { throw 'RunProfileMalformed: not a hashtable' }
    foreach ($key in $Profile.Keys) { if ($key -cnotin $script:AllowedKeys) { throw "RunProfileUnknownKey: $key" } }
    foreach ($key in @('SchemaVersion', 'Name', 'Script', 'Parameters')) { if (-not $Profile.ContainsKey($key)) { throw "RunProfileMissingKey: $key" } }
    if ($Profile.SchemaVersion -isnot [int] -or $Profile.SchemaVersion -ne $script:SchemaVersion) { throw "RunProfileUnsupportedSchema: $($Profile.SchemaVersion)" }
    if ($Profile.Name -isnot [string] -or -not (Test-RunProfileName $Profile.Name)) { throw "RunProfileInvalidName: '$($Profile.Name)'" }
    if ($ExpectedName -and $Profile.Name -cne $ExpectedName) { throw "RunProfileNameMismatch: file '$ExpectedName' declares '$($Profile.Name)'" }
    if ($Profile.ContainsKey('Description') -and $Profile.Description -isnot [string]) { throw 'RunProfileInvalidDescription' }
    if ($Profile.Script -isnot [string] -or $Profile.Script -cnotmatch $script:ScriptPattern) { throw "RunProfileInvalidScript: '$($Profile.Script)'" }
    if ($Profile.Parameters -isnot [hashtable]) { throw 'RunProfileInvalidParameters' }
    foreach ($key in $Profile.Parameters.Keys) {
        if ($key -isnot [string] -or $key -cnotmatch $script:ParameterPattern) { throw "RunProfileInvalidParameterName: '$key'" }
        if (-not (Test-RunProfileValue $Profile.Parameters[$key])) { throw "RunProfileUnsupportedValue: $key" }
    }
}

function Read-RunProfile {
    <#
    .SYNOPSIS
    Loads and validates a profile file without ever executing code from it.
    .PARAMETER Path
    Profile file path; its file name must be `<Name>.profile.psd1`.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $text = Read-RunTextFile -Path $Path
    $expected = [IO.Path]::GetFileName($Path)
    if (-not $expected.EndsWith('.profile.psd1', [StringComparison]::Ordinal)) { throw "RunProfileInvalidFileName: $expected" }
    $expected = $expected.Substring(0, $expected.Length - '.profile.psd1'.Length)
    try {
        $block = [scriptblock]::Create($text)
        $block.CheckRestrictedLanguage([string[]]@(), [string[]]@('true', 'false', 'null'), $false)
    }
    catch { throw "RunProfileNotDataOnly: $expected ($($_.Exception.Message))" }
    $data = @(& $block)
    if ($data.Count -ne 1) { throw "RunProfileMalformed: $expected yields $($data.Count) values" }
    Assert-RunProfile -Profile $data[0] -ExpectedName $expected
    return $data[0]
}

function ConvertTo-RunProfileLiteral {
    <#
    .SYNOPSIS
    Renders a supported value as PowerShell source with deterministic, culture-invariant formatting.
    .PARAMETER Value
    String, integer, double, boolean or array of them.
    #>
    param($Value)
    if (-not (Test-RunProfileValue $Value)) { throw "RunProfileUnsupportedValue: $($Value.GetType().FullName)" }
    if ($Value -is [string]) { return ConvertTo-RunSingleQuoted $Value }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [int] -or $Value -is [long]) { return $Value.ToString([Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [double]) {
        $text = $Value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        return $(if ($text -match '[.eE]') { $text } else { "$text.0" })
    }
    return '@(' + ((@($Value) | ForEach-Object { ConvertTo-RunProfileLiteral $_ }) -join ', ') + ')'
}

function ConvertTo-RunProfileSource {
    <#
    .SYNOPSIS
    Renders a validated profile as the exact text stored on disk (UTF-8, LF, sorted parameter names).
    .PARAMETER Profile
    Profile hashtable.
    #>
    param([Parameter(Mandatory)][hashtable]$Profile)
    Assert-RunProfile -Profile $Profile
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# Run profile '$($Profile.Name)'. Data only: parsed in restricted language mode, never executed.")
    $lines.Add('@{')
    $lines.Add("    SchemaVersion = $($Profile.SchemaVersion)")
    $lines.Add("    Name = $(ConvertTo-RunSingleQuoted $Profile.Name)")
    if ($Profile.ContainsKey('Description')) { $lines.Add("    Description = $(ConvertTo-RunSingleQuoted $Profile.Description)") }
    $lines.Add("    Script = $(ConvertTo-RunSingleQuoted $Profile.Script)")
    $lines.Add('    Parameters = @{')
    foreach ($key in ($Profile.Parameters.Keys | Sort-Object -CaseSensitive)) { $lines.Add("        $key = $(ConvertTo-RunProfileLiteral $Profile.Parameters[$key])") }
    $lines.Add('    }')
    $lines.Add('}')
    return ($lines -join "`n") + "`n"
}

function Write-RunProfile {
    <#
    .SYNOPSIS
    Writes a profile file, refusing to overwrite an existing one unless forced; returns the file path.
    .PARAMETER Profile
    Profile hashtable.
    .PARAMETER Directory
    Profile directory override.
    .PARAMETER Force
    Allows replacing an existing profile.
    #>
    param([Parameter(Mandatory)][hashtable]$Profile, [string]$Directory, [switch]$Force)
    $path = Get-RunProfilePath -Name $Profile.Name -Directory $Directory
    if ((Test-Path -LiteralPath $path) -and -not $Force) { throw "RunProfileExists: $($Profile.Name)" }
    $source = ConvertTo-RunProfileSource $Profile
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    Write-RunTextFile -Path $path -Text $source
    return $path
}

function Merge-RunProfileArguments {
    <#
    .SYNOPSIS
    Returns the profile parameters overridden by caller arguments (caller wins).
    .PARAMETER Profile
    Validated profile.
    .PARAMETER Arguments
    Caller overrides.
    #>
    param([Parameter(Mandatory)][hashtable]$Profile, [hashtable]$Arguments = @{})
    $merged = @{}
    foreach ($key in $Profile.Parameters.Keys) { $merged[$key] = $Profile.Parameters[$key] }
    foreach ($key in $Arguments.Keys) { $merged[$key] = $Arguments[$key] }
    return $merged
}

function Resolve-RunProfileTarget {
    <#
    .SYNOPSIS
    Resolves the target script of a profile inside the script directory and returns its path.
    .PARAMETER Profile
    Validated profile.
    .PARAMETER ScriptDirectory
    Script directory override.
    #>
    param([Parameter(Mandatory)][hashtable]$Profile, [string]$ScriptDirectory)
    $path = [IO.Path]::Combine((Get-RunScriptDirectory $ScriptDirectory),$Profile.Script)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RunProfileTargetNotFound: $($Profile.Script)" }
    return $path
}

function Assert-RunTargetParameters {
    <#
    .SYNOPSIS
    Throws when a parameter name is not declared by the target script.
    .PARAMETER TargetPath
    Target script path.
    .PARAMETER Parameters
    Hashtable whose keys are checked.
    #>
    param([Parameter(Mandatory)][string]$TargetPath, [Parameter(Mandatory)][hashtable]$Parameters)
    $declared = (Get-Command -Name $TargetPath -CommandType ExternalScript).Parameters
    foreach ($key in $Parameters.Keys) {
        if (-not $declared.ContainsKey($key)) { throw "RunProfileUnknownParameter: $key (target $([IO.Path]::GetFileName($TargetPath)))" }
    }
}

Export-ModuleMember -Function Get-RunProfileDirectory, Get-RunScriptDirectory, Test-RunProfileName, Get-RunProfilePath, Get-RunProfileNames,
    Test-RunProfileValue, Assert-RunProfile, Read-RunProfile, ConvertTo-RunProfileLiteral, ConvertTo-RunProfileSource, Write-RunProfile,
    Merge-RunProfileArguments, Resolve-RunProfileTarget, Assert-RunTargetParameters
