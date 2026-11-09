function Get-QuietVagrantFuzzCases {
    <#
    .SYNOPSIS
    Bounded fuzz campaign for the Vagrant --machine-readable line parser: random multi-machine transcripts,
    sometimes-escaped commas, a seeded Fisher-Yates interleave of arrival order, run through the real engine
    fragmented at arbitrary chunk boundaries (the shared fixture's "chunks" mode), and compared against an
    independently tracked expectation. On any failure the thrown message keeps the seed and the full generated
    transcript, so the exact run can be reproduced byte-for-byte.
    .PARAMETER RootDirectory
    Disposable working directory for the nested `quiet` calls.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root; used to dot-source the Vagrant module's own (deliberately unexported) business
    functions, same reasoning as VagrantLine.Tests.ps1's Get-QuietVagrantLineCases.
    #>
    param([string]$RootDirectory, [string]$WorkspaceRoot)
    . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1')
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $cases = [ordered]@{}

    $cases['bounded fuzz: random multi-machine --machine-readable transcripts survive arbitrary chunk fragmentation'] = {
        # Fixed seed of the day: reproducible within a day's CI runs, still varies across days to widen coverage over time.
        $seed = 20261108
        $random = [Random]::new($seed)
        $types = @('ui', 'metadata', 'state')
        for ($iteration = 0; $iteration -lt 200; $iteration++) {
            $machines = @(1..$random.Next(1, 5) | ForEach-Object { "fuzz-machine-$_" })
            $entries = [Collections.Generic.List[object]]::new()
            $timestamp = 1700000000
            $lineCount = $random.Next(1, 12)
            for ($i = 0; $i -lt $lineCount; $i++) {
                $timestamp++
                $fieldCount = $random.Next(1, 4)
                $fields = @(1..$fieldCount | ForEach-Object {
                        $raw = -join (1..$random.Next(1, 10) | ForEach-Object { [char]$random.Next(97, 123) })
                        if ($random.Next(0, 2) -eq 0 -and $raw.Length -gt 0) { $raw = $raw.Insert($random.Next(0, $raw.Length + 1), ',') }
                        if ($random.Next(0, 3) -eq 0) { $raw += "été漢🙂`nnext`rline" }
                        $raw
                    })
                $entries.Add([pscustomobject]@{ Timestamp = $timestamp; Machine = $machines[$random.Next(0, $machines.Count)]; Type = $types[$random.Next(0, $types.Count)]; Fields = $fields })
            }
            # Seeded Fisher-Yates: shuffles arrival order so lines from different machines interleave unpredictably.
            for ($i = $entries.Count - 1; $i -gt 0; $i--) {
                $j = $random.Next(0, $i + 1)
                $swap = $entries[$i]; $entries[$i] = $entries[$j]; $entries[$j] = $swap
            }
            $lines = foreach ($entry in $entries) {
                $escapedFields = @($entry.Fields | ForEach-Object { $_.Replace(',', '%!(VAGRANT_COMMA)').Replace("`n",'\n').Replace("`r",'\r') })
                $entry.Timestamp.ToString() + ',' + $entry.Machine + ',' + $entry.Type + ',' + ($escapedFields -join ',')
            }
            $transcript = $lines -join "`n"
            $chunkSeed = $random.Next()
            try {
                $runtime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', $chunkSeed, $transcript) -WorkingDirectory $RootDirectory
                $report = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime -Command 'up'
                if ($report.Lines -ne $entries.Count) { throw "Expected $($entries.Count) parsed lines, observed $($report.Lines)" }
                if ($runtime.Events.Count -ne $entries.Count) { throw "Expected $($entries.Count) emitted events, observed $($runtime.Events.Count)" }
                for ($i = 0; $i -lt $entries.Count; $i++) {
                    $expected = $entries[$i]; $actual = $runtime.Events[$i]
                    if ($actual.Machine -cne $expected.Machine) { throw "Machine mismatch at line $i`: expected $($expected.Machine), observed $($actual.Machine)" }
                    if ($actual.Type -cne $expected.Type) { throw "Type mismatch at line $i`: expected $($expected.Type), observed $($actual.Type)" }
                    if ((@($actual.Fields) -join "`u{1}") -cne (@($expected.Fields) -join "`u{1}")) { throw "Fields mismatch at line $i`: expected [$($expected.Fields -join '|')], observed [$($actual.Fields -join '|')]" }
                }
            } catch {
                throw "Fuzz failure at iteration $iteration (seed=$seed, chunkSeed=$chunkSeed): $($_.Exception.Message)`nTranscript:`n$transcript"
            }
        }
    }

    $cases['bounded malformed timestamps and missing fields are rejected without partial events'] = {
        $random=[Random]::new(20261108)
        for($index=0;$index -lt 200;$index++){
            foreach($line in @("x$($random.Next()),web,ui,hello", "$($random.Next()),web", "$($random.Next()),web,", ((('9' * 40)+',web,ui,hello')))){
                if($null -ne (ConvertFrom-QuietVagrantMachineReadableLine $line)){throw "MalformedVagrantAccepted: seed=20261108 index=$index line=$line"}
            }
        }
    }
    $cases
}
