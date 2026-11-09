function New-QuietVagrantRecordingUi {
    <#
    .SYNOPSIS
    Lightweight PowerShell test double for the `$Runtime.Ui` surface Invoke-QuietVagrantMachineReadableRun
    calls (`SetHeader`/`Write`). Records calls instead of rendering, so a case can assert exactly what the
    Vagrant module handed its Ui without constructing a real QuietUiRenderer/Spectre.Console surface.
    .DESCRIPTION
    The deeper lane-formatting/scrolling/dedup behavior of the real renderer is independently covered by
    engine-tests/UiRendererCases.cs (section 8) against the real QuietUiRenderer and a C# RecordingSurface --
    this double only checks that the Vagrant module's own integration calls SetHeader/Write with the right
    shape and arguments, so the two suites cover different layers rather than duplicating one another.
    #>
    $ui = [pscustomobject]@{ Headers = [Collections.Generic.List[string[]]]::new(); Calls = [Collections.Generic.List[object]]::new() }
    Add-Member -InputObject $ui -MemberType ScriptMethod -Name SetHeader -Value { param($lines) $this.Headers.Add(@($lines)) }
    Add-Member -InputObject $ui -MemberType ScriptMethod -Name Write -Value { param($evt, $key) $this.Calls.Add([pscustomobject]@{ Event = $evt; Key = $key }) }
    $ui
}

function New-QuietVagrantFakeRuntime {
    <#
    .SYNOPSIS
    Minimal stand-in for the real QuietRuntime passed to Invoke-QuietVagrantMachineReadableRun, enough to drive
    it directly without a real `vagrant` binary or the handler registry (both tested generically elsewhere --
    see this suite's own comments on scope).
    .PARAMETER FilePath
    Native executable this fake "vagrant" run actually launches (the dotnet host, running the shared fixture).
    .PARAMETER Arguments
    Argument vector up to but excluding `--machine-readable`, which Invoke-QuietVagrantMachineReadableRun always appends itself.
    .PARAMETER WorkingDirectory
    Working directory for the nested `quiet` call.
    .PARAMETER Ui
    Optional recording double (see New-QuietVagrantRecordingUi); omit for $null (no -UI).
    #>
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory, $Ui)
    $runtime = [pscustomobject]@{
        Request = @{ FilePath = $FilePath; ArgumentList = $Arguments; WorkingDirectory = $WorkingDirectory }
        Ui      = $Ui
        Events  = [Collections.Generic.List[object]]::new()
    }
    Add-Member -InputObject $runtime -MemberType ScriptMethod -Name Emit -Value { param($evt) $this.Events.Add($evt) }
    $runtime
}

function ConvertFrom-QuietVagrantOracleLine {
    <#
    .SYNOPSIS
    Independent reference parser for one --machine-readable line, used ONLY by this test file's oracle --
    deliberately written as a single regex plus its own unescape chain, rather than calling (or copying the
    structure of) ConvertFrom-QuietVagrantMachineReadableLine, so a passing case can never be a mere
    restatement of the implementation it is meant to check.
    .PARAMETER Line
    Raw line, without its trailing newline.
    .OUTPUTS
    A [pscustomobject] with Timestamp/Machine/Type/Fields, or $null when the shape does not match.
    #>
    param([string]$Line)
    if ($Line -notmatch '^(?<ts>[0-9]+),(?<machine>[^,]*),(?<type>[^,]*)(,(?<data>.*))?$') { return $null }
    try {
        $fields = if ($Matches.ContainsKey('data')) {
            @($Matches['data'] -split ',' | ForEach-Object { $_.Replace('%!(VAGRANT_COMMA)', ',').Replace('\n', "`n").Replace('\r', "`r") })
        } else { @() }
        [pscustomobject]@{
            Timestamp = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches['ts'])
            Machine   = if ($Matches['machine']) { $Matches['machine'] } else { $null }
            Type      = $Matches['type']
            Fields    = $fields
        }
    } catch { $null }
}

function Assert-QuietVagrantEventEqual {
    <#
    .SYNOPSIS
    Compares a parsed event against the independent oracle's expectation, field by field.
    #>
    param($Actual, $Expected, [string]$Because = 'Parsed Vagrant event must match the independent oracle')
    if ($null -eq $Expected) { Assert-QuietEqual $Actual $null $Because; return }
    Assert-QuietEqual $Actual.Timestamp.ToUnixTimeSeconds() $Expected.Timestamp.ToUnixTimeSeconds() ($Because + ' (Timestamp)')
    Assert-QuietEqual $Actual.Machine $Expected.Machine ($Because + ' (Machine)')
    Assert-QuietEqual $Actual.Type $Expected.Type ($Because + ' (Type)')
    Assert-QuietEqual (@($Actual.Fields) -join "`u{1}") (@($Expected.Fields) -join "`u{1}") ($Because + ' (Fields)')
}

