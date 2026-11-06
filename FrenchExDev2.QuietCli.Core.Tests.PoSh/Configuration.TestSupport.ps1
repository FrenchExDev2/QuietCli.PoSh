function global:Get-QuietTestConfiguration {
    <#
    .SYNOPSIS
    Exposes the test subject's internal snapshot to companion assertions and fault injection.
    #>
    $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    if(!$core){throw 'TestCoreNotImported'}
    return & $core {Get-QuietConfigurationSnapshot}
}
