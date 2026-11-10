<#
.SYNOPSIS
    Checks and applies NuGet package updates for Directory.Packages.props (Central Package Management).
.PARAMETER Apply
    Apply all available updates without prompting.
.PARAMETER IncludePrerelease
    Include pre-release versions in the update check.
.PARAMETER ParallelMax
    Maximum number of concurrent NuGet API requests (default 4).
.EXAMPLE
    .\Update-Packages.ps1
    .\Update-Packages.ps1 -Apply
    .\Update-Packages.ps1 -Apply -IncludePrerelease
    .\Update-Packages.ps1 -ParallelMax 8
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$IncludePrerelease,
    [int]$ParallelMax = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$propsFile = Join-Path $PSScriptRoot 'Directory.Packages.props'

if (-not (Test-Path $propsFile)) {
    Write-Error "Directory.Packages.props not found at: $propsFile"
    exit 1
}

# ── Helpers ──────────────────────────────────────────────────────────────────

function Get-LatestNuGetVersion {
    param(
        [string]$PackageId,
        [string]$CurrentVersion,
        [bool]$IncludePrerelease
    )

    $url = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLower())/index.json"
    try {
        $response = Invoke-RestMethod -Uri $url -TimeoutSec 10 -ErrorAction Stop
        $versions = $response.versions

        $currentIsPrerelease = $CurrentVersion -match '-'

        $candidates = $versions | Where-Object {
            if ($IncludePrerelease -or $currentIsPrerelease) { $true }
            else { $_ -notmatch '-' }
        }

        return $candidates | Select-Object -Last 1
    }
    catch {
        return $null
    }
}

