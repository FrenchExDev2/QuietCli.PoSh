function Test-QuietScriptLiterals {
    <#
    .SYNOPSIS
    Checks literal round trips with deterministic Unicode and injection corpora.
    .PARAMETER Encoder
    Production encoder or a source-checked mutant.
    #>
    param([scriptblock]$Encoder)
    $random = [Random]::new(73619)
    $corpus = @('', "'", "`r`n", 'é漢😀', '$([IO.File]::WriteAllText("bad","bad"))', "'; throw 'injected'; #", '`"$;{}[]')
    foreach ($index in 0..127) {
        $text = $corpus[$index % $corpus.Count] + [char]$random.Next(1, 0xd7ff) + $random.Next().ToString()
        $scalar = & $Encoder -Value $text
        if ((& ([scriptblock]::Create($scalar))) -cne $text) { throw 'ScriptScalarPropertyFailed: seed 73619' }
        $value = [ordered]@{ Text = $text; Nested = @(@{ Flag = $true; Nil = $null }, [long]$index); Bytes = [byte[]]@(0, 128, 255) }
        $literal = & $Encoder -Value $value
        $restored = & ([scriptblock]::Create($literal))
        if ($restored.Text -cne $text -or $restored.Nested[1] -cne [long]$index -or $restored.Bytes.GetType() -ne [byte[]] -or $restored.Bytes[2] -ne 255 -or !$restored.Nested[0].Flag -or $null -ne $restored.Nested[0].Nil) { throw 'ScriptLiteralPropertyFailed: seed 73619' }
    }
}

function Test-QuietScriptFactoryIsolation {
    <#
    .SYNOPSIS
    Verifies repeatable initialization without consuming the reusable definition.
    .PARAMETER Initializer
    Production factory initializer or a source-checked mutant.
    #>
    param([scriptblock]$Initializer)
    $request = @{ DataFactory = { @{ Count = 0 } }; StateFactory = { @{ Seen = [Collections.Generic.List[string]]::new() } } }
    $first = & $Initializer $request
    $first.Data.Count = 99; $first.State.Seen.Add('old')
    $second = & $Initializer $request
    if ($second.Data.Count -ne 0 -or $second.State.Seen.Count -ne 0 -or !$request.ContainsKey('DataFactory')) { throw 'ScriptFactoryStateLeaked' }
}

