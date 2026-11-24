#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseTags.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietBumpedModuleVersion {
    <#
    .SYNOPSIS
    Increments a three-part module version or its numeric preview counter.
    .PARAMETER Version
    Numeric version from the manifest's ModuleVersion field.
    .PARAMETER Prerelease
    Current prerelease label from the manifest.
    .PARAMETER Bump
    Component to increment.
    #>
    param([string]$Version,[string]$Prerelease,[string]$Bump)
    $current = $null
    if (![version]::TryParse($Version,[ref]$current) -or $current.Build -lt 0 -or $current.Revision -ge 0) {
        throw "ModuleVersionBumpRequiresThreeParts: $Version"
    }
    if ($Bump -ieq 'preview') {
        $number = 0
        if ($Prerelease -and $Prerelease -ine 'preview') {
            if ($Prerelease -inotmatch '\Apreview([0-9]+)\z') { throw "ModuleVersionExpectedPreview: $Prerelease" }
            if (![int]::TryParse($Matches[1],[ref]$number) -or $number -eq [int]::MaxValue) {
                throw "ModuleVersionBumpOverflow: $Version-$Prerelease"
            }
        }
        return "$current-preview$($number + 1)"
    }
    $parts = @($current.Major,$current.Minor,$current.Build)
    $index = @('major','minor','patch').IndexOf($Bump.ToLowerInvariant())
    if ($parts[$index] -eq [int]::MaxValue) { throw "ModuleVersionBumpOverflow: $Version ($Bump)" }
    $parts[$index]++
    for ($next = $index + 1; $next -lt $parts.Count; $next++) { $parts[$next] = 0 }
    [version]::new($parts[0],$parts[1],$parts[2]).ToString()
}

function Update-QuietModuleVersionFiles {
    <#
    .SYNOPSIS
    Stages all manifest texts and replaces each original atomically, keeping originals for rollback.
    .PARAMETER Changes
    Approved manifest changes with their original and updated text.
    .PARAMETER Encoding
    UTF-8 encoding used to read and stage manifests.
    #>
    param([object[]]$Changes,[Text.Encoding]$Encoding)
    $staged = [Collections.Generic.List[object]]::new()
    $committed = $false
    try {
        foreach ($change in $Changes) {
            $temporary = $change.ManifestPath + '.' + [guid]::NewGuid().ToString('N')
            $entry = [pscustomobject]@{ Change = $change; Temporary = $temporary + '.tmp'; Backup = $temporary + '.bak'; Replaced = $false }
            $staged.Add($entry)
            [void][IO.File]::WriteAllTextAsync($entry.Temporary,$change.UpdatedText,$Encoding).GetAwaiter().GetResult()
            if (!$IsWindows) { [IO.File]::SetUnixFileMode($entry.Temporary,[IO.File]::GetUnixFileMode($change.ManifestPath)) }
        }
        foreach ($entry in $staged) {
            $change = $entry.Change
            $path = $change.ManifestPath
            if (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -or
                [IO.File]::ReadAllText($path,$Encoding) -cne $change.OriginalText) {
                throw "ModuleVersionManifestChanged: $path"
            }
            [IO.File]::Replace($entry.Temporary,$path,$entry.Backup)
            $entry.Replaced = $true
        }
        $committed = $true
    } catch {
        $failure = $_
        $recovery = foreach ($entry in $staged | Where-Object Replaced) {
            $path = $entry.Change.ManifestPath
            try {
                if (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -or
                    [IO.File]::ReadAllText($path,$Encoding) -cne $entry.Change.UpdatedText) {
                    throw "ModuleVersionManifestChanged: $path"
                }
                [IO.File]::Replace($entry.Backup,$path,[NullString]::Value)
            } catch {
                $entry.Backup
            }
        }
        if ($recovery) { throw "ModuleVersionRollbackIncomplete: $($failure.Exception.Message) | Original backups: $($recovery -join ', ')" }
        throw $failure
    } finally {
        foreach ($entry in $staged) {
            [IO.File]::Delete($entry.Temporary)
            if ($committed) { [IO.File]::Delete($entry.Backup) }
        }
    }
}

function Invoke-QuietScriptNewVersion {
    <#
    .SYNOPSIS
    Plans and applies local module manifest version changes using the release manifest editor.
    .PARAMETER Version
    Exact stable or Gallery prerelease version.
    .PARAMETER Bump
    Major, minor, patch or preview increment, calculated independently for each manifest.
    .PARAMETER Module
    Business module aliases or manifest names. All selects every business module.
    .PARAMETER WorkspaceRoot
    Checkout whose manifests are discovered.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Version')]
    param(
        [Parameter(Mandatory, ParameterSetName='Version')][string]$Version,
        [Parameter(Mandatory, ParameterSetName='Bump')][ValidateSet('major','minor','patch','preview')][string]$Bump,
        [ValidateNotNullOrEmpty()][string[]]$Module = @('All'),
        [string]$WorkspaceRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))
    )
    $ErrorActionPreference = 'Stop'
    $projects = @(Get-QuietWorkspaceProjects -WorkspaceRoot $WorkspaceRoot | Where-Object { !$_.IsTest })
    foreach ($name in $Module) {
        if ($name -ine 'All' -and $name -inotin $projects.Suite -and $name -inotin $projects.Name) {
            throw "ModuleVersionUnknownModule: $name"
        }
    }
    $selected = @($projects | Where-Object { 'All' -iin $Module -or $_.Suite -iin $Module -or $_.Name -iin $Module })
    if (!$selected.Count) { throw 'ModuleVersionNoBusinessModules' }

    $encoding = [Text.UTF8Encoding]::new($false,$true)
    $plan = foreach ($project in $selected) {
        $path = $project.ManifestPath
        $original = [IO.File]::ReadAllTextAsync($path,$encoding).GetAwaiter().GetResult()
        $manifest = Import-PowerShellDataFile -LiteralPath $path
        if ([IO.File]::ReadAllText($path,$encoding) -cne $original) { throw "ModuleVersionManifestChanged: $path" }
        $base = [string]$manifest.ModuleVersion
        $label = [string]$manifest.PrivateData.PSData.Prerelease
        $previous = if ($label) { "$base-$label" } else { $base }
        $next = if ($PSCmdlet.ParameterSetName -eq 'Bump') {
            Get-QuietBumpedModuleVersion -Version $base -Prerelease $label -Bump $Bump
        } else { $Version }
        $updated = Get-QuietReleaseManifestText -Text $original -Version $next
        [pscustomobject]@{
            Module = $project.Name
            PreviousVersion = $previous
            Version = $next
            ManifestPath = $path
            OriginalText = $original
            UpdatedText = $updated
            Changed = $original -cne $updated
        }
    }
    $changes = @($plan | Where-Object Changed)
    $applied = $false
    if ($changes.Count) {
        $summary = ($changes | ForEach-Object { "$($_.Module) $($_.PreviousVersion) -> $($_.Version)" }) -join ', '
        if ($PSCmdlet.ShouldProcess($WorkspaceRoot,"Update module versions ($summary)")) {
            Update-QuietModuleVersionFiles -Changes $changes -Encoding $encoding
            $applied = $true
        }
    }
    foreach ($entry in $plan) {
        [pscustomobject]@{
            Module = $entry.Module
            ManifestPath = $entry.ManifestPath
            PreviousVersion = $entry.PreviousVersion
            Version = $entry.Version
            Changed = $entry.Changed
            Updated = $applied -and $entry.Changed
        }
    }
}

Export-ModuleMember -Function 'Invoke-QuietScriptNewVersion'
