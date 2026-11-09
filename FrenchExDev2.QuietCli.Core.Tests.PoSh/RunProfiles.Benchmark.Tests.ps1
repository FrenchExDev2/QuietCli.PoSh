# Dot-sourced by RunProfiles.Tests.ps1; shares its independent assertions and temporary root.
Import-Module (Join-Path $scripts 'lib/RunColdStart.psm1') -Force

Test-Case 'benchmark: generated durations round-trip exactly under a non-invariant caller culture' {
    $previous = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $random = [Random]::new($Seed + 11)
        for ($index = 0; $index -lt $Iterations; $index++) {
            $values = @(0..2 | ForEach-Object { $random.Next(0, 100000) / 8.0 })
            $fields = @($values | ForEach-Object { $_.ToString('R', [Globalization.CultureInfo]::InvariantCulture) })
            $sample = ConvertFrom-RunColdSample $fields
            Assert-That ($sample.Import -eq $values[0] -and $sample.First -eq $values[1] -and $sample.Second -eq $values[2]) 'duration mapping or culture changed'
        }
    }
    finally { [Threading.Thread]::CurrentThread.CurrentCulture = $previous }
}
Test-Case 'benchmark: malformed, non-finite, negative and incomplete child samples are rejected' {
    foreach ($bad in @(@(), @('1'), @('1','2'), @('1','2','3','4'), @('NaN','2','3'), @('1','Infinity','3'), @('1','2','-1'), @('1,5','2','3'), @('x','2','3'), @('1e9999','2','3'))) {
        Assert-Throws { ConvertFrom-RunColdSample $bad } 'ColdSampleInvalid'
    }
    $random = [Random]::new($Seed + 12)
    for ($index = 0; $index -lt $Iterations; $index++) {
        $fields = @('1','2','3'); $fields[$random.Next(3)] = 'bad-' + $random.Next().ToString()
        Assert-Throws { ConvertFrom-RunColdSample $fields } 'ColdSampleInvalid'
    }
}

