#requires -Version 7.6
<#
.SYNOPSIS
Locates import costs in isolated controls without changing product sources or security settings.
.PARAMETER Manifest
Explicit local Core manifest.
.PARAMETER Mode
Import measures the real loader twice; other modes independently measure its source files.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Manifest,[ValidateSet('Import','CmdletOperations','PreloadManagement','PreloadUtility','PreloadBoth','Read','Parse','DotSource')][string]$Mode)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
if(Get-Module FrenchExDev2.QuietCli.Core.PoSh){throw 'ContaminatedDiagnosticProbe'}
$root=[IO.Path]::GetDirectoryName($Manifest)
$rows=[Collections.Generic.List[object]]::new()
$initialModules=@(foreach($module in Get-Module){$module.Name})
if($Mode -eq 'CmdletOperations'){
    $protocolPath=[IO.Path]::Combine($root,'protocol.json')
    $protocolText=[IO.File]::ReadAllTextAsync($protocolPath,$utf8).GetAwaiter().GetResult()
    $operations=[ordered]@{
        JoinPath={Join-Path $root 'protocol.json'}
        GetContent={Get-Content -LiteralPath $protocolPath -Encoding utf8 -Raw}
        ConvertFromJson={ConvertFrom-Json -InputObject $protocolText}
        SetAlias={Set-Alias -Name quiet-diagnostic -Value Get-Module}
    }
    foreach($iteration in 1..2){
        foreach($operation in $operations.GetEnumerator()){
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $null=& $operation.Value
            $watch.Stop()
            $rows.Add(@{Name=$operation.Key;Iteration=$iteration;ElapsedMs=$watch.Elapsed.TotalMilliseconds})
        }
    }
}elseif($Mode -in @('Import','PreloadManagement','PreloadUtility','PreloadBoth')){
    $preload=@(switch($Mode){
        PreloadManagement {'Microsoft.PowerShell.Management'}
        PreloadUtility {'Microsoft.PowerShell.Utility'}
        PreloadBoth {'Microsoft.PowerShell.Management';'Microsoft.PowerShell.Utility'}
    })
    foreach($name in $preload){
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Import-Module -Name $name -ErrorAction Stop
        $watch.Stop()
        $rows.Add(@{Name=$name;ElapsedMs=$watch.Elapsed.TotalMilliseconds})
    }
    foreach($iteration in 1..2){
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Import-Module -Name $Manifest -ErrorAction Stop
        $watch.Stop()
        $module=Get-Module FrenchExDev2.QuietCli.Core.PoSh
        if($null -ne [FrenchExDev2.QuietCli.QuietSession]::Engine){throw 'DiagnosticImportStartedEngine'}
        $rows.Add(@{Name="Import-$iteration";ElapsedMs=$watch.Elapsed.TotalMilliseconds})
        Remove-Module FrenchExDev2.QuietCli.Core.PoSh
    }
}else{
    $null=New-Module -Name QuietImportDiagnostic -ArgumentList $root,$Mode,$rows -ScriptBlock {
        param($root,$mode,$rows)
        foreach($name in @('Contracts','Protocol','Invoke','Delivery','Registry','Gain','Scaffold')){
            $path=Join-Path $root "src/$name.ps1"
            $watch=[Diagnostics.Stopwatch]::StartNew()
            switch($mode){
                Read {$null=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()}
                Parse {
                    $tokens=$null;$errors=$null
                    $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
                    if($errors.Count){throw 'DiagnosticSourceParseFailure'}
                }
                DotSource {. $path}
            }
            $watch.Stop()
            $rows.Add(@{Name=$name;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Bytes=(Get-Item -LiteralPath $path).Length})
        }
    }
}
[pscustomobject]@{
    Mode=$Mode;ProcessId=$PID;PowerShellVersion=$PSVersionTable.PSVersion.ToString()
    Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    InitialModules=$initialModules;FinalModules=@(foreach($module in Get-Module){$module.Name})
    Rows=$rows.ToArray();TotalMs=($rows|Measure-Object ElapsedMs -Sum).Sum
    Limits='Independent fresh-process controls, not an additive decomposition. DotSource uses a diagnostic module scope and includes parsing, compilation, binding and applicable security checks. No security component is disabled or causally isolated.'
}|ConvertTo-Json -Depth 6 -Compress
