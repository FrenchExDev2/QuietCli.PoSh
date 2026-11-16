#requires -Version 7.6
$script:VagrantRoot = $PSScriptRoot
$script:VagrantModuleManifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh.psd1')
$script:VagrantModuleVersion = [string]$script:VagrantModuleManifest.ModuleVersion
if ($script:VagrantModuleManifest.PrivateData.PSData.ContainsKey('Prerelease') -and $script:VagrantModuleManifest.PrivateData.PSData.Prerelease) {
    $script:VagrantModuleVersion += '-' + $script:VagrantModuleManifest.PrivateData.PSData.Prerelease
}
. (Join-Path $PSScriptRoot 'src/Commands.ps1')

# Shared by both handlers below (same binary, same supported version range) -- kept in one place rather than
# literally duplicated across the two Register-QuietHandler calls (DRY).
$script:VagrantProbe = {
    param($runtime)
    $r = quiet -AsObject -Role Probe -WorkingDirectory $runtime.Request.WorkingDirectory -Environment $runtime.Request.Environment -TimeoutSeconds $runtime.Request.TimeoutSeconds `
        -Data ([Text.StringBuilder]::new()) `
        -Output { param($e, $r) if ($e.Stream -eq 'stdout') { if ($r.Data.Length + $e.Text.Length -gt 1024) { throw 'VersionProbeTooLarge' }; [void]$r.Data.Append($e.Text) } } `
        -Complete { param($r) if ($r.Data.ToString().Trim() -cnotmatch '\AVagrant (\d+\.\d+\.\d+)\z') { throw 'UnexpectedVagrantVersion' }; $Matches[1] } `
        -FilePath $runtime.Request.FilePath -ArgumentList @('--version')
    if ($r.Outcome -ne 'Success') { throw 'VagrantVersionProbeFailed' }
    $r.Data
}
$script:VagrantTestVersion = {
    param($version)
    if ($version -notmatch '^\d+\.\d+\.\d+$') { return $false }
    $numeric = $null
    if (![version]::TryParse($version, [ref]$numeric)) { return $false }
    $numeric -ge [version]'2.3.0' -and $numeric -lt [version]'2.5.0'
}

Register-QuietHandler -Id 'FrenchExDev2.QuietCli.Vagrant.PoSh.Up' -Definition @{
    Binary = 'vagrant'; ModuleVersion = $script:VagrantModuleVersion; VersionRange = 'stable >=2.3.0 <2.5.0'; Qualification = 'Partial'
    Summary = 'Observed Vagrant up (--machine-readable).'
    SupportedForms = @('up'); Documentation = @('https://developer.hashicorp.com/vagrant/docs/cli/up', 'https://developer.hashicorp.com/vagrant/docs/cli/machine-readable')
    Probe = $script:VagrantProbe
    TestVersion = $script:VagrantTestVersion
    Match = { param($request, $version) $request.ArgumentList.Count -gt 0 -and $request.ArgumentList[0] -ceq 'up' }
    Execute = { param($runtime) Invoke-QuietVagrantUp $runtime }
}
Register-QuietHandler -Id 'FrenchExDev2.QuietCli.Vagrant.PoSh.Provision' -Definition @{
    Binary = 'vagrant'; ModuleVersion = $script:VagrantModuleVersion; VersionRange = 'stable >=2.3.0 <2.5.0'; Qualification = 'Partial'
    Summary = 'Observed Vagrant provision (--machine-readable).'
    SupportedForms = @('provision'); Documentation = @('https://developer.hashicorp.com/vagrant/docs/cli/provision', 'https://developer.hashicorp.com/vagrant/docs/cli/machine-readable')
    Probe = $script:VagrantProbe
    TestVersion = $script:VagrantTestVersion
    Match = { param($request, $version) $request.ArgumentList.Count -gt 0 -and $request.ArgumentList[0] -ceq 'provision' }
    Execute = { param($runtime) Invoke-QuietVagrantProvision $runtime }
}
$ExecutionContext.SessionState.Module.OnRemove = {
    Unregister-QuietHandler -Id 'FrenchExDev2.QuietCli.Vagrant.PoSh.Up'
    Unregister-QuietHandler -Id 'FrenchExDev2.QuietCli.Vagrant.PoSh.Provision'
}
