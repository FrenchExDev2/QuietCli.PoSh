#requires -Version 7.6
<#
.SYNOPSIS
Owns a disposable real BaGet server, isolated clients and retained terminal diagnostics.
.PARAMETER WorkspaceRoot
Shared qualification-tooling root.
.PARAMETER RunDirectory
Owned external request/report directory.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
$request=Get-Content (Join-Path $RunDirectory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json
if(!$PSCmdlet.ShouldProcess($request.Image,'Run owned registry compatibility fixture')){return}
$state=[ordered]@{Project='PSResource localhost compatibility';Task='BaGet Windows/Linux real client roundtrip';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'scripts/workers');Platform='Windows + Linux';State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Container preflight';Error=$null}
$id=[guid]::NewGuid().ToString('N').Substring(0,12)
$server='rac-gallery-'+$id;$client='rac-client-'+$id;$network='rac-network-'+$id;$volume='rac-volume-'+$id
$owned=[Collections.Generic.List[string]]::new();$receipt=[ordered]@{ServerImage=$request.Image;ServerId=$null;ClientImage=$request.LinuxClientImage;ClientId=$null;DependencyStrategy=$request.DependencyStrategy;Server=$server;Client=$client;Network=$network;Volume=$volume;Windows='NotRun';Linux='NotRun';Cleanup=@()}

function Invoke-GalleryNative {
    <#
    .SYNOPSIS
    Runs qualification-native operations through the independent CI helper with bounded diagnostics.
    .PARAMETER Arguments
    Literal docker argument vector.
    .PARAMETER TimeoutSeconds
    Native operation deadline.
    #>
    param([string[]]$Arguments,[int]$TimeoutSeconds=60)
    $state.Case='docker '+($Arguments | Select-Object -First 2) -join ' '
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
    $capture=@{Lines=[Collections.Generic.List[string]]::new()}
    $native=Invoke-CiProcess -FilePath (Get-Command docker -CommandType Application | Select-Object -First 1).Source -ArgumentList $Arguments -WorkingDirectory $RunDirectory -TimeoutSeconds $TimeoutSeconds -State $capture -OnOutput {param($record,$data) if($data.Lines.Count -lt 100){$data.Lines.Add($record.Text)}}
    $index=@(Get-ChildItem $RunDirectory -Filter 'native-*.json' -File).Count
    Write-WorkspaceJson (Join-Path $RunDirectory ("native-$index.json")) @{Arguments=$Arguments;Outcome=$native.Outcome;Lines=$capture.Lines.ToArray()}
    if($native.Outcome -ne 'Success'){throw "RegistryNativeFailed:$($Arguments[0]):$($native.Outcome)"}
    return ($capture.Lines -join "`n").Trim()
}
Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
try{
    $null=Invoke-GalleryNative @('version','--format','{{json .}}')
    $receipt.ClientId=Invoke-GalleryNative @('image','inspect',$request.LinuxClientImage,'--format','{{.Id}}')
    $null=Invoke-GalleryNative @('pull',$request.Image) -TimeoutSeconds 90
    $receipt.ServerId=Invoke-GalleryNative @('image','inspect',$request.Image,'--format','{{.Id}}')
    $null=Invoke-GalleryNative @('network','create',$network);$owned.Add('network')
    $null=Invoke-GalleryNative @('volume','create',$volume);$owned.Add('volume')
    $null=Invoke-GalleryNative @('run','-d','--name',$server,'--network',$network,'--network-alias','gallery','-p','127.0.0.1::80','-e','ApiKey=OwnedFixtureOnly','-e','Storage__Type=FileSystem','-e','Storage__Path=/var/baget/packages','-e','Database__Type=Sqlite','-e','Database__ConnectionString=Data Source=/var/baget/baget.db','-e','Search__Type=Database','-v',($volume+':/var/baget'),$receipt.ServerId);$owned.Add('server')
    $port=Invoke-GalleryNative @('port',$server,'80/tcp')
    if($port -notmatch '127\.0\.0\.1:(\d+)'){throw 'RegistryLoopbackPortUnknown'}
    $uri='http://127.0.0.1:'+$Matches[1]+'/v3/index.json'
    $ready=$false
    for($attempt=0;$attempt -lt 30;$attempt++){
        try{$null=Invoke-RestMethod -Uri $uri -TimeoutSec 2;$ready=$true;break}catch{[void][Threading.Tasks.Task]::Delay(1000).GetAwaiter().GetResult()}
    }
    if(!$ready){throw 'RegistryHealthTimeout'}
    $clientScript=Join-Path $WorkspaceRoot 'scripts/workers/Invoke-LocalGalleryClient.ps1'
    $windowsDirectory=Join-Path $RunDirectory 'windows-client';[void][IO.Directory]::CreateDirectory($windowsDirectory)
    $windowsEnvironment=Join-Path $windowsDirectory 'user';[void][IO.Directory]::CreateDirectory($windowsEnvironment)
    $state.Case='Windows publish/find/save/import';Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
    $windows=Start-Process (Join-Path $PSHOME 'pwsh.exe') -WindowStyle Hidden -Environment @{LOCALAPPDATA=$windowsEnvironment;USERPROFILE=$windowsEnvironment;HOME=$windowsEnvironment} -ArgumentList @('-File',(ConvertTo-CiArgument $clientScript),'-Uri',$uri,'-RunDirectory',(ConvertTo-CiArgument $windowsDirectory),'-DependencyStrategy',$request.DependencyStrategy,'-Publish') -RedirectStandardOutput (Join-Path $windowsDirectory 'stdout.log') -RedirectStandardError (Join-Path $windowsDirectory 'stderr.log') -PassThru
    try{[void]$windows.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(90)).GetAwaiter().GetResult()}catch [TimeoutException]{$windows.Kill($true);throw 'WindowsRegistryClientTimeout'}
    $receipt.Windows=(Get-Content (Join-Path $windowsDirectory 'client-summary.json') -Raw -Encoding utf8 | ConvertFrom-Json).State
    if($windows.ExitCode -ne 0 -or $receipt.Windows -cne 'Success'){throw 'WindowsRegistryClientFailed'}
    $state.Passed++;Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
    $null=Invoke-GalleryNative @('create','--name',$client,'--network',$network,'-e','HOME=/tmp/probe-user','-e','XDG_DATA_HOME=/tmp/probe-user/data','--entrypoint','pwsh',$receipt.ClientId,'-File','/probe-client.ps1','-Uri','http://gallery/v3/index.json','-RunDirectory','/tmp/probe-results','-DependencyStrategy',$request.DependencyStrategy);$owned.Add('client')
    $null=Invoke-GalleryNative @('cp',$clientScript,($client+':/probe-client.ps1'))
    # No bind-mount assumption across a Windows/Podman VM.
    $linuxDirectory=Join-Path $RunDirectory 'linux-client';[void][IO.Directory]::CreateDirectory($linuxDirectory)
    try{$null=Invoke-GalleryNative @('start','-a',$client) -TimeoutSeconds 90}
    finally{$null=Invoke-GalleryNative @('cp',($client+':/tmp/probe-results/client-summary.json'),(Join-Path $linuxDirectory 'client-summary.json'))}
    $receipt.Linux=(Get-Content (Join-Path $linuxDirectory 'client-summary.json') -Raw -Encoding utf8 | ConvertFrom-Json).State
    if($receipt.Linux -cne 'Success'){throw 'LinuxRegistryClientFailed'}
    $state.Passed++;$state.State='Success';$state.Case='Windows and Linux roundtrips succeeded'
}catch{$state.State='Failed';$state.Failed++;$state.Error=$_.Exception.Message}
finally{
    if('server' -cin $owned){try{$null=Invoke-GalleryNative @('logs',$server)}catch{}}
    foreach($kind in @('client','server','volume','network')){
        if($kind -cnotin $owned){continue}
        try{
            $args= switch($kind){client {@('rm','-f',$client)} server {@('rm','-f',$server)} volume {@('volume','rm',$volume)} network {@('network','rm',$network)}}
            $null=Invoke-GalleryNative $args -TimeoutSeconds 20
            $receipt.Cleanup+=@("${kind}:Removed")
        }catch{$receipt.Cleanup+=@("${kind}:Failed");$state.State='Failed';$state.Failed++}
    }
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Receipt=$receipt;Scope='Exploratory compatibility only; persistent restart, malformed packages and full platform/mutation qualification remain separate.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
if($state.State -ne 'Success'){exit 1}
