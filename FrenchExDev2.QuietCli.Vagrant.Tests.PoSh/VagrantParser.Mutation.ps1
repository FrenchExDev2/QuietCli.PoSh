function Invoke-QuietVagrantParserMutation {
    <#
    .SYNOPSIS
    Targeted mutation campaign for the Vagrant --machine-readable parser/engine (Commands.ps1).
    .DESCRIPTION
    Pure PowerShell source, so no build step is needed: for each mutant, the real source text is copied to an
    isolated per-mutant file under RunDirectory with exactly one source-checked substitution applied, then
    dot-sourced inside its own child scope (`& { . $path; ... }`). A function defined this way lives only in
    that child scope and the scopes nested under it -- it is never added to this module's own scope, so the
    real, unmutated Commands.ps1 functions this module dot-sourced at import time are never replaced. The
    working copy on disk at FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1 is only ever read, never written.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root; source of the original Commands.ps1 and the shared native fixture.
    .PARAMETER RunDirectory
    Disposable root for the per-mutant isolated copies.
    .OUTPUTS
    [pscustomobject] with Passed/Failed counts and a Cases array of {Name;Outcome;Error}; Outcome is one of
    Killed, Survived or InfrastructureFailure.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot, [Parameter(Mandatory)][string]$RunDirectory)
    $source = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1'
    $original = [IO.File]::ReadAllText($source)
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $mutants = @(
        @{Name = 'unescape-comma-removed'; File = 'Commands.ps1'; From = ".Replace('%!(VAGRANT_COMMA)', ',')"; To = '' },
        @{Name = 'escaped-newline-not-restored'; File = 'Commands.ps1'; From = '.Replace(''\n'', "`n")'; To = '' },
        @{Name = 'malformed-short-line-returned-as-event'; File = 'Commands.ps1'; From = 'if ($parts.Count -lt 3) { return $null }'; To = 'if ($parts.Count -lt 3) { return [pscustomobject]@{ Timestamp=$null; Machine=$null; Type="invalid"; Fields=@() } }' },
        @{Name = 'provisioner-trigger-anchor-broken'; File = 'Commands.ps1'; From = "'\ARunning provisioner: (?<Provisioner>.+)\.\.\.\z'"; To = "'^Running provisioner NEVER: (?<Provisioner>.+)\.\.\.$'" },
        @{Name = 'real-machine-prefix-not-stripped'; File = 'Commands.ps1'; From = '$text=$text.Substring($prefix.Length)'; To = '$text=$text' },
        @{Name = 'provisioner-detail-channel-accepted'; File = 'Commands.ps1'; From = "`$Event.Fields[0] -cne 'info'"; To = '$false' },
        @{Name = 'ui-write-lane-key-wrong'; File = 'Commands.ps1'; From = '$Runtime.Ui.Write($parsed, $parsed.Machine)'; To = "`$Runtime.Ui.Write(`$parsed, 'all')" }
    )
    $results = [Collections.Generic.List[object]]::new(); $passed = 0; $failed = 0
    foreach ($mutant in $mutants) {
        $outcome = 'InfrastructureFailure'; $detail = $null
        try {
            if (([regex]::Matches($original, [regex]::Escape($mutant.From))).Count -ne 1) { throw "VagrantParserMutationAnchorInvalid: $($mutant.Name)" }
            $mutated = $original.Replace($mutant.From, $mutant.To)
            $destination = Join-Path $RunDirectory ('mutation/' + $mutant.Name)
            [void][IO.Directory]::CreateDirectory($destination)
            $path = Join-Path $destination 'Commands.mutant.ps1'
            [void][IO.File]::WriteAllTextAsync($path, $mutated, [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $killed = & {
                . $path
                switch ($mutant.Name) {
                    'unescape-comma-removed' {
                        (ConvertFrom-QuietVagrantMachineReadableLine '1700000003,web,ui,detail,a%!(VAGRANT_COMMA)b').Fields[1] -cne 'a,b'
                    }
                    'escaped-newline-not-restored' {
                        (ConvertFrom-QuietVagrantMachineReadableLine '1700000003,web,ui,detail,a\nb').Fields[1] -cne "a`nb"
                    }
                    'malformed-short-line-returned-as-event' {
                        ($null -ne (ConvertFrom-QuietVagrantMachineReadableLine '1700000004,web')) -or ($null -ne (ConvertFrom-QuietVagrantMachineReadableLine '1700000004'))
                    }
                    'provisioner-trigger-anchor-broken' {
                        $runtime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '99', '1700000012,web,ui,info,Running provisioner: shell...') -WorkingDirectory $destination
                        $null = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime -Command 'up'
                        (@($runtime.Events | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProvisionerStarted' })).Count -ne 1
                    }
                    'real-machine-prefix-not-stripped' {
                        (Get-QuietVagrantProvisionerName ([pscustomobject]@{Machine='web';Type='ui';Fields=@('info','==> web: Running provisioner: shell...')})) -cne 'shell'
                    }
                    'provisioner-detail-channel-accepted' {
                        $null -ne (Get-QuietVagrantProvisionerName ([pscustomobject]@{Machine='web';Type='ui';Fields=@('detail','Running provisioner: shell...')}))
                    }
                    'ui-write-lane-key-wrong' {
                        $ui = New-QuietVagrantRecordingUi
                        $runtime = New-QuietVagrantFakeRuntime -FilePath $dotnet -Arguments @($fixture, 'chunks', '98', '1700000012,web,ui,detail,hi') -WorkingDirectory $destination -Ui $ui
                        $null = Invoke-QuietVagrantMachineReadableRun -Runtime $runtime -Command 'up'
                        $ui.Calls[0].Key -cne 'web'
                    }
                }
            }
            $outcome = if ($killed) { 'Killed' } else { 'Survived' }
        } catch { $detail = $_.ToString(); $outcome = 'InfrastructureFailure' }
        if ($outcome -eq 'Killed') { $passed++ } else { $failed++ }
        $results.Add([pscustomobject]@{ Name = $mutant.Name; Outcome = $outcome; Error = $detail })
    }
    [pscustomobject]@{ Passed = $passed; Failed = $failed; Cases = $results.ToArray() }
}
