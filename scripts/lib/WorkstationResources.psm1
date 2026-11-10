#Objective: Track owned temporary workstations and release only their inactive resources.
#requires -Version 7.6
. (Join-Path $PSScriptRoot '../Ci.Process.ps1')

function Write-WorkstationOwnership {
    <#
    .SYNOPSIS
    Atomically persists an ownership receipt beside a run's evidence.
    .PARAMETER RunDirectory
    Owned run directory.
    .PARAMETER Receipt
    Closed ownership metadata, never credentials or native business output.
    #>
    param([string]$RunDirectory,$Receipt)
    $path=Join-Path $RunDirectory 'ownership.json';$temporary=$path+'.'+[guid]::NewGuid().ToString('N')
    [void][IO.File]::WriteAllTextAsync($temporary,($Receipt|ConvertTo-Json -Depth 12)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [IO.File]::Move($temporary,$path,$true)
}

function Register-WorkstationRun {
    <#
    .SYNOPSIS
    Registers a temporary run and its actual worker identity before creating resources.
    .PARAMETER RunDirectory
    Existing owned run directory.
    .PARAMETER WorkspaceRoot
    Source workspace owning this run.
    .PARAMETER PodmanIdentity
    Explicit hostname/store identity of the engine creating disposable resources.
    #>
    param([string]$RunDirectory,[string]$WorkspaceRoot,$PodmanIdentity)
    $receipt=@{SchemaVersion=1;Kind='QuietCli.DevelopmentWorkstation';RunId=[IO.Path]::GetFileName($RunDirectory);Workspace=[IO.Path]::GetFullPath($WorkspaceRoot);Directory=[IO.Path]::GetFullPath($RunDirectory);Owner=@{Host=[Environment]::MachineName;User=[Environment]::UserName;ProcessId=$PID;ProcessStartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')};State='Running';CreatedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;Resources=@()}
    $receipt.PodmanIdentity=$PodmanIdentity
    Write-WorkstationOwnership $RunDirectory $receipt
    $receipt
}

function Add-WorkstationResource {
    <#
    .SYNOPSIS
    Declares a uniquely labelled container or image before its creation.
    .PARAMETER RunDirectory
    Registered run.
    .PARAMETER Kind
    Container or Image.
    .PARAMETER Name
    Exact owned resource name.
    #>
    param([string]$RunDirectory,[ValidateSet('Container','Image')][string]$Kind,[string]$Name)
    $receipt=Get-Content -LiteralPath (Join-Path $RunDirectory 'ownership.json') -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String
    if($Name -cnotmatch '^(localhost/)?quietcli-workstation-[a-z0-9-]+$'){throw 'WorkstationResourceNameInvalid'}
    $receipt.Resources+=@{Kind=$Kind;Name=$Name;Label=$receipt.RunId;State='Registered'}
    Write-WorkstationOwnership $RunDirectory $receipt
}

function Test-WorkstationOwnerActive {
    <#
    .SYNOPSIS
    Checks a PID together with its creation time; foreign or unverifiable ownership stays protected.
    .PARAMETER Owner
    Persisted worker identity.
    #>
    param($Owner)
    if(!$Owner -or $Owner.Host -cne [Environment]::MachineName){return $true}
    if(!$Owner.ProcessId -or !$Owner.ProcessStartedUtc){return $true}
    $process=Get-Process -Id $Owner.ProcessId -ErrorAction SilentlyContinue
    if(!$process){return $false}
    try{
        $recorded=if($Owner.ProcessStartedUtc -is [DateTimeOffset]){$Owner.ProcessStartedUtc}elseif($Owner.ProcessStartedUtc -is [DateTime]){[DateTimeOffset]::new($Owner.ProcessStartedUtc)}else{[DateTimeOffset]::Parse($Owner.ProcessStartedUtc,[Globalization.CultureInfo]::InvariantCulture)}
        return $process.StartTime.ToUniversalTime().Ticks -eq $recorded.UtcTicks
    }catch{return $true}
}

function Test-WorkstationDirectoryBoundary {
    <#
    .SYNOPSIS
    Rejects recursive deletion outside the selected report root or through filesystem links.
    .PARAMETER Root
    Explicit managed report root.
    .PARAMETER Path
    Candidate run directory.
    #>
    param([string]$Root,[string]$Path)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $pathFull=[IO.Path]::GetFullPath($Path)
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(!$pathFull.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,$comparison)){return $false}
    $current=[IO.DirectoryInfo]::new($pathFull)
    while($current){if($current.Attributes -band [IO.FileAttributes]::ReparsePoint){return $false};if($current.FullName -eq $rootFull){break};$current=$current.Parent}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($pathFull)
    while($pending.Count){foreach($entry in [IO.DirectoryInfo]::new($pending.Pop()).EnumerateFileSystemInfos()){
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}
        if($entry -is [IO.DirectoryInfo]){$pending.Push($entry.FullName)}
    }}
    return $true
}

function Get-WorkstationCleanupDecision {
    <#
    .SYNOPSIS
    Classifies an owned run independently from age-based retention and without changing it.
    .PARAMETER RunDirectory
    Run to inspect.
    .PARAMETER WorkspaceRoot
    Expected owning workspace.
    #>
    param([string]$RunDirectory,[string]$WorkspaceRoot)
    $path=Join-Path $RunDirectory 'ownership.json'
    if(!(Test-Path -LiteralPath $path)){return [pscustomobject]@{State='Unmanaged';Reason='No ownership receipt; preserved';Receipt=$null}}
    try{$receipt=Get-Content -LiteralPath $path -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String}catch{return [pscustomobject]@{State='Protected';Reason='Unreadable ownership receipt';Receipt=$null}}
    if($receipt -isnot [Collections.IDictionary]){return [pscustomobject]@{State='Protected';Reason='Ownership receipt must be an object';Receipt=$null}}
    foreach($field in @('SchemaVersion','Kind','Directory','Workspace','RunId','Owner','State','Resources','CreatedUtc','FinishedUtc')){if(!$receipt.Contains($field)){return [pscustomobject]@{State='Protected';Reason='Incomplete ownership receipt';Receipt=$null}}}
    if($receipt.SchemaVersion -ne 1 -or $receipt.Kind -cne 'QuietCli.DevelopmentWorkstation' -or $receipt.Directory -ne [IO.Path]::GetFullPath($RunDirectory) -or $receipt.Workspace -ne [IO.Path]::GetFullPath($WorkspaceRoot) -or $receipt.RunId -cne [IO.Path]::GetFileName($RunDirectory)){return [pscustomobject]@{State='Protected';Reason='Ownership identity mismatch';Receipt=$receipt}}
    foreach($resource in $receipt.Resources){if($resource.Label -cne $receipt.RunId){return [pscustomobject]@{State='Protected';Reason='Resource belongs to another run';Receipt=$receipt}}}
    if(Test-WorkstationOwnerActive $receipt.Owner){return [pscustomobject]@{State='Active';Reason="Worker $($receipt.Owner.ProcessId) is active or cannot be verified";Receipt=$receipt}}
    [pscustomobject]@{State='Inactive';Reason=$(if($receipt.State -ceq 'Running'){'Abandoned worker; retained until the age policy expires'}else{$receipt.State});Receipt=$receipt}
}

function Invoke-WorkstationResourceCommand {
    <#
    .SYNOPSIS
    Executes one bounded Podman metadata/removal command independently of the product engine.
    .PARAMETER Arguments
    Exact Podman arguments.
    #>
    param([string[]]$Arguments)
    $data=@{Text=[Text.StringBuilder]::new()}
    $result=Invoke-CiProcess podman $Arguments -TimeoutSeconds 30 -State $data -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){if($s.Text.Length+$e.Text.Length -gt 1048576){throw 'WorkstationResourceMetadataTooLarge'};[void]$s.Text.AppendLine($e.Text)}}
    [pscustomobject]@{Outcome=$result.Outcome;ExitCode=$result.ExitCode;Text=$data.Text.ToString()}
}

