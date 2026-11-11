function Invoke-QuietDotNetQualification {
    <#
    .SYNOPSIS
    Runs only selected .NET tooling assertions and retains each campaign's counts and source hashes.
    .PARAMETER WorkspaceRoot
    QuietCli source checkout.
    .PARAMETER RunDirectory
    Shared launcher's private report directory.
    .PARAMETER Suite
    Readiness, Provisioning, Layout, Locks or All.
    .PARAMETER OnProgress
    Shared monitor callback receiving name, passed and failed counts.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$Suite='All',[scriptblock]$OnProgress)
    $selected=if($Suite -eq 'All'){@('Readiness','Provisioning','Layout','Locks')}else{@($Suite)}
    $passed=0;$summaries=[Collections.Generic.List[object]]::new()
    foreach($name in $selected){
        & $OnProgress "DotNet$name offline fixtures and bounded mutations" $passed 0
        $test=Join-Path $WorkspaceRoot "FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNet$name.Tests.ps1"
        $summary=$null
        & $test -Confirm:$false | ForEach-Object {
            if($_.PSObject.Properties['Assertions']){$summary=$_}else{Write-Host $_}
        }
        if(!$summary -or $summary.State -ne 'Passed'){throw "DotNet$name did not return a passing terminal summary."}
        $passed+=$summary.Assertions
        $summaries.Add($summary)
        Write-WorkspaceJson (Join-Path $RunDirectory "dotnet-$($name.ToLowerInvariant()).json") $summary
        & $OnProgress "DotNet$name completed" $passed 0
    }
    $hashes=@{}
    foreach($file in @('scripts/lib/DotNetReadiness.psm1','scripts/lib/DotNetProvisioning.psm1','scripts/lib/DotNetLocks.psm1','scripts/ScriptShouldProcess.ps1','scripts/SourceIdentity.ps1','scripts/Update-WorkspaceLock.ps1')+@($selected|ForEach-Object {"FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNet$_.Tests.ps1"})){
        $hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $WorkspaceRoot $file) -Algorithm SHA256).Hash
    }
    $result=[pscustomobject]@{Suite='DotNet';Passed=$passed;Failed=0;Assertions=$passed;PropertyCases=($summaries|Measure-Object PropertyCases -Sum).Sum;FuzzCases=($summaries|Measure-Object FuzzCases -Sum).Sum;MutantsKilled=($summaries|Measure-Object MutantsKilled -Sum).Sum;SourceHashes=$hashes;Campaigns=$summaries.ToArray()}
    Write-WorkspaceJson (Join-Path $RunDirectory 'dotnet-summary.json') $result
    $result
}
