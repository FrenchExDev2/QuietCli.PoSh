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
    $validation=Test-QuietStatusAggregation
    $protocolValidation=& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
        param($tests,$workspace)
        . $tests
        Test-QuietProtocolSpecification -WorkspaceRoot $workspace
    } (Join-Path $PSScriptRoot 'ProtocolSpecification.Tests.ps1') $WorkspaceRoot
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $diagnostics=[Collections.Generic.List[object]]::new()
    $repositories=[Collections.Generic.List[object]]::new()
    $passed=0
    $diagnosticEvidence=Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot -OnProgress $OnProgress
    foreach($sample in $diagnosticEvidence.Samples){$diagnostics.Add($sample)}
    foreach($target in $targets){
        if($OnProgress){& $OnProgress "Core-only git status: $target" Running $passed 0}
        $directory=Join-Path $RunDirectory ('repo-'+$repositories.Count)
        [void][IO.Directory]::CreateDirectory($directory)
        $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 600 -Data ([Text.StringBuilder]::new()) -Output {
            param($event,$runtime)
            if($event.Stream -eq 'stdout'){
                if($runtime.Data.Length+$event.Text.Length -gt 131072){throw 'RealStatusProbeOutputLimit'}
                [void]$runtime.Data.Append($event.Text)
            }elseif($event.Stream -eq 'stderr'){
                if(!$runtime.State.ContainsKey('Diagnostic')){$runtime.State.Diagnostic=''}
                if($runtime.State.Diagnostic.Length -lt 4096){$runtime.State.Diagnostic+=$event.Text}
            }
        } -Complete {param($runtime)if($runtime.State.ContainsKey('Diagnostic')){throw $runtime.State.Diagnostic};$runtime.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Status.RealProbe.ps1'),'-WorkspaceRoot',$WorkspaceRoot,'-RepositoryPath',$target,'-RunDirectory',$directory)
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('RealStatusProbeFailed: '+$target+' '+($result.Error|ConvertTo-Json -Compress))}
        $repo=$result.Data
        if($repo.GitModuleLoaded -or $repo.RegisteredHandlers -ne 0 -or $repo.Samples.Count -ne 4){throw 'RealStatusEvidenceIncomplete'}
        $warm=@($repo.Samples|Where-Object Kind -EQ WarmEngine)
        $repo|Add-Member WarmStatistics @{
            InvocationMs=(Get-QuietImportStatistics @($warm|ForEach-Object InvocationMs))
            ReferenceMs=(Get-QuietImportStatistics @($warm|ForEach-Object ReferenceMs))
            CallbackMs=(Get-QuietImportStatistics @($warm|ForEach-Object CallbackMs))
        }
        $repositories.Add($repo);$passed++
        Write-WorkspaceJson (Join-Path $RunDirectory 'real-status.partial.json') @{Diagnostics=$diagnostics.ToArray();Repositories=$repositories.ToArray();Validation=$validation}
        if($OnProgress){& $OnProgress "Core-only git status verified: $target" Passed $passed 0}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=0;Diagnostics=$diagnostics.ToArray();Repositories=$repositories.ToArray();Validation=$validation;ProtocolValidation=$protocolValidation;SecurityAttribution='Not established; security checks were neither disabled nor independently traced.'}
}