function Get-WorkstationPodmanIdentity {
    <#
    .SYNOPSIS
    Reads the current engine/store identity so a later default-connection change cannot hide resources.
    #>
    $query=Invoke-WorkstationResourceCommand @('info','--format','json')
    if($query.Outcome -ne 'Success'){throw 'WorkstationPodmanIdentityUnavailable'}
    $info=$query.Text|ConvertFrom-Json
    if(!$info.host.hostname -or !$info.store.graphRoot){throw 'WorkstationPodmanIdentityIncomplete'}
    [pscustomobject]@{Hostname=$info.host.hostname;GraphRoot=$info.store.graphRoot}
}

function Test-WorkstationPodmanIdentity {
    <#
    .SYNOPSIS
    Protects resources when their original engine/store cannot be verified.
    .PARAMETER Expected
    Engine identity recorded before resource creation.
    #>
    param($Expected)
    if(!$Expected){return $false}
    try{$actual=Get-WorkstationPodmanIdentity;return $actual.Hostname -ceq $Expected.Hostname -and $actual.GraphRoot -ceq $Expected.GraphRoot}catch{return $false}
}

function Remove-WorkstationOwnedResource {
    <#
    .SYNOPSIS
    Removes an inactive resource only when its exact ownership label matches; never uses force or prune.
    .PARAMETER Resource
    Declared resource identity.
    .PARAMETER Preview
    Reads metadata only; does not invoke removal.
    #>
    param($Resource,[switch]$Preview)
    if($Resource.Kind -cnotin @('Container','Image') -or $Resource.Name -cnotmatch '^(localhost/)?quietcli-workstation-[a-z0-9-]+$' -or !$Resource.Label){return 'Unverified'}
    $kind=$Resource.Kind.ToLowerInvariant()
    $exists=Invoke-WorkstationResourceCommand @($kind,'exists',$Resource.Name)
    if($exists.ExitCode -eq 1){return 'Absent'}
    if($exists.Outcome -ne 'Success'){return 'Unverified'}
    $inspection=Invoke-WorkstationResourceCommand @($kind,'inspect',$Resource.Name)
    if($inspection.Outcome -ne 'Success'){return 'Unverified'}
    try{$record=@($inspection.Text|ConvertFrom-Json)[0];$labels=if($kind -ceq 'image'){$record.Labels}else{$record.Config.Labels}}catch{return 'Unverified'}
    if($labels.'io.frenchexdev.quietcli.workstation.run' -cne $Resource.Label){return 'Foreign'}
    if($kind -ceq 'container' -and $record.State.Running){return 'InUse'}
    if($kind -ceq 'image'){
        $references=Invoke-WorkstationResourceCommand @('ps','--all','--filter',('ancestor='+$Resource.Name),'--format','{{.ID}}')
        if($references.Outcome -ne 'Success'){return 'Unverified'}
        $Resource.Consumers=@()
        if($references.Text.Trim()){$Resource.Consumers=@($references.Text.Trim() -split '\r?\n');return 'InUse'}
    }
    if($Preview){return 'Eligible'}
    $remove=Invoke-WorkstationResourceCommand @($kind,'rm',$Resource.Name)
    if($remove.Outcome -eq 'Success'){return 'Removed'}
    return 'InUseOrFailed'
}

