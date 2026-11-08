#requires -Version 7.6
<#
.SYNOPSIS
Leveled logging with named counters for the run-profile tooling.

.DESCRIPTION
Separates the event model (RunLogger), the destinations (RunLogSink strategies) and the factory (New-RunLogger).
Every emitted event increments a per-level counter even when the level filter suppresses it, so counters describe
what the code did independently of how verbose the run was.
#>

Import-Module (Join-Path $PSScriptRoot 'RunEncoding.psm1')

enum RunLogLevel { Trace = 0; Debug = 1; Info = 2; Warn = 3; Error = 4; Off = 5 }

# Destination of formatted log lines. Subclasses implement Write.
class RunLogSink {
    # Writes one formatted line.
    [void] Write([string]$Line) { throw [NotImplementedException]::new('RunLogSink.Write') }
}

# Writes lines to standard error so that standard output stays reserved for results.
class ConsoleLogSink : RunLogSink {
    [void] Write([string]$Line) { [Console]::Error.WriteLine($Line) }
}

# Appends UTF-8 lines with LF endings to a file.
class FileLogSink : RunLogSink {
    [string]$Path
    FileLogSink([string]$path) {
        $this.Path = [IO.Path]::GetFullPath($path)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($this.Path))
    }
    [void] Write([string]$Line) {
        Add-RunTextLine -Path $this.Path -Line $Line
    }
}

# Keeps lines in memory; used by tests to assert on emitted events.
class MemoryLogSink : RunLogSink {
    [Collections.Generic.List[string]]$Lines = [Collections.Generic.List[string]]::new()
    [void] Write([string]$Line) { $this.Lines.Add($Line) }
}

# Leveled logger with named counters. Children share sinks and counters with their parent.
class RunLogger {
    [RunLogLevel]$Level
    [string]$Component
    [Collections.Generic.List[RunLogSink]]$Sinks
    [Collections.Generic.Dictionary[string, long]]$Counters

    RunLogger([RunLogLevel]$level, [string]$component, [Collections.Generic.List[RunLogSink]]$sinks, [Collections.Generic.Dictionary[string, long]]$counters) {
        $this.Level = $level
        $this.Component = $component
        $this.Sinks = $sinks
        $this.Counters = $counters
    }

    # Creates a logger for a sub-component that shares sinks and counters.
    [RunLogger] Child([string]$component) {
        return [RunLogger]::new($this.Level, ($this.Component + '.' + $component), $this.Sinks, $this.Counters)
    }

    # Adds an amount to a named counter, creating it when missing.
    [void] Add([string]$name, [long]$amount) {
        [long]$current = 0
        [void]$this.Counters.TryGetValue($name, [ref]$current)
        $this.Counters[$name] = $current + $amount
    }

    # Increments a named counter by one.
    [void] Increment([string]$name) { $this.Add($name, 1) }

    # Returns the value of a counter, or zero when it was never touched.
    [long] Get([string]$name) {
        [long]$current = 0
        [void]$this.Counters.TryGetValue($name, [ref]$current)
        return $current
    }

    # Emits one event: counts it, then formats and dispatches it when the level passes the filter.
    [void] Write([RunLogLevel]$level, [string]$message) {
        $this.Add('log.' + $level.ToString().ToLowerInvariant(), 1)
        if ($level -lt $this.Level) { $this.Add('log.suppressed', 1); return }
        $stamp = [DateTime]::Now.ToString('HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
        $line = '{0} [{1}] {2}: {3}' -f $stamp, $level.ToString().ToUpperInvariant().PadRight(5), $this.Component, $message
        foreach ($sink in $this.Sinks) {
            try { $sink.Write($line) } catch { $this.Add('log.sinkfailed', 1) }
        }
    }

    [void] Trace([string]$message) { $this.Write([RunLogLevel]::Trace, $message) }
    [void] Debug([string]$message) { $this.Write([RunLogLevel]::Debug, $message) }
    [void] Info([string]$message) { $this.Write([RunLogLevel]::Info, $message) }
    [void] Warn([string]$message) { $this.Write([RunLogLevel]::Warn, $message) }
    [void] Error([string]$message) { $this.Write([RunLogLevel]::Error, $message) }

    # Runs a script block while counting calls (name.count), failures (name.failed), successes (name.ok) and elapsed milliseconds (name.ms).
    [object] Time([string]$name, [scriptblock]$body) {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
            $result = & $body
            $this.Add($name + '.ok', 1)
            return $result
        }
        catch {
            $this.Add($name + '.failed', 1)
            throw
        }
        finally {
            $this.Add($name + '.count', 1)
            $this.Add($name + '.ms', [long]$clock.ElapsedMilliseconds)
        }
    }

    # Returns an ordinal-sorted copy of all counters.
    [Collections.Specialized.OrderedDictionary] Snapshot() {
        $copy = [Collections.Specialized.OrderedDictionary]::new()
        foreach ($key in ($this.Counters.Keys | Sort-Object -CaseSensitive)) { $copy[$key] = $this.Counters[$key] }
        return $copy
    }
}

function New-RunLogger {
    <#
    .SYNOPSIS
    Creates a logger with a console sink and an optional file sink.
    .PARAMETER Level
    Minimum level written to the sinks.
    .PARAMETER Component
    Name shown on every line.
    .PARAMETER LogPath
    Optional file receiving every written line.
    .PARAMETER NoConsole
    Disables the standard-error sink.
    .PARAMETER ExtraSinks
    Additional sinks, for example a MemoryLogSink in tests.
    #>
    [CmdletBinding()]
    param(
        [RunLogLevel]$Level = [RunLogLevel]::Info,
        [string]$Component = 'run',
        [string]$LogPath,
        [switch]$NoConsole,
        [RunLogSink[]]$ExtraSinks = @()
    )
    $sinks = [Collections.Generic.List[RunLogSink]]::new()
    if (-not $NoConsole) { $sinks.Add([ConsoleLogSink]::new()) }
    if ($LogPath) { $sinks.Add([FileLogSink]::new($LogPath)) }
    foreach ($sink in $ExtraSinks) { $sinks.Add($sink) }
    return [RunLogger]::new($Level, $Component, $sinks, [Collections.Generic.Dictionary[string, long]]::new([StringComparer]::Ordinal))
}

Export-ModuleMember -Function New-RunLogger
