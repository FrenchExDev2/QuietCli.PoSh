function ConvertFrom-QuietVagrantMachineReadableLine {
    <#
    .SYNOPSIS
    Parses one --machine-readable line into its timestamp/target/type/data envelope, undoing Vagrant's comma/newline escaping.
    .DESCRIPTION
    Vagrant's --machine-readable format is one event per line: timestamp,target,type,data... The 'data' part may
    itself contain escaped commas (%!(VAGRANT_COMMA)) and escaped newline/carriage-return literals (\n/\r), which
    this function undoes. Never throws on an unexpected shape (missing fields, non-numeric timestamp, a line
    truncated at a chunk boundary) -- it returns $null instead, treating a cast failure the same way as a
    missing field, since the format is documented by HashiCorp as partially stabilized.
    .PARAMETER Line
    One raw line already decoded from the native stdout stream, without its trailing newline.
    .OUTPUTS
    A [pscustomobject] with Timestamp/Machine/Type/Fields, or $null when the line could not be parsed.
    #>
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Line)
    try {
        $parts = $Line.Split(',', 4)   # timestamp,target,type,data... -- at most 4 pieces; 'data' itself may still hold escaped commas
        if ($parts.Count -lt 3) { return $null }
        if (!$parts[2]) { return $null }
        $unescape = { param($text) $text.Replace('%!(VAGRANT_COMMA)', ',').Replace('\n', "`n").Replace('\r', "`r") }
        $fields = if ($parts.Count -eq 4) { $parts[3].Split(',') | ForEach-Object { & $unescape $_ } } else { @() }
        [pscustomobject]@{
            Timestamp = [DateTimeOffset]::FromUnixTimeSeconds([long]$parts[0])
            Machine   = if ($parts[1]) { $parts[1] } else { $null }
            Type      = $parts[2]
            Fields    = @($fields)
        }
    } catch {
        return $null
    }
}

function Get-QuietVagrantProvisionerName {
    <#
    .SYNOPSIS
    Infers a provisioner name from an info event, accepting Vagrant's exact machine display prefix.
    .DESCRIPTION
    Real Vagrant 2.4.9 emits "==> web: Running provisioner: shell..." in machine-readable info data.
    A prefix is stripped only when it names the envelope's machine. Unknown channels, foreign machine
    prefixes and incomplete messages do not establish that a provisioner started.
    .PARAMETER Event
    Parsed machine-readable event.
    .OUTPUTS
    Provisioner name, or null when the event does not establish a provisioner start.
    #>
    param($Event)
    if($null -eq $Event -or $Event.Type -cne 'ui' -or $Event.Fields.Count -lt 2 -or $Event.Fields[0] -cne 'info'){return $null}
    $text=[string]$Event.Fields[1]
    $prefix="==> $($Event.Machine): "
    if($text.StartsWith($prefix,[StringComparison]::Ordinal)){$text=$text.Substring($prefix.Length)}
    if($text -cmatch '\ARunning provisioner: (?<Provisioner>.+)\.\.\.\z'){return $Matches['Provisioner']}
    return $null
}

function Get-QuietVagrantProviderLabel {
    <#
    .SYNOPSIS
    Returns a short human label for the Vagrant provider actually in effect ('docker' or 'docker via podman'),
    for the -UI header.
    .DESCRIPTION
    Heuristic only, not authoritative: looks at $env:DOCKER_HOST for a path containing 'podman' (the documented
    "sans plugin" wiring points DOCKER_HOST at podman.socket). Does not detect the community `podman` gem path --
    that one still presents itself as the ordinary docker provider to this process. Never throws; falls back to 'docker'.
    .OUTPUTS
    'docker' or 'docker via podman'.
    #>
    if ($env:DOCKER_HOST -and $env:DOCKER_HOST -match 'podman') { return 'docker via podman' }
    return 'docker'
}

