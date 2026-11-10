#requires -Version 7.6
Set-StrictMode -Version Latest

function Test-PowerShellModuleExports {
    <#
    .SYNOPSIS
    Imports one explicitly selected whitelisted module in a fresh monitored process and observes its actual exports.
    .PARAMETER SourceRoot
    Workspace containing the selected whitelist item.
    .PARAMETER PolicyPath
    Explicit candidate whitelist; inclusion permits selection, not automatic import of every module.
    .PARAMETER ItemId
    Single exact candidate identifier from the policy.
    .PARAMETER EntryPath
    Explicit psd1 or psm1 path relative to the selected item's directory.
    .PARAMETER ExpectedFunctions
    Optional exact expected exported function names. Without it the result is observation only.
    .PARAMETER ExpectedCmdlets
    Optional exact exported cmdlet contract, independent from PowerShell function names.
    .PARAMETER RunDirectory
    New owned report directory; defaults to the shared external report root.
    .PARAMETER TimeoutSeconds
    Deadline for the owned worker, including module import.
    .PARAMETER WorkspaceRoot
    Tooling root containing the shared process supervisor and visible monitor.
    .PARAMETER StageCopy
    Imports an owned source copy instead of the original; location-sensitive behavior remains explicitly scoped.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PolicyPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$EntryPath,
        [AllowEmptyCollection()][string[]]$ExpectedFunctions,[AllowEmptyCollection()][string[]]$ExpectedCmdlets,
        [switch]$StageCopy,[string]$RunDirectory,[ValidateRange(1,600)][int]$TimeoutSeconds=60,
        [string]$WorkspaceRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
    $ErrorActionPreference='Stop'
    if(!$IsWindows){throw 'ModuleExportProbeLocalMonitorRequiresWindows'}
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    $policy=Get-Content -LiteralPath $PolicyPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
    $selected=@($policy.items | Where-Object id -CEQ $ItemId)
    if($policy.schemaVersion -ne 1 -or $selected.Count -ne 1 -or $selected[0].intent -ceq 'Exclude'){throw 'ModuleExportProbeNotWhitelisted'}
    if([IO.Path]::IsPathRooted($selected[0].path) -or $selected[0].path -match '(^|[/\\])\.\.([/\\]|$)' -or [IO.Path]::IsPathRooted($EntryPath) -or $EntryPath -match '(^|[/\\])\.\.([/\\]|$)'){throw 'ModuleExportProbePathInvalid'}
    $source=[IO.Path]::GetFullPath($SourceRoot)
    $itemRoot=[IO.Path]::GetFullPath((Join-Path $source $selected[0].path))
    $entry=[IO.Path]::GetFullPath((Join-Path $itemRoot $EntryPath))
    if([IO.Path]::GetExtension($entry) -cnotin @('.psd1','.psm1') -or !(Test-Path -LiteralPath $entry -PathType Leaf)){throw 'ModuleExportProbeEntryInvalid'}
    for($probe=$entry;$probe -and $probe -ne [IO.Path]::GetDirectoryName($source);$probe=[IO.Path]::GetDirectoryName($probe)){
        if((Get-Item -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ModuleExportProbeLinkRefused'}
        if($probe -eq $source){break}
    }
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ('module-exports-'+[guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'ModuleExportProbeRunExists'}
    if(!$PSCmdlet.ShouldProcess($entry,'Execute selected module import and observe real exports in a monitored child process')){return}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $originalEntry=$entry
    if($StageCopy){
        $staged=Join-Path $RunDirectory 'source'
        $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($itemRoot);$copied=0
        while($queue.Count){
            $directory=$queue.Dequeue()
            foreach($file in Get-ChildItem -LiteralPath $directory -Force){
                if($file.Name -in @('.git','bin','obj','.tools','.cache','node_modules','artifacts')){continue}
                if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ModuleExportProbeCopyLinkRefused'}
                $destination=Join-Path $staged ([IO.Path]::GetRelativePath($itemRoot,$file.FullName))
                if($file.PSIsContainer){[void][IO.Directory]::CreateDirectory($destination);$queue.Enqueue($file.FullName)}
                else{
                    $copied++;if($copied -gt 10000 -or $file.Length -gt 16MB){throw 'ModuleExportProbeCopyLimit'}
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                    Copy-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
                    if((Get-FileHash -LiteralPath $file.FullName).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){throw 'ModuleExportProbeCopyMismatch'}
                }
            }
        }
        $entry=Join-Path $staged $EntryPath
    }
    $request=[pscustomobject]@{Entry=$entry;OriginalEntry=$originalEntry;Staged=[bool]$StageCopy;EntrySha256=(Get-FileHash -LiteralPath $entry).Hash;Item=$ItemId;SourceRoot=$source;PolicyPath=[IO.Path]::GetFullPath($PolicyPath);PolicySha256=(Get-FileHash -LiteralPath $PolicyPath).Hash;CompareFunctions=$PSBoundParameters.ContainsKey('ExpectedFunctions');ExpectedFunctions=@($ExpectedFunctions);CompareCmdlets=$PSBoundParameters.ContainsKey('ExpectedCmdlets');ExpectedCmdlets=@($ExpectedCmdlets)}
    Write-WorkspaceJson (Join-Path $RunDirectory 'request.json') $request
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $workerPath=Join-Path $WorkspaceRoot 'scripts/workers/Invoke-ModuleExportProbe.ps1'
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $worker=Start-Process $runner -WindowStyle Hidden -ArgumentList @('-File',(ConvertTo-CiArgument $workerPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
    try{$monitor=Start-Process $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log') -PassThru}
    catch{if(!$worker.HasExited){$worker.Kill($true)};throw}
    Write-Host "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
    [pscustomobject]@{State=$summary.State.State;RunDirectory=$RunDirectory;Observation=if($summary.PSObject.Properties['Observation']){$summary.Observation}else{$null};Qualification=if($summary.PSObject.Properties['Qualification']){$summary.Qualification}else{'Failed'}}
}

Export-ModuleMember -Function Test-PowerShellModuleExports
