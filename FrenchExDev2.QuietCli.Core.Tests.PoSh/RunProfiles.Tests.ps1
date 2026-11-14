#requires -Version 7.6
<#
.SYNOPSIS
Example, property, fuzz and integration tests of the run-profile tooling (scripts/lib/Run*.psm1 and the profile scripts).

.DESCRIPTION
Standalone runner: exits with the number of failed cases. Property and fuzz cases use fixed seeds so every failure is
reproducible. With -Mutation, the suite is replaced by the mutation campaign of RunProfiles.Mutation.ps1.

.PARAMETER Seed
Base seed of the generated cases.

.PARAMETER Iterations
Generated inputs per property case.

.PARAMETER Skip
Case-name fragments; matching cases are counted as skipped.

.PARAMETER Mutation
Runs the mutation campaign (RunProfiles.Mutation.ps1) instead of the suite.

.PARAMETER MutantName
With -Mutation, restricts the campaign to the named mutants.

.EXAMPLE
pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1 -Mutation
#>
using module ../scripts/lib/RunLog.psm1
[CmdletBinding()]
param(
    [int]$Seed = 61207,
    [ValidateRange(10, 100000)][int]$Iterations = 300,
    [string[]]$Skip = @(),
    [switch]$Mutation,
    [string[]]$MutantName = @(),
    [ValidateSet('utf-8', 'oem')][string]$ConsoleEncoding = 'utf-8'
)
$ErrorActionPreference = 'Stop'
$scripts = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts'))
foreach ($module in 'RunEncoding', 'RunFormat', 'RunStatistics', 'RunProfileStore', 'RunProfiler') { Import-Module (Join-Path $scripts "lib/$module.psm1") -Force }
# The console encoding is a boundary setting: tables use box-drawing characters and the consumer decodes strict UTF-8.
[void](Set-RunConsoleEncoding -Name $ConsoleEncoding)
# Boundary self-check with an independent oracle (65001 and the culture's OEM page, not the module's own resolution).
# It fails in pure ASCII, because a consumer that decodes strict UTF-8 cannot read anything else once the console is wrong.
$expectedCodePage = if ($ConsoleEncoding -eq 'utf-8') { 65001 } else { [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage }
if ([Console]::OutputEncoding.CodePage -ne $expectedCodePage -or $global:OutputEncoding.CodePage -ne $expectedCodePage) {
    [Console]::Error.WriteLine("console encoding self-check failed: expected code page $expectedCodePage, console $([Console]::OutputEncoding.CodePage), pipe $($global:OutputEncoding.CodePage)")
    'SUMMARY Passed=0 Failed=1 Skipped=0'
    exit 1
}
# Skip entries may be comma-separated, because `pwsh -File` passes an array argument as one string.
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Mutation) { & (Join-Path $PSScriptRoot 'RunProfiles.Mutation.ps1') -Seed $Seed -MutantName $MutantName -ConsoleEncoding $ConsoleEncoding; exit $LASTEXITCODE }
$work = Join-Path ([IO.Path]::GetTempPath()) ('RunProfilesTests-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$counters = @{ Passed = 0; Failed = 0; Skipped = 0 }
$clock = [Diagnostics.Stopwatch]::StartNew()

function Test-Case {
    <#
    .SYNOPSIS
    Runs one named case and records its outcome.
    .PARAMETER Name
    Case name.
    .PARAMETER Body
    Case body; throws on failure.
    #>
    param([string]$Name, [scriptblock]$Body)
    if (@($Skip | Where-Object { $Name.Contains($_) }).Count -gt 0) { $counters.Skipped++; return }
    $case = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body; $counters.Passed++; $state = 'passed' } catch { $counters.Failed++; $state = "FAILED: $($_.Exception.Message)" }
    '{0,-92} {1,8}  {2}' -f $Name, (Format-RunDuration $case.Elapsed.TotalMilliseconds), $state
}

function Assert-That {
    <#
    .SYNOPSIS
    Throws with a bounded message when a condition is false.
    .PARAMETER Condition
    Expected property.
    .PARAMETER Message
    Failure description.
    #>
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    <#
    .SYNOPSIS
    Throws unless the body fails with a message starting with the expected code.
    .PARAMETER Body
    Code expected to fail.
    .PARAMETER Code
    Expected error-code prefix.
    #>
    param([scriptblock]$Body, [string]$Code)
    try { $null = & $Body } catch { Assert-That ($_.Exception.Message.Contains($Code)) "Expected '$Code' but got '$($_.Exception.Message)'"; return }
    throw "Expected failure '$Code' but nothing was thrown"
}

