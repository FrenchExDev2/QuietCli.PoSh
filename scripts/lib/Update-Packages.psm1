#requires -Version 7.6
Set-StrictMode -Version Latest

function ConvertTo-QuietTfm {
    <#
    .SYNOPSIS
    Parses a NuGet or MSBuild target framework moniker into a family, a version and an optional platform.
    .PARAMETER Moniker
    Short (net10.0, netstandard2.0, net472) or long (.NETCoreApp3.1, .NETStandard2.0) framework name.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Moniker)
    $value = $Moniker.Trim().ToLowerInvariant()
    $match = [regex]::Match($value, '^\.?netcoreapp(\d+)\.(\d+)$')
    if ($match.Success) {
        return [pscustomobject]@{ Family = 'netcore'; Version = [version]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value); Platform = '' }
    }
    $match = [regex]::Match($value, '^net(\d+)\.(\d+)(?:-([a-z]+)[0-9.]*)?$')
    if ($match.Success -and [int]$match.Groups[1].Value -ge 5) {
        return [pscustomobject]@{ Family = 'netcore'; Version = [version]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value); Platform = $match.Groups[3].Value }
    }
    $match = [regex]::Match($value, '^\.?netstandard(\d+)\.(\d+)$')
    if ($match.Success) {
        return [pscustomobject]@{ Family = 'netstandard'; Version = [version]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value); Platform = '' }
    }
    if ($value -match '^net\d{2,3}$' -or $value -like '.netframework*') {
        return [pscustomobject]@{ Family = 'netfx'; Version = $null; Platform = '' }
    }
    return [pscustomobject]@{ Family = 'unknown'; Version = $null; Platform = '' }
}

function Test-QuietTfmCompatible {
    <#
    .SYNOPSIS
    Tells whether assets built for one framework can be consumed by a project targeting another one.
    .PARAMETER Package
    Framework of the package asset folder or dependency group (for example net11.0).
    .PARAMETER Target
    Framework the consuming project builds for (for example net10.0).
    #>
    param([Parameter(Mandatory)][string]$Package, [Parameter(Mandatory)][string]$Target)
    $packageTfm = ConvertTo-QuietTfm $Package
    $targetTfm = ConvertTo-QuietTfm $Target
    if ($targetTfm.Family -ne 'netcore') { return $false }
    switch ($packageTfm.Family) {
        'netcore' {
            return ($packageTfm.Version -le $targetTfm.Version) -and (-not $packageTfm.Platform -or $packageTfm.Platform -eq $targetTfm.Platform)
        }
        'netstandard' {
            $highest = if ($targetTfm.Version -ge [version]'3.0') { [version]'2.1' } else { [version]'2.0' }
            return $packageTfm.Version -le $highest
        }
        default { return $false }
    }
}

function Test-QuietPackageCompatible {
    <#
    .SYNOPSIS
    Tells whether a package version exposing the given frameworks is usable from the target framework.
    .DESCRIPTION
    A package without any recognized framework (tools, content or metadata-only packages) is treated as
    compatible: there is nothing to contradict it and the restore check after -Apply stays authoritative.
    .PARAMETER Tfms
    Frameworks read from the package asset folders or dependency groups.
    .PARAMETER Target
    Framework the consuming project builds for.
    #>
    param([AllowEmptyCollection()][string[]]$Tfms = @(), [Parameter(Mandatory)][string]$Target)
    $known = @($Tfms | Where-Object { (ConvertTo-QuietTfm $_).Family -ne 'unknown' })
    if (-not $known.Count) { return $true }
    foreach ($tfm in $known) { if (Test-QuietTfmCompatible -Package $tfm -Target $Target) { return $true } }
    return $false
}

function Compare-QuietSemVer {
    <#
    .SYNOPSIS
    Compares two NuGet versions; negative when Left is lower, zero when equal, positive when higher.
    .PARAMETER Left
    First version.
    .PARAMETER Right
    Second version.
    #>
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $parse = {
        param([string]$Value)
        $parts = ($Value -split '\+', 2)[0] -split '-', 2
        $numbers = @($parts[0] -split '\.' | ForEach-Object { [long]$_ })
        while ($numbers.Count -lt 4) { $numbers += [long]0 }
        @{ Numbers = $numbers; Pre = if ($parts.Count -gt 1) { $parts[1] } else { $null } }
    }
    $a = & $parse $Left
    $b = & $parse $Right
    for ($i = 0; $i -lt 4; $i++) {
        $delta = $a.Numbers[$i].CompareTo($b.Numbers[$i])
        if ($delta -ne 0) { return $delta }
    }
    if ($null -eq $a.Pre -and $null -ne $b.Pre) { return 1 }
    if ($null -ne $a.Pre -and $null -eq $b.Pre) { return -1 }
    if ($null -ne $a.Pre -and $null -ne $b.Pre) { return [string]::Compare($a.Pre, $b.Pre, [StringComparison]::OrdinalIgnoreCase) }
    return 0
}

