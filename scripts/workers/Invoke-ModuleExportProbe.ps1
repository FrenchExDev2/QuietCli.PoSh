#requires -Version 7.6
<#
.SYNOPSIS
Owned child worker: imports the explicit source entry and records real Get-Module exports.
.PARAMETER WorkspaceRoot
Tooling root providing the shared report writer.
.PARAMETER RunDirectory
Owned directory containing the validated request, progress and final evidence.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
$request=Get-Content -LiteralPath (Join-Path $RunDirectory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 16
if(!$PSCmdlet.ShouldProcess($request.Entry,'Import selected module and write owned export observation')){return}
$state=[ordered]@{Project=$request.Item;Task='Migration module import and actual exported commands';Workspace=$request.SourceRoot;ProjectDirectory=[IO.Path]::GetDirectoryName($request.Entry);Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Importing selected module';Error=$null}
$observation=$null;$qualification='NotAssessed'
Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
try{
    if((Get-FileHash -LiteralPath $request.Entry).Hash -cne $request.EntrySha256 -or (Get-FileHash -LiteralPath $request.PolicyPath).Hash -cne $request.PolicySha256){throw 'ModuleExportProbeInputChanged'}
    # A fresh process isolates loaded assemblies/modules; it is not an OS security sandbox.
    $importOutput=@(Import-Module -Name $request.Entry -PassThru -Force -ErrorAction Stop)
    $actual=@(Get-Module -All | Where-Object { $_.ModuleBase -eq [IO.Path]::GetDirectoryName($request.Entry) -and $_.Name -eq [IO.Path]::GetFileNameWithoutExtension($request.Entry) })
    if($actual.Count -ne 1){throw 'ModuleExportProbeIdentityMismatch'}
    $module=$actual[0]
    $functions=@($module.ExportedFunctions.Keys | Sort-Object -CaseSensitive)
    $commands=@($module.ExportedCommands.Values | Sort-Object Name | ForEach-Object {[pscustomobject]@{Name=$_.Name;CommandType=[string]$_.CommandType;Module=$_.ModuleName;Source=$_.Source}})
    $observation=[pscustomobject]@{Name=$module.Name;Version=[string]$module.Version;Guid=[string]$module.Guid;Path=$module.Path;Entry=$request.Entry;EntrySha256=$request.EntrySha256;LoadedModuleSha256=(Get-FileHash -LiteralPath $module.Path).Hash;Functions=$functions;Cmdlets=@($module.ExportedCmdlets.Keys | Sort-Object);Aliases=@($module.ExportedAliases.Keys | Sort-Object);Commands=$commands;UnexpectedImportOutput=@($importOutput | Where-Object {$_ -isnot [Management.Automation.PSModuleInfo]}).Count;RequiredModules=@($module.RequiredModules | ForEach-Object {[pscustomobject]@{Name=$_.Name;Version=[string]$_.Version;Path=$_.Path}});PowerShell=[string]$PSVersionTable.PSVersion;Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;PolicySha256=$request.PolicySha256;Scope='Observed exports after a real import, not behavior qualification.'}
    $observation | Add-Member NoteProperty OriginalEntry $request.OriginalEntry
    $originalModulePath=if($request.Staged){Join-Path ([IO.Path]::GetDirectoryName($request.OriginalEntry)) ([IO.Path]::GetRelativePath([IO.Path]::GetDirectoryName($request.Entry),$module.Path))}else{$module.Path}
    $observation | Add-Member NoteProperty OriginalModulePath $originalModulePath
    $observation | Add-Member NoteProperty Staged $request.Staged
    $observation | Add-Member NoteProperty Comparison ([pscustomobject]@{Functions=[bool]$request.CompareFunctions;Cmdlets=[bool]$request.CompareCmdlets})
    if($request.CompareFunctions){
        $expected=@($request.ExpectedFunctions | Sort-Object -CaseSensitive)
        $same=$functions.Count -eq $expected.Count
        for($index=0;$same -and $index -lt $functions.Count;$index++){$same=$functions[$index] -ceq $expected[$index]}
        if(!$same){throw 'ModuleExportContractMismatch'}
        $qualification='ExportContractPassed'
    }
    if($request.CompareCmdlets){
        $expected=@($request.ExpectedCmdlets | Sort-Object -CaseSensitive)
        $actualCmdlets=@($module.ExportedCmdlets.Keys | Sort-Object -CaseSensitive)
        $same=$actualCmdlets.Count -eq $expected.Count
        for($index=0;$same -and $index -lt $actualCmdlets.Count;$index++){$same=$actualCmdlets[$index] -ceq $expected[$index]}
        if(!$same){throw 'ModuleCmdletExportContractMismatch'}
        $qualification='ExportContractPassed'
    }
    if($observation.UnexpectedImportOutput){throw 'ModuleImportUnexpectedOutput'}
    $state.State='Success';$state.Passed=1;$state.Case='Actual exports recorded'
}catch{$state.State='Failed';$state.Failed=1;$state.Error=$_.Exception.Message;$qualification='Failed'}
finally{
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') ([pscustomobject]@{State=$state;Observation=$observation;Qualification=$qualification})
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
if($state.State -ne 'Success'){exit 1}