function Get-QuietVagrantLineCases {
    <#
    .SYNOPSIS
    Deterministic cases for the Vagrant --machine-readable line parser and the shared up/provision engine.
    .PARAMETER RootDirectory
    Disposable fixture root; used as -WorkingDirectory for every nested run below.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root. Used to dot-source the Vagrant module's own business functions directly:
    FrenchExDev2.QuietCli.Vagrant.PoSh.psd1's FunctionsToExport is deliberately empty (these are internal
    handler implementations, only ever invoked through the handler registry), so a white-box unit test
    dot-sources the exact same source file the module itself loads at import time, rather than reimplementing
    or exporting anything new just to make it reachable.
    #>
    param([string]$RootDirectory, [string]$WorkspaceRoot)
    . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1')
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $cases = [ordered]@{}

    $cases['ConvertFrom-QuietVagrantMachineReadableLine matches the independent oracle on interleaved web/db lines'] = {
        $lines = @(
            "1699999999,web,ui,info,Bringing machine 'web' up...",
            '1699999999,db,ui,detail,some output',
            '1700000000,web,ui,detail,more web output',
            '1700000001,db,ui,detail,more db output'
        )
        foreach ($line in $lines) {
            $actual = ConvertFrom-QuietVagrantMachineReadableLine $line
            $expected = ConvertFrom-QuietVagrantOracleLine $line
            Assert-QuietVagrantEventEqual $actual $expected ('Line: ' + $line)
        }
        Assert-QuietEqual (ConvertFrom-QuietVagrantMachineReadableLine $lines[0]).Machine 'web'
        Assert-QuietEqual (ConvertFrom-QuietVagrantMachineReadableLine $lines[1]).Machine 'db'
    }

    $cases['a ui/info Running provisioner line is recognized as the ProvisionerStarted trigger shape'] = {
        $line = '1700000002,web,ui,info,Running provisioner: shell...'
        $parsed = ConvertFrom-QuietVagrantMachineReadableLine $line
        $oracle = ConvertFrom-QuietVagrantOracleLine $line
        Assert-QuietVagrantEventEqual $parsed $oracle
        Assert-QuietEqual $parsed.Type 'ui'
        Assert-QuietEqual $parsed.Fields[0] 'info'
        if ($parsed.Fields[1] -notmatch '^Running provisioner: (?<Provisioner>.+)\.\.\.$') { throw 'Expected trigger regex to match the oracle-parsed field' }
        Assert-QuietEqual $Matches['Provisioner'] 'shell'
    }

    $cases['real provisioner prefixes preserve exact machine identity across generated names and malformed messages'] = {
        $random=[Random]::new(20261109)
        foreach($index in 1..100){
            $machine=@('web','db','été漢🙂','machine.[x]+')[$index % 4]+$random.Next(10000)
            $name='shell-'+$random.Next(10000)
            foreach($text in @("Running provisioner: $name...","==> ${machine}: Running provisioner: $name...")){
                $event=[pscustomobject]@{Machine=$machine;Type='ui';Fields=@('info',$text)}
                Assert-QuietEqual (Get-QuietVagrantProvisionerName $event) $name "seed=20261109 index=$index"
            }
            foreach($text in @("==> foreign: Running provisioner: $name...","Running provisioner: $name..","prefix Running provisioner: $name...","Running provisioner: $name...suffix")){
                $event=[pscustomobject]@{Machine=$machine;Type='ui';Fields=@('info',$text)}
                Assert-QuietEqual (Get-QuietVagrantProvisionerName $event) $null "seed=20261109 malformed=$text"
            }
            foreach($channel in @(@('ui','detail'),@('metadata','info'))){
                $event=[pscustomobject]@{Machine=$machine;Type=$channel[0];Fields=@($channel[1],"Running provisioner: $name...")}
                Assert-QuietEqual (Get-QuietVagrantProvisionerName $event) $null "seed=20261109 channel=$channel"
            }
        }
    }

    $cases['an escaped comma in Vagrant data is correctly un-escaped'] = {
        $line = '1700000003,web,ui,detail,a%!(VAGRANT_COMMA)b'
        $actual = ConvertFrom-QuietVagrantMachineReadableLine $line
        $expected = ConvertFrom-QuietVagrantOracleLine $line
        Assert-QuietVagrantEventEqual $actual $expected
        Assert-QuietEqual $actual.Fields[1] 'a,b'
    }

    $cases['a malformed or truncated line is dropped without throwing'] = {
        foreach ($line in @('', 'nope', '1700000004', '1700000004,web', '1700000004,web,', '9999999999999999999999,web,ui,hello', 'not-time,web,ui,hello')) {
            $result = $null
            $threw = $false
            try { $result = ConvertFrom-QuietVagrantMachineReadableLine $line } catch { $threw = $true }
            Assert-QuietEqual $threw $false ('Must never throw on: ' + $line)
            Assert-QuietEqual $result $null ('Must return $null on: ' + $line)
        }
    }

    $cases['Get-QuietVagrantProviderLabel reports docker by default and docker via podman when DOCKER_HOST points at a podman socket'] = {
        $saved = $env:DOCKER_HOST
        try {
            $env:DOCKER_HOST = $null
            Assert-QuietEqual (Get-QuietVagrantProviderLabel) 'docker'
            $env:DOCKER_HOST = 'unix:///run/user/1000/podman/podman.sock'
            Assert-QuietEqual (Get-QuietVagrantProviderLabel) 'docker via podman'
            $env:DOCKER_HOST = 'tcp://127.0.0.1:2375'
            Assert-QuietEqual (Get-QuietVagrantProviderLabel) 'docker'
        } finally { $env:DOCKER_HOST = $saved }
    }

    $cases['Invoke-QuietVagrantMachineReadableRun emits one event per valid line, skips malformed ones, and sets the Ui header/lanes'] = {
        $savedDockerHost = $env:DOCKER_HOST
        $env:DOCKER_HOST = $null   # pin the provider label this case asserts on ('Mode: docker'), independent of the host's own environment
        try {
        $transcript = @(
            "1700000010,web,ui,info,Bringing machine 'web' up...",
            'this line is malformed and must be silently dropped',
            '1700000011,db,ui,detail,some output',
            '1700000012,web,ui,info,==> web: Running provisioner: shell...'
        ) -join "`n"
        $ui = New-QuietVagrantRecordingUi
        $runtime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '1', $transcript) -WorkingDirectory $RootDirectory -Ui $ui
        $report = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime -Command 'up'
        Assert-QuietEqual $report.Command 'up'
        Assert-QuietEqual $report.Lines 3
        Assert-QuietEqual (($report.Machines | Sort-Object) -join ',') 'db,web'
        # 3 valid lines + 1 synthetic ProvisionerStarted
        Assert-QuietEqual $runtime.Events.Count 4
        $provisioner = @($runtime.Events | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProvisionerStarted' })
        Assert-QuietEqual $provisioner.Count 1
        Assert-QuietEqual $provisioner[0].Machine 'web'
        Assert-QuietEqual $provisioner[0].Provisioner 'shell'
        Assert-QuietEqual $ui.Headers.Count 1
        Assert-QuietEqual $ui.Headers[0][3] 'Mode: docker'
        # one Write per machine-tagged event (3 generic + 1 provisioner), all with the lane keyed by machine
        Assert-QuietEqual $ui.Calls.Count 4
        Assert-QuietEqual (($ui.Calls | Select-Object -ExpandProperty Key | Sort-Object -Unique) -join ',') 'db,web'
        } finally { $env:DOCKER_HOST = $savedDockerHost }
    }

    $cases['Invoke-QuietVagrantUp and Invoke-QuietVagrantProvision produce the same events/lanes from the same transcript'] = {
        $transcript = @(
            '1700000020,web,ui,detail,already running',
            '1700000021,db,ui,detail,already running'
        ) -join "`n"
        $upUi = New-QuietVagrantRecordingUi
        $upRuntime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '2', $transcript) -WorkingDirectory $RootDirectory -Ui $upUi
        $upReport = Invoke-QuietVagrantUp $upRuntime

        $provisionUi = New-QuietVagrantRecordingUi
        $provisionRuntime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '2', $transcript) -WorkingDirectory $RootDirectory -Ui $provisionUi
        $provisionReport = Invoke-QuietVagrantProvision $provisionRuntime

        Assert-QuietEqual $upReport.Lines $provisionReport.Lines
        Assert-QuietEqual $upRuntime.Events.Count $provisionRuntime.Events.Count
        Assert-QuietEqual $upUi.Calls.Count $provisionUi.Calls.Count
        Assert-QuietEqual $upReport.Command 'up'
        Assert-QuietEqual $provisionReport.Command 'provision'
    }

    $cases['--no-provision is purely the absence of the trigger line: zero ProvisionerStarted events, no special-casing'] = {
        $machines = @('machine-00', 'machine-01', 'machine-02', 'machine-03')
        $withoutProvisioning = ($machines | ForEach-Object { "170000003{0},{1},ui,detail,machine '{1}' already up" -f ([array]::IndexOf($machines, $_)), $_ }) -join "`n"
        $ui1 = New-QuietVagrantRecordingUi
        $runtime1 = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '3', $withoutProvisioning) -WorkingDirectory $RootDirectory -Ui $ui1
        $report1 = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime1 -Command 'up'
        Assert-QuietEqual $report1.Lines 4
        Assert-QuietEqual (@($runtime1.Events | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProvisionerStarted' })).Count 0

        $withProvisioning = ($machines | ForEach-Object { "170000004{0},{1},ui,info,Running provisioner: shell..." -f ([array]::IndexOf($machines, $_)), $_ }) -join "`n"
        $ui2 = New-QuietVagrantRecordingUi
        $runtime2 = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '4', $withProvisioning) -WorkingDirectory $RootDirectory -Ui $ui2
        $report2 = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime2 -Command 'up'
        $started = @($runtime2.Events | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProvisionerStarted' })
        Assert-QuietEqual $started.Count 4
        Assert-QuietEqual (($started | Select-Object -ExpandProperty Machine | Sort-Object) -join ',') (($machines | Sort-Object) -join ',')
        # Same function, same code path, zero branching on --no-provision: the only difference between the two
        # runs above is which lines Vagrant itself would have written -- nothing in Invoke-QuietVagrantMachineReadableRun
        # inspects an ArgumentList flag to decide whether to emit ProvisionerStarted.
    }

    $cases['a silent machine keeps its last-written lane entry while another machine keeps advancing'] = {
        $transcript = @(
            '1700000050,machine-00,ui,detail,boot',
            '1700000051,machine-01,ui,detail,boot',
            '1700000052,machine-01,ui,detail,still booting',
            '1700000053,machine-01,ui,detail,ready'
        ) -join "`n"
        $ui = New-QuietVagrantRecordingUi
        $runtime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '5', $transcript) -WorkingDirectory $RootDirectory -Ui $ui
        $null = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime -Command 'up'
        $machine00Calls = @($ui.Calls | Where-Object Key -CEQ 'machine-00')
        $machine01Calls = @($ui.Calls | Where-Object Key -CEQ 'machine-01')
        Assert-QuietEqual $machine00Calls.Count 1 'machine-00 only ever wrote once -- its lane must keep exactly that one entry'
        Assert-QuietEqual $machine01Calls.Count 3
        Assert-QuietEqual $machine00Calls[0].Event.Fields[1] 'boot'
    }

    $cases['registered Vagrant handlers deliver live events through the outer native pipeline and preserve failure visibility'] = {
        $seen=[Collections.Generic.List[object]]::new()
        foreach($command in @('up','provision')){
            $id='fixture-vagrant-'+$command
            $original=[FrenchExDev2.QuietCli.Cmdlets.HandlerRegistry]::Handlers[('FrenchExDev2.QuietCli.Vagrant.PoSh.'+$(if($command -eq 'up'){'Up'}else{'Provision'}))]
            foreach($version in @('2.3.0','2.4.9')){Assert-QuietEqual (& $original.TestVersion $version) $true}
            foreach($version in @('2.2.9','2.5.0','2.4.9-rc1','garbage')){Assert-QuietEqual (& $original.TestVersion $version) $false}
            Assert-QuietEqual (& $original.Match @{ArgumentList=@($command)} '2.4.9') $true
            Assert-QuietEqual (& $original.Match @{ArgumentList=@('status')} '2.4.9') $false
            $definition=$original.Clone();$definition.Binary=[IO.Path]::GetFileNameWithoutExtension($dotnet)
            $definition.Probe={'2.4.9'};$definition.Match={param($request,$version)$true}
            Register-QuietHandler -Id $id -Definition $definition
            try{
                $seen.Clear()
                $transcript="1700000010,web,ui,info,Running provisioner: shell...`n1700000011,db,ui,detail,été漢🙂"
                $result=quiet -AsObject -Ui -HandlerId $id -WorkingDirectory $RootDirectory -Listeners @(
                    {param($event,$runtime)[void]$seen.Add($event)},
                    {param($event,$runtime)throw 'ObserverFixtureFailure'}
                ) -FilePath $dotnet -ArgumentList @($fixture,'chunks','20261108',$transcript)
                Assert-QuietEqual $result.Outcome 'Success'
                Assert-QuietEqual $result.Completeness.Analysis $true
                Assert-QuietEqual $seen.Count 3
                Assert-QuietEqual $result.Events.Count 3
                Assert-QuietEqual $result.Error.Count 1
                Assert-QuietEqual $result.Error[0].Code 'ListenerFailed'
                Assert-QuietEqual $result.Data.Command $command
                Assert-QuietEqual $result.Data.Lines 2
                $failed=quiet -AsObject -HandlerId $id -WorkingDirectory $RootDirectory -FilePath $dotnet -ArgumentList @($fixture,'fail')
                if($failed.Outcome -eq 'Success' -or $failed.Completeness.Analysis){throw 'VagrantChildFailureHidden'}
            }finally{Unregister-QuietHandler $id}
        }
    }

    $cases
}
