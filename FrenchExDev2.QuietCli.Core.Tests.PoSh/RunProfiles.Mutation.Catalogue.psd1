@{ SchemaVersion=1; Mutants=@(
    @{ Name = 'name-anchor-loose'; File = 'lib/RunProfileStore.psm1'; From = '{0,63}\z''' ; To = '{0,63}$''' }
    @{ Name = 'name-length-off-by-one'; File = 'lib/RunProfileStore.psm1'; From = '{0,63}\z'; To = '{0,64}\z' }
    @{ Name = 'restricted-language-off'; File = 'lib/RunProfileStore.psm1'; From = '$block.CheckRestrictedLanguage([string[]]@(), [string[]]@(''true'', ''false'', ''null''), $false)'; To = '$block | Out-Null' }
    @{ Name = 'restricted-env-allowed'; File = 'lib/RunProfileStore.psm1'; From = '''null''), $false)'; To = '''null''), $true)' }
    @{ Name = 'unknown-key-allowed'; File = 'lib/RunProfileStore.psm1'; From = 'if ($key -cnotin $script:AllowedKeys)'; To = 'if ($false)' }
    @{ Name = 'name-mismatch-ignored'; File = 'lib/RunProfileStore.psm1'; From = 'if ($ExpectedName -and $Profile.Name -cne $ExpectedName)'; To = 'if ($false)' }
    @{ Name = 'script-pattern-open'; File = 'lib/RunProfileStore.psm1'; From = '''^[A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z'''; To = '''^.*\.ps1\z''' }
    @{ Name = 'overwrite-unguarded'; File = 'lib/RunProfileStore.psm1'; From = '-and -not $Force)'; To = '-and $false)' }
    @{ Name = 'merge-profile-wins'; File = 'lib/RunProfileStore.psm1'; From = 'foreach ($key in $Arguments.Keys) { $merged[$key] = $Arguments[$key] }'; To = 'foreach ($key in $Arguments.Keys) { if (-not $merged.ContainsKey($key)) { $merged[$key] = $Arguments[$key] } }' }
    @{ Name = 'double-loses-type'; File = 'lib/RunProfileStore.psm1'; From = 'else { "$text.0" }'; To = 'else { $text }' }
    @{ Name = 'infinity-accepted'; File = 'lib/RunProfileStore.psm1'; From = '-not ([double]::IsNaN($Value) -or [double]::IsInfinity($Value))'; To = '-not [double]::IsNaN($Value)' }
    @{ Name = 'schema-version-open'; File = 'lib/RunProfileStore.psm1'; From = ' -or $Profile.SchemaVersion -ne $script:SchemaVersion'; To = '' }
    @{ Name = 'parameters-unsorted'; File = 'lib/RunProfileStore.psm1'; From = '($Profile.Parameters.Keys | Sort-Object -CaseSensitive)'; To = '$Profile.Parameters.Keys' }
    @{ Name = 'directory-not-created'; File = 'lib/RunProfileStore.psm1'; From = '    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))'; To = '' }
    @{ Name = 'unknown-parameter-allowed'; File = 'lib/RunProfileStore.psm1'; From = 'if (-not $declared.ContainsKey($key)) { throw'; To = 'if ($false) { throw' }
    @{ Name = 'control-characters-allowed'; File = 'lib/RunFormat.psm1'; From = '''[\u0000-\u001F\u007F]'''; To = '''[\u0000]''' }
    @{ Name = 'typographic-quotes-undoubled'; File = 'lib/RunFormat.psm1'; From = '"[''‘‘’’‚‚‛‛]"'; To = '"['']"' }
    @{ Name = 'right-alignment-lost'; File = 'lib/RunFormat.psm1'; From = 'if ($Right) { return $Text.PadLeft($Width) }'; To = 'if ($Right) { return $Text.PadRight($Width) }' }
    @{ Name = 'ellipsis-lost'; File = 'lib/RunFormat.psm1'; From = '$Text.Substring(0, [Math]::Max(0, $Width - 1)) + ''…'''; To = '$Text.Substring(0, $Width)' }
    @{ Name = 'shrink-disabled'; File = 'lib/RunFormat.psm1'; From = '$widths[$widest]--; $overflow--'; To = '$overflow--' }
    @{ Name = 'duration-boundary'; File = 'lib/RunFormat.psm1'; From = '$magnitude -lt 999.5'; To = '$magnitude -lt 1000' }
    @{ Name = 'minutes-dropped'; File = 'lib/RunFormat.psm1'; From = 'elseif ($minutes -gt 0) { "${minutes}m"'; To = 'elseif ($false) { "${minutes}m"' }
    @{ Name = 'hours-dropped'; File = 'lib/RunFormat.psm1'; From = 'if ($hours -gt 0) { "${hours}h"'; To = 'if ($false) { "${hours}h"' }
    @{ Name = 'ms-counters-raw'; File = 'lib/RunFormat.psm1'; From = '$key.EndsWith(''.ms'', [StringComparison]::Ordinal)'; To = '$false' }
    @{ Name = 'quantile-floor'; File = 'lib/RunStatistics.psm1'; From = '$Sorted[$low] + ($Sorted[$high] - $Sorted[$low]) * ($position - $low)'; To = '$Sorted[$low]' }
    @{ Name = 'even-median-upper'; File = 'lib/RunStatistics.psm1'; From = '($buffer[$middle - 1] + $buffer[$middle]) / 2'; To = '$buffer[$middle]' }
    @{ Name = 'seed-fixed'; File = 'lib/RunStatistics.psm1'; From = '[Random]::new($Seed)'; To = '[Random]::new(1)' }
    @{ Name = 'alpha-one-tail'; File = 'lib/RunStatistics.psm1'; From = '$alpha = (1 - $Confidence) / 2'; To = '$alpha = (1 - $Confidence)' }
    @{ Name = 'verdict-low-boundary'; File = 'lib/RunStatistics.psm1'; From = 'if ($Interval.Low -gt 0)'; To = 'if ($Interval.Low -ge 0)' }
    @{ Name = 'verdict-high-boundary'; File = 'lib/RunStatistics.psm1'; From = 'if ($Interval.High -lt 0)'; To = 'if ($Interval.High -le 0)' }
    @{ Name = 'minimum-pairs-boundary'; File = 'lib/RunStatistics.psm1'; From = '$Interval.Pairs -lt $MinPairs'; To = '$Interval.Pairs -le $MinPairs' }
    @{ Name = 'summary-q3-wrong'; File = 'lib/RunStatistics.psm1'; From = 'Q3     = Get-SortedQuantile $sorted 0.75'; To = 'Q3     = Get-SortedQuantile $sorted 0.5' }
    @{ Name = 'bootstrap-no-resampling'; File = 'lib/RunStatistics.psm1'; From = '$buffer[$i] = $Differences[$random.Next($n)]'; To = '$buffer[$i] = $Differences[$i]' }
    @{ Name = 'log-level-boundary'; File = 'lib/RunLog.psm1'; From = 'if ($level -lt $this.Level)'; To = 'if ($level -le $this.Level)' }
    @{ Name = 'level-counter-missing'; File = 'lib/RunLog.psm1'; From = '$this.Add(''log.'' + $level.ToString().ToLowerInvariant(), 1)'; To = '$null = 0' }
    @{ Name = 'suppressed-uncounted'; File = 'lib/RunLog.psm1'; From = '{ $this.Add(''log.suppressed'', 1); return }'; To = '{ return }' }
    @{ Name = 'child-private-counters'; File = 'lib/RunLog.psm1'; From = '$this.Sinks, $this.Counters)'; To = '$this.Sinks, [Collections.Generic.Dictionary[string, long]]::new())' }
    @{ Name = 'time-failure-uncounted'; File = 'lib/RunLog.psm1'; From = '$this.Add($name + ''.failed'', 1)'; To = '$null = 0' }
    @{ Name = 'time-count-missing'; File = 'lib/RunLog.psm1'; From = '$this.Add($name + ''.count'', 1)'; To = '$null = 0' }
    @{ Name = 'snapshot-unsorted'; File = 'lib/RunLog.psm1'; From = 'foreach ($key in ($this.Counters.Keys | Sort-Object -CaseSensitive))'; To = 'foreach ($key in $this.Counters.Keys)' }
    @{ Name = 'sink-failure-fatal'; File = 'lib/RunLog.psm1'; From = 'catch { $this.Add(''log.sinkfailed'', 1) }'; To = 'catch { throw }' }
    @{ Name = 'forward-undeclared'; File = 'Invoke-RunProfile.ps1'; From = 'if ($declared.ContainsKey($forwarded.Key) -and -not $parameters.ContainsKey($forwarded.Key) -and $forwarded.Value)'; To = 'if (-not $parameters.ContainsKey($forwarded.Key) -and $forwarded.Value)' }
    @{ Name = 'forward-overrides-explicit'; File = 'Invoke-RunProfile.ps1'; From = 'if ($declared.ContainsKey($forwarded.Key) -and -not $parameters.ContainsKey($forwarded.Key) -and $forwarded.Value)'; To = 'if ($declared.ContainsKey($forwarded.Key) -and $forwarded.Value)' }
    @{ Name = 'whatif-ignored'; File = 'Invoke-RunProfile.ps1'; From = 'if (-not $PSCmdlet.ShouldProcess($target, "Run profile ''$Name''"))'; To = 'if ($false)' }
    @{ Name = 'parameter-count-hijacked'; File = 'Invoke-RunProfile.ps1'; From = '[string]$entry.Parameters.get_Count()'; To = '[string]$entry.Parameters.Count' }
    @{ Name = 'create-unvalidated'; File = 'New-RunProfile.ps1'; From = 'Assert-RunTargetParameters -TargetPath $target -Parameters $Parameters'; To = '$null = 0' }
    # Encoding policy: files are fixed (UTF-8 without BOM, LF, strict), the console boundary is a parameter.
    @{ Name = 'file-bom-added'; File = 'lib/RunEncoding.psm1'; From = '$script:Utf8Writer = [Text.UTF8Encoding]::new($false, $true)'; To = '$script:Utf8Writer = [Text.UTF8Encoding]::new($true, $true)' }
    @{ Name = 'file-write-latin1'; File = 'lib/RunEncoding.psm1'; From = '$script:Utf8Writer = [Text.UTF8Encoding]::new($false, $true)'; To = '$script:Utf8Writer = [Text.Encoding]::Latin1' }
    @{ Name = 'file-write-lenient'; File = 'lib/RunEncoding.psm1'; From = '$script:Utf8Writer = [Text.UTF8Encoding]::new($false, $true)'; To = '$script:Utf8Writer = [Text.UTF8Encoding]::new($false, $false)' }
    @{ Name = 'file-read-lenient'; File = 'lib/RunEncoding.psm1'; From = '$script:Utf8Strict = [Text.UTF8Encoding]::new($false, $true)'; To = '$script:Utf8Strict = [Text.UTF8Encoding]::new($false, $false)' }
    @{ Name = 'file-crlf-written'; File = 'lib/RunEncoding.psm1'; From = '(ConvertTo-RunLf $Text), $script:Utf8Writer'; To = '$Text, $script:Utf8Writer' }
    @{ Name = 'lone-cr-kept'; File = 'lib/RunEncoding.psm1'; From = '.Replace("`r`n", "`n").Replace("`r", "`n")'; To = '.Replace("`r`n", "`n")' }
    @{ Name = 'append-crlf'; File = 'lib/RunEncoding.psm1'; From = '((ConvertTo-RunLf $Line) + "`n")'; To = '((ConvertTo-RunLf $Line) + "`r`n")' }
    @{ Name = 'append-unnormalized'; File = 'lib/RunEncoding.psm1'; From = '((ConvertTo-RunLf $Line) + "`n")'; To = '($Line + "`n")' }
    @{ Name = 'console-utf8-is-oem'; File = 'lib/RunEncoding.psm1'; From = '''utf-8'' { return [Text.UTF8Encoding]::new($false) }'; To = '''utf-8'' { return [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }' }
    @{ Name = 'console-utf8-bom'; File = 'lib/RunEncoding.psm1'; From = '''utf-8'' { return [Text.UTF8Encoding]::new($false) }'; To = '''utf-8'' { return [Text.UTF8Encoding]::new($true) }' }
    @{ Name = 'console-name-case-sensitive'; File = 'lib/RunEncoding.psm1'; From = 'switch ($Name.ToLowerInvariant())'; To = 'switch -CaseSensitive ($Name)' }
    @{ Name = 'console-unknown-accepted'; File = 'lib/RunEncoding.psm1'; From = 'default { throw "RunConsoleEncodingUnknown: ''$Name'' (expected utf-8 or oem)" }'; To = 'default { return [Text.UTF8Encoding]::new($false) }' }
    @{ Name = 'console-output-not-applied'; File = 'lib/RunEncoding.psm1'; From = '[Console]::OutputEncoding = $encoding'; To = '$null = 0' }
    @{ Name = 'console-pipe-not-applied'; File = 'lib/RunEncoding.psm1'; From = '$global:OutputEncoding = $encoding'; To = '$null = 0' }
    @{ Name = 'profile-write-bypasses-policy'; File = 'lib/RunProfileStore.psm1'; From = 'Write-RunTextFile -Path $path -Text $source'; To = '[IO.File]::WriteAllText($path, $source, [Text.UTF8Encoding]::new($true))' }
    @{ Name = 'profile-read-bypasses-policy'; File = 'lib/RunProfileStore.psm1'; From = '$text = Read-RunTextFile -Path $Path'; To = '$text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $false))' }
    @{ Name = 'log-sink-bypasses-policy'; File = 'lib/RunLog.psm1'; From = 'Add-RunTextLine -Path $this.Path -Line $Line'; To = '[IO.File]::AppendAllText($this.Path, $Line + "`r`n")' }
    @{ Name = 'sample-arity-open'; File = 'lib/RunColdStart.psm1'; From = '$Fields.Count -ne 3'; To = '$Fields.Count -lt 3' }
    @{ Name = 'sample-nonfinite-accepted'; File = 'lib/RunColdStart.psm1'; From = '-not [double]::IsFinite($value)'; To = '$false' }
    @{ Name = 'sample-negative-accepted'; File = 'lib/RunColdStart.psm1'; From = '$value -lt 0'; To = '$false' }
    @{ Name = 'sample-first-swapped'; File = 'lib/RunColdStart.psm1'; From = 'First = $values[1]'; To = 'First = $values[0]' }
    @{ Name = 'benchmark-warmup-included'; File = 'Measure-ColdStart.ps1'; From = '$pair -gt $Warmup'; To = '$pair -ge $Warmup' }
    @{ Name = 'benchmark-failure-budget-exclusive'; File = 'Measure-ColdStart.ps1'; From = "Get('pair.discarded') -gt"; To = "Get('pair.discarded') -ge" }
    @{ Name = 'benchmark-difference-reversed'; File = 'Measure-ColdStart.ps1'; From = '$cand[$i] - $base[$i]'; To = '$base[$i] - $cand[$i]' }
    @{ Name = 'benchmark-duplicate-marker-accepted'; File = 'Measure-ColdStart.ps1'; From = '-or $result.Data.Matches -ne 1'; To = '' }
    @{ Name = 'benchmark-failed-child-accepted'; File = 'Measure-ColdStart.ps1'; From = '$result.Outcome -ne ''Success'' -or'; To = '$false -or' }
    @{ Name = 'benchmark-profile-path-split'; File = 'Measure-ColdStart.ps1'; From = '($fields -join '' '')'; To = '$fields[0]' }
    @{ Name = 'profiler-version-ignored'; File = 'lib/RunProfiler.psm1'; From = '$manifest.ModuleVersion -ne $script:PinnedVersion'; To = '$false' }
    @{ Name = 'profiler-explicit-path-ignored'; File = 'lib/RunProfiler.psm1'; From = 'if ($Path) { $candidates += $Path }'; To = 'if ($false) { $candidates += $Path }' }
    @{ Name = 'profiler-environment-ignored'; File = 'lib/RunProfiler.psm1'; From = '$candidates += $env:QUIETCLI_PROFILER_MODULE'; To = '$candidates += "absent-profiler.psd1"' }
    @{ Name = 'profiler-duration-not-ms'; File = 'lib/RunProfiler.psm1'; From = '([TimeSpan]$row.SelfDuration).TotalMilliseconds'; To = '([TimeSpan]$row.SelfDuration).TotalSeconds' }
    @{ Name = 'profiler-total-duration-wrong'; File = 'lib/RunProfiler.psm1'; From = '([TimeSpan]$row.Duration).TotalMilliseconds'; To = '([TimeSpan]$row.SelfDuration).TotalMilliseconds' }
    @{ Name = 'profiler-hitcount-dropped'; File = 'lib/RunProfiler.psm1'; From = 'HitCount   = [long]$row.HitCount'; To = 'HitCount   = 0L' }
    @{ Name = 'profiler-text-unbounded'; File = 'lib/RunProfiler.psm1'; From = '$text.Length -gt 200'; To = '$false' }
    @{ Name = 'profiler-no-trace-accepted'; File = 'lib/RunProfiler.psm1'; From = 'if ($null -eq $trace)'; To = 'if ($false)' }
    @{ Name = 'tool-cache-digest-ignored'; File = 'lib/RunToolCache.psm1'; From = '[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($cached)) -cne $package.SHA256'; To = '$false' }
    @{ Name = 'tool-cache-layout-ignored'; File = 'lib/RunToolCache.psm1'; From = 'if (-not [IO.File]::Exists($entrypoint)) { throw ''ProfilerPackageLayoutMismatch'' }'; To = '' }
    @{ Name = 'tool-cache-extraction-skipped'; File = 'lib/RunToolCache.psm1'; From = '[void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive, $directory, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()'; To = '$null = 0' }
    @{ Name = 'tool-cache-warm-extracts-again'; File = 'lib/RunToolCache.psm1'; From = 'if (-not [IO.File]::Exists($entrypoint)) { [void][IO.Compression.ZipFile]'; To = 'if ($true) { [void][IO.Compression.ZipFile]' }
    @{ Name = 'tool-cache-global-installation'; File = 'lib/RunToolCache.psm1'; From = 'GlobalInstallation = $false'; To = 'GlobalInstallation = $true' }
    @{ Name = 'tool-cache-profiler-version-drift'; File = 'lib/RunToolCache.psm1'; From = "Version = '4.3.0'"; To = "Version = '4.4.0'" }
    @{ Name = 'tool-download-digest-ignored'; File = 'lib/RunToolCache.psm1'; From = '[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $package.SHA256'; To = '$false' }
    @{ Name = 'tool-offline-ignored'; File = 'lib/RunToolCache.psm1'; From = 'if ($Offline)'; To = 'if ($false)' }
    @{ Name = 'initializer-offline-not-forwarded'; File = 'Initialize-Profilers.ps1'; From = '-Offline:$Offline'; To = '-Offline:$false' }
    @{ Name = 'initializer-selection-ignored'; File = 'Initialize-Profilers.ps1'; From = 'Get-RunProfilerPackages -Module $Module'; To = 'Get-RunProfilerPackages' }
    @{ Name = 'initializer-directory-ignored'; File = 'Initialize-Profilers.ps1'; From = '-OutputDirectory $OutputDirectory'; To = '-OutputDirectory "wrong-cache"' }
)
}
