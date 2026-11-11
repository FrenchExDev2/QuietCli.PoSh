# Dot-sourced by the run-profile suite; every fixture remains local and no download is allowed.
Import-Module (Join-Path $scripts 'lib/RunToolCache.psm1') -Force

Test-Case 'assertions: an unmet failure expectation cannot leak objects and swallow the console summary' {
    $leaked = [Collections.Generic.List[object]]::new()
    $message = $null
    try { Assert-Throws { [pscustomobject]@{ Unexpected = 'output' } } 'ExpectedError' | ForEach-Object { $leaked.Add($_) } }
    catch { $message = $_.Exception.Message }
    Assert-That ($message -like 'Expected failure*' -and $leaked.Count -eq 0) 'assertion output contaminated the summary stream'
}

Test-Case 'profiler-unit: resolver honors explicit paths, environment and the exact pinned version' {
    $saved = $env:QUIETCLI_PROFILER_MODULE
    try {
        $good = Join-Path $work 'pinned.psd1'; $bad = Join-Path $work 'wrong-version.psd1'
        Write-RunTextFile $good "@{ ModuleVersion = '4.3.0' }"
        Write-RunTextFile $bad "@{ ModuleVersion = '4.2.0' }"
        $env:QUIETCLI_PROFILER_MODULE = $bad
        Assert-That ((Resolve-RunProfilerModule $good) -ceq $good) 'explicit path lost precedence'
        Assert-Throws { Resolve-RunProfilerModule } 'RunProfilerVersionMismatch'
        $env:QUIETCLI_PROFILER_MODULE = $good
        Assert-That ((Resolve-RunProfilerModule) -ceq $good) 'environment ignored'
        Assert-Throws { Resolve-RunProfilerModule (Join-Path $work 'absent.psd1') } 'RunProfilerNotFound'
    }
    finally { $env:QUIETCLI_PROFILER_MODULE = $saved }
}
Test-Case 'profiler-unit: generated trace rows preserve values, durations and bounded Unicode text' {
    $module = Get-Module RunProfiler
    $random = [Random]::new($Seed + 14)
    for ($index = 0; $index -lt $Iterations; $index++) {
        $ms = $random.Next(1,100000) / 8.0
        $row = [pscustomobject]@{ File = 'é.ps1'; Line = 17; Function = 'F'; Module = 'M'; HitCount = 19; SelfDuration = [TimeSpan]::FromMilliseconds($ms); Duration = [TimeSpan]::FromMilliseconds($ms * 2); SelfPercent = 12.5; Text = ('x' * 210) }
        $converted = & $module { param($value) Convert-RunTraceRows @($value) } $row
        Assert-That ($converted.SelfMs -eq $ms -and $converted.DurationMs -eq $ms * 2 -and $converted.HitCount -eq 19 -and $converted.Line -eq 17) 'trace numeric mapping'
        Assert-That ($converted.File -ceq 'é.ps1' -and $converted.Function -ceq 'F' -and $converted.Module -ceq 'M' -and $converted.SelfPercent -eq 12.5) 'trace identity'
        Assert-That ($converted.Text -ceq (('x' * 199) + '…')) 'trace text budget'
    }
    $empty = @(& $module { Convert-RunTraceRows @() })
    Assert-That ($empty.Count -eq 0) 'empty trace generated a row'
}
Test-Case 'profiler-unit: absent traces fail and do not publish a report' {
    $directory = Join-Path $work 'fake-profiler'; [void][IO.Directory]::CreateDirectory($directory)
    Write-RunTextFile (Join-Path $directory 'Profiler.psd1') "@{ ModuleVersion = '4.3.0'; RootModule = 'Profiler.psm1'; FunctionsToExport = @('Trace-Script') }"
    Write-RunTextFile (Join-Path $directory 'Profiler.psm1') 'function Trace-Script { param([scriptblock]$ScriptBlock, [switch]$DisableWarning) & $ScriptBlock; "noise" }; Export-ModuleMember -Function Trace-Script'
    $output = Join-Path $work 'no-trace'
    try { Assert-Throws { Invoke-RunProfiled -ScriptBlock { 1 } -OutputDirectory $output -Label 'missing' -ProfilerModulePath (Join-Path $directory 'Profiler.psd1') } 'RunProfilerNoTrace' }
    finally { Remove-Module Profiler -ErrorAction SilentlyContinue }
    Assert-That (-not (Test-Path (Join-Path $output 'missing.profile.json'))) 'failed profiler wrote a report'
}

