function Invoke-QuietCompanionSmokeTests {
    <#
    .SYNOPSIS
    Exercises selected module imports and one real native integration per companion without full qualification.
    .PARAMETER WorkspaceRoot
    Selected source checkout.
    .PARAMETER Suites
    Explicit companion names selected by the impact graph.
    .PARAMETER RunDirectory
    Owned report directory.
    .PARAMETER OnProgress
    Actual smoke case progress.
    #>
    param([string]$WorkspaceRoot,[string[]]$Suites,[string]$RunDirectory,[scriptblock]$OnProgress)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
    $results=[Collections.Generic.List[object]]::new();$passed=0;$failed=0
    foreach($suite in $Suites){
        Assert-QuietCompanionProfile -WorkspaceRoot $WorkspaceRoot -Suite $suite
        if($suite -cnotin @('Core','Git','Vagrant')){throw ('CompanionSmokeRunnerUndeclared: '+$suite)}
        if($OnProgress){& $OnProgress ($suite+' integration smoke') 'Running' $passed $failed}
        $errorText=$null
        try{
            $context=[pscustomobject]@{Root=$WorkspaceRoot;Suite=$suite}
            $companions=@($suite|Where-Object {$_ -cne 'Core'})
            & ([IO.Path]::Combine($WorkspaceRoot,'scripts/Invoke-Quiet.ps1')) -Companion $companions -Runtime $context -Code {
                param($context)
                $fixture=[IO.Path]::Combine($context.Root,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll')
                $text='1700000000,web,ui,info,ready'+[char]10
                $result=quiet -AsObject -C companion-smoke -RecordDelimiter ([string][char]10) -Data @{Lines=0;Text=''} -Output {
                    param($event,$runtime)
                    if($event.Stream -eq 'stdout'){$runtime.Data.Lines++;$runtime.Data.Text=$event.Text}
                } -Complete {param($runtime) $runtime.Data} -FilePath dotnet -ArgumentList @($fixture,'chunks','20261116',$text)
                if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count -or $result.Data.Lines -ne 1 -or $result.Data.Text -cne $text.TrimEnd([char]10)){throw 'CompanionNativeSmokeFailed'}
                if($context.Suite -ceq 'Git'){
                    $result=quiet -AsObject -C git-smoke -WorkingDirectory $context.Root -FilePath git -ArgumentList @('-c',('safe.directory='+$context.Root),'status','--','README.md')
                    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count){throw 'GitStatusSmokeFailed'}
                }elseif($context.Suite -ceq 'Vagrant'){
                    $parsed=& (Get-Module FrenchExDev2.QuietCli.Vagrant.PoSh) {ConvertFrom-QuietVagrantMachineReadableLine '1700000000,web,ui,info,ready'}
                    if(!$parsed -or $parsed.Machine -cne 'web' -or $parsed.Type -cne 'ui' -or ($parsed.Fields -join ',') -cne 'info,ready'){throw 'VagrantParserSmokeFailed'}
                }
            }
            $passed++;$caseState='Passed'
        }catch{$failed++;$caseState='Failed';$errorText=$_.ToString()}
        $results.Add([pscustomobject]@{Name=$suite+' integration smoke';State=$caseState;Error=$errorText;Companion=$suite;Mode='smoke'})
        if($OnProgress){& $OnProgress ($suite+' integration smoke') $caseState $passed $failed}
    }
    [pscustomobject]@{Project='CompanionSmoke';Passed=$passed;Failed=$failed;Partial=$false;Incomplete=$false;Skipped=0;QualificationMode='smoke';Cases=$results.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietCompanionSmokeTests
