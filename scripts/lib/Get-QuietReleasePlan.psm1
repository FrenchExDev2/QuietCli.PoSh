function Invoke-QuietScriptGetQuietReleasePlan {
#requires -Version 7.6
<#
.SYNOPSIS
Validates a module-specific publication tag and optionally writes bounded GitHub job outputs.
.PARAMETER Tag
Exact pushed tag, such as FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview; must match its script module and manifest.
.PARAMETER WorkspaceRoot
Selected QuietCli2 source checkout.
.PARAMETER OutputPath
Optional GitHub output file receiving the validated module and version.
.PARAMETER ReadBatch
Reads the annotated tag and verifies every batch tag points to Revision on origin before emitting leader outputs.
.PARAMETER Revision
Exact workflow commit required with ReadBatch. WhatIf makes no Git or remote probes.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Tag,[string]$WorkspaceRoot=(Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),[string]$OutputPath,[switch]$ReadBatch,[string]$Revision)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GalleryRelease.psm1')) -DisableNameChecking -ErrorAction Stop
$plan=Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag $Tag
$batchOutputs=''
if($ReadBatch){
    if(!$PSCmdlet.ShouldProcess($Tag,'Read annotated release batch and verify remote tag commits')){return}
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
    function Read-ReleaseGitMetadata {
        <#
        .SYNOPSIS
        Reads bounded administrative tag metadata with exact arguments.
        .PARAMETER Arguments
        Git argument vector; no shell expansion or retry.
        #>
        param([string[]]$Arguments)
        $state=@{Text=[Text.StringBuilder]::new()}
        $result=Invoke-CiProcess -FilePath git -ArgumentList $Arguments -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 60 -State $state -OnOutput {
            param($event,$state)
            if($event.Stream -ne 'stdout'){return}
            if($state.Text.Length+$event.Text.Length -gt 65536){throw 'ReleaseMetadataLimitExceeded'}
            [void]$state.Text.AppendLine($event.Text)
        }
        if($result.Outcome -ne 'Success'){throw 'ReleaseMetadataUnavailable'}
        $state.Text.ToString()
    }
    if($Revision -cnotmatch '\A[a-f0-9]{40}\z'){throw 'ReleaseBatchRevisionRequired'}
    $annotation=Read-ReleaseGitMetadata @('for-each-ref','--format=%(contents)','--',('refs/tags/'+$Tag))
    $batch=Resolve-QuietGalleryReleaseBatch -WorkspaceRoot $WorkspaceRoot -Tag $Tag -Revision $Revision -Annotation $annotation
    $refs=@($batch.Tags|ForEach-Object {'refs/tags/'+$_;'refs/tags/'+$_+'^{}'})
    $remote=Read-ReleaseGitMetadata (@('ls-remote','origin')+$refs)
    $observed=@{}
    foreach($line in $remote -split '\r?\n'){if($line -match '\A([a-f0-9]{40})\s+(refs/tags/.+)\z'){$observed[$Matches[2]]=$Matches[1]}}
    foreach($member in $batch.Tags){
        $ref='refs/tags/'+$member
        $actual=if($observed.ContainsKey($ref+'^{}')){$observed[$ref+'^{}']}else{$observed[$ref]}
        if($actual -cne $Revision){throw ('ReleaseBatchRemoteTagMismatch: '+$member)}
    }
    $batchOutputs="is_leader=$($batch.IsLeader.ToString().ToLowerInvariant())`nrelease_tags=$($batch.Tags|ConvertTo-Json -Compress -AsArray)`n"
    $plan|Add-Member -NotePropertyName Batch -NotePropertyValue $batch
}
if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Append validated Gallery release outputs')){
    [IO.File]::AppendAllText([IO.Path]::GetFullPath($OutputPath,$PWD.Path),"module=$($plan.Module)`ncomponent=$($plan.Component)`nversion=$($plan.Version)`n"+$batchOutputs,[Text.UTF8Encoding]::new($false))
}
$plan

}
Export-ModuleMember -Function 'Invoke-QuietScriptGetQuietReleasePlan'
