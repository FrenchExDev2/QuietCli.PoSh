# Objectif : Compiler les bridges PTY Linux x64 et ARM64 depuis leur source C avec une toolchain vérifiée.
#requires -Version 7.6
<#
.SYNOPSIS
Builds static musl bridges for both Linux libc families without installing software on the host.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
.PARAMETER CompilerPath
Explicit Zig executable from the pinned version.
.PARAMETER DownloadCompiler
Explicitly downloads the checksum-pinned Windows Zig archive into workspace artifacts.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$CompilerPath,[switch]$DownloadCompiler)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
$lock=Get-Content (Join-Path $WorkspaceRoot 'build/zig.lock.json') -Encoding utf8 -Raw|ConvertFrom-Json
if(!$CompilerPath){
    if(!$IsWindows){throw 'Supply CompilerPath on Linux; no host installation is performed.'}
    $hostName=if([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -eq 'Arm64'){'aarch64-windows'}else{'x86_64-windows'}
    $tool=$lock.Hosts|Where-Object Host -CEQ $hostName
    $directory=Join-Path $WorkspaceRoot ('artifacts/toolchains/zig-'+$lock.Version+'-'+$hostName)
    if(!(Test-Path -LiteralPath $directory)){
        if(!$DownloadCompiler){throw 'Pinned compiler missing; use DownloadCompiler explicitly.'}
        $archive=$directory+'.zip';[void][IO.Directory]::CreateDirectory((Split-Path $directory -Parent))
        if($tool.Url -notmatch '^https://ziglang.org/download/[0-9.]+/zig-[a-z0-9_.-]+\.zip$'){throw 'UntrustedCompilerUrl'}
        Invoke-WebRequest -Uri $tool.Url -OutFile $archive -TimeoutSec 180
        if((Get-Item $archive).Length -ne $tool.Bytes -or (Get-FileHash $archive -Algorithm SHA256).Hash -cne $tool.SHA256){throw 'CompilerArchiveIntegrityFailed'}
        [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($archive,$directory,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    $candidates=@(Get-ChildItem $directory -Recurse -File -Filter zig.exe)
    if($candidates.Count -ne 1){throw 'CompilerExecutableAmbiguous'}
    $CompilerPath=$candidates[0].FullName
}
$version=@{Text=''}
$r=Invoke-CiProcess -FilePath $CompilerPath -ArgumentList @('version') -State $version -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Text=$e.Text.Trim()}}
if($r.Outcome -ne 'Success' -or $version.Text -cne $lock.Version){throw 'CompilerVersionMismatch'}
$module=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
$source=Join-Path $module 'native/quietcli-pty.c';$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash
$toolRoot=Split-Path $CompilerPath -Parent;$licenses=Join-Path $module 'third_party/quietcli-pty'
foreach($item in @(@{Source='LICENSE';Name='ZIG-LICENSE'},@{Source='lib/libc/musl/COPYRIGHT';Name='MUSL-COPYRIGHT'})){
    Copy-Item -LiteralPath (Join-Path $toolRoot $item.Source) -Destination (Join-Path $licenses $item.Name)
}
foreach($arch in @('x64','arm64')){
    $triple=if($arch -eq 'arm64'){'aarch64-linux-musl'}else{'x86_64-linux-musl'}
    $staging=Join-Path $WorkspaceRoot ('artifacts/pty-build/'+$arch);[void][IO.Directory]::CreateDirectory($staging)
    $binary=Join-Path $staging quietcli-pty
    $arguments=@('cc','-target',$triple,'-std=c11','-O2','-s','-Wall','-Wextra','-Werror','-fstack-protector-strong','-D_FORTIFY_SOURCE=2','-fPIE','-static','-pie','-Wl,-z,relro,-z,now','-pthread','-lutil',$source,'-o',$binary)
    $null=Invoke-WorkspaceNative $CompilerPath $arguments $WorkspaceRoot -TimeoutSeconds 600
    if((Get-FileHash $source -Algorithm SHA256).Hash -cne $sourceHash){throw 'BridgeSourcesChangedDuringBuild'}
    $hash=(Get-FileHash $binary -Algorithm SHA256).Hash
    foreach($rid in @(('linux-'+$arch),('linux-musl-'+$arch))){
        $directory=Join-Path $module ('resources/transport/'+$rid);[void][IO.Directory]::CreateDirectory($directory)
        Copy-Item $binary (Join-Path $directory quietcli-pty) -Force
        [void][IO.File]::WriteAllTextAsync((Join-Path $directory quietcli-pty.sha256),$hash,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        Write-WorkspaceJson (Join-Path $directory build.json) @{SchemaVersion=2;Runtime=$rid;Target=$triple;Compiler=('Zig '+$version.Text);ToolchainLockSHA256=(Get-FileHash (Join-Path $WorkspaceRoot 'build/zig.lock.json') -Algorithm SHA256).Hash;Arguments=@('cc','-target',$triple,'-std=c11','-O2','-s','-Wall','-Wextra','-Werror','-fstack-protector-strong','-D_FORTIFY_SOURCE=2','-fPIE','-static','-pie','-Wl,-z,relro,-z,now','-pthread','-lutil','native/quietcli-pty.c','-o','quietcli-pty');SourceSHA256=$sourceHash;ExecutableSHA256=$hash;Static=$true}
    }
}
$inventoryPath=Join-Path $module resources/dependencies.lock.json
$inventory=Get-Content $inventoryPath -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
$retained=@($inventory.Files|Where-Object Path -NotLike 'resources/transport/*')
$transport=@(Get-ChildItem (Join-Path $module resources/transport) -Recurse -File|ForEach-Object {@{Path=[IO.Path]::GetRelativePath($module,$_.FullName).Replace('\','/');SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash;Bytes=$_.Length;Package='quietcli-pty';Version='source-build';ReferencePath='native/quietcli-pty.c';AssemblyVersion=$null}})
$inventory.Files=$retained+$transport
$entry=$inventory.Packages|Where-Object Id -CEQ quietcli-pty
$entry.LicenseEvidence=@(Get-ChildItem $licenses -File|ForEach-Object {@{Path=[IO.Path]::GetRelativePath($module,$_.FullName).Replace('\','/');SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
$entry.Provenance='Built from bundled C source with the pinned Zig compiler; musl license retained.'
Write-WorkspaceJson $inventoryPath $inventory
Assert-QuietPtyPublications $WorkspaceRoot
[pscustomobject]@{Architectures=@('x64','arm64');Static=$true;Resources=$transport.Count;SourceSHA256=$sourceHash}
