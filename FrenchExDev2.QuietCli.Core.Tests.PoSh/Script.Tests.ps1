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
    $cases['CI argument quoting round-trips hostile values through a child process'] = {
        . (Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1')
        $echo = Join-Path $root 'echo-args.ps1'
        [IO.File]::WriteAllText($echo, '[Console]::Out.Write(($args | ConvertTo-Json -Compress))', [Text.UTF8Encoding]::new($false))
        $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        foreach ($value in @('C:\a b\', 'x"y', 'a\"b', '', 'plain', 'trail\\', '\\srv\sh are\', 'q"', '"', 'a b\\"c', "tab`there", 'a" -Injected "b')) {
            $line = '-NoProfile -File ' + (ConvertTo-CiArgument $echo) + ' ' + (ConvertTo-CiArgument $value)
            $null = Start-Process -FilePath $pwsh -ArgumentList $line -NoNewWindow -Wait -RedirectStandardOutput "$echo.out"
            $received = @([IO.File]::ReadAllText("$echo.out") | ConvertFrom-Json -NoEnumerate)
            if ($received.Count -ne 1 -or $received[0] -cne $value) { throw 'CiArgumentQuotingChanged' }
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
    }
    $cases['targeted mutations are rejected by behavioral oracles'] = {
        $specs = @(
            @{ Name='inert generation'; Function='Invoke-QuietCli'; Before='return Export-QuietCallScript $request'; After='Export-QuietCallScript $request'; Kind='inert' }
        )
        foreach ($spec in $specs) {
            $source = & $core { param($name) (Get-Command $name).ScriptBlock.ToString() } $spec.Function
            if (!$source.Contains($spec.Before)) { throw ('ScriptInvalidMutant: ' + $spec.Name) }
            $mutant = $core.NewBoundScriptBlock([scriptblock]::Create($source.Replace($spec.Before, $spec.After)))
            $detected = $false
            try {
                # The compiled encoder and exporter are mutated by the C# catalogue; this oracle covers the PowerShell facade only.
                $signal = @{ Count = 0 }
                $values = @(& $mutant -Script (Join-Path $root 'mutant-inert.ps1') -DataFactory { $signal.Count++; @{} } -Complete {} absent)
                if ($signal.Count -or $values.Count -ne 1 -or $values[0] -isnot [IO.FileInfo]) { throw 'OracleDetectedExecution' }
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
    [pscustomobject]@{ Project='FrenchExDev2.QuietCli.Core.PoSh'; Passed=$passed; Failed=$failed; Cases=$results.ToArray(); Mutations=$mutations.ToArray(); Limits='Focused PowerShell script-generation qualification; no C# or native behavior changes and no release matrix.' }
}
