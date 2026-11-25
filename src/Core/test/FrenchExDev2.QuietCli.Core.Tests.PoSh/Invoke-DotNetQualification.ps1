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
    Shared monitor callback receiving the case name, state, passed and failed test counts.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$Suite='All',[scriptblock]$OnProgress)
    $selected=if($Suite -eq 'All'){@('Readiness','Provisioning','Layout','Locks')}else{@($Suite)}
    $summaries=[Collections.Generic.List[object]]::new()
    $cases=[ordered]@{}
    $writeReport=Get-Command Write-WorkspaceJson -ErrorAction Stop
    foreach($name in $selected){
        $caseName="DotNet$name offline fixtures and bounded mutations"
        $cases.Add($caseName,{
            $test=[IO.Path]::Combine($WorkspaceRoot,"src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNet$name.Tests.ps1")
            $campaign=$null
            & $test -Confirm:$false | ForEach-Object {
                if($_.PSObject.Properties['Assertions']){$campaign=$_}else{Write-Host $_}
            }
            if(!$campaign -or $campaign.State -ne 'Passed'){throw "DotNet$name did not return a passing terminal summary."}
            $summaries.Add($campaign)
            & $writeReport ([IO.Path]::Combine($RunDirectory,"dotnet-$($name.ToLowerInvariant()).json")) $campaign
        }.GetNewClosure())
    }
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
    $tested=Invoke-QuietPesterCaseTable -WorkspaceRoot $WorkspaceRoot -Suite DotNet -Cases $cases -OnProgress $OnProgress -InvokePester {
        param($configuration,$body)
        if($body){& $body}else{Pester\Invoke-Pester -Configuration $configuration}
    }
    $hashes=@{}
    foreach($file in @('scripts/lib/DotNetReadiness.psm1','scripts/lib/DotNetProvisioning.psm1','scripts/lib/DotNetLocks.psm1','scripts/lib/ScriptShouldProcess.psm1','scripts/lib/SourceIdentity.psm1')+@($selected|ForEach-Object {"src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/DotNet$_.Tests.ps1"})){
        $hashes[$file]=(Get-FileHash -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$file)) -Algorithm SHA256).Hash
    }
    $result=[pscustomobject]@{Suite='DotNet';Passed=$tested.Passed;Failed=$tested.Failed;Cases=$tested.Cases;Assertions=($summaries|Measure-Object Assertions -Sum).Sum;PropertyCases=($summaries|Measure-Object PropertyCases -Sum).Sum;FuzzCases=($summaries|Measure-Object FuzzCases -Sum).Sum;MutantsKilled=($summaries|Measure-Object MutantsKilled -Sum).Sum;SourceHashes=$hashes;Campaigns=$summaries.ToArray()}
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'dotnet-summary.json')) $result
    $result
}
