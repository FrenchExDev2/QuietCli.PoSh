#requires -Version 7.6
Set-StrictMode -Version Latest
function Assert-QuietEqual {
    <#
.SYNOPSIS
Asserts an independently known expected value with an actionable failure.
    .PARAMETER Actual
    Observed value.
    .PARAMETER Expected
    Independent expectation.
    .PARAMETER Because
    Invariant being checked.
    #>
    param([AllowNull()]$Actual,[AllowNull()]$Expected,[string]$Because='Values must match')
    if($Actual -cne $Expected){throw "$Because : expected <$Expected>, observed <$Actual>"}
}
function Invoke-QuietConformance {
    <#
.SYNOPSIS
Checks the shared envelope invariants without serializing business values.
    .PARAMETER Result
    Result returned by a candidate handler.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$Result)
    Assert-QuietEqual $Result.PSObject.TypeNames[0] 'QuietCli2.Result'
    Assert-QuietEqual $Result.Execution.State 'Finalized'
    Assert-QuietEqual $Result.Measurement.OutputBytes $null 'AsObject must not invent a serialized size'
    Assert-QuietEqual $Result.Deliveries.Count 0 'AsObject must not serialize a delivery'
    foreach($source in $Result.Internal.Sources.Values){if($source.Contains('Capture') -or $source.Contains('Stdout') -or $source.Contains('Stderr')){throw 'Raw native output retained in source metadata'}}
}
function Invoke-QuietCoreTests {
    <#
.SYNOPSIS
Executes independent native byte and object invariants in a companion module.
    .PARAMETER OnProgress
    Callback receiving name, state, passed and failed counters.
    .PARAMETER WorkspaceRoot
    Workspace containing the engine and independent fixture.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress)
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    if(!(Test-Path -LiteralPath $fixture)){throw 'Build the independent C# fixture first.'}
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $performance=[Collections.Generic.List[object]]::new()
    $galleryEvidence=[Collections.Generic.List[object]]::new()
    $cases=[ordered]@{}
    $cases['cold engine and warm block-size measurements retain no business output']={
        Stop-QuietEngine
        $cold=[Diagnostics.Stopwatch]::StartNew();$identity=Get-QuietEngine;$cold.Stop()
        $performance.Add(@{Kind='ColdEngine';Milliseconds=$cold.Elapsed.TotalMilliseconds;Runtime=$identity.Engine.Runtime})
        foreach($size in @(4096,16384)){
            $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
            $r=quiet -AsObject -Role Infrastructure -ReadBlockBytes $size -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 8388608
            $elapsed=$watch.Elapsed.TotalMilliseconds;$after=Get-QuietEngine
            Assert-QuietEqual $r.Outcome Success
            Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 8388608
            $performance.Add(@{Kind='WarmStream';ReadBlockBytes=$size;Bytes=8388608;ElapsedMs=$elapsed;NativeMs=$r.Execution.Native.ElapsedMs;CallbackMs=$r.Execution.CallbackMs;ProtocolBytes=($after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes);ProtocolRequests=$after.Requests-$before.Requests;Interpretation='One fixture sample, not a general speed claim.'})
        }
    }
    $cases['build provenance rejects changed binaries and stale source']={
        $directory=Join-Path $WorkspaceRoot ('artifacts/build-provenance/'+[guid]::NewGuid().ToString('N'))
        foreach($folder in @('FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture','FrenchExDev2.QuietCli.Core.PoSh','output')){[void][IO.Directory]::CreateDirectory((Join-Path $directory $folder))}
        $project='FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Synthetic.csproj'
        $files=@{'global.json'='{}';'FrenchExDev2.QuietCli.Core.PoSh/protocol.json'='{}';$project='<Project />';'FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Program.cs'='// synthetic source';'output/Synthetic.dll'='synthetic binary'}
        foreach($entry in $files.GetEnumerator()){[void][IO.File]::WriteAllTextAsync((Join-Path $directory $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        & {
            param($scripts,$directory,$project)
            . (Join-Path $scripts 'Common.ps1')
            $inputs=@(Get-QuietBinaryInputs $directory $project)
            Write-QuietBuildManifest $directory $project output -Inputs $inputs
            $null=Test-QuietBuildManifest $directory output
            $binary=Join-Path $directory 'output/Synthetic.dll'
            [void][IO.File]::WriteAllTextAsync($binary,'modified binary',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Test-QuietBuildManifest $directory output}catch{$rejected=$_.Exception.Message -like 'BuildBinaryMismatch:*'}
            if(!$rejected){throw 'Modified binary was accepted'}
            [void][IO.File]::WriteAllTextAsync($binary,'synthetic binary',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/Program.cs'),'// modified source',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Test-QuietBuildManifest $directory output}catch{$rejected=$_.Exception.Message -like 'StaleBuild:*'}
            if(!$rejected){throw 'Stale build was accepted'}
        } (Join-Path $WorkspaceRoot 'scripts') $directory $project
    }
    $cases['all six embedded engines have matching native and managed architectures']={
        & {
            param($root)
            . (Join-Path $root 'scripts/Common.ps1')
            $targets=@(Get-QuietRuntimeTargets $root)
            $expected=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')
            if($targets.Count -ne 6 -or @($expected|Where-Object {$_ -cnotin $targets.Rid}).Count){throw 'Release target set incomplete'}
            foreach($target in $targets){
                $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$target.Rid
                $manifest=Test-QuietBuildManifest $root $output
                if($manifest.RuntimeIdentifier -cne $target.Rid -or $manifest.PlatformTarget -cne $target.PlatformTarget){throw 'Compiler target metadata mismatch'}
                Assert-QuietRuntimePublication (Join-Path $root $output) $target
                $configuration=Get-Content -LiteralPath (Join-Path (Join-Path $root $output) 'QuietCli.Engine.runtimeconfig.json') -Encoding utf8 -Raw|ConvertFrom-Json
                if($configuration.runtimeOptions.framework.version -cne '11.0.0-rc.3.26522.148'){throw 'Published engine runtime changed'}
            }
        } $WorkspaceRoot
        $identity=Get-QuietEngine
        Assert-QuietEqual $identity.Engine.BuildRuntimeIdentifier ([Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)
    }
    $cases['C# protocol and concurrent SQLite assertions']={
        $assembly=Join-Path $PSScriptRoot 'lib/engine-tests/QuietCli.Engine.Tests.dll'
        $nativeDirectory=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $nativeDirectory
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Passed 13
        Assert-QuietEqual $r.Data.Failed 0
    }
    $cases['PTY reports a merged terminal counter without fake stderr separation']={
        $r=quiet -AsObject -Transport Pty -Data @{Seen=0L;Text=[Text.StringBuilder]::new()} -Output {param($e,$r)$r.Data.Seen+=$e.ByteCount;[void]$r.Data.Text.Append($e.Text)} $dotnet $fixture terminal
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead $null
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead $null
        Assert-QuietEqual $r.Execution.Native.TerminalBytesRead $r.Data.Seen
        if(!$r.Data.Text.ToString().Contains('out') -or !$r.Data.Text.ToString().Contains('err')){throw 'PTY lost stdout or stderr'}
    }
    $cases['exact stdout/stderr counters with no capture']={
        $r=quiet -AsObject -StdoutMode Bytes -StderrMode Bytes -Data @{Seen=0L} -Output {param($e,$r)$r.Data.Seen+=$e.Bytes.Length} $dotnet $fixture mixed 123456 234567
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 123456
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead 234567
        Assert-QuietEqual $r.Data.Seen 358023
        Invoke-QuietConformance $r
    }
    $cases['AsObject does not enumerate or serialize business getters']={
        $business=[pscustomobject]@{Marker='local'}
        $business|Add-Member ScriptProperty Forbidden {throw 'Business object was enumerated for measurements'}
        $r=quiet -AsObject -Data $business -Output {param($e,$r)} $dotnet $fixture emit 10
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual ([object]::ReferenceEquals($r.Data,$business)) $true
        Invoke-QuietConformance $r
    }
    $cases['large output retains only bounded transport blocks']={
        $before=[GC]::GetTotalMemory($true)
        $r=quiet -AsObject -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 67108864
        $after=[GC]::GetTotalMemory($true)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 67108864
        if($after-$before -gt 33554432){throw 'Managed memory grew proportionally to discarded output'}
        Invoke-QuietConformance $r
    }
    $cases['nested callback inherits context without serializing child objects']={
        $r=quiet -AsObject -C nested -Data @{Child=$null} -Output {param($e,$r)if(!$r.Data.Child){$r.Data.Child=quiet -AsObject -Data @{Bytes=0L} -StdoutMode Bytes -Output {param($e,$r)$r.Data.Bytes+=$e.Bytes.Length} $dotnet $fixture emit 29}} $dotnet $fixture emit 17
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Child.Context nested
        Assert-QuietEqual $r.Data.Child.Data.Bytes 29
        Assert-QuietEqual $r.Execution.Children 1
        Assert-QuietEqual $r.Internal.Sources.Count 2
        Invoke-QuietConformance $r.Data.Child
    }
    $cases['assigned child failure remains visible']={
        $r=quiet -AsObject -Output {param($e,$r)$child=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture fail} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Execution.Issues.Count 1
    }
    $cases['context is not sticky across independent invocations']={
        $named=quiet -AsObject -C named -Output {param($e,$r)} $dotnet $fixture emit 1
        $generic=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $named.Context named
        Assert-QuietEqual $generic.Context $null
    }
    $cases['stdin bytes are exact and output is drained while feeding']={
        $bytes=[byte[]]::new(1048576);[Random]::new(42).NextBytes($bytes)
        $r=quiet -AsObject -InputBytes $bytes -Data @{Hash=[Text.StringBuilder]::new()} -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Hash.Append($e.Text)}} -Complete {param($r) @{Hash=$r.Data.Hash.ToString()}} $dotnet $fixture hash
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdinBytesWritten $bytes.Length
        Assert-QuietEqual $r.Data.Hash ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
    }
    $cases['UTF8 and NUL framing preserve split Unicode characters']={
        $r=quiet -AsObject -RecordDelimiter ([string][char]0) -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add($e.Text)} $dotnet $fixture unicode
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 2
        Assert-QuietEqual $r.Data[0] 'é漢🙂'
        Assert-QuietEqual $r.Data[1] 'fin'
    }
    $cases['truncated UTF8 fails analysis rather than dropping bytes']={
        $r=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture invalid
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 1
    }
    $cases['Complete runs once after Output failure and native drain']={
        $state=@{Calls=0}
        $r=quiet -AsObject -State $state -Output {param($e,$r)throw 'expected parser failure'} -Complete {param($r)$r.State.Calls++} $dotnet $fixture emit 131072
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $state.Calls 1
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 131072
    }
    $cases['accidental Output emission never becomes business Data']={
        $r=quiet -AsObject -Data @{Kept=$true} -Output {param($e,$r)'accidental'} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Data.Kept $true
    }
    $cases['timeout preserves partial native state']={
        $r=quiet -AsObject -TimeoutSeconds 0.3 -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Timeout
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['interactive cancellation affects only the owned child']={
        $r=quiet -AsObject -Interaction {param($r)$r.Cancel()} -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Cancelled
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['delimiter overflow fails analysis and still drains bytes']={
        $r=quiet -AsObject -RecordDelimiter "`n" -MaxRecordBytes 64 -Output {param($e,$r)} $dotnet $fixture emit 20000
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 20000
    }
    $cases['native arguments preserve empty strings spaces and Unicode']={
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)[void]$r.Data.Append($e.Text)} -Complete {param($r),@($r.Data.ToString()|ConvertFrom-Json)} $dotnet $fixture args '' 'a b' 'é🙂' '--native'
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 4
        Assert-QuietEqual $r.Data[0] ''
        Assert-QuietEqual $r.Data[2] 'é🙂'
    }
    $cases['delivery is bounded and AsObject remains unserialized until requested']={
        $r=quiet -AsObject -Data @{Values=@(1..100)} -Output {param($e,$r)} $dotnet $fixture emit 2000
        Assert-QuietEqual $r.Deliveries.Count 0
        $json=$r|ConvertTo-QuietJson -MaxItems 5 -MaxOutputBytes 1024
        $doc=$json|ConvertFrom-Json
        Assert-QuietEqual $doc.Data.Values.Count 5
        Assert-QuietEqual $doc.Truncation.Applied $true
        Assert-QuietEqual $r.Data.Values.Count 100
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($json))
        Assert-QuietEqual $r.Deliveries[0].Text $json
    }
    $cases['empty singleton and nested arrays preserve JSON shape']={
        $r=quiet -AsObject -Data @{Empty=@();One=@(7);Nested=@(@(1,2),@(3,4));Nothing=$null;Object=@{}} -Output {param($e,$r)} $dotnet $fixture emit 1
        $json=$r|ConvertTo-QuietJson
        $doc=$json|ConvertFrom-Json -AsHashtable
        Assert-QuietEqual ($doc.Data.Empty -is [array]) $true
        Assert-QuietEqual $doc.Data.Empty.Count 0
        Assert-QuietEqual $doc.Data.One.Count 1
        Assert-QuietEqual $doc.Data.Nested[0].Count 2
        Assert-QuietEqual $doc.Data.Nothing $null
    }
    $cases['bounded delivery preserves failure identity without serializing omitted business data']={
        $r=quiet -AsObject -Data @{Large=('é'*5000)} -Output {param($e,$r)throw ('diagnostic '*1000)} $dotnet $fixture emit 10
        $json=$r|ConvertTo-QuietJson -MaxOutputBytes 300
        $document=$json|ConvertFrom-Json
        Assert-QuietEqual $document.Outcome Failed
        Assert-QuietEqual $document.Error.Code OutputCallbackFailed
        Assert-QuietEqual $document.Truncation.Applied $true
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 300){throw 'Failure envelope exceeded the final budget'}
    }
    $cases['generic and named gain filters are independent']={
        $named=Get-QuietCliGain -C named -AsObject
        $generic=Get-QuietCliGain -Generic -AsObject
        if($named.Invocations -lt 1 -or $generic.Invocations -lt 1){throw 'Expected persisted named and generic invocations'}
        Assert-QuietEqual $named.RootDeliveryBytes $null
    }
    $cases['delivery token count observes produced text only']={
        $r=quiet -AsObject -Data @{Message='évidence'} -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Measurement.OutputTokens $null
        $text=Out-QuietResult -InputObject $r -Tokenizer o200k_base
        if($r.Measurement.OutputTokens -le 0){throw 'Exact delivery tokenizer was not applied'}
        Assert-QuietEqual $r.Measurement.NativeTokens $null
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($text))
    }
    $cases['module scaffolding creates inert handlers and independent failing test companions']={
        $parent=Join-Path $WorkspaceRoot ('artifacts/scaffold-tests/'+[guid]::NewGuid().ToString('N'))
        $name='Sample.QuietTool.PoSh'
        $generated=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent
        $manifest=Import-PowerShellDataFile (Join-Path $generated.Module ($name+'.psd1'))
        Assert-QuietEqual $manifest.RequiredModules.Count 1
        Assert-QuietEqual $manifest.RequiredModules[0].ModuleName FrenchExDev2.QuietCli.Core.PoSh
        $testName='Sample.QuietTool.Tests.PoSh'
        $testManifest=Import-PowerShellDataFile (Join-Path $generated.Tests ($testName+'.psd1'))
        Assert-QuietEqual $testManifest.RequiredModules.Count 2
        $module=Import-Module (Join-Path $generated.Module ($name+'.psd1')) -PassThru
        try{
            $catalogue=@(Get-QuietHandler -Binary quietfixture)
            Assert-QuietEqual $catalogue.Count 1
            Assert-QuietEqual $catalogue[0].Qualification NotImplemented
            $errors=$null;$tokens=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $generated.Tests ($testName+'.psm1')),[ref]$tokens,[ref]$errors)
            Assert-QuietEqual $errors.Count 0
            $function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
            if(!$function.GetHelpContent()){throw 'Generated test entry point has no readable help'}
            $rejected=$false
            try{$null=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent}catch{$rejected=$_.Exception.Message -eq 'ModuleDestinationExists'}
            Assert-QuietEqual $rejected $true
        }finally{Remove-Module $module}
        Assert-QuietEqual @(Get-QuietHandler -Binary quietfixture).Count 0
    }
    $cases['monitor duration preserves November timestamps in French and English cultures']={
        . (Join-Path $WorkspaceRoot 'scripts/Monitor.Time.ps1')
        $culture=[Globalization.CultureInfo]::CurrentCulture
        try{
            foreach($name in @('fr-FR','en-US')){
                [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($name)
                $start=[DateTimeOffset]::Parse('2026-11-04T20:00:00Z',[Globalization.CultureInfo]::InvariantCulture)
                $end=$start.AddSeconds(125)
                foreach($value in @($start,$start.UtcDateTime,'2026-11-04T20:00:00Z')){
                    Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $value -Now $end) 2m5s
                    Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $value -FinishedUtc $end -Now $end.AddDays(207)) 2m5s
                }
                $decoded='{"StartedUtc":"2026-11-04T20:00:00Z","FinishedUtc":"2026-11-04T20:02:05Z"}'|ConvertFrom-Json
                Assert-QuietEqual (Get-QuietMonitorDuration -StartedUtc $decoded.StartedUtc -FinishedUtc $decoded.FinishedUtc) 2m5s
            }
        }finally{[Globalization.CultureInfo]::CurrentCulture=$culture}
    }
    $cases['PowerShell functions have readable help and sources parse without errors']={
        $directories=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh','scripts')
        foreach($directory in $directories){
            foreach($file in Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot $directory) -Recurse -File -Include *.ps1,*.psm1 | Where-Object FullName -NotMatch '[\\/](bin|obj|lib|artifacts|\.git)[\\/]'){
                $tokens=$null;$errors=$null
                $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
                if($errors.Count){throw ('PowerShell syntax: '+$file.Name+': '+$errors[0].Message)}
                foreach($function in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
                    $help=$function.GetHelpContent()
                    if(!$help -or [string]::IsNullOrWhiteSpace($help.Synopsis)){throw ('Unreadable function help: '+$file.Name+' / '+$function.Name)}
                }
            }
        }
    }
    $cases['security audit counterexamples are closed with independent evidence']={
        $run=Join-Path $WorkspaceRoot ('artifacts/security-regressions/'+[guid]::NewGuid().ToString('N'))
        $worker=Join-Path $PSScriptRoot 'audit/Invoke-AuditWorker.ps1'
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -WorkspaceRoot $WorkspaceRoot -RunDirectory $run
        Assert-QuietEqual $r.Outcome Success ('Audit regression failed: '+$run)
        Assert-QuietEqual $r.Data.State Success
        Assert-QuietEqual $r.Data.Failed 0
    }
    $cases['packaged modules verify and import outside source checkouts']={
        $packageRoot=Join-Path $WorkspaceRoot ('artifacts/package-tests/'+[guid]::NewGuid().ToString('N'))
        $null=& (Join-Path $WorkspaceRoot 'scripts/Update-WorkspaceLock.ps1') -WorkspaceRoot $WorkspaceRoot
        Push-Location -LiteralPath $WorkspaceRoot
        try{$null=& (Join-Path $WorkspaceRoot 'scripts/New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'packages')))}finally{Pop-Location}
        $verify=Join-Path $WorkspaceRoot 'scripts/Verify-Distribution.ps1'
        $r=quiet -AsObject -Role Infrastructure -WorkingDirectory $WorkspaceRoot -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $verify -PackageDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'packages'))) -ExtractionDirectory ([IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $packageRoot 'extracted'))) -TestImport
        Assert-QuietEqual $r.Outcome Success ('Package verifier: '+($r.Error|ConvertTo-Json -Compress))
        Assert-QuietEqual $r.Data.Verified $true
        Assert-QuietEqual $r.Data.Handlers 1
    }
    $cases['PSGallery packages install outside sources with their embedded engine and Core dependency']={
        $root=Join-Path $WorkspaceRoot ('artifacts/gallery-tests/'+[guid]::NewGuid().ToString('N'))
        $packages=Join-Path $root packages
        $prepared=& (Join-Path $WorkspaceRoot 'scripts/New-QuietGalleryPackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $packages -Version 0.1.0
        & {
            param($scripts,$packages)
            . (Join-Path $scripts Common.ps1);. (Join-Path $scripts Gallery.ps1)
            $rejected=$false
            try{$null=Test-QuietGalleryPackageSet $packages -Version 9.9.9}catch{$rejected=$_.Exception.Message -eq 'GalleryReleaseVersionMismatch'}
            if(!$rejected){throw 'Wrong release version was accepted'}
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version 0.1.0 -ValidateOnly
            $null=& (Join-Path $scripts Publish-QuietGallery.ps1) -PackageDirectory $packages -Version 0.1.0 -WhatIf
        } (Join-Path $WorkspaceRoot scripts) $packages
        $probe=Join-Path $PSScriptRoot audit/Probe-GalleryInstall.ps1
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -NoProfile -File $probe -PackageDirectory $packages -InstallationDirectory (Join-Path $root installed)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Installed $true
        Assert-QuietEqual $r.Data.CoreLoadedFromPackage $true
        Assert-QuietEqual $r.Data.GitLoadedFromPackage $true
        $galleryEvidence.Add(@{Packages=$prepared.Packages;Targets=$prepared.Targets;Installation=$r.Data;ExternalPublication=$false})
    }
    $passed=0;$failed=0;$results=[Collections.Generic.List[object]]::new()
    foreach($entry in $cases.GetEnumerator()){
        $failure=$null
        try{& $entry.Value;$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
        $results.Add([pscustomobject]@{Name=$entry.Key;State=$state;Error=$failure})
        if($OnProgress){& $OnProgress $entry.Key $state $passed $failed}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Performance=$performance.ToArray();Gallery=$galleryEvidence.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietCoreTests,Assert-QuietEqual,Invoke-QuietConformance