function Resolve-QuietDotNet {
    <#
    .SYNOPSIS
    Returns the repository-local SDK listed by global.json sdk.paths, else the dotnet found on PATH.
    .PARAMETER WorkspaceRoot
    Repository containing global.json.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $executable = if ($IsWindows) { 'dotnet.exe' } else { 'dotnet' }
    $globalJson = [IO.Path]::Combine($WorkspaceRoot, 'global.json')
    if (Test-Path -LiteralPath $globalJson -PathType Leaf) {
        $sdk = (Get-Content -LiteralPath $globalJson -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable)['sdk']
        if ($sdk -and $sdk['paths']) {
            foreach ($path in @($sdk['paths'])) {
                if (-not $path -or $path.StartsWith('$')) { continue }
                $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot, $path, $executable))
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }
    }
    $command = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw 'DotNetNotFound: no repository-local SDK from global.json sdk.paths and no dotnet on PATH.'
}

function Get-QuietCsprojFiles {
    <#
    .SYNOPSIS
    Lists the tracked .csproj files of the repository, ignoring build copies under artifacts, bin or obj.
    .PARAMETER WorkspaceRoot
    Repository root.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $tracked = @(& $git.Source -C $WorkspaceRoot ls-files -- '*.csproj' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $tracked.Count) {
            return @($tracked | ForEach-Object { [IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot, $_)) } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Sort-Object)
        }
    }
    return @(Get-ChildItem -LiteralPath $WorkspaceRoot -Recurse -File -Filter '*.csproj' |
        Where-Object { $_.FullName -notmatch '[\\/](\.dotnet|\.git|artifacts|bin|obj)[\\/]' } |
        ForEach-Object { $_.FullName } | Sort-Object)
}