function Complete-WorkstationRun {
    <#
    .SYNOPSIS
    Releases only finished owned resources and saves a terminal ownership receipt, keeping evidence.
    .PARAMETER RunDirectory
    Registered run.
    .PARAMETER State
    Terminal worker outcome.
    #>
    param([string]$RunDirectory,[string]$State)
    $receipt=Get-Content -LiteralPath (Join-Path $RunDirectory 'ownership.json') -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String
    $sameEngine=if($receipt.Resources.Count){Test-WorkstationPodmanIdentity $receipt.PodmanIdentity}else{$true}
    foreach($resource in @($receipt.Resources|Sort-Object Kind)){
        try{$resource.State=if($sameEngine){Remove-WorkstationOwnedResource $resource}else{'UnverifiedEngine'}}catch{$resource.State='Unverified';$resource.Error=$_.Exception.Message}
    }
    $receipt.State=$State;$receipt.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkstationOwnership $RunDirectory $receipt
    $receipt
}

Export-ModuleMember -Function Register-WorkstationRun,Add-WorkstationResource,Complete-WorkstationRun,Get-WorkstationCleanupDecision,Test-WorkstationOwnerActive,Test-WorkstationDirectoryBoundary,Remove-WorkstationOwnedResource,Get-WorkstationPodmanIdentity,Test-WorkstationPodmanIdentity
