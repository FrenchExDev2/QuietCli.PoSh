. (Join-Path $PSScriptRoot 'Status.Aggregation.ps1')
. (Join-Path $PSScriptRoot 'Import.Tests.ps1')

function Invoke-QuietRealStatusIntegration {
    <#
    .SYNOPSIS
    Profiles local import controls and tests plain Git status on explicitly selected real repositories.
    .PARAMETER WorkspaceRoot
    Local QuietCli2 monorepo.
    .PARAMETER RunDirectory
    Existing private report directory.
    .PARAMETER RepositoryConfig
    UTF-8 JSON array of existing absolute repository paths.
    .PARAMETER OnProgress
    Shared visible-monitor progress callback.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[Parameter(Mandatory)][string]$RepositoryConfig,[scriptblock]$OnProgress)
    $targets=@(Get-Content -LiteralPath $RepositoryConfig -Encoding utf8 -Raw|ConvertFrom-Json)
    if(!$targets.Count -or $targets.Count -gt 16){throw 'RealStatusTargetCount'}
    foreach($target in $targets){if($target -isnot [string] -or ![IO.Path]::IsPathFullyQualified($target) -or !(Test-Path -LiteralPath $target -PathType Container) -or !(Test-Path -LiteralPath (Join-Path $target '.git'))){throw 'RealStatusRequiresExplicitRepositoryRoot'}}
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $diagnostics=[Collections.Generic.List[object]]::new()
    $repositories=[Collections.Generic.List[object]]::new()
    $evidence=@{}
    $cases=[ordered]@{'Core aggregation, protocol and import controls'={
        $evidence.Validation=Test-QuietStatusAggregation
        $evidence.Protocol=& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
            param($tests,$workspace)
            . $tests
            Test-QuietProtocolSpecification -WorkspaceRoot $workspace
        } ([IO.Path]::Combine($PSScriptRoot,'ProtocolSpecification.Tests.ps1')) $WorkspaceRoot
        $diagnosticEvidence=Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot
        foreach($sample in $diagnosticEvidence.Samples){$diagnostics.Add($sample)}
    }}
    $writeReport=Get-Command Write-WorkspaceJson -ErrorAction Stop
    $measureImport=Get-Command Get-QuietImportStatistics -ErrorAction Stop
    $invokeQuiet=(Get-Command quiet -ErrorAction Stop).ResolvedCommand
    $ordinal=0
    foreach($target in $targets){
        $directory=[IO.Path]::Combine($RunDirectory,('repo-'+$ordinal))
        $ordinal++
        $probe=[IO.Path]::Combine($PSScriptRoot,'Status.RealProbe.ps1')
        $cases.Add("Core-only git status $ordinal ($target)",{
        [void][IO.Directory]::CreateDirectory($directory)
        $result=& $invokeQuiet -AsObject -Role Infrastructure -TimeoutSeconds 600 -Data ([Text.StringBuilder]::new()) -Output {
            param($event,$runtime)
            if($event.Stream -eq 'stdout'){
                if($runtime.Data.Length+$event.Text.Length -gt 131072){throw 'RealStatusProbeOutputLimit'}
                [void]$runtime.Data.Append($event.Text)
            }elseif($event.Stream -eq 'stderr'){
                if(!$runtime.State.ContainsKey('Diagnostic')){$runtime.State.Diagnostic=''}
                if($runtime.State.Diagnostic.Length -lt 4096){$runtime.State.Diagnostic+=$event.Text}
            }
        } -Complete {param($runtime)if($runtime.State.ContainsKey('Diagnostic')){throw $runtime.State.Diagnostic};$runtime.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-NoProfile','-NonInteractive','-File',$probe,'-WorkspaceRoot',$WorkspaceRoot,'-RepositoryPath',$target,'-RunDirectory',$directory)
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('RealStatusProbeFailed: '+$target+' '+($result.Error|ConvertTo-Json -Compress))}
        $repo=$result.Data
        if($repo.GitModuleLoaded -or $repo.RegisteredHandlers -ne 0 -or $repo.Samples.Count -ne 4){throw 'RealStatusEvidenceIncomplete'}
        $warm=@($repo.Samples|Where-Object Kind -EQ WarmEngine)
        $repo|Add-Member WarmStatistics @{
            InvocationMs=(& $measureImport @($warm|ForEach-Object InvocationMs))
            ReferenceMs=(& $measureImport @($warm|ForEach-Object ReferenceMs))
            CallbackMs=(& $measureImport @($warm|ForEach-Object CallbackMs))
        }
        $repositories.Add($repo)
        & $writeReport ([IO.Path]::Combine($RunDirectory,'real-status.partial.json')) @{Diagnostics=$diagnostics.ToArray();Repositories=$repositories.ToArray();Validation=$evidence.Validation}
        }.GetNewClosure())
    }
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
    $tested=Invoke-QuietPesterCaseTable -WorkspaceRoot $WorkspaceRoot -Suite RealStatus -Cases $cases -OnProgress $OnProgress -InvokePester {
        param($configuration,$body)
        if($body){& $body}else{Pester\Invoke-Pester -Configuration $configuration}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$tested.Passed;Failed=$tested.Failed;Cases=$tested.Cases;Diagnostics=$diagnostics.ToArray();Repositories=$repositories.ToArray();Validation=$evidence.Validation;ProtocolValidation=$evidence.Protocol;SecurityAttribution='Not established; security checks were neither disabled nor independently traced.'}
}