function Get-QuietPackageInventory {
    <#
    .SYNOPSIS
    Evaluates every project once per target framework with MSBuild and returns the resolved CPM pins.
    .DESCRIPTION
    MSBuild itself resolves every Condition (element, ItemGroup, property functions, imports), so the
    result is exactly what restore would see. Only PackageVersion items defined by PropsPath are kept;
    each record says whether the project references the package for that framework.
    .PARAMETER DotNet
    dotnet executable.
    .PARAMETER Projects
    Project files to evaluate.
    .PARAMETER PropsPath
    Directory.Packages.props whose PackageVersion items are inventoried.
    .PARAMETER ParallelMax
    Maximum number of concurrent MSBuild evaluations.
    #>
    param(
        [Parameter(Mandatory)][string]$DotNet,
        [Parameter(Mandatory)][string[]]$Projects,
        [Parameter(Mandatory)][string]$PropsPath,
        [int]$ParallelMax = 4
    )
    $Projects | ForEach-Object -ThrottleLimit $ParallelMax -Parallel {
        $project = $_
        $dotnet = $using:DotNet
        $props = [IO.Path]::GetFullPath($using:PropsPath)
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        $read = {
            param([string[]]$Arguments)
            $text = (& $dotnet msbuild $project -nologo @Arguments 2>&1 | Out-String)
            $code = $LASTEXITCODE
            $start = $text.IndexOf('{'); $end = $text.LastIndexOf('}')
            if ($code -ne 0 -or $start -lt 0 -or $end -lt $start) {
                $message = ($text -split "`r?`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1)
                throw ('MSBuild exit ' + $code + ': ' + $(if ($message) { $message.Trim() } else { $text.Trim() }))
            }
            $text.Substring($start, $end - $start + 1) | ConvertFrom-Json -AsHashtable
        }
        try {
            $properties = (& $read @('-getProperty:TargetFramework', '-getProperty:TargetFrameworks'))['Properties']
            $tfms = @(([string]$properties['TargetFrameworks']) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if (-not $tfms.Count -and $properties['TargetFramework']) { $tfms = @([string]$properties['TargetFramework']) }
            if (-not $tfms.Count) { throw 'NoTargetFramework' }
            foreach ($tfm in $tfms) {
                $items = (& $read @('-getItem:PackageVersion', '-getItem:PackageReference', '-getProperty:TargetFramework', "-p:TargetFramework=$tfm"))['Items']
                $referenced = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($reference in @($items['PackageReference'])) { if ($reference) { [void]$referenced.Add([string]$reference['Identity']) } }
                foreach ($pin in @($items['PackageVersion'])) {
                    if (-not $pin) { continue }
                    if (-not [string]::Equals([IO.Path]::GetFullPath([string]$pin['DefiningProjectFullPath']), $props, $comparison)) { continue }
                    [pscustomobject]@{
                        Kind = 'Pin'; Project = $project; Tfm = $tfm
                        Id = [string]$pin['Identity']; Version = [string]$pin['Version']
                        Referenced = $referenced.Contains([string]$pin['Identity'])
                    }
                }
            }
        }
        catch {
            [pscustomobject]@{ Kind = 'Error'; Project = $project; Message = $_.Exception.Message }
        }
    }
}

function Get-QuietPackageVersionElements {
    <#
    .SYNOPSIS
    Lists the literal PackageVersion elements of a props file, ignoring commented-out ones.
    .PARAMETER Content
    Raw props file text.
    #>
    param([Parameter(Mandatory)][string]$Content)
    $comments = @([regex]::Matches($Content, '(?s)<!--.*?-->'))
    foreach ($match in [regex]::Matches($Content, '<PackageVersion\b[^>]*?/?>')) {
        if (@($comments | Where-Object { $match.Index -ge $_.Index -and $match.Index -lt ($_.Index + $_.Length) }).Count) { continue }
        $attributes = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($attribute in [regex]::Matches($match.Value, '([A-Za-z_][\w.:-]*)\s*=\s*"([^"]*)"')) {
            $attributes[$attribute.Groups[1].Value] = $attribute.Groups[2].Value
        }
        if (-not $attributes['Include'] -or -not $attributes['Version']) { continue }
        [pscustomobject]@{
            Index = $match.Index; Id = $attributes['Include']; Version = $attributes['Version']
            Condition = if ($null -ne $attributes['Condition']) { $attributes['Condition'] } else { '' }
        }
    }
}

function Set-QuietPackageVersion {
    <#
    .SYNOPSIS
    Rewrites the Version of exactly the PackageVersion elements identified by Include, Version and Condition.
    .PARAMETER Content
    Raw props file text.
    .PARAMETER Updates
    Objects with Id, Current, Condition and Latest; attribute order inside the element does not matter.
    #>
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][object[]]$Updates)
    $byKey = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($update in $Updates) { $byKey[$update.Id.ToLowerInvariant() + '|' + $update.Current + '|' + $update.Condition] = $update.Latest }
    $comments = @([regex]::Matches($Content, '(?s)<!--.*?-->'))
    $state = @{ Count = 0 }
    $result = [regex]::Replace($Content, '<PackageVersion\b[^>]*?/?>', [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        if (@($comments | Where-Object { $match.Index -ge $_.Index -and $match.Index -lt ($_.Index + $_.Length) }).Count) { return $match.Value }
        $attributes = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($attribute in [regex]::Matches($match.Value, '([A-Za-z_][\w.:-]*)\s*=\s*"([^"]*)"')) { $attributes[$attribute.Groups[1].Value] = $attribute.Groups[2].Value }
        if (-not $attributes['Include'] -or -not $attributes['Version']) { return $match.Value }
        $condition = if ($null -ne $attributes['Condition']) { $attributes['Condition'] } else { '' }
        $key = $attributes['Include'].ToLowerInvariant() + '|' + $attributes['Version'] + '|' + $condition
        if (-not $byKey.ContainsKey($key)) { return $match.Value }
        $state.Count++
        return [regex]::Replace($match.Value, '(\bVersion\s*=\s*")[^"]*(")', ('${1}' + $byKey[$key] + '${2}'))
    })
    [pscustomobject]@{ Content = $result; Count = $state.Count }
}

