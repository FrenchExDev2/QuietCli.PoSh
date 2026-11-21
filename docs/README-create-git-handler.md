# Create a QuietCli Git handler

This example takes one form from the [Git companion](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psm1), `git version`. The production handler also handles build information. The example returns only the version and registers under its own identity, so it can coexist with the installed companion.

## Register one form and verify its result

In PowerShell with QuietCli Core and Git installed, run the block below in one session. It reads the installed Git version. The supported stable version range is the same as the existing Git companion.

<!-- git-example:version -->
```powershell
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop

$readVersion = {
    param($parent, $role, $form)
    $child = quiet -AsObject -Role $role -WorkingDirectory $parent.Request.WorkingDirectory `
        -Environment $parent.Request.Environment -TimeoutSeconds $parent.Request.TimeoutSeconds `
        -FilePath $parent.Request.FilePath -ArgumentList @($form) `
        -RecordDelimiter "`n" -MaxRecordBytes 1024 -Data @{ Version = $null } -StdOut {
            param($event, $runtime)
            if ($null -ne $runtime.Data.Version -or $event.Text.TrimEnd("`r") -cnotmatch '^git version (\S+)$') {
                throw 'Unexpected Git version record'
            }
            $runtime.Data.Version = $Matches[1]
        }
    if ($child.Outcome -ne 'Success' -or !$child.Completeness.Source -or
        !$child.Completeness.Analysis -or $child.Error.Count -or !$child.Data.Version) {
        throw 'Git version observation failed'
    }
    $child.Data.Version
}

$id = 'Example.Git.Version'
Register-QuietHandler -Id $id -Definition @{
    Binary = 'git'
    VersionRange = 'stable >=2.40.0 <2.57.0, including .windows.N'
    SupportedForms = @('version')
    Qualification = 'Example'
    Documentation = @('https://git-scm.com/docs/git-version')
    Probe = {
        param($runtime)
        & $readVersion $runtime Probe '--version'
    }.GetNewClosure()
    TestVersion = {
        param($version)
        if ($version -cnotmatch '^([0-9]+\.[0-9]+\.[0-9]+)(?:\.windows\.[0-9]+)?$') { return $false }
        $number = [version]$Matches[1]
        $number -ge [version]'2.40.0' -and $number -lt [version]'2.57.0'
    }
    Match = {
        param($request, $version)
        $request.ArgumentList.Count -eq 1 -and $request.ArgumentList[0] -ceq 'version'
    }
    Execute = {
        param($runtime)
        [ordered]@{ Command = 'version'; Version = (& $readVersion $runtime Business 'version') }
    }.GetNewClosure()
}

try {
    $result = quiet -AsObject -HandlerId $id -FilePath git -ArgumentList @('version')
    if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
        !$result.Completeness.Analysis -or $result.Error.Count) {
        throw 'The registered handler failed'
    }

    $control = quiet -AsObject -FilePath git -ArgumentList @('--version') `
        -RecordDelimiter "`n" -MaxRecordBytes 1024 -Data @{ Line = $null } -StdOut {
            param($event, $runtime)
            $runtime.Data.Line = $event.Text.Trim()
        }
    if ($control.Outcome -ne 'Success' -or !$control.Completeness.Source -or
        !$control.Completeness.Analysis -or $control.Error.Count -or
        $result.Data.Command -cne 'version' -or ('git version ' + $result.Data.Version) -cne $control.Data.Line) {
        throw 'The handler result disagrees with Git'
    }
    $result.Data
} finally {
    Unregister-QuietHandler -Id $id
}
```

`Probe` returns one version value and the registry caches it for this handler and executable context. `TestVersion` and `Match` each return one Boolean. `Execute` makes one business call and returns one object. The explicit stdout callback tells the nested call how to read the output, so the nested call uses direct analysis. `-HandlerId` selects the example explicitly when the Git companion is already loaded.

The assertion reads `git --version` with a separate callback and compares its literal record to the projected version. The command metadata and example result are independent of the registered handler's parser. See the [runtime registry](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/Cmdlets/HandlerCommands.cs) and [Git version projection](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/src/Queries.ps1).

## Show live updates using the Vagrant pattern

The [Vagrant handler](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1#L89) parses each machine-readable stdout line in a nested call. It sends events and renders UI through the **parent** runtime, which owns the caller's listeners and dashboard. This is the event and UI portion of its output callback.

```powershell
param($event, $childRuntime)
if ($event.Stream -ne 'stdout') { return }
$parsed = ConvertFrom-QuietVagrantMachineReadableLine $event.Text.TrimEnd("`r")
if ($null -eq $parsed) { return }

$Runtime.Emit($parsed.Type, $parsed)
if ($Runtime.Ui -and $parsed.Machine) {
    $Runtime.Ui.Write($parsed, $parsed.Machine)
}
```

Set a static header once with `$Runtime.Ui.SetHeader([string[]]$header)` when the dashboard exists. Use a stable lane key such as `Machine` to keep simultaneous updates separate. `Emit` supplies structured listener data. `Ui.Write` selects what the dashboard displays. Callers can use either independently and opt into event retention with `-CollectEvents`. [Try the Vagrant UI and listener examples](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/README.md#event-contract).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