function New-ToolCacheFixture {
    <#
    .SYNOPSIS
    Creates tiny local ZIP packages with independently computed hashes, never contacting a server.
    .PARAMETER OmitEntrypoint
    Creates an archive without the required Profiler manifest.
    #>
    param([switch]$OmitEntrypoint)
    $directory = Join-Path $work ('cache-' + [guid]::NewGuid().ToString('N'))
    $packages = @(Get-RunProfilerPackages)
    foreach ($package in $packages) {
        $destination = Join-Path $directory $package.Name
        [void][IO.Directory]::CreateDirectory($destination)
        $path = Join-Path $destination ($package.Name + '.' + $package.Version + '.nupkg')
        $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $name = if ($OmitEntrypoint -and $package.Name -eq 'Profiler') { 'absent.txt' } else { $package.Entrypoint }
            $entry = $zip.CreateEntry($name)
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write('fixture é') } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        $package.SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    [pscustomobject]@{ Directory = $directory; Packages = $packages }
}
Test-Case 'tool-cache: production tools retain exact pinned identities and entrypoints' {
    $packages = @(Get-RunProfilerPackages)
    Assert-That ($packages.Count -eq 2 -and $packages[0].Version -ceq '4.3.0' -and $packages[1].Version -ceq '10.0.750501') 'pinned versions'
    Assert-That ($packages[0].SHA256 -ceq '4BB44C89117EABAAFDA17B3DFFA622CFDFC770ED05EB6084469203C66DB43E0F' -and $packages[1].SHA256 -ceq 'EF17F25724A55F9685BFAF8506A778EA87C2B62783ECA2CA73263226128B0D4E') 'pinned digests'
    Assert-That ($packages[0].Entrypoint -ceq 'Profiler.psd1' -and $packages[1].Entrypoint -ceq 'tools/net8.0/any/dotnet-trace.dll') 'package layout'
}
Test-Case 'tool-cache: the initializer forwards the selected directory, offline policy and pinned catalogue' {
    function Invoke-FixtureCache {
        <# .SYNOPSIS
        Observes the initializer boundary without downloading, extracting or installing anything.
        #>
        param([string]$OutputDirectory, [hashtable[]]$Packages, [switch]$Offline)
        [pscustomobject]@{ Directory = $OutputDirectory; Offline = [bool]$Offline; Packages = $Packages }
    }
    Set-Alias -Name Initialize-RunToolCache -Value Invoke-FixtureCache -Scope Local
    $path = Join-Path $work 'initializer fixture'
    $result = & (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory $path -Offline
    Assert-That ($result.Directory -ceq $path -and $result.Offline -and $result.Packages.Count -eq 2 -and $result.Packages[0].Version -ceq '4.3.0') 'initializer discarded its contract'
    foreach($selection in @(@('profiler'),@('dottrace'),@('dottrace','profiler'),@('PROFILER','profiler'))){
        $result=& (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory $path -Module $selection -Offline
        $expected=@(if($selection -contains 'profiler'){'Profiler'};if($selection -contains 'dottrace'){'dotnet-trace'})
        Assert-That (($result.Packages.Name -join ',') -ceq ($expected -join ',')) 'initializer ignored requested modules'
    }
    foreach($invalid in @(@('unknown'),@('profiler','bad'),@(''),@())){
        $rejected=$false
        try{$null=& (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory $path -Module $invalid -Offline}catch{$rejected=$true}
        Assert-That $rejected 'invalid module selection accepted'
    }
    $preview=@(& (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory $path -Module profiler -WhatIf)
    Assert-That ($preview.Count -eq 0 -and !(Test-Path $path)) 'preview executed initializer'
}
Test-Case 'tool-cache: only requested packages are required and unselected tools remain absent' {
    foreach($selection in @(@('profiler'),@('dottrace'),@('profiler','dottrace'))){
        $fixture=New-ToolCacheFixture
        $names=@(Get-RunProfilerPackages -Module $selection | ForEach-Object Name)
        $selected=@($fixture.Packages | Where-Object Name -In $names)
        $target=Join-Path $work ([guid]::NewGuid().ToString('N'))
        $calls=[Collections.Generic.List[string]]::new()
        $tools=Initialize-RunToolCache -OutputDirectory $target -Packages $selected -DownloadBytes {
            param($url)
            $calls.Add($url)
            $p=@($fixture.Packages | Where-Object Url -CEQ $url)[0]
            ,([IO.File]::ReadAllBytes((Join-Path $fixture.Directory ($p.Name+'/'+$p.Name+'.'+$p.Version+'.nupkg'))))
        }.GetNewClosure()
        Assert-That ($calls.Count -eq $selected.Count) 'unrequested download'
        Assert-That ([bool]$tools.ProfilerModulePath -eq ($selection -contains 'profiler') -and [bool]$tools.ClrProfilerPath -eq ($selection -contains 'dottrace')) 'unrequested tool path'
        foreach($p in $fixture.Packages){
            Assert-That ((Test-Path (Join-Path $target $p.Name)) -eq ($names -contains $p.Name)) 'unrequested tool created'
        }
        Assert-Throws { Initialize-RunToolCache -OutputDirectory (Join-Path $target 'missing') -Packages $selected -Offline } 'ProfilerOfflineCacheMiss'
    }
}
Test-Case 'tool-cache: offline cache verifies, extracts, reuses and records both tools without global installation' {
    $fixture = New-ToolCacheFixture
    $tools = Initialize-RunToolCache -OutputDirectory $fixture.Directory -Packages $fixture.Packages -Offline
    Assert-That ([IO.File]::Exists($tools.ProfilerModulePath) -and [IO.File]::Exists($tools.ClrProfilerPath)) 'entrypoints absent'
    $receipt = Read-RunTextFile $tools.Receipt | ConvertFrom-Json
    Assert-That ($receipt.GlobalInstallation -eq $false -and $receipt.Packages.Count -eq 2 -and $receipt.ProfilerModulePath -ceq $tools.ProfilerModulePath) 'receipt incorrect'
    Write-RunTextFile $tools.ProfilerModulePath 'already extracted'
    $again = Initialize-RunToolCache -OutputDirectory $fixture.Directory -Packages $fixture.Packages -Offline
    Assert-That ((Read-RunTextFile $again.ProfilerModulePath) -ceq 'already extracted') 'warm cache unnecessarily extracted again'
}
Test-Case 'tool-cache: offline misses, tampered archives and missing package entrypoints fail closed' {
    Assert-Throws { Initialize-RunToolCache -OutputDirectory (Join-Path $work 'missing-cache') -Packages (Get-RunProfilerPackages) -Offline -DownloadBytes { throw 'ProviderMustNotRun' } } 'ProfilerOfflineCacheMiss'
    $fixture = New-ToolCacheFixture
    $package = $fixture.Packages[0]
    $archive = Join-Path $fixture.Directory ($package.Name + '/' + $package.Name + '.' + $package.Version + '.nupkg')
    [IO.File]::WriteAllBytes($archive, [byte[]]@(1,2,3))
    Assert-Throws { Initialize-RunToolCache -OutputDirectory $fixture.Directory -Packages $fixture.Packages -Offline } 'ProfilerCacheDigestMismatch'
    Assert-That (-not [IO.File]::Exists((Join-Path $fixture.Directory 'tool-receipt.json'))) 'corruption published a receipt'
    $missing = New-ToolCacheFixture -OmitEntrypoint
    Assert-Throws { Initialize-RunToolCache -OutputDirectory $missing.Directory -Packages $missing.Packages -Offline } 'ProfilerPackageLayoutMismatch'
}
Test-Case 'tool-cache: downloaded bytes are independently verified before cache writes or extraction' {
    $fixture = New-ToolCacheFixture
    $destination = Join-Path $work 'downloaded-cache'
    $calls = [Collections.Generic.List[string]]::new()
    $fetch = {
        param($url)
        $calls.Add($url)
        $package = @($fixture.Packages | Where-Object Url -CEQ $url)[0]
        return ,([IO.File]::ReadAllBytes((Join-Path $fixture.Directory ($package.Name + '/' + $package.Name + '.' + $package.Version + '.nupkg'))))
    }.GetNewClosure()
    $tools = Initialize-RunToolCache -OutputDirectory $destination -Packages $fixture.Packages -DownloadBytes $fetch
    Assert-That ($calls.Count -eq 2 -and [IO.File]::Exists($tools.ProfilerModulePath)) 'byte provider not used exactly once per tool'
    $badRoot = Join-Path $work 'bad-download'
    Assert-Throws { Initialize-RunToolCache -OutputDirectory $badRoot -Packages $fixture.Packages -DownloadBytes { param($url) ,([byte[]]@(0,1,2)) } } 'ProfilerDownloadDigestMismatch'
    Assert-That (-not [IO.File]::Exists((Join-Path $badRoot 'Profiler/Profiler.4.3.0.nupkg'))) 'unverified download was cached'
    Assert-Throws { Initialize-RunToolCache -OutputDirectory (Join-Path $work 'offline-provider') -Packages $fixture.Packages -Offline -DownloadBytes { throw 'ProviderMustNotRun' } } 'ProfilerOfflineCacheMiss'
}
Test-Case 'tool-cache-live: the initializer verifies both cached official archives offline' {
    $manifest = Resolve-RunProfilerModule
    $source = Split-Path (Split-Path $manifest -Parent) -Parent
    foreach($selection in @(@('profiler'),@('dottrace'),@('profiler','dottrace'))){
    $destination = Join-Path $work ('official-cache-'+($selection -join '-'))
    foreach ($package in Get-RunProfilerPackages -Module $selection) {
        $name = $package.Name + '.' + $package.Version + '.nupkg'
        $directory = Join-Path $destination $package.Name
        [void][IO.Directory]::CreateDirectory($directory)
        Copy-Item -LiteralPath (Join-Path $source ($package.Name + '/' + $name)) -Destination (Join-Path $directory $name)
    }
    $result = & (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory $destination -Module $selection -Offline
    Assert-That ([IO.File]::Exists($result.ProfilerModulePath) -eq ($selection -contains 'profiler') -and [IO.File]::Exists($result.ClrProfilerPath) -eq ($selection -contains 'dottrace') -and [IO.File]::Exists($result.Receipt)) 'initializer did not honor requested modules'
    }
    Assert-Throws { & (Join-Path $scripts 'Initialize-Profilers.ps1') -OutputDirectory (Join-Path $work 'initializer-cache-miss') -Offline } 'ProfilerOfflineCacheMiss'
}