function Invoke-QuietVagrantMachineReadableRun {
    <#
    .SYNOPSIS
    Shared engine behind the up/provision handlers: runs the given Vagrant subcommand with --machine-readable,
    emits one structured event per output line (for -Listeners), and drives $Runtime.Ui (for -UI) via one lane
    per machine plus a static header.
    .DESCRIPTION
    Private, not exported. $Runtime.Emit(...)/$Runtime.Ui below always refer to the OUTER runtime (the one
    created for the caller's own `quiet vagrant up`/`quiet vagrant provision`, whose Listeners/Ui come from their
    own -Listeners/-UI), never $r (the runtime of the nested `quiet ... --machine-readable` call this function
    launches internally, whose Ui is always null since -UI is never passed to it). This is what lets
    -Listeners/-UI work on a plain `quiet vagrant up -Listeners {...}` / `quiet -UI vagrant provision` without the
    caller propagating anything explicitly.
    .PARAMETER Runtime
    The outer QuietRuntime for this invocation (its Request carries the caller's own FilePath/ArgumentList/WorkingDirectory).
    .PARAMETER Command
    The business command name to report back ('up' or 'provision'); purely cosmetic, does not affect parsing.
    #>
    param($Runtime, [string]$Command)
    if ($Runtime.Ui) {
        $vagrantfile = Join-Path $Runtime.Request.WorkingDirectory 'Vagrantfile'
        $Runtime.Ui.SetHeader([string[]]@("Project: QuietCli Vagrant | Task: $Command", $Runtime.Request.WorkingDirectory, "Vagrantfile path: $vagrantfile", "Mode: $(Get-QuietVagrantProviderLabel)"))
    }
    $lines = [Collections.Generic.List[object]]::new()
    $forward=@{}
    foreach($key in @('Environment','TimeoutSeconds','DrainTimeoutSeconds','ReadBlockBytes','MaxRecordBytes','Transport','TerminalSize','InputText','InputBytes','InputPath','Interaction','CancellationFile','CancellationToken','SuccessExitCodes')) {
        if($Runtime.Request.ContainsKey($key)){$forward[$key]=$Runtime.Request[$key]}
    }
    $result = quiet @forward -AsObject -Role Business -WorkingDirectory $Runtime.Request.WorkingDirectory `
        -FilePath $Runtime.Request.FilePath -ArgumentList (@($Runtime.Request.ArgumentList) + '--machine-readable') `
        -RecordDelimiter "`n" -Data $lines `
        -Output {
            param($e, $r)
            if ($e.Stream -ne 'stdout') { return }
            $parsed = ConvertFrom-QuietVagrantMachineReadableLine $e.Text.TrimEnd("`r")
            if ($null -eq $parsed) { return }   # malformed/unrecognized line -- forward-compatible: never throw on an unknown shape
            [void]$r.Data.Add($parsed)
            $Runtime.Emit($parsed)   # outer runtime captured by closure, not $r (the nested call's own runtime)

            # Lane model: each machine gets its own lane, keyed by name. Writing to a lane never disturbs any
            # other machine's lane, so interleaved output from several machines never blends onto one line.
            if ($Runtime.Ui -and $parsed.Machine) { $Runtime.Ui.Write($parsed, $parsed.Machine) }

            $provisionerName=Get-QuietVagrantProvisionerName $parsed
            if ($null -ne $provisionerName) {
                # --no-provision handling: this branch only ever runs because Vagrant itself emitted this exact
                # line. A caller that passed --no-provision never sees it -- Vagrant simply never writes it -- so
                # there is no `if (-not $noProvision)` here: the absence of this event IS how --no-provision
                # shows up, with zero branching in this handler.
                $provisioner = [pscustomobject]@{ Kind = 'ProvisionerStarted'; Machine = $parsed.Machine; Provisioner = $provisionerName; Timestamp = $parsed.Timestamp }
                $Runtime.Emit($provisioner)
                if ($Runtime.Ui -and $parsed.Machine) { $Runtime.Ui.Write($provisioner, $parsed.Machine) }   # same lane, just overwrites that machine's displayed line
            }
        } -Complete { param($r) ,$r.Data.ToArray() }
    if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis) {
        throw "VagrantRunIncomplete: $($result.Outcome); $(($result.Error | ForEach-Object Message) -join '; ')"
    }
    [ordered]@{ Command = $Command; Lines = $result.Data.Count; Machines = @($result.Data.Machine | Where-Object { $_ } | Select-Object -Unique) }
}

function Invoke-QuietVagrantUp {
    <#
    .SYNOPSIS
    Runs `vagrant up --machine-readable` via Invoke-QuietVagrantMachineReadableRun.
    .DESCRIPTION
    Vagrant's own default behavior -- not something this handler decides or injects -- is that the FIRST `up` of
    a given machine auto-runs its provisioners unless the caller passed --no-provision. This handler forwards the
    caller's own ArgumentList verbatim (only appending --machine-readable), so `quiet vagrant up` provisions on
    first boot and `quiet vagrant up --no-provision` does not, exactly as plain `vagrant up` would -- no
    conditional logic here reproduces that choice.
    .PARAMETER Runtime
    The QuietRuntime for this invocation.
    #>
    param($Runtime)
    Invoke-QuietVagrantMachineReadableRun -Runtime $Runtime -Command 'up'
}

function Invoke-QuietVagrantProvision {
    <#
    .SYNOPSIS
    Runs `vagrant provision --machine-readable` via Invoke-QuietVagrantMachineReadableRun.
    .DESCRIPTION
    Unlike `up`, `vagrant provision` always re-runs provisioners on already-running machines and has no
    --no-provision equivalent of its own -- that flag only affects `up`'s automatic first-boot provisioning. The
    caller's ArgumentList (e.g. `provision --provision-with shell`) is forwarded verbatim; this handler only
    observes and reports what Vagrant itself decides to run, it never filters provisioners on its own.
    .PARAMETER Runtime
    The QuietRuntime for this invocation.
    #>
    param($Runtime)
    Invoke-QuietVagrantMachineReadableRun -Runtime $Runtime -Command 'provision'
}
