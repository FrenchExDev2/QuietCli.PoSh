#requires -Version 7.6
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$ResultPath
)
if(!$PSCmdlet.ShouldProcess($ResultPath,'Run isolated commit-workspace mutant and write its result')){return}
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
$name=(Split-Path $RunDirectory -Leaf) -replace '^commit-workspace-mutant-',''
$result=[ordered]@{Name=$name;State='InfrastructureFailure';Diagnostic=$null}
try{
    $runtime=[pscustomobject]@{Data=@{WorkspaceRoot=$WorkspaceRoot;RunDirectory=$RunDirectory;CandidatePath=$CandidatePath};State=@{}}
    $null=& (Join-Path $WorkspaceRoot 'scripts/Invoke-Quiet.ps1') -Companion Git -Runtime $runtime -Code {
        param($context)
        . (Join-Path $context.Data.WorkspaceRoot 'scripts/Common.ps1')
        . (Join-Path $context.Data.WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/CommitWorkspace.Tests.ps1')
        Test-QuietCommitWorkspace -WorkspaceRoot $context.Data.WorkspaceRoot -RunDirectory $context.Data.RunDirectory -CandidatePath $context.Data.CandidatePath
    }
    $result.State='Survived'
}catch{
    $result.State='Killed'
    $result.Diagnostic=$_.Exception.Message
}
[void][IO.Directory]::CreateDirectory((Split-Path $ResultPath -Parent))
[void][IO.File]::WriteAllTextAsync($ResultPath,(ConvertTo-Json $result -Depth 4)+"`n",$utf8).GetAwaiter().GetResult()