function New-RandomText {
    <#
    .SYNOPSIS
    Generates text rich in characters that stress PowerShell quoting.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER ControlFree
    Excludes control characters.
    #>
    param([Random]$Random, [switch]$ControlFree)
    $alphabet = @('a', 'Z', '0', ' ', "'", '"', '`', '$', '@', '{', '}', '(', ')', '#', ';', '|', '&', '\', '/', '-', '_', '.', ',', 'é', 'ß', '漢', '😀', [string][char]0x2018, [string][char]0x2019, [string][char]0x201A, [string][char]0x201B, '$(1)', '@{', '<#')
    -join (1..$Random.Next(0, 14) | ForEach-Object { $alphabet[$Random.Next($alphabet.Count)] })
}

function New-RandomParameters {
    <#
    .SYNOPSIS
    Generates a parameter table with every supported value kind.
    .PARAMETER Random
    Seeded generator.
    #>
    param([Random]$Random)
    $parameters = @{}
    foreach ($index in 1..$Random.Next(0, 7)) {
        $value = switch ($Random.Next(6)) {
            0 { New-RandomText $Random }
            1 { $Random.Next([int]::MinValue, [int]::MaxValue) }
            2 { [long]$Random.NextInt64([long]::MinValue, [long]::MaxValue) }
            3 { [double]($Random.NextDouble() * 1e6 - 5e5) }
            4 { $Random.Next(2) -eq 0 }
            5 { , @(1..$Random.Next(0, 4) | ForEach-Object { New-RandomText $Random }) }
        }
        $parameters["P$index"] = $value
    }
    return $parameters
}

function Test-DeepEqual {
    <#
    .SYNOPSIS
    Compares supported values by type and content.
    .PARAMETER Left
    First value.
    .PARAMETER Right
    Second value.
    #>
    param($Left, $Right)
    if ($Left -is [Array]) { if ($Right -isnot [Array] -or $Left.Count -ne $Right.Count) { return $false }; for ($i = 0; $i -lt $Left.Count; $i++) { if (-not (Test-DeepEqual $Left[$i] $Right[$i])) { return $false } }; return $true }
    return $Left.GetType() -eq $Right.GetType() -and $Left -ceq $Right
}

try {
    "Project: QuietCli.Core.Tests.PoSh | Task: run-profile tooling tests (seed $Seed, $Iterations iterations)"
    "Workspace: $scripts"
    ''
    Test-Case 'names: accept the documented shape, reject everything else' {
        foreach ($good in 'a', 'coldstart-100', '0-a', ('a' * 64)) { Assert-That (Test-RunProfileName $good) "rejected '$good'" }
        foreach ($bad in $null, '', '-a', 'A', 'a_b', 'a b', 'a.b', '../x', 'a/b', ('a' * 65), "a`n", 'é') { Assert-That (-not (Test-RunProfileName $bad)) "accepted '$bad'" }
    }
    Test-Case "names: property - regex agrees with an independent character-class oracle ($Iterations random strings)" {
        $random = [Random]::new($Seed)
        for ($i = 0; $i -lt $Iterations; $i++) {
            $text = New-RandomText $random
            $oracle = $text.Length -ge 1 -and $text.Length -le 64 -and ($text.ToCharArray() | ForEach-Object { ($_ -ge 'a' -and $_ -le 'z') -or ($_ -ge '0' -and $_ -le '9') -or $_ -eq '-' }) -notcontains $false -and $text[0] -ne '-'
            Assert-That ((Test-RunProfileName $text) -eq $oracle) "disagreement on '$text'"
        }
    }
    Test-Case "store: property - render then load is the identity ($Iterations random profiles)" {
        $random = [Random]::new($Seed + 1)
        $directory = Join-Path $work 'roundtrip'
        for ($i = 0; $i -lt $Iterations; $i++) {
            $profile = @{ SchemaVersion = 1; Name = "p$i"; Script = 'Target.ps1'; Parameters = (New-RandomParameters $random) }
            if ($random.Next(2) -eq 0) { $profile.Description = New-RandomText $random }
            $path = Write-RunProfile -Profile $profile -Directory $directory
            $loaded = Read-RunProfile -Path $path
            Assert-That ($loaded.Keys.Count -eq $profile.Keys.Count) "key count differs at $i"
            foreach ($key in $profile.Parameters.Keys) { Assert-That (Test-DeepEqual $profile.Parameters[$key] $loaded.Parameters[$key]) "parameter $key differs at $i (seed $($Seed + 1))" }
            if ($profile.ContainsKey('Description')) { Assert-That ($loaded.Description -ceq $profile.Description) "description differs at $i" }
        }
    }
    Test-Case 'store: files are UTF-8 without BOM, LF only, byte-identical across renders' {
        $profile = @{ SchemaVersion = 1; Name = 'bytes'; Script = 'Target.ps1'; Description = 'é 漢 😀'; Parameters = @{ B = 2; A = 'x' } }
        $first = ConvertTo-RunProfileSource $profile
        Assert-That ($first -ceq (ConvertTo-RunProfileSource $profile)) 'render is not deterministic'
        Assert-That (-not $first.Contains("`r")) 'CR found'
        $path = Write-RunProfile -Profile $profile -Directory (Join-Path $work 'bytes')
        $bytes = [IO.File]::ReadAllBytes($path)
        Assert-That (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'BOM found'
        Assert-That ($first.IndexOf('A = ', [StringComparison]::Ordinal) -lt $first.IndexOf('B = ', [StringComparison]::Ordinal)) 'parameters are not sorted'
    }
    Test-Case 'store: existing profile is protected unless forced' {
        $profile = @{ SchemaVersion = 1; Name = 'guard'; Script = 'Target.ps1'; Parameters = @{ A = 1 } }
        $directory = Join-Path $work 'guard'
        [void](Write-RunProfile -Profile $profile -Directory $directory)
        Assert-Throws { Write-RunProfile -Profile $profile -Directory $directory } 'RunProfileExists'
        $profile.Parameters.A = 2
        [void](Write-RunProfile -Profile $profile -Directory $directory -Force)
        Assert-That ((Read-RunProfile -Path (Get-RunProfilePath 'guard' $directory)).Parameters.A -eq 2) 'force did not replace'
    }
    Test-Case 'store: fuzz - code in a profile file is rejected and never executed' {
        $marker = Join-Path $work 'pwned.txt'
        $payloads = @(
            "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = (Set-Content '$marker' 1) } }",
            "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = `$(Set-Content '$marker' 1) } }",
            "Set-Content '$marker' 1; @{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{} }",
            "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = `$env:PATH } }",
            "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = [IO.File]::WriteAllText('$marker','1') } }",
            "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = { Set-Content '$marker' 1 } } }",
            "& { Set-Content '$marker' 1 }", '@{ SchemaVersion = 1; Name = ', "@{ SchemaVersion = 1; Name = 'x'; Script = 'a.ps1'; Parameters = @{ A = `$unknown } }")
        $directory = Join-Path $work 'fuzz'; [void][IO.Directory]::CreateDirectory($directory)
        $index = 0
        foreach ($payload in $payloads) {
            $index++
            $file = Join-Path $directory "x.profile.psd1"
            [IO.File]::WriteAllText($file, $payload)
            Assert-Throws { Read-RunProfile -Path $file } 'RunProfile'
        }
        Assert-That (-not (Test-Path $marker)) 'a payload executed'
    }
    Test-Case 'store: schema violations are each rejected with a coded error' {
        $base = { @{ SchemaVersion = 1; Name = 'ok'; Script = 'Target.ps1'; Parameters = @{ A = 1 } } }
        $cases = @(
            @{ Mutate = { param($p) $p.Extra = 1 }; Code = 'RunProfileUnknownKey' }
            @{ Mutate = { param($p) $p.Remove('Script') }; Code = 'RunProfileMissingKey' }
            @{ Mutate = { param($p) $p.SchemaVersion = 2 }; Code = 'RunProfileUnsupportedSchema' }
            @{ Mutate = { param($p) $p.Name = 'Bad Name' }; Code = 'RunProfileInvalidName' }
            @{ Mutate = { param($p) $p.Script = '..\evil.ps1' }; Code = 'RunProfileInvalidScript' }
            @{ Mutate = { param($p) $p.Script = 'a/b.ps1' }; Code = 'RunProfileInvalidScript' }
            @{ Mutate = { param($p) $p.Script = 'x.exe' }; Code = 'RunProfileInvalidScript' }
            @{ Mutate = { param($p) $p.Parameters = @{ 'bad key' = 1 } }; Code = 'RunProfileInvalidParameterName' }
            @{ Mutate = { param($p) $p.Parameters = @{ A = @{ Nested = 1 } } }; Code = 'RunProfileUnsupportedValue' }
            @{ Mutate = { param($p) $p.Parameters = @{ A = $null } }; Code = 'RunProfileUnsupportedValue' }
            @{ Mutate = { param($p) $p.Parameters = @{ A = [double]::NaN } }; Code = 'RunProfileUnsupportedValue' }
            @{ Mutate = { param($p) $p.Description = 5 }; Code = 'RunProfileInvalidDescription' }
        )
        foreach ($case in $cases) { $profile = & $base; & $case.Mutate $profile; Assert-Throws { Assert-RunProfile -Profile $profile } $case.Code }
        Assert-Throws { Assert-RunProfile -Profile (& $base) -ExpectedName 'other' } 'RunProfileNameMismatch'
    }
    Test-Case "store: property - merge is a right-biased union ($Iterations random pairs)" {
        $random = [Random]::new($Seed + 2)
        for ($i = 0; $i -lt $Iterations; $i++) {
            $profile = @{ Parameters = (New-RandomParameters $random) }; $arguments = New-RandomParameters $random
            $arguments.Remove('P1'); $arguments['Q1'] = 'override'; if ($profile.Parameters.Count) { $arguments[@($profile.Parameters.Keys)[0]] = 'wins' }
            $merged = Merge-RunProfileArguments -Profile $profile -Arguments $arguments
            Assert-That ($merged.Count -eq (@($profile.Parameters.Keys) + @($arguments.Keys) | Sort-Object -Unique).Count) 'not a union'
            foreach ($key in $arguments.Keys) { Assert-That (Test-DeepEqual $merged[$key] $arguments[$key]) "argument $key lost" }
            foreach ($key in $profile.Parameters.Keys) { if (-not $arguments.ContainsKey($key)) { Assert-That (Test-DeepEqual $merged[$key] $profile.Parameters[$key]) "default $key lost" } }
        }
    }
    Test-Case 'logger: filtering, per-level counters, suppressed counter and shared child counters' {
        $memory = [MemoryLogSink]::new()
        $logger = New-RunLogger -Level Warn -Component 'unit' -NoConsole -ExtraSinks $memory
        $child = $logger.Child('sub')
        $logger.Trace('t'); $logger.Debug('d'); $logger.Info('i'); $logger.Warn('w'); $child.Error('e')
        Assert-That ($memory.Lines.Count -eq 2) "expected 2 written lines, got $($memory.Lines.Count)"
        Assert-That ($memory.Lines[1] -match '^\d\d:\d\d:\d\d\.\d{3} \[ERROR\] unit\.sub: e$') "bad line format: $($memory.Lines[1])"
        foreach ($level in 'trace', 'debug', 'info', 'warn', 'error') { Assert-That ($logger.Get("log.$level") -eq 1) "counter log.$level" }
        Assert-That ($logger.Get('log.suppressed') -eq 3) 'suppressed counter'
        $off = New-RunLogger -Level Off -NoConsole -ExtraSinks $memory; $off.Error('x')
        Assert-That ($memory.Lines.Count -eq 2) 'Off level wrote a line'
    }
    Test-Case 'logger: Time counts calls, failures and elapsed time; Snapshot is a sorted copy' {
        $logger = New-RunLogger -Level Off -NoConsole
        Assert-That ($logger.Time('op', { 42 }) -eq 42) 'result not returned'
        Assert-Throws { $logger.Time('op', { throw 'boom' }) } 'boom'
        Assert-That ($logger.Get('op.count') -eq 2 -and $logger.Get('op.ok') -eq 1 -and $logger.Get('op.failed') -eq 1) 'time counters'
        $snapshot = $logger.Snapshot(); $logger.Increment('op.count')
        Assert-That ($snapshot['op.count'] -eq 2) 'snapshot is not a copy'
        $keys = @($snapshot.Keys); Assert-That ((($keys | Sort-Object -CaseSensitive) -join ',') -ceq ($keys -join ',')) 'snapshot not sorted'
    }
    Test-Case 'logger: file sink appends UTF-8 lines with LF and a failing sink is counted, not fatal' {
        $path = Join-Path $work 'logs/run.log'
        $logger = New-RunLogger -Level Info -NoConsole -LogPath $path
        $logger.Info('héllo 漢'); $logger.Info('second')
        $text = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true))
        Assert-That ($text.Split("`n").Count -eq 3 -and -not $text.Contains("`r") -and $text.Contains('héllo 漢')) 'file content'
        class FailingSink : RunLogSink {
            [void] Write([string]$Line) {
                <#
                .SYNOPSIS
                Simulates a sink failure without publishing the log line.
                .PARAMETER Line
                Line intentionally rejected by this fixture.
                #>
                throw 'sink down'
            }
        }
        $failing = New-RunLogger -Level Info -NoConsole -ExtraSinks ([FailingSink]::new()); $failing.Info('x')
        Assert-That ($failing.Get('log.sinkfailed') -eq 1) 'sink failure not counted'
    }
    Test-Case "statistics: property - quantiles are bounded, monotone and shuffle-invariant ($Iterations samples)" {
        $random = [Random]::new($Seed + 3)
        for ($i = 0; $i -lt $Iterations; $i++) {
            $values = [double[]](1..$random.Next(1, 40) | ForEach-Object { $random.NextDouble() * 200 - 100 })
            $shuffled = [double[]]($values | Sort-Object { $random.Next() })
            $previous = [double]::NegativeInfinity
            foreach ($p in 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1) {
                $q = Get-RunQuantile $values $p
                Assert-That ($q -ge $previous) "not monotone at p=$p"; $previous = $q
                Assert-That ($q -eq (Get-RunQuantile $shuffled $p)) 'not shuffle-invariant'
            }
            Assert-That ((Get-RunQuantile $values 0) -eq ($values | Measure-Object -Minimum).Minimum -and (Get-RunQuantile $values 1) -eq ($values | Measure-Object -Maximum).Maximum) 'bounds'
        }
        Assert-Throws { Get-RunQuantile ([double[]]@()) 0.5 } 'RunStatistics'
    }
    Test-Case 'statistics: bootstrap - constant shift, determinism, zero noise and direction (seeded)' {
        Assert-That ((Get-RunVerdict (Get-PairedBootstrapInterval -Differences ([double[]]@(5, 5, 5)) -Seed 1)) -eq 'too-few-pairs') 'three pairs must not yield a direction'
        $constant = Get-PairedBootstrapInterval -Differences ([double[]](1..50 | ForEach-Object { 5.0 })) -Seed 1
        Assert-That ($constant.Low -eq 5 -and $constant.High -eq 5 -and (Get-RunVerdict $constant) -eq 'slower') 'constant shift'
        $random = [Random]::new($Seed + 4)
        $noise = { param([double]$shift, [int]$n) [double[]](1..$n | ForEach-Object { $shift + ($random.NextDouble() + $random.NextDouble() + $random.NextDouble() - 1.5) * 20 }) }
        $zero = & $noise 0 200
        Assert-That ((Get-PairedBootstrapInterval $zero -Seed 9).Low -eq (Get-PairedBootstrapInterval $zero -Seed 9).Low) 'not deterministic'
        Assert-That ((Get-RunVerdict (Get-PairedBootstrapInterval $zero -Seed 9)) -eq 'inconclusive') 'noise alone must be inconclusive'
        Assert-That ((Get-RunVerdict (Get-PairedBootstrapInterval (& $noise 15 200) -Seed 9)) -eq 'slower') 'positive shift must be slower'
        Assert-That ((Get-RunVerdict (Get-PairedBootstrapInterval (& $noise -15 200) -Seed 9)) -eq 'faster') 'negative shift must be faster'
        $small = Get-PairedBootstrapInterval (& $noise 0 20) -Seed 9; $large = Get-PairedBootstrapInterval (& $noise 0 1000) -Seed 9
        Assert-That (($large.High - $large.Low) -lt ($small.High - $small.Low)) 'interval must narrow as pairs grow'
    }
    Test-Case "format: property - every table line has one width within the limit ($Iterations random tables)" {
        $random = [Random]::new($Seed + 5)
        for ($i = 0; $i -lt $Iterations; $i++) {
            $columns = $random.Next(1, 6); $width = $random.Next(20, 140)
            $headers = 1..$columns | ForEach-Object { New-RandomText $random }
            $rows = [Collections.Generic.List[object]]::new(); foreach ($r in 1..$random.Next(0, 6)) { $rows.Add(@(1..$columns | ForEach-Object { New-RandomText $random })) }
            $lines = @(Format-RunTable -Headers $headers -Rows $rows -Width $width)
            $lengths = $lines | ForEach-Object { $_.Length } | Sort-Object -Unique
            Assert-That (@($lengths).Count -eq 1) "ragged table at $i"
            Assert-That ($lines[0].StartsWith('┌') -and $lines[-1].StartsWith('└')) 'frame'
            if ($columns * 7 + 1 -le $width) { Assert-That ($lengths -le $width) "table wider than $width at $i" }
        }
    }
    Test-Case 'format: a single row and a single counter keep their column structure' {
        $lines = @(Format-RunCounters ([ordered]@{ 'only.one' = 7 }) -Width 60)
        Assert-That ($lines.Count -eq 5 -and $lines[3] -match 'only\.one' -and $lines[3] -match '7 │$') "single counter table: $($lines -join '|')"
    }
    Test-Case 'format: compact durations follow the documented examples' {
        $expected = @{ 0 = '0ms'; 12 = '12ms'; 999 = '999ms'; 1000 = '1s'; 90000 = '1m30s'; 60000 = '1m'; 3600000 = '1h'; 7500000 = '2h5m'; -37 = '-37ms' }
        foreach ($pair in $expected.GetEnumerator()) { Assert-That ((Format-RunDuration $pair.Key) -ceq $pair.Value) "$($pair.Key) -> $(Format-RunDuration $pair.Key), expected $($pair.Value)" }
        Assert-That ((Format-RunDuration $null) -ceq '-') 'unknown'
    }
    Test-Case 'format: compact data sizes round to 2 decimals, signed adds a leading + only when non-negative' {
        Assert-That ((Format-RunDataSize 1MB) -ceq '1.00 MiB') 'exact MiB'
        Assert-That ((Format-RunDataSize (1.5 * 1MB)) -ceq '1.50 MiB') 'fractional MiB'
        Assert-That ((Format-RunDataSize 0) -ceq '0.00 MiB') 'zero'
        Assert-That ((Format-RunDataSize (-2 * 1MB)) -ceq '-2.00 MiB') 'negative keeps its sign unsigned'
        Assert-That ((Format-RunDataSize $null) -ceq '-') 'unknown'
        Assert-That ((Format-RunDataSize (1MB) -Signed) -ceq '+1.00 MiB') 'signed positive gets a +'
        Assert-That ((Format-RunDataSize 0 -Signed) -ceq '+0.00 MiB') 'signed zero gets a + (non-negative)'
        Assert-That ((Format-RunDataSize (-1MB) -Signed) -ceq '-1.00 MiB') 'signed negative keeps its own sign, no double sign'
    }
    Test-Case 'format: control characters are rejected in literals; quotes of every kind are doubled' {
        foreach ($bad in "a`nb", "a`rb", "a`tb", "a$([char]0)b", "a$([char]0x7F)b") { Assert-Throws { ConvertTo-RunSingleQuoted $bad } 'RunLiteralControlCharacter' }
        Assert-That ((ConvertTo-RunSingleQuoted "it's") -ceq "'it''s'") 'ASCII quote'
        Assert-That ((ConvertTo-RunSingleQuoted ([string][char]0x2019)) -ceq "'$([char]0x2019)$([char]0x2019)'") 'typographic quote'
    }
    Test-Case 'store: doubles keep their type, parameters are sorted, unsupported numbers are refused' {
        $profile = @{ SchemaVersion = 1; Name = 'types'; Script = 'Target.ps1'; Parameters = @{ Whole = 2.0; Big = 1e21; Neg = -0.5 } }
        $loaded = Read-RunProfile -Path (Write-RunProfile -Profile $profile -Directory (Join-Path $work 'types'))
        foreach ($key in 'Whole', 'Big', 'Neg') { Assert-That ($loaded.Parameters[$key] -is [double] -and $loaded.Parameters[$key] -eq $profile.Parameters[$key]) "$key lost its type or value" }
        $sorted = @{ SchemaVersion = 1; Name = 'sorted'; Script = 'Target.ps1'; Parameters = @{} }
        foreach ($name in 'H', 'C', 'F', 'A', 'G', 'B', 'E', 'D') { $sorted.Parameters[$name] = 1 }
        $names = [regex]::Matches((ConvertTo-RunProfileSource $sorted), '(?m)^        ([A-H]) = ') | ForEach-Object { $_.Groups[1].Value }
        Assert-That (($names -join '') -ceq 'ABCDEFGH') "unsorted: $($names -join '')"
        foreach ($bad in [double]::PositiveInfinity, [double]::NegativeInfinity, [double]::NaN) { Assert-That (-not (Test-RunProfileValue $bad)) "accepted $bad" }
    }
    Test-Case 'statistics: exact quantiles, even-sized bootstrap median, seed and confidence sensitivity' {
        Assert-That ((Get-RunQuantile ([double[]]@(1, 2, 3, 4)) 0.5) -eq 2.5 -and (Get-RunQuantile ([double[]]@(1, 2, 3, 4)) 0.25) -eq 1.75) 'interpolation'
        $summary = Get-RunSummary ([double[]]@(4, 1, 3, 2))
        Assert-That ($summary.N -eq 4 -and $summary.Min -eq 1 -and $summary.Max -eq 4 -and $summary.Median -eq 2.5 -and $summary.Q1 -eq 1.75 -and $summary.Q3 -eq 3.25) 'summary'
        $even = Get-PairedBootstrapInterval -Differences ([double[]]@(4, 6)) -Seed 3 -Confidence 0.2
        Assert-That ($even.Low -eq 5 -and $even.High -eq 5 -and $even.Median -eq 5) "even median: [$($even.Low), $($even.High)]"
        $random = [Random]::new($Seed + 6); $noise = [double[]](1..60 | ForEach-Object { $random.NextDouble() * 10 - 5 })
        $a = Get-PairedBootstrapInterval $noise -Seed 1; $b = Get-PairedBootstrapInterval $noise -Seed 2
        Assert-That ($a.Low -ne $b.Low -or $a.High -ne $b.High) 'seed ignored'
        $narrow = Get-PairedBootstrapInterval $noise -Seed 1 -Confidence 0.5; $wide = Get-PairedBootstrapInterval $noise -Seed 1 -Confidence 0.99
        Assert-That (($wide.High - $wide.Low) -gt ($narrow.High - $narrow.Low)) 'confidence must widen the interval'
    }
    Test-Case 'statistics: verdict boundaries (zero is inconclusive, 20 pairs is enough, 19 is not)' {
        $make = { param([double]$low, [double]$high, [int]$pairs) [pscustomobject]@{ Pairs = $pairs; Low = $low; High = $high } }
        Assert-That ((Get-RunVerdict (& $make 0 5 100)) -eq 'inconclusive') 'Low = 0'
        Assert-That ((Get-RunVerdict (& $make -5 0 100)) -eq 'inconclusive') 'High = 0'
        Assert-That ((Get-RunVerdict (& $make 1 5 100)) -eq 'slower' -and (Get-RunVerdict (& $make -5 -1 100)) -eq 'faster') 'direction'
        Assert-That ((Get-RunVerdict (& $make 1 5 20)) -eq 'slower' -and (Get-RunVerdict (& $make 1 5 19)) -eq 'too-few-pairs') 'minimum pairs'
    }
    Test-Case 'format: long cells are truncated with an ellipsis, durations round at the second boundary, .ms counters are durations' {
        $lines = @(Format-RunTable -Headers @('A') -Rows @(, @('x' * 60)) -Width 20)
        Assert-That ($lines[3].Contains('…') -and $lines[3].Length -le 20) "no ellipsis: $($lines[3])"
        Assert-That ((Format-RunDuration 999.6) -ceq '1s' -and (Format-RunDuration 999.4) -ceq '999ms') 'rounding boundary'
        $counted = @(Format-RunCounters ([ordered]@{ 'a.ms' = 90000; 'a.n' = 90000 }) -Width 60)
        Assert-That ($counted[3].Contains('1m30s') -and $counted[4].Contains('90000')) 'ms formatting'
    }
    $fixtureScripts = Join-Path $work 'fixture-scripts'; [void][IO.Directory]::CreateDirectory($fixtureScripts)
    [IO.File]::WriteAllText((Join-Path $fixtureScripts 'Fixture.Target.ps1'), @'
[CmdletBinding()]
param([int]$Count = 1, [string]$Word = 'x', [ValidateSet('Trace','Debug','Info','Warn','Error','Off')][string]$LogLevel = 'Info', [string]$LogPath, [switch]$Fail)
if ($Fail) { throw 'FixtureFailed' }
"$Count|$Word|$LogLevel"
'@)
    $profiles = Join-Path $work 'fixture-profiles'
    Test-Case 'scripts: New-RunProfile creates a profile that Invoke-RunProfile runs with merged arguments' {
        $path = & (Join-Path $scripts 'New-RunProfile.ps1') -Name 'fixture-a' -Script 'Fixture.Target.ps1' -Parameters @{ Count = 3; Word = 'é' } -Description 'fixture' -Directory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off
        Assert-That (Test-Path $path) 'profile file missing'
        $out = & (Join-Path $scripts 'Invoke-RunProfile.ps1') fixture-a -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off
        Assert-That ($out -ceq '3|é|Off') "unexpected output '$out'"
        $out = & (Join-Path $scripts 'Invoke-RunProfile.ps1') fixture-a -Arguments @{ Count = 9 } -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off
        Assert-That ($out -like '9|é|*') "override ignored: '$out'"
    }
    Test-Case 'scripts: unknown parameters, missing profiles, existing profiles and failing targets are rejected' {
        $invoke = Join-Path $scripts 'Invoke-RunProfile.ps1'; $create = Join-Path $scripts 'New-RunProfile.ps1'
        Assert-Throws { & $create -Name 'fixture-b' -Script 'Fixture.Target.ps1' -Parameters @{ Nope = 1 } -Directory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'RunProfileUnknownParameter'
        Assert-Throws { & $create -Name 'fixture-a' -Script 'Fixture.Target.ps1' -Directory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'RunProfileExists'
        Assert-Throws { & $create -Name 'fixture-c' -Script 'Missing.ps1' -Directory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'RunProfileTargetNotFound'
        Assert-Throws { & $invoke 'nope' -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'Could not find'
        Assert-Throws { & $invoke 'fixture-a' -Arguments @{ Bogus = 1 } -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'RunProfileUnknownParameter'
        Assert-Throws { & $invoke 'fixture-a' -Arguments @{ Fail = $true } -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off } 'FixtureFailed'
        Assert-Throws { & $invoke '../x' -ProfilesDirectory $profiles -LogLevel Off } 'RunProfileInvalidName'
    }
    Test-Case 'scripts: -WhatIf does not run the target; -List shows the profile; LogLevel is forwarded' {
        $invoke = Join-Path $scripts 'Invoke-RunProfile.ps1'
        Assert-That (-not (& $invoke 'fixture-a' -WhatIf -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off)) 'WhatIf executed the target'
        $listing = @(& $invoke -List -ProfilesDirectory $profiles -LogLevel Off) -join "`n"
        Assert-That ($listing -match 'fixture-a') 'profile not listed'
        Assert-That ($listing -match 'fixture-a\s+│ Fixture\.Target\.ps1\s+│\s+2 │') "a parameter named Count hijacked the parameter count: $listing"
        Assert-That ((& $invoke 'fixture-a' -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Debug) -ceq '3|é|Debug') 'LogLevel not forwarded'
    }
    Test-Case 'scripts: LogLevel is not forwarded to targets that do not declare it; explicit values win' {
        [IO.File]::WriteAllText((Join-Path $fixtureScripts 'Fixture.Plain.ps1'), "[CmdletBinding()]`nparam([int]`$Count = 1)`n`"plain|`$Count`"`n")
        [void](& (Join-Path $scripts 'New-RunProfile.ps1') -Name 'fixture-plain' -Script 'Fixture.Plain.ps1' -Parameters @{ Count = 4 } -Directory $profiles -ScriptDirectory $fixtureScripts -LogLevel Off)
        $invoke = Join-Path $scripts 'Invoke-RunProfile.ps1'
        Assert-That ((& $invoke 'fixture-plain' -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Debug) -ceq 'plain|4') 'plain target'
        Assert-That ((& $invoke 'fixture-a' -Arguments @{ LogLevel = 'Warn' } -ProfilesDirectory $profiles -ScriptDirectory $fixtureScripts -LogLevel Debug) -ceq '3|é|Warn') 'explicit LogLevel overridden'
    }
    . (Join-Path $PSScriptRoot 'RunProfiles.Benchmark.Tests.ps1')
    . (Join-Path $PSScriptRoot 'RunProfiles.Profiler.Tests.ps1')
    Test-Case 'encoding: files are UTF-8 without BOM with LF only; CRLF and CR input is normalized; appends follow the same contract' {
        $path = Join-Path $work 'encoded.txt'
        Write-RunTextFile -Path $path -Text "é`r`n漢`r😀x"
        $expected = [Text.UTF8Encoding]::new($false).GetBytes("é`n漢`n😀x")
        Assert-That ([Convert]::ToHexString([IO.File]::ReadAllBytes($path)) -ceq [Convert]::ToHexString($expected)) 'written bytes differ from BOM-free UTF-8 with LF'
        Write-RunTextFile -Path $path -Text ''
        Assert-That ([IO.File]::ReadAllBytes($path).Length -eq 0) 'an empty text must produce an empty file'
        $log = Join-Path $work 'appended.txt'
        Add-RunTextLine -Path $log -Line "a`r`nb"
        Add-RunTextLine -Path $log -Line 'é'
        $expectedLog = [Text.UTF8Encoding]::new($false).GetBytes("a`nb`né`n")
        Assert-That ([Convert]::ToHexString([IO.File]::ReadAllBytes($log)) -ceq [Convert]::ToHexString($expectedLog)) 'appended bytes differ from BOM-free UTF-8 with LF'
        Assert-That ((Read-RunTextFile -Path $log) -ceq "a`nb`né`n") 'read does not return what was appended'
        Assert-That ((ConvertTo-RunLf "x`r`ny`rz`n") -ceq "x`ny`nz`n") 'ConvertTo-RunLf'
    }
    Test-Case 'encoding: reading and writing are strict - malformed bytes and lone surrogates are errors, never replacements' {
        $path = Join-Path $work 'malformed.txt'
        [IO.File]::WriteAllBytes($path, [byte[]](0x61, 0xFF, 0x62))
        $failure = $null
        try { Read-RunTextFile -Path $path | Out-Null } catch { $failure = $_.Exception.GetBaseException() }
        Assert-That ($failure -is [Text.DecoderFallbackException]) "read of malformed bytes must throw DecoderFallbackException, got '$failure'"
        # A profile that is valid once malformed bytes are replaced: only strict decoding can reject it.
        $source = (ConvertTo-RunProfileSource @{ SchemaVersion = 1; Name = 'bad'; Script = 'Target.ps1'; Description = 'AxB'; Parameters = @{} }).Replace("'AxB'", "'A?B'")
        $sourceBytes = [Text.UTF8Encoding]::new($false).GetBytes($source)
        $marker = [Array]::IndexOf($sourceBytes, [byte]0x3F)
        Assert-That ($marker -ge 0) 'fixture marker not found'
        $sourceBytes[$marker] = 0xFF
        $profilePath = Join-Path $work 'bad.profile.psd1'
        [IO.File]::WriteAllBytes($profilePath, $sourceBytes)
        $failure = $null
        try { Read-RunProfile -Path $profilePath | Out-Null } catch { $failure = $_.Exception.GetBaseException() }
        Assert-That ($failure -is [Text.DecoderFallbackException]) "a profile with malformed bytes must be rejected by strict decoding, got '$failure'"
        $failure = $null
        try { Write-RunTextFile -Path (Join-Path $work 'surrogate.txt') -Text ('a' + [char]0xD800) } catch { $failure = $_.Exception.GetBaseException() }
        Assert-That ($failure -is [Text.EncoderFallbackException]) "write of a lone surrogate must throw EncoderFallbackException, got '$failure'"
    }
    Test-Case 'encoding: console names resolve to documented encodings and Set-RunConsoleEncoding applies them' {
        $utf8 = Resolve-RunConsoleEncoding -Name 'UTF-8'
        Assert-That ($utf8.CodePage -eq 65001 -and $utf8.GetPreamble().Length -eq 0) 'utf-8 must be code page 65001 without BOM'
        $oem = Resolve-RunConsoleEncoding -Name 'oem'
        Assert-That ($oem.CodePage -eq [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) 'oem must be the active OEM code page'
        Assert-Throws { Resolve-RunConsoleEncoding -Name 'latin-1' } 'RunConsoleEncodingUnknown'
        $previous = [Console]::OutputEncoding
        $previousPipe = $global:OutputEncoding
        try {
            [void](Set-RunConsoleEncoding -Name 'oem')
            Assert-That ([Console]::OutputEncoding.CodePage -eq $oem.CodePage -and $global:OutputEncoding.CodePage -eq $oem.CodePage) 'oem was not applied to the console and the pipe'
            [void](Set-RunConsoleEncoding -Name 'utf-8')
            Assert-That ([Console]::OutputEncoding.CodePage -eq 65001 -and $global:OutputEncoding.CodePage -eq 65001) 'utf-8 was not applied to the console and the pipe'
        }
        finally { [Console]::OutputEncoding = $previous; $global:OutputEncoding = $previousPipe }
    }
    Test-Case 'console: quiet decodes child output as strict UTF-8 - a UTF-8 child succeeds, an OEM child fails with a decode error' {
        $oemPage = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        if ($oemPage -eq 65001) { $counters.Skipped++; $counters.Passed--; return }
        if (-not (Get-Command quiet -ErrorAction SilentlyContinue)) { Import-Module (Join-Path $scripts '../FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') }
        $emit = '[Console]::OutputEncoding = [Text.Encoding]::GetEncoding({0}); [Console]::Out.WriteLine([string][char]0x2500 * 3)'
        foreach ($case in @(@{ Page = 65001; Outcome = 'Success' }, @{ Page = $oemPage; Outcome = 'Failed' })) {
            $result = quiet -AsObject -RecordDelimiter "`n" -TimeoutSeconds 60 -Data @{ Lines = 0 } -Output { param($event, $runtime) $runtime.Data.Lines++ } -Complete { param($runtime) } pwsh -NoProfile -Command ($emit -f $case.Page)
            Assert-That ($result.Outcome -eq $case.Outcome) "code page $($case.Page): expected $($case.Outcome) but got $($result.Outcome)"
            if ($case.Outcome -eq 'Failed') { Assert-That ($result.Error[0]['Code'] -ceq 'DecodeOrFramingFailed') "unexpected error code '$($result.Error[0]['Code'])'" }
        }
    }
    Test-Case 'profiler: PSProfiler report is exported for a script block (skipped when the pinned module is absent)' {
        try { $manifest = Resolve-RunProfilerModule } catch { $counters.Skipped++; $counters.Passed--; $script:ProfilerGap = $_.Exception.Message; return }
        $report = Invoke-RunProfiled -ScriptBlock { 1..50 | ForEach-Object { $_ * 2 } | Out-Null } -OutputDirectory (Join-Path $work 'prof') -Label 'unit' -ProfilerModulePath $manifest
        $json = [IO.File]::ReadAllText($report) | ConvertFrom-Json
        Assert-That ($json.Label -eq 'unit' -and $json.ProfilerVersion -eq '4.3.0' -and $json.TopLinesBySelfDuration.Count -gt 0) 'report content'
        Assert-That (-not [IO.File]::ReadAllText($report).Contains("`r")) 'CR in report'
        Assert-Throws { Invoke-RunProfiled -ScriptBlock { } -OutputDirectory $work -Label 'bad label!' -ProfilerModulePath $manifest } 'Label'
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
''
$rows = [Collections.Generic.List[object]]::new(); $rows.Add(@('RunProfiles', [string]$counters.Passed, [string]$counters.Failed, [string]$counters.Skipped, (Format-RunDuration $clock.Elapsed.TotalMilliseconds)))
Format-RunTable -Headers @('Suite', 'Passed', 'Failed', 'Skipped', 'Duration') -Rows $rows -RightAligned @(1, 2, 3, 4)
"SUMMARY Passed=$($counters.Passed) Failed=$($counters.Failed) Skipped=$($counters.Skipped)"
if ($script:ProfilerGap) { "Gap: profiler case skipped - $script:ProfilerGap" }
'Mutation testing: run this file with -Mutation (see RunProfiles.Mutation.ps1).'
exit $counters.Failed