function Read-QuietPackageTfms {
    <#
    .SYNOPSIS
    Reads the frameworks a NuGet package version ships, from its nuget.org catalog leaf.
    .DESCRIPTION
    Self-contained (it also runs in parallel runspaces). Asset folders lib/<tfm>/, ref/<tfm>/ and
    runtimes/<rid>/lib/<tfm>/ are authoritative; dependency groups are the fallback; Source is
    assets, dependencies, none or error.
    .PARAMETER Id
    Package id.
    .PARAMETER Version
    Normalized package version.
    #>
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Version)
    $leaf = $null
    for ($attempt = 1; ; $attempt++) {
        try {
            $registration = Invoke-RestMethod -Uri ('https://api.nuget.org/v3/registration5-gz-semver2/' + $Id.ToLowerInvariant() + '/' + $Version.ToLowerInvariant() + '.json') -TimeoutSec 20 -ErrorAction Stop
            $leaf = Invoke-RestMethod -Uri ([string]$registration.catalogEntry) -TimeoutSec 20 -ErrorAction Stop
            break
        }
        catch {
            if ($attempt -ge 3) { return [pscustomobject]@{ Id = $Id; Version = $Version; Tfms = [string[]]@(); Source = 'error'; Error = $_.Exception.Message } }
            Start-Sleep -Milliseconds (300 * $attempt)
        }
    }
    $set = [Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($leaf.PSObject.Properties['packageEntries']) {
        foreach ($entry in @($leaf.packageEntries)) {
            $match = [regex]::Match([string]$entry.fullName, '^(?:lib|ref|runtimes/[^/]+/lib)/([^/]+)/[^/]')
            if ($match.Success) { [void]$set.Add($match.Groups[1].Value) }
        }
    }
    $source = 'assets'
    if (-not $set.Count) {
        $source = 'dependencies'
        if ($leaf.PSObject.Properties['dependencyGroups']) {
            foreach ($group in @($leaf.dependencyGroups)) {
                if ($group.PSObject.Properties['targetFramework'] -and $group.targetFramework) { [void]$set.Add([string]$group.targetFramework) }
            }
        }
        if (-not $set.Count) { $source = 'none' }
    }
    [pscustomobject]@{ Id = $Id; Version = $Version; Tfms = [string[]]@($set); Source = $source; Error = $null }
}

function Get-QuietPackageTfms {
    <#
    .SYNOPSIS
    Cached front of Read-QuietPackageTfms, keyed by lowercase id/version.
    .PARAMETER Id
    Package id.
    .PARAMETER Version
    Package version.
    .PARAMETER Cache
    Hashtable shared by the whole run.
    #>
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][hashtable]$Cache)
    $key = $Id.ToLowerInvariant() + '/' + $Version.ToLowerInvariant()
    if (-not $Cache.ContainsKey($key)) { $Cache[$key] = Read-QuietPackageTfms -Id $Id -Version $Version }
    return $Cache[$key]
}

function Add-QuietPackageTfmsParallel {
    <#
    .SYNOPSIS
    Fills the framework cache for many id/version pairs concurrently.
    .PARAMETER Pairs
    Objects with Id and Version.
    .PARAMETER Cache
    Hashtable shared by the whole run.
    .PARAMETER ParallelMax
    Maximum number of concurrent nuget.org requests.
    #>
    param([AllowEmptyCollection()][object[]]$Pairs = @(), [Parameter(Mandatory)][hashtable]$Cache, [int]$ParallelMax = 4)
    $missing = @($Pairs | Where-Object { -not $Cache.ContainsKey($_.Id.ToLowerInvariant() + '/' + $_.Version.ToLowerInvariant()) })
    if (-not $missing.Count) { return }
    $definition = ${function:Read-QuietPackageTfms}.ToString()
    $results = $missing | ForEach-Object -ThrottleLimit $ParallelMax -Parallel {
        ${function:Read-QuietPackageTfms} = $using:definition
        Read-QuietPackageTfms -Id $_.Id -Version $_.Version
    }
    foreach ($result in @($results)) { $Cache[$result.Id.ToLowerInvariant() + '/' + $result.Version.ToLowerInvariant()] = $result }
}

function Get-QuietNuGetVersions {
    <#
    .SYNOPSIS
    Fetches the published versions of each package id from the nuget.org flat container, concurrently.
    .PARAMETER Ids
    Distinct package ids.
    .PARAMETER ParallelMax
    Maximum number of concurrent requests.
    #>
    param([Parameter(Mandatory)][string[]]$Ids, [int]$ParallelMax = 4)
    $byId = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    $results = $Ids | ForEach-Object -ThrottleLimit $ParallelMax -Parallel {
        $id = $_; $versions = $null; $failure = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $versions = [string[]]@((Invoke-RestMethod -Uri ('https://api.nuget.org/v3-flatcontainer/' + $id.ToLowerInvariant() + '/index.json') -TimeoutSec 15 -ErrorAction Stop).versions)
                $failure = $null; break
            }
            catch { $failure = $_.Exception.Message; Start-Sleep -Milliseconds (300 * $attempt) }
        }
        [pscustomobject]@{ Id = $id; Versions = $versions; Error = $failure }
    }
    foreach ($result in @($results)) { $byId[$result.Id] = $result }
    return $byId
}