function Invoke-QuietScriptTests {
    <#
    .SYNOPSIS
    Qualifies script generation, live factories, property corpora and targeted mutations.
    .PARAMETER WorkspaceRoot
    Selected QuietCli checkout.
    .PARAMETER RunDirectory
    Owned monitored report directory.
    .PARAMETER OnProgress
    Existing launcher progress callback.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory, [scriptblock]$OnProgress)
    $core = Get-Module FrenchExDev2.QuietCli.Core.PoSh
    $root = Join-Path $RunDirectory 'scripts'; [void][IO.Directory]::CreateDirectory($root)
    $encoder = & $core { (Get-Command ConvertTo-QuietScriptLiteral).ScriptBlock }
    $initializer = & $core { (Get-Command Initialize-QuietCallFactories).ScriptBlock }
    $cases = [ordered]@{}; $results = [Collections.Generic.List[object]]::new(); $mutations = [Collections.Generic.List[object]]::new()
    $cases['generation is inert with an absent executable and throwing callbacks'] = {
        $before = [FrenchExDev2.QuietCli.QuietSession]::Engine
        $database = & $core { [string](Get-QuietConfigurationSnapshot).Values['telemetry.database'] }
        $dbBefore = if ($database -and [IO.File]::Exists($database)) { (Get-FileHash -LiteralPath $database).Hash } else { $null }
        $file = quiet -Script (Join-Path $root 'inert.ps1') -AsObject -DataFactory { throw 'factory ran' } -Output { throw 'output ran' } missing-quiet-script-executable
        if ($file -isnot [IO.FileInfo] -or ![object]::ReferenceEquals($before, ([FrenchExDev2.QuietCli.QuietSession]::Engine))) { throw 'ScriptGenerationNotInert' }
        $bytes = [IO.File]::ReadAllBytesAsync($file.FullName).GetAwaiter().GetResult()
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        if ($text.Contains("`r") -or $bytes[0] -eq 0xef -or $text.Contains("Add('-Script')") -or $text.Contains("Add('-TimeoutSeconds')")) { throw 'ScriptSourceContractChanged' }
        $dbAfter = if ($database -and [IO.File]::Exists($database)) { (Get-FileHash -LiteralPath $database).Hash } else { $null }
        if ($dbBefore -cne $dbAfter) { throw 'ScriptGenerationWroteMeasurements' }
    }
    $cases['literal properties preserve nested data, types, Unicode and hostile strings'] = { Test-QuietScriptLiterals $encoder }
    $cases['literal validation rejects malformed values, cycles and depth overflow'] = {
        $cycle = @{}; $cycle.Self = $cycle
        $deep = @{}; foreach ($index in 1..35) { $deep = @{ Next = $deep } }
        foreach ($value in @($cycle, $deep, [version]'1.2', [double]::NaN, [object]::new(), [int[,]]::new(2,2))) {
            $rejected = $false; try { $null = & $encoder -Value $value } catch { $rejected = $true }
            if (!$rejected) { throw 'ScriptInvalidLiteralAccepted' }
        }
        foreach ($value in @([byte]255, [sbyte]-128, [int16]-32768, [uint16]65535, [int]::MinValue, [uint32]::MaxValue, [long]::MinValue, [uint64]::MaxValue, [single]0.1, [double]1e-100, [decimal]12.34, [char]'é', $false, [string[]]@(), [int[]]@(1))) {
            $literal = & $encoder -Value $value
            $restored = & ([scriptblock]::Create(',' + '(' + $literal + ')'))
            if ($restored.GetType() -ne $value.GetType() -or ($restored -isnot [array] -and $restored -cne $value) -or ($restored -is [array] -and $restored.Length -ne $value.Length)) { throw 'ScriptPrimitiveTypeChanged' }
        }
        foreach ($value in @(@{ Text = 'x' * 1048577 }, [object[]]::new(10001))) {
            $rejected = $false; try { $null = & $encoder -Value $value } catch { $rejected = $true }
            if (!$rejected) { throw 'ScriptLiteralBudgetIgnored' }
        }
    }
    $cases['invalid exports fail without creating or replacing files'] = {
        $target = Join-Path $root 'invalid.ps1'
        $variants = @(
            @('-Recall', $false), @('-CancellationToken', [Threading.CancellationToken]::None),
            @('-Data', [version]'1.2'), @('-Data', @{}, '-DataFactory', { @{} }),
            @('-State', @{}, '-StateFactory', { @{} }), @('-Output', 'not a callback'),
            @('-TimeoutSeconds', -1), @('-Transport', 'bad'), @('-AsJson:True'),
            @('-InputText', 'a', '-InputBytes', [byte[]]@(1))
        )
        foreach ($variant in $variants) {
            $arguments = @('-Script', $target, '-AsObject', '-Complete', { param($r) $r.Data }) + $variant + @('-FilePath','absent')
            $rejected = $false; try { $null = quiet @arguments } catch { $rejected = $true }
            if (!$rejected -or [IO.File]::Exists($target)) { throw 'InvalidScriptCreated' }
        }
        foreach ($path in @((Join-Path $root 'bad.txt'), (Join-Path $root 'missing/child.ps1'))) {
            $rejected = $false; try { $null = quiet -Script $path -Complete { } absent } catch { $rejected = $true }
            if (!$rejected -or [IO.File]::Exists($path)) { throw 'InvalidScriptPathAccepted' }
        }
        $rejected = $false; try { $null = quiet -Script $target absent } catch { $rejected = $true }
        if (!$rejected) { throw 'ScriptMissingCallbackAccepted' }
        $file = quiet -Script $target -Complete { } absent
        $hash = (Get-FileHash -LiteralPath $target).Hash
        $rejected = $false; try { $null = quiet -Script $target -Complete { throw 'replacement' } absent } catch { $rejected = $true }
        if (!$rejected -or (Get-FileHash -LiteralPath $target).Hash -cne $hash) { throw 'ScriptExistingFileChanged' }
    }
    $cases['factories are isolated and reject missing, multiple and invalid state returns'] = {
        Test-QuietScriptFactoryIsolation $initializer
        foreach ($factory in @({}, { 1; 2 }, { throw 'factory error' })) {
            $rejected = $false; try { $null = quiet -AsObject -DataFactory $factory -Complete {} absent } catch { $rejected = $true }
            if (!$rejected) { throw 'ScriptInvalidDataFactoryAccepted' }
        }
        $rejected = $false; try { $null = quiet -AsObject -StateFactory { 'invalid' } -Complete {} absent } catch { $rejected = $true }
        if (!$rejected) { throw 'ScriptInvalidStateFactoryAccepted' }
    }
    $cases['generated script matches direct execution, supports overrides and recreates state'] = {
        $runner = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $nativeArguments = @('-NoLogo','-NonInteractive','-Command', '[Console]::Out.Write("é漢")')
        $factory = { @{ Bytes = 0L; StateCount = 0; Completions = 0 } }
        $stateFactory = { @{ Events = 0 } }
        $output = { param($event, $runtime) if ($event.Stream -eq 'stdout') { $runtime.Data.Bytes += $event.ByteCount; $runtime.State.Events++ } }
        $complete = { param($runtime) $runtime.Data.StateCount = $runtime.State.Events; $runtime.Data.Completions++; $runtime.Data }
        $file = quiet -Script (Join-Path $root 'live.ps1') -AsObject -StdoutMode Bytes -DataFactory $factory -StateFactory $stateFactory -Output $output -Complete $complete -FilePath $runner -ArgumentList $nativeArguments
        $direct = quiet -AsObject -StdoutMode Bytes -DataFactory $factory -StateFactory $stateFactory -Output $output -Complete $complete -FilePath $runner -ArgumentList $nativeArguments
        $first = & $file.FullName; $second = & $file.FullName
        foreach ($result in @($direct, $first, $second)) {
            if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Data.Bytes -ne 5 -or $result.Data.StateCount -lt 1 -or $result.Data.Completions -ne 1) { throw ('ScriptLiveResultMismatch: ' + ($result.Error | ConvertTo-Json -Compress)) }
        }
        if ([object]::ReferenceEquals($first.Data, $second.Data)) { throw 'ScriptLiveDataShared' }
        $overridden = & $file.FullName -ArgumentList @('-NoLogo','-NonInteractive','-Command','[Console]::Out.Write("a")') -WorkingDirectory $root
        if ($overridden.Data.Bytes -ne 1 -or $overridden.Outcome -ne 'Success') { throw 'ScriptOverridesIgnored' }
    }
    $cases['external dependencies remain explicit and nested calls initialize independently'] = {
        $runner = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $file = quiet -Script (Join-Path $root 'external.ps1') -AsObject -DataFactory { @{ Value = $scriptExternalValue } } -Complete { param($r) $r.Data } -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-Command','exit 0')
        $scriptExternalValue = 'provided by caller'
        $result = & $file.FullName
        if ($result.Data.Value -cne $scriptExternalValue) { throw 'ScriptDependencyNotExplicit' }
        $outer = quiet -AsObject -DataFactory { @{ Child = $null } } -Complete {
            param($r)
            $r.Data.Child = quiet -AsObject -DataFactory { @{ Value = 7 } } -Complete { param($child) $child.Data } -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-Command','exit 0')
        } -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-Command','exit 0')
        if ($outer.Outcome -ne 'Success' -or $outer.Data.Child.Data.Value -ne 7) { throw 'ScriptNestedFactoryFailed' }
    }
    $cases['literal initialization is fresh and dynamic callback source remains valid'] = {
        $runner = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $complete = [scriptblock]::Create('param($r) $r.Data.Count++; $r.Data.State = $r.State.Name; $r.Data # trailing comment')
        $file = quiet -Script (Join-Path $root 'literal.ps1') -AsObject -Data @{ Count = 0; Text = "é'`r`n" } -State @{ Name = 'fresh' } -Complete $complete -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-Command','exit 0')
        foreach ($iteration in 1..2) {
            $result = & $file.FullName
            if ($result.Outcome -ne 'Success' -or $result.Data.Count -ne 1 -or $result.Data.State -cne 'fresh' -or $result.Data.Text -cne "é'`r`n") { throw 'ScriptLiteralInitializationShared' }
        }
        $request = & $initializer @{ DataFactory = { ,@(1, 2) } }
        if ($request.Data -isnot [array] -or $request.Data.Count -ne 2) { throw 'ScriptFactoryArrayEnumerationChanged' }
        $request = & $initializer @{ DataFactory = { $null } }
        if (!$request.ContainsKey('Data') -or $null -ne $request.Data) { throw 'ScriptFactoryNullRejected' }
    }
    $cases['targeted mutations are rejected by behavioral oracles'] = {
        $specs = @(
            @{ Name='escaping'; Function='ConvertTo-QuietScriptLiteral'; Before='.Replace("''", "''''")'; After=''; Kind='literal' },
            @{ Name='factory isolation'; Function='Initialize-QuietCallFactories'; Before='$Request.Clone()'; After='$Request'; Kind='factory' },
            @{ Name='factory cardinality'; Function='Initialize-QuietCallFactories'; Before='$values.Count -ne 1'; After='$false'; Kind='cardinality' },
            @{ Name='no overwrite'; Function='Export-QuietCallScript'; Before="throw 'QuietScriptAlreadyExists'"; After='return [IO.FileInfo]::new($path)'; Kind='overwrite' },
            @{ Name='inert generation'; Function='Invoke-QuietCli'; Before='return Export-QuietCallScript $request'; After='Export-QuietCallScript $request'; Kind='inert' }
        )
        foreach ($spec in $specs) {
            $source = & $core { param($name) (Get-Command $name).ScriptBlock.ToString() } $spec.Function
            if (!$source.Contains($spec.Before)) { throw ('ScriptInvalidMutant: ' + $spec.Name) }
            $mutant = $core.NewBoundScriptBlock([scriptblock]::Create($source.Replace($spec.Before, $spec.After)))
            $detected = $false
            try {
                switch ($spec.Kind) {
                    literal { Test-QuietScriptLiterals $mutant }
                    factory { Test-QuietScriptFactoryIsolation $mutant }
                    cardinality {
                        $rejected = $false; try { $null = & $mutant @{ DataFactory = { 1; 2 } } } catch { $rejected = $true }
                        if (!$rejected) { throw 'OracleAcceptedInvalidCardinality' }
                    }
                    overwrite {
                        $target = Join-Path $root 'invalid.ps1'
                        $rejected = $false; try { $null = & $mutant @{ Script=$target; Complete={}; FilePath='absent'; ArgumentList=@() } } catch { $rejected = $true }
                        if (!$rejected) { throw 'OracleAcceptedExistingFile' }
                    }
                    inert {
                        $signal = @{ Count = 0 }
                        $values = @(& $mutant -Script (Join-Path $root 'mutant-inert.ps1') -DataFactory { $signal.Count++; @{} } -Complete {} absent)
                        if ($signal.Count -or $values.Count -ne 1 -or $values[0] -isnot [IO.FileInfo]) { throw 'OracleDetectedExecution' }
                    }
                }
            } catch { $detected = $true }
            if (!$detected) { throw ('ScriptMutantSurvived: ' + $spec.Name) }
            $mutations.Add(@{ Name=$spec.Name; State='Killed' })
        }
    }
    $passed = 0; $failed = 0
    foreach ($entry in $cases.GetEnumerator()) {
        if ($OnProgress) { & $OnProgress $entry.Key Running $passed $failed }
        try { & $entry.Value; $passed++; $results.Add(@{Name=$entry.Key;State='Passed';Error=$null}) }
        catch { $failed++; $results.Add(@{Name=$entry.Key;State='Failed';Error=$_.Exception.ToString();Stack=$_.ScriptStackTrace}) }
        if ($OnProgress) { & $OnProgress $entry.Key $(if ($results[-1].State -eq 'Passed') {'Passed'} else {'Failed'}) $passed $failed }
    }
    [pscustomobject]@{ Project='FrenchExDev2.QuietCli.Core.PoSh'; Passed=$passed; Failed=$failed; Cases=$results.ToArray(); Properties=@{Seed=73619;Generated=128}; Mutations=$mutations.ToArray(); Limits='Focused PowerShell script-generation qualification; no C# or native behavior changes and no release matrix.' }
}