Test-Case 'benchmark: module footprint sums every file under the manifest directory, nested and at the root alike' {
    $random = [Random]::new($Seed + 13)
    for ($index = 0; $index -lt [Math]::Min($Iterations, 20); $index++) {
        $root = Join-Path $work ('footprint-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($root)
        $manifest = Join-Path $root 'module.psd1'
        $expected = 0L
        foreach ($file in @('module.psd1', 'lib/engine.dll', 'lib/native/engine.so', 'docs/readme.txt')) {
            $path = Join-Path $root $file
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            $size = $random.Next(0, 5000)
            [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
            $expected += $size
        }
        $actual = Get-RunModuleFootprintBytes -ManifestPath $manifest
        Assert-That ($actual -eq $expected) "footprint mismatch at $index`: expected $expected, got $actual"
    }
    $empty = Join-Path $work ('footprint-empty-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($empty)
    $onlyManifest = Join-Path $empty 'module.psd1'
    [IO.File]::WriteAllBytes($onlyManifest, [byte[]]::new(0))
    Assert-That ((Get-RunModuleFootprintBytes -ManifestPath $onlyManifest) -eq 0) 'empty manifest-only directory must report zero'
}

Test-Case 'benchmark: hosted-path footprint sums only the active lib/inprocess or lib/engine/<rid> directory, ignoring other RIDs and files outside it' {
    $rid = [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $hostedRelative = if ($PSVersionTable.PSVersion.Major -ge 11) { "lib/engine/$rid" } else { 'lib/inprocess' }
    $otherRid = if ($rid -eq 'win-x64') { 'linux-x64' } else { 'win-x64' }
    $random = [Random]::new($Seed + 15)
    for ($index = 0; $index -lt [Math]::Min($Iterations, 20); $index++) {
        $root = Join-Path $work ('hosted-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($root)
        $manifest = Join-Path $root 'module.psd1'
        $expected = 0L
        foreach ($file in @("$hostedRelative/engine.dll", "$hostedRelative/native/engine.so")) {
            $path = Join-Path $root $file
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            $size = $random.Next(0, 5000)
            [IO.File]::WriteAllBytes($path, [byte[]]::new($size))
            $expected += $size
        }
        foreach ($outside in @('module.psd1', "lib/engine/$otherRid/engine.dll", 'docs/readme.txt')) {
            $path = Join-Path $root $outside
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            [IO.File]::WriteAllBytes($path, [byte[]]::new($random.Next(0, 5000)))
        }
        $actual = Get-RunModuleHostedPathBytes -ManifestPath $manifest -RuntimeIdentifier $rid
        Assert-That ($actual -eq $expected) "hosted-path footprint mismatch at $index`: expected $expected, got $actual"
    }
    $missing = Join-Path $work ('hosted-missing-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($missing)
    $missingManifest = Join-Path $missing 'module.psd1'
    [IO.File]::WriteAllBytes($missingManifest, [byte[]]::new(0))
    Assert-Throws { Get-RunModuleHostedPathBytes -ManifestPath $missingManifest -RuntimeIdentifier $rid } 'RunModuleHostedPathMissing'
}

Test-Case 'benchmark: a packaged module reports a real, positive .nupkg size that grows with its payload (skipped when Compress-PSResource is unavailable)' {
    try { Get-Command Compress-PSResource -ErrorAction Stop | Out-Null } catch { $counters.Skipped++; $counters.Passed--; return }
    function New-PackageFixtureModule {
        <#
        .SYNOPSIS
        Creates a disposable module with a deterministic payload for package-size assertions.
        .PARAMETER Root
        Owned fixture directory whose leaf name determines the module name.
        .PARAMETER PayloadBytes
        Number of generated payload bytes; zero creates the manifest-only fixture.
        #>
        param([string]$Root, [int]$PayloadBytes)
        [void][IO.Directory]::CreateDirectory($Root)
        $name = Split-Path -Leaf $Root
        $manifest = Join-Path $Root "$name.psd1"
        New-ModuleManifest -Path $manifest -ModuleVersion '1.0.0' -Guid ([guid]::NewGuid()) -Author 'fixture' -Description 'fixture'
        if ($PayloadBytes -gt 0) {
            $buffer = [byte[]]::new($PayloadBytes)
            [Random]::new($Seed + 14).NextBytes($buffer)
            [IO.File]::WriteAllBytes((Join-Path $Root 'payload.bin'), $buffer)
        }
        return $manifest
    }
    $smallManifest = New-PackageFixtureModule -Root (Join-Path $work ('pkg-small-' + [guid]::NewGuid().ToString('N'))) -PayloadBytes 0
    $bigManifest = New-PackageFixtureModule -Root (Join-Path $work ('pkg-big-' + [guid]::NewGuid().ToString('N'))) -PayloadBytes 500000
    $smallBytes = Get-RunModulePackageBytes -ManifestPath $smallManifest
    $bigBytes = Get-RunModulePackageBytes -ManifestPath $bigManifest
    Assert-That ($smallBytes -gt 0) "manifest-only package must not be empty: $smallBytes"
    Assert-That ($bigBytes -gt $smallBytes) "a 500000-byte random payload must grow the package: small=$smallBytes big=$bigBytes"
}

function Invoke-BenchmarkFixture {
    <#
    .SYNOPSIS
    Runs the real benchmark script with a deterministic native boundary, preserving its actual callbacks.
    .PARAMETER Warmup
    Warm-up pairs excluded from the report.
    .PARAMETER FailCalls
    One-based child calls that fail.
    .PARAMETER MaxFailedPairs
    Failure budget passed to the script.
    .PARAMETER Duplicate
    Emits a duplicate measurement marker to verify rejection.
    .PARAMETER ProfileImport
    Also exercises the separately profiled worker path.
    #>
    param([int]$Warmup = 1, [int[]]$FailCalls = @(), [int]$MaxFailedPairs = 5, [switch]$Duplicate, [switch]$ProfileImport)
    $fixture = Join-Path $work ('bench-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($fixture)
    $baselineRoot = Join-Path $fixture 'baseline'; $candidateRoot = Join-Path $fixture 'candidate'
    [void][IO.Directory]::CreateDirectory($baselineRoot); [void][IO.Directory]::CreateDirectory($candidateRoot)
    $baseline = Join-Path $baselineRoot 'baseline.psd1'; $candidate = Join-Path $candidateRoot 'candidate.psd1'
    Write-RunTextFile $baseline '@{}'; Write-RunTextFile $candidate '@{}'
    [IO.File]::WriteAllBytes((Join-Path $baselineRoot 'engine.dll'), [byte[]]::new(1000))
    [IO.File]::WriteAllBytes((Join-Path $candidateRoot 'engine.dll'), [byte[]]::new(2500))
    $state = @{ Calls = [Collections.Generic.List[string]]::new(); FailCalls = $FailCalls; Duplicate = [bool]$Duplicate }
    function Invoke-FixtureNative {
        <# .SYNOPSIS
        Supplies controlled stream records to the benchmark's real Output and Complete callbacks.
        #>
        param([switch]$AsObject, [string]$RecordDelimiter, [double]$TimeoutSeconds, $Data, [scriptblock]$Output, [scriptblock]$Complete, [Parameter(ValueFromRemainingArguments)][object[]]$NativeArguments)
        $worker = [string]$NativeArguments[-1]
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($worker, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'FixtureWorkerSyntaxInvalid' }
        $variant = if ($worker.Contains('candidate.psd1')) { 'candidate' } else { 'baseline' }
        $state.Calls.Add($variant)
        $outcome = if ($state.Calls.Count -in $state.FailCalls) { 'Failed' } else { 'Success' }
        $runtime = [pscustomobject]@{ Data = $Data }
        & $Output ([pscustomobject]@{ Stream = 'stderr'; Text = 'RESULT 999 999 999' }) $runtime
        & $Output ([pscustomobject]@{ Stream = 'stdout'; Text = 'unrelated diagnostic' }) $runtime
        $line = if ($variant -eq 'baseline') { 'RESULT 10.25 20.5 30.75' } else { 'RESULT 11.25 22.5 33.75' }
        if ($Data.Marker -ceq 'PROFILE') { $line = "PROFILE /fixture with spaces/$variant.profile.json" }
        & $Output ([pscustomobject]@{ Stream = 'stdout'; Text = $line }) $runtime
        if ($state.Duplicate) { & $Output ([pscustomobject]@{ Stream = 'stdout'; Text = $line }) $runtime }
        & $Complete $runtime
        return [pscustomobject]@{ Outcome = $outcome; Data = $Data }
    }
    Set-Alias -Name quiet -Value Invoke-FixtureNative -Scope Local
    $path = Join-Path $fixture 'result.json'
    $null = & (Join-Path $scripts 'Measure-ColdStart.ps1') -BaselineModule $baseline -CandidateModule $candidate -Runs 3 -Warmup $Warmup -Seed 61207 -BootstrapResamples 100 -OutputPath $path -MaxFailedPairs $MaxFailedPairs -LogLevel Off -ProfileImport:$ProfileImport
    [pscustomobject]@{ Report = (Read-RunTextFile $path | ConvertFrom-Json); Calls = $state.Calls.ToArray(); Path = $path }
}

Test-Case 'benchmark: the real script preserves paired identity, excludes warm-up and produces reproducible order' {
    $first = Invoke-BenchmarkFixture
    $second = Invoke-BenchmarkFixture
    Assert-That ($first.Calls.Count -eq 8 -and ($first.Calls -join ',') -ceq ($second.Calls -join ',')) 'child count or seeded order'
    for ($index = 0; $index -lt 8; $index += 2) { Assert-That ($first.Calls[$index] -ne $first.Calls[$index+1]) 'a pair ran one variant twice' }
    Assert-That ($first.Report.Pairs.Count -eq 3 -and $first.Report.Counters.'pair.warmup' -eq 1) 'warm-up leaked into samples'
    Assert-That ($first.Report.Counters.'run.started' -eq 8 -and $first.Report.Counters.'bootstrap.resamples' -eq 300) 'counters'
    Assert-That ($first.Report.Footprint.DifferenceBytes -eq 1500 -and $first.Report.Footprint.CandidateBytes -eq ($first.Report.Footprint.BaselineBytes + 1500)) "footprint: $($first.Report.Footprint | ConvertTo-Json -Compress)"
    foreach ($pair in $first.Report.Pairs) {
        Assert-That ($pair.Baseline.Import -eq 10.25 -and $pair.Candidate.Import -eq 11.25 -and $pair.Baseline.Second -eq 30.75) 'variant identity changed'
    }
    foreach ($phase in @('Import','First call','Second call')) { Assert-That ($first.Report.Summary.$phase.Verdict -ceq 'too-few-pairs') 'three pairs must not claim a speedup' }
    Assert-That ($first.Report.Summary.Import.Difference.Median -eq 1 -and $first.Report.Summary.'First call'.Difference.Median -eq 2) 'difference sign'
    $bytes = [IO.File]::ReadAllBytes($first.Path)
    Assert-That ($bytes[0] -ne 0xEF -and -not (Read-RunTextFile $first.Path).Contains("`r")) 'report encoding'
}
Test-Case 'benchmark: failed pairs are discarded without retry, exact failure budgets are enforced' {
    $run = Invoke-BenchmarkFixture -Warmup 2 -FailCalls @(1) -MaxFailedPairs 1
    Assert-That ($run.Report.Pairs.Count -eq 3 -and $run.Calls.Count -eq 9 -and $run.Report.Counters.'pair.discarded' -eq 1) 'retry or partial pair retained'
    Assert-Throws { Invoke-BenchmarkFixture -FailCalls @(1) -MaxFailedPairs 0 } 'ChildRunFailed'
    Assert-Throws { Invoke-BenchmarkFixture -Warmup 0 -FailCalls @(1) -MaxFailedPairs 1 } 'TooFewMeasuredPairs'
    Assert-Throws { Invoke-BenchmarkFixture -Duplicate -MaxFailedPairs 0 } 'ChildRunFailed'
}
Test-Case 'benchmark: profiled runs stay outside measured pairs and retain report paths containing spaces' {
    $run = Invoke-BenchmarkFixture -Warmup 0 -ProfileImport
    Assert-That ($run.Report.Pairs.Count -eq 3 -and $run.Calls.Count -eq 8 -and $run.Report.Counters.'profile.exported' -eq 2) 'profiled samples entered measurements'
    Assert-That ($run.Report.Profiles.Count -eq 2 -and $run.Report.Profiles[0] -ceq '/fixture with spaces/baseline.profile.json' -and $run.Report.Profiles[1] -ceq '/fixture with spaces/candidate.profile.json') 'profile path split or variant identity changed'
}

Test-Case 'coldstart-live: the benchmark measures fresh real processes and writes an A/A smoke report' {
    $manifest = Join-Path $scripts '../FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
    Import-Module $manifest -ErrorAction Stop
    $path = Join-Path $work 'coldstart-live.json'
    $null = & (Join-Path $scripts 'Measure-ColdStart.ps1') -CandidateModule $manifest -Runs 3 -Warmup 0 -BootstrapResamples 100 -OutputPath $path -LogLevel Off
    $report = Read-RunTextFile $path | ConvertFrom-Json
    Assert-That ($report.Pairs.Count -eq 3 -and $report.Counters.'run.succeeded' -eq 6) 'live measurements missing'
    foreach ($pair in $report.Pairs) { Assert-That ($pair.Baseline.Import -gt 0 -and $pair.Candidate.First -gt 0 -and $pair.Candidate.Second -gt 0) 'invalid live durations' }
}