function Write-QuietPackageRow {
    <#
    .SYNOPSIS
    Writes one aligned console row: version, status (with an optional gray note) and package label.
    .PARAMETER Version
    Current version.
    .PARAMETER Status
    Status text.
    .PARAMETER StatusColor
    Status color.
    .PARAMETER Note
    Optional gray annotation appended to the status.
    .PARAMETER Name
    Package label, including its framework.
    .PARAMETER VersionWidth
    Version column width.
    .PARAMETER StatusWidth
    Status column width (status and note together).
    #>
    param([string]$Version, [string]$Status, [ConsoleColor]$StatusColor = 'Gray', [string]$Note = '', [string]$Name, [int]$VersionWidth = 14, [int]$StatusWidth = 22)
    Write-Host -NoNewline ('  ' + $Version.PadRight($VersionWidth) + '  ')
    Write-Host -NoNewline $Status -ForegroundColor $StatusColor
    $noteText = if ($Note) { ' ' + $Note } else { '' }
    Write-Host -NoNewline ($noteText.PadRight([Math]::Max(0, $StatusWidth - $Status.Length)) + '  ') -ForegroundColor DarkGray
    Write-Host $Name
}

function Invoke-QuietScriptUpdatePackages {
<#
.SYNOPSIS
Checks and applies NuGet updates for Directory.Packages.props per package and target framework, honoring CPM conditions.
.DESCRIPTION
Every tracked project is evaluated by MSBuild once per target framework, so each PackageVersion
Condition is resolved exactly as restore resolves it. Each resulting package x framework row is
checked against nuget.org: a newer version is proposed only if its catalog assets (lib/, ref/,
runtimes/*/lib/, else its dependency groups) are compatible with that framework. An element used
by several frameworks receives the highest version compatible with all of them.
Without -Apply the updates are listed and chosen interactively. -WhatIf runs the whole analysis,
selects every compatible update and prints it without prompting or writing. -Apply writes the
selected versions, then runs dotnet restore on the referencing projects and restores the original
file if restore fails (for example NU1202). In GitHub Actions the table is also appended to the job
summary.
.PARAMETER WorkspaceRoot
Repository whose tracked .csproj files are evaluated. Defaults to this script's workspace root.
.PARAMETER PropsPath
Central package management file to update. Defaults to Directory.Packages.props at WorkspaceRoot.
.PARAMETER Apply
Applies every compatible update without prompting.
.PARAMETER IncludePrerelease
Also proposes pre-release versions (always the case for a package already pinned to a pre-release).
.PARAMETER ParallelMax
Maximum number of concurrent MSBuild evaluations and nuget.org requests.
.PARAMETER NoRestore
Skips the dotnet restore check after writing.
.EXAMPLE
./scripts/Update-Packages.ps1 -WhatIf
Shows every package x framework row and the updates that would be written, without prompting or writing.
.EXAMPLE
./scripts/Update-Packages.ps1
Lists the compatible updates and asks which ones to write.
.EXAMPLE
./scripts/Update-Packages.ps1 -Apply
Writes every compatible update, then checks it with dotnet restore.
.EXAMPLE
./scripts/Update-Packages.ps1 -Apply -IncludePrerelease -ParallelMax 8
Also considers pre-release versions, with more concurrent requests.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),
    [string]$PropsPath = '',
    [switch]$Apply,
    [switch]$IncludePrerelease,
    [ValidateRange(1, 32)][int]$ParallelMax = 4,
    [switch]$NoRestore
)
$ErrorActionPreference = 'Stop'
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
if (-not $PropsPath) { $PropsPath = [IO.Path]::Combine($WorkspaceRoot, 'Directory.Packages.props') }
$PropsPath = [IO.Path]::GetFullPath($PropsPath)
if (-not (Test-Path -LiteralPath $PropsPath -PathType Leaf)) { throw "PackagePropsNotFound: $PropsPath" }

$bytes = [IO.File]::ReadAllBytes($PropsPath)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$encoding = [Text.UTF8Encoding]::new($hasBom)
$original = [IO.File]::ReadAllText($PropsPath, $encoding)
$elements = @(Get-QuietPackageVersionElements -Content $original)
if (-not $elements.Count) { Write-Host "No PackageVersion element in $PropsPath."; return }

# Inventory: one MSBuild evaluation per project x framework.
$dotnet = Resolve-QuietDotNet -WorkspaceRoot $WorkspaceRoot
$projects = @(Get-QuietCsprojFiles -WorkspaceRoot $WorkspaceRoot)
if (-not $projects.Count) { throw "NoProjectFound: $WorkspaceRoot" }
Write-Host ("Evaluating {0} project(s) per target framework with {1}..." -f $projects.Count, $dotnet) -ForegroundColor DarkGray
$inventory = @(Get-QuietPackageInventory -DotNet $dotnet -Projects $projects -PropsPath $PropsPath -ParallelMax $ParallelMax)
$evalErrors = @($inventory | Where-Object Kind -EQ 'Error')
$pins = @($inventory | Where-Object Kind -EQ 'Pin')

# Rows: one per element x framework. Frameworks are those whose projects reference the package,
# or every framework defining the pin when no project references it.
$rows = [Collections.Generic.List[object]]::new()
foreach ($element in $elements) {
    $twins = @($elements | Where-Object { $_.Id -eq $element.Id -and $_.Version -eq $element.Version })
    $matching = @($pins | Where-Object { $_.Id -eq $element.Id -and $_.Version -eq $element.Version })
    $referenced = @($matching | Where-Object Referenced)
    $source = if ($referenced.Count) { $referenced } else { $matching }
    $tfms = @($source | ForEach-Object { $_.Tfm } | Sort-Object -Unique)
    if (-not $tfms.Count) {
        $rows.Add([pscustomobject]@{ Element = $element; Tfm = '-'; Projects = @(); Unreferenced = $false; Ambiguous = $twins.Count -gt 1; Latest = $null; Newest = $null; NewestTfms = @(); Status = 'no tfm' })
        continue
    }
    foreach ($tfm in $tfms) {
        $rows.Add([pscustomobject]@{
            Element = $element; Tfm = $tfm
            Projects = @($referenced | Where-Object Tfm -EQ $tfm | ForEach-Object { $_.Project } | Sort-Object -Unique)
            Unreferenced = -not $referenced.Count; Ambiguous = $twins.Count -gt 1
            Latest = $null; Newest = $null; NewestTfms = @(); Status = $null
        })
    }
}

# Versions and frameworks from nuget.org.
$ids = @($elements | ForEach-Object { $_.Id } | Sort-Object -Unique)
Write-Host ("Checking {0} package id(s) on nuget.org..." -f $ids.Count) -ForegroundColor DarkGray
$published = Get-QuietNuGetVersions -Ids $ids -ParallelMax $ParallelMax
$tfmCache = [hashtable]::new([StringComparer]::Ordinal)
$candidatesFor = {
    param($element)
    $entry = $published[$element.Id]
    if (-not $entry -or $entry.Error -or $null -eq $entry.Versions) { return $null }
    $allowPre = $IncludePrerelease -or $element.Version -match '-'
    $newer = [Collections.Generic.List[string]]::new()
    foreach ($version in $entry.Versions) { if (($allowPre -or $version -notmatch '-') -and (Compare-QuietSemVer $version $element.Version) -gt 0) { $newer.Add($version) } }
    $newer.Sort([Comparison[string]]{ param($x, $y) [int](Compare-QuietSemVer $y $x) })
    ,$newer.ToArray()
}
$prefetch = [Collections.Generic.List[object]]::new()
foreach ($element in $elements) {
    $candidates = & $candidatesFor $element
    if ($candidates -and $candidates.Count) { $prefetch.Add([pscustomobject]@{ Id = $element.Id; Version = $candidates[0] }) }
}
Add-QuietPackageTfmsParallel -Pairs $prefetch.ToArray() -Cache $tfmCache -ParallelMax $ParallelMax

foreach ($row in $rows) {
    if ($row.Status) { continue }
    if ($row.Ambiguous) { $row.Status = 'ambiguous'; continue }
    $candidates = & $candidatesFor $row.Element
    if ($null -eq $candidates) { $row.Status = 'fetch error'; continue }
    $row.Latest = $row.Element.Version
    if (-not $candidates.Count) { $row.Status = 'current'; continue }
    $row.Newest = $candidates[0]
    foreach ($candidate in $candidates) {
        $info = Get-QuietPackageTfms -Id $row.Element.Id -Version $candidate -Cache $tfmCache
        if ($candidate -eq $row.Newest) { $row.NewestTfms = @($info.Tfms) }
        if ($info.Source -eq 'error') { $row.Status = 'lookup error'; break }
        if (Test-QuietPackageCompatible -Tfms $info.Tfms -Target $row.Tfm) { $row.Latest = $candidate; break }
    }
    if (-not $row.Status) { $row.Status = if ((Compare-QuietSemVer $row.Latest $row.Element.Version) -gt 0) { 'update' } else { 'current' } }
}

# Table: one line per package x framework.
$label = { param($row) $row.Element.Id + ' [' + $row.Tfm + ']' + $(if ($row.Unreferenced) { ' (unreferenced)' } else { '' }) }
$display = foreach ($row in ($rows | Sort-Object { $_.Element.Id }, Tfm)) {
    $note = ''
    if ($row.Newest -and $row.Latest -ne $row.Newest -and $row.Status -in 'update', 'current') { $note = '(' + $row.Newest + ': ' + $(if ($row.NewestTfms.Count) { $row.NewestTfms -join ', ' } else { 'no tfm' }) + ')' }
    $status, $color = switch ($row.Status) {
        'update' { ([char]0x2191 + ' ' + $row.Latest), 'Yellow' }
        'current' { [string][char]0x2713, 'Green' }
        default { $row.Status, 'Red' }
    }
    [pscustomobject]@{ Row = $row; Label = (& $label $row); Status = $status; Color = $color; Note = $note }
}
$display = @($display)
$versionWidth = [Math]::Max(7, ($display | ForEach-Object { $_.Row.Element.Version.Length } | Measure-Object -Maximum).Maximum)
$statusWidth = [Math]::Max(6, ($display | ForEach-Object { $_.Status.Length + $(if ($_.Note) { $_.Note.Length + 1 } else { 0 }) } | Measure-Object -Maximum).Maximum)
$nameWidth = ($display | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
Write-Host ''
Write-Host ('  ' + 'Version'.PadRight($versionWidth) + '  ' + 'Status'.PadRight($statusWidth) + '  ' + 'Package [tfm]') -ForegroundColor Cyan
Write-Host ('  ' + ([string][char]0x2500 * $versionWidth) + '  ' + ([string][char]0x2500 * $statusWidth) + '  ' + ([string][char]0x2500 * $nameWidth)) -ForegroundColor DarkGray
foreach ($line in $display) {
    Write-QuietPackageRow -Version $line.Row.Element.Version -Status $line.Status -StatusColor $line.Color -Note $line.Note -Name $line.Label -VersionWidth $versionWidth -StatusWidth $statusWidth
}
Write-Host ''
foreach ($failure in $evalErrors) { Write-Host ('eval error ' + [IO.Path]::GetRelativePath($WorkspaceRoot, $failure.Project) + ': ' + $failure.Message) -ForegroundColor Red }
foreach ($row in @($rows | Where-Object Status -EQ 'fetch error' | Group-Object { $_.Element.Id } | ForEach-Object { $_.Group[0] })) {
    Write-Host ('fetch error ' + $row.Element.Id + ': ' + $published[$row.Element.Id].Error) -ForegroundColor Red
}

# Proposals: one per element, the highest version compatible with all its frameworks.
$updates = [Collections.Generic.List[object]]::new()
foreach ($element in $elements) {
    $own = @($rows | Where-Object { $_.Element.Index -eq $element.Index })
    if (@($own | Where-Object { $_.Status -notin 'update', 'current' }).Count) { continue }
    $target = $null
    foreach ($row in $own) { if ($null -eq $target -or (Compare-QuietSemVer $row.Latest $target) -lt 0) { $target = $row.Latest } }
    if ($target -and (Compare-QuietSemVer $target $element.Version) -gt 0) {
        $updates.Add([pscustomobject]@{
            Id = $element.Id; Current = $element.Version; Condition = $element.Condition; Latest = $target
            Label = $element.Id + ' [' + (@($own | ForEach-Object { $_.Tfm }) -join ', ') + ']'
            Projects = @($own | ForEach-Object { $_.Projects } | Sort-Object -Unique)
        })
    }
}

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = [Collections.Generic.List[string]]::new()
    $summary.Add('## NuGet package updates'); $summary.Add('')
    $summary.Add('`' + [IO.Path]::GetRelativePath($WorkspaceRoot, $PropsPath).Replace('\', '/') + '`, one row per package x target framework.'); $summary.Add('')
    $summary.Add('| Package | TFM | Current | Status |'); $summary.Add('| --- | --- | --- | --- |')
    foreach ($line in $display) { $summary.Add('| ' + $line.Row.Element.Id + ' | ' + $line.Row.Tfm + ' | ' + $line.Row.Element.Version + ' | ' + ($line.Status + ' ' + $line.Note).Trim().Replace('|', '\|') + ' |') }
    $summary.Add('')
    $summary.Add($(if ($updates.Count) { '**' + $updates.Count + ' update(s) available:** ' + (@($updates | ForEach-Object { '`' + $_.Label + ' ' + $_.Current + ' -> ' + $_.Latest + '`' }) -join ', ') } else { 'All packages are up to date.' }))
    [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, ($summary -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

if (-not $updates.Count) {
    Write-Host 'All packages are up to date for their target frameworks.' -ForegroundColor Green
    if ($evalErrors.Count -or @($rows | Where-Object { $_.Status -notin 'update', 'current' }).Count) { Write-Host 'Some rows could not be checked; see the errors above.' -ForegroundColor Yellow }
    return
}

# Selection.
$toApply = [Collections.Generic.List[object]]::new()
$labelWidth = ($updates | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
if ($Apply -or $WhatIfPreference) {
    $toApply.AddRange($updates)
}
else {
    Write-Host 'Available updates:' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $u = $updates[$i]
        Write-Host ('  [{0,2}]  {1}  {2} -> {3}' -f ($i + 1), $u.Label.PadRight($labelWidth), $u.Current, $u.Latest)
    }
    Write-Host ''
    Write-Host "  Enter package numbers (e.g.  1,3), 'all', or 'none' (default: all)"
    $answer = (Read-Host '  Selection').Trim()
    if ($answer -eq '' -or $answer -ieq 'all') { $toApply.AddRange($updates) }
    elseif ($answer -ieq 'none') { Write-Host 'No updates selected.'; return }
    else {
        foreach ($token in ($answer -split '[,\s]+')) {
            $index = 0
            if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $updates.Count) { if (-not $toApply.Contains($updates[$index - 1])) { $toApply.Add($updates[$index - 1]) } }
            else { Write-Warning "Ignored invalid selection: '$token'" }
        }
    }
}
if (-not $toApply.Count) { Write-Host 'No updates selected.'; return }

# Write, then check with restore.
$rewrite = Set-QuietPackageVersion -Content $original -Updates $toApply.ToArray()
if ($rewrite.Count -ne $toApply.Count) { throw ('PackageVersionRewriteMismatch: expected ' + $toApply.Count + ' element(s), matched ' + $rewrite.Count) }
foreach ($u in $toApply) {
    $prefix = if ($WhatIfPreference) { 'What if: ' } else { '' }
    Write-Host ('  {0}{1}  {2} -> {3}' -f $prefix, $u.Label.PadRight($labelWidth), $u.Current, $u.Latest) -ForegroundColor $(if ($WhatIfPreference) { 'Cyan' } else { 'Green' })
}
if ($PSCmdlet.ShouldProcess($PropsPath, "Update $($toApply.Count) package version(s)")) {
    [IO.File]::WriteAllText($PropsPath, $rewrite.Content, $encoding)
    Write-Host ''
    Write-Host "Updated $PropsPath." -ForegroundColor Green
    if ($NoRestore) { Write-Host 'Restore check skipped (-NoRestore).' -ForegroundColor Yellow; return }
    $restoreProjects = @($toApply | ForEach-Object { $_.Projects } | Sort-Object -Unique)
    if (-not $restoreProjects.Count) { Write-Host 'No project references the updated packages; restore check skipped.' -ForegroundColor Yellow; return }
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($project in $restoreProjects) {
        $relative = [IO.Path]::GetRelativePath($WorkspaceRoot, $project)
        Write-Host "Restoring $relative..." -ForegroundColor DarkGray
        $output = (& $dotnet restore $project -nologo 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            $codes = @([regex]::Matches($output, '\b(NU\d{4})\b[^\r\n]*') | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
            $failures.Add($relative + ': ' + $(if ($codes.Count) { $codes -join ' | ' } else { 'dotnet restore exit ' + $LASTEXITCODE }))
        }
    }
    if ($failures.Count) {
        [IO.File]::WriteAllText($PropsPath, $original, $encoding)
        foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
        throw "PackageRestoreFailed: $PropsPath was restored to its previous content."
    }
    Write-Host 'Restore check passed.' -ForegroundColor Green
}
}
Export-ModuleMember -Function 'Invoke-QuietScriptUpdatePackages'
