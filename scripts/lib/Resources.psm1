#requires -Version 7.6
function Ensure-QuietResource {
    <#
    .SYNOPSIS
    Verifies a pinned resource, restores its package when necessary, and optionally loads a managed type.
    .PARAMETER WorkspaceRoot
    Source workspace owning the resource manifest and restore script.
    .PARAMETER RelativePath
    Exact module-relative path declared by dependencies.lock.json.
    .PARAMETER AssemblyType
    Optional managed type whose assembly must match the pinned resource.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot=(Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),[Parameter(Mandatory)][string]$RelativePath,[string]$AssemblyType)
    $module=[IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh')
    $manifest=Get-Content -LiteralPath ([IO.Path]::Combine($module,'resources/dependencies.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $entries=@($manifest.Files|Where-Object Path -CEQ $RelativePath)
    if($entries.Count -ne 1 -or $RelativePath -notmatch '^resources/[A-Za-z0-9_./-]+$' -or $RelativePath -match '(^|/)\.\.(/|$)'){throw ('ResourceNotDeclared: '+$RelativePath)}
    $entry=$entries[0];$path=[IO.Path]::Combine($module,$RelativePath)
    $valid=(Test-Path -LiteralPath $path -PathType Leaf) -and (Get-FileHash -LiteralPath $path).Hash -ceq $entry.SHA256
    $restored=$false
    if(!$valid){
        if($entry.Package -ceq 'quietcli-pty'){throw ('SourceBuiltResourceMissing: '+$RelativePath+'; run Build-PtyBridge.ps1 explicitly.')}
        if(!$PSCmdlet.ShouldProcess($path,('Restore checksum-pinned package '+$entry.Package))){return [pscustomobject]@{State='Planned';Path=$path;Loaded=$false;Restored=$false}}
        Write-Host ('Progress: Restore missing or invalid pinned resource '+$RelativePath)
        $null=& ([IO.Path]::Combine(([IO.Path]::GetDirectoryName($PSScriptRoot)),'Restore-CoreResources.ps1')) -WorkspaceRoot $WorkspaceRoot -IncludePackage $entry.Package -Confirm:$false
        $restored=$true
    }
    if(!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -cne $entry.SHA256){throw ('ResourceIntegrityFailed: '+$RelativePath)}
    $loaded=$false
    if($AssemblyType){
        $type=$AssemblyType -as [type]
        if($type){
            if((Get-FileHash -LiteralPath $type.Assembly.Location).Hash -cne $entry.SHA256){throw 'ResourceAssemblyConflict: restart PowerShell before loading a different assembly.'}
        }else{
            $null=[Reflection.Assembly]::LoadFrom($path)
            if(!($AssemblyType -as [type])){throw ('ResourceAssemblyTypeMissing: '+$AssemblyType)}
        }
        $loaded=$true
    }
    [pscustomobject]@{State='Ready';Path=$path;SHA256=$entry.SHA256;Restored=$restored;Loaded=$loaded}
}

Export-ModuleMember -Function 'Ensure-QuietResource'