function Compare-SemVer {
    # Returns negative if a < b, 0 if equal, positive if a > b
    param([string]$a, [string]$b)

    $parse = {
        param([string]$v)
        $parts  = $v -split '-', 2
        $nums   = $parts[0] -split '\.' | ForEach-Object { [int]$_ }
        while ($nums.Count -lt 4) { $nums += @(0) }
        @{ nums = $nums; pre = if ($parts.Count -gt 1) { $parts[1] } else { $null } }
    }

    $pa = & $parse $a
    $pb = & $parse $b

    for ($i = 0; $i -lt 4; $i++) {
        $d = $pa.nums[$i] - $pb.nums[$i]
        if ($d -ne 0) { return $d }
    }

    # No pre-release tag is "higher" than having one (1.0.0 > 1.0.0-preview)
    if ($null -eq $pa.pre -and $null -ne $pb.pre) { return 1  }
    if ($null -ne $pa.pre -and $null -eq $pb.pre) { return -1 }
    if ($null -ne $pa.pre -and $null -ne $pb.pre) {
        return [string]::Compare($pa.pre, $pb.pre, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return 0
}

# ── Load packages ─────────────────────────────────────────────────────────────

[xml]$xml = [System.IO.File]::ReadAllText($propsFile, [System.Text.UTF8Encoding]::new($false))

$packages = @($xml.Project.ItemGroup.PackageVersion | ForEach-Object {
    [PSCustomObject]@{ Id = $_.Include; Current = $_.Version }
})

# ── Check versions ───────────────────────────────────────────────────────────

$checkMark  = '✓'
$upArrow    = '↑'
$crossMark  = '✗'

$updates  = [System.Collections.Generic.List[PSCustomObject]]::new()
$errors   = [System.Collections.Generic.List[string]]::new()
$maxLen   = [int](($packages | ForEach-Object { $_.Id.Length } | Measure-Object -Maximum).Maximum) + 2
$verColW  = 14
$statColW = 22

function Write-Row {
    param(
        [string]$Cycle,       [ConsoleColor]$CycleColor  = 'Gray',
        [string]$Version,
        [string]$Status,      [ConsoleColor]$StatusColor = 'Gray',
        [string]$Name
    )
    Write-Host -NoNewline '  '
    Write-Host -NoNewline ($Cycle.PadRight(1) + '  ') -ForegroundColor $CycleColor
    Write-Host -NoNewline ($Version.PadRight($verColW) + '  ')
    Write-Host -NoNewline ($Status.PadRight($statColW) + '  ') -ForegroundColor $StatusColor
    Write-Host $Name
}

Write-Host ''
Write-Host ("  {0}  {1}  {2}  {3}" -f ' ', 'Version'.PadRight($verColW), 'Status'.PadRight($statColW), 'Package') -ForegroundColor Cyan
Write-Host ("  {0}  {1}  {2}  {3}" -f '─', ('─' * $verColW), ('─' * $statColW), ('─' * $maxLen)) -ForegroundColor DarkGray

# Append completed rows instead of addressing console coordinates: tables may
# exceed the buffer height, wrap in narrow terminals, or be redirected to a file.

# ── Parallel fetch using curl.exe processes ───────────────────────────────────

# Build all jobs upfront — processes start as $null (launched in waves)
$jobs = @()
for ($i = 0; $i -lt $packages.Count; $i++) {
    $jobs += @{
        Index   = $i
        Process = $null
        TmpFile = [System.IO.Path]::GetTempFileName()
        Done    = $false
        Attempt = 0
        Started = $false
    }
}

function Launch-Curl {
    param([hashtable]$Job)
    $pkg = $packages[$Job.Index]
    $url = "https://api.nuget.org/v3-flatcontainer/$($pkg.Id.ToLower())/index.json"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'curl.exe'
    $psi.Arguments = "-s --connect-timeout 10 --max-time 15 -o `"$($Job.TmpFile)`" `"$url`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $Job.Process = [System.Diagnostics.Process]::Start($psi)
    $Job.Attempt++
    $Job.Started = $true
}

$pendingCount = $packages.Count

try {
    while ($pendingCount -gt 0) {
        Write-Progress -Id 1 -Activity 'Checking NuGet packages' -Status "$($packages.Count - $pendingCount) / $($packages.Count) completed" -PercentComplete ([int](100 * ($packages.Count - $pendingCount) / $packages.Count))

        # Launch new jobs up to $ParallelMax active
        $active = @($jobs | Where-Object { $_.Started -and -not $_.Done }).Count
        foreach ($job in $jobs) {
            if ($active -ge $ParallelMax) { break }
            if (-not $job.Started) {
                Launch-Curl -Job $job
                $active++
            }
        }

        # Poll all active jobs
        foreach ($job in $jobs) {
            if ($job.Done -or -not $job.Started) { continue }

            $i   = $job.Index
            $pkg = $packages[$i]

            if ($job.Process.HasExited) {
                $exitCode = $job.Process.ExitCode
                $job.Process.Dispose()
                $json = $null

                if ($exitCode -eq 0 -and (Test-Path $job.TmpFile)) {
                    $raw = [System.IO.File]::ReadAllText($job.TmpFile)
                    if ($raw.Length -gt 0) { $json = $raw }
                }

                # Retry on failure (up to 3 attempts)
                if ($null -eq $json -and $job.Attempt -lt 3) {
                    Launch-Curl -Job $job
                    continue
                }

                # Clean up temp file
                if (Test-Path $job.TmpFile) { Remove-Item $job.TmpFile -Force }

                $job.Done = $true
                $pendingCount--

                # Parse result
                $latest = $null
                if ($json) {
                    try {
                        $response = $json | ConvertFrom-Json
                        $versions = $response.versions
                        $currentIsPrerelease = $pkg.Current -match '-'
                        $candidates = $versions | Where-Object {
                            if ($IncludePrerelease -or $currentIsPrerelease) { $true }
                            else { $_ -notmatch '-' }
                        }
                        $latest = $candidates | Select-Object -Last 1
                    }
                    catch { }
                }

                if ($null -eq $latest) {
                    Write-Row `
                        -Cycle $crossMark -CycleColor Red `
                        -Version $pkg.Current `
                        -Status 'fetch error' -StatusColor Red `
                        -Name $pkg.Id
                    $errors.Add($pkg.Id)
                }
                elseif ((Compare-SemVer $pkg.Current $latest) -lt 0) {
                    Write-Row `
                        -Cycle ' ' `
                        -Version $pkg.Current `
                        -Status "$upArrow $latest" -StatusColor Yellow `
                        -Name $pkg.Id
                    $updates.Add([PSCustomObject]@{ Id = $pkg.Id; Current = $pkg.Current; Latest = $latest })
                }
                else {
                    Write-Row `
                        -Cycle ' ' `
                        -Version $pkg.Current `
                        -Status $checkMark -StatusColor Green `
                        -Name $pkg.Id
                }
            }
        }

        if ($pendingCount -gt 0) { Start-Sleep -Milliseconds 80 }
    }
}
finally {
    Write-Progress -Id 1 -Activity 'Checking NuGet packages' -Completed
}

Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "Could not fetch: $($errors -join ', ')" -ForegroundColor Yellow
    Write-Host ""
}

if ($updates.Count -eq 0) {
    Write-Host "All packages are up to date." -ForegroundColor Green
    exit 0
}

# ── Select updates ────────────────────────────────────────────────────────────

$toApply = [System.Collections.Generic.List[PSCustomObject]]::new()

if ($Apply) {
    $toApply.AddRange($updates)
}
else {
    Write-Host "Available updates:" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $updates.Count; $i++) {
        $u = $updates[$i]
        Write-Host ("  [{0,2}]  {1}  {2} -> {3}" -f ($i + 1), $u.Id.PadRight($maxLen), $u.Current.PadRight(12), $u.Latest)
    }
    Write-Host ""
    Write-Host "  Enter package numbers (e.g.  1,3), 'all', or 'none' (default: all)"
    $raw = (Read-Host "  Selection").Trim()

    if ($raw -eq '' -or $raw.ToLower() -eq 'all') {
        $toApply.AddRange($updates)
    }
    elseif ($raw.ToLower() -eq 'none') {
        Write-Host "No updates selected. Exiting."
        exit 0
    }
    else {
        foreach ($token in ($raw -split '[,\s]+')) {
            $idx = 0
            if ([int]::TryParse($token, [ref]$idx) -and $idx -ge 1 -and $idx -le $updates.Count) {
                $toApply.Add($updates[$idx - 1])
            }
            else {
                Write-Warning "Ignored invalid selection: '$token'"
            }
        }
    }
}

if ($toApply.Count -eq 0) {
    Write-Host "No updates selected."
    exit 0
}

# ── Apply updates ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Applying $($toApply.Count) update(s)..." -ForegroundColor Cyan
Write-Host ""

$content = [System.IO.File]::ReadAllText($propsFile, [System.Text.UTF8Encoding]::new($false))

foreach ($u in $toApply) {
    $escapedId  = [regex]::Escape($u.Id)
    $escapedVer = [regex]::Escape($u.Current)
    $pattern    = "(<PackageVersion\s+Include=""$escapedId""\s+Version="")$escapedVer("")"
    $replacement = "`${1}$($u.Latest)`${2}"
    $newContent  = $content -replace $pattern, $replacement

    if ($newContent -eq $content) {
        Write-Warning "  Pattern not matched for $($u.Id) — skipped"
        continue
    }

    $content = $newContent
    Write-Host ("  {0}  {1} -> {2}" -f $u.Id.PadRight($maxLen), $u.Current, $u.Latest) -ForegroundColor Green
}

[System.IO.File]::WriteAllText($propsFile, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Done. $propsFile updated." -ForegroundColor Green
