# Objectif : Restaurer les binaires tiers non suivis par Git depuis leur source NuGet pinned, vérifiés par hash.
#requires -Version 7.6
<#
.SYNOPSIS
Restores Core's pinned managed and native third-party resources (SQLite, tokenizers, YamlDotNet) from
their recorded NuGet package sources in resources/dependencies.lock.json, verifying every restored
file's SHA256 against that lock. These binaries are not tracked in Git; this script is the only way to
populate them in a fresh checkout or CI runner. The source-built quietcli-pty binaries are untouched -
they come from scripts/Build-PtyBridge.ps1, not a downloaded package.
.PARAMETER WorkspaceRoot
QuietCli2 workspace (the module's parent directory).
.PARAMETER Force
Redownloads and re-extracts every package even when the local file already matches its pinned hash.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Force)
$ErrorActionPreference='Stop'
$moduleRoot=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
$lockPath=Join-Path $moduleRoot 'resources/dependencies.lock.json'
if(!(Test-Path -LiteralPath $lockPath)){throw 'DependencyManifestMissing'}
$lock=Get-Content -LiteralPath $lockPath -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
$packagesById=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($package in $lock.Packages){if($package.Id){$packagesById[$package.Id]=$package}}
$downloadable=@($lock.Files|Where-Object{$_.Package -ne 'quietcli-pty'})
$cacheRoot=Join-Path $WorkspaceRoot '.cache/nuget-resources'
[void][IO.Directory]::CreateDirectory($cacheRoot)
$restored=0;$reused=0
foreach($group in ($downloadable|Group-Object Package)){
    $packageId=$group.Name
    $package=$packagesById[$packageId]
    if(!$package -or !$package.Source){throw ('ResourcePackageSourceMissing: '+$packageId)}
    $pending=[Collections.Generic.List[object]]::new()
    foreach($file in $group.Group){
        $destination=Join-Path $moduleRoot $file.Path
        $current=if(!$Force -and (Test-Path -LiteralPath $destination)){(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}else{$null}
        if($current -ceq $file.SHA256){$reused++}else{[void]$pending.Add($file)}
    }
    if($pending.Count -eq 0){continue}
    $nupkgPath=Join-Path $cacheRoot ($packageId+'.'+$package.Version+'.nupkg')
    if($Force -or !(Test-Path -LiteralPath $nupkgPath)){
        $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromMinutes(5)
        $deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(5))
        try{
            $response=$client.GetAsync($package.Source,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$deadline.Token).GetAwaiter().GetResult()
            try{
                [void]$response.EnsureSuccessStatusCode()
                $input=$response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
                $output=[IO.FileStream]::new($nupkgPath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,$true)
                try{[void]$input.CopyToAsync($output,$deadline.Token).WaitAsync($deadline.Token).GetAwaiter().GetResult()}finally{$output.Dispose();$input.Dispose()}
            }finally{$response.Dispose()}
        }finally{$deadline.Dispose();$client.Dispose()}
    }
    $archive=[IO.Compression.ZipFile]::OpenRead($nupkgPath)
    try{
        foreach($file in $pending){
            $match=$null
            foreach($entry in $archive.Entries){
                if($entry.Length -ne $file.Bytes){continue}
                $probe=$entry.Open()
                try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($probe))}finally{$probe.Dispose()}
                if($hash -ceq $file.SHA256){$match=$entry;break}
            }
            if(!$match){throw ('ResourceNotFoundInPackage: '+$file.Path+' ('+$packageId+')')}
            $destination=Join-Path $moduleRoot $file.Path
            [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
            $entryStream=$match.Open()
            try{
                $output=[IO.FileStream]::new($destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,$true)
                try{[void]$entryStream.CopyToAsync($output).GetAwaiter().GetResult()}finally{$output.Dispose()}
            }finally{$entryStream.Dispose()}
            $restored++
        }
    }finally{$archive.Dispose()}
}
[pscustomobject]@{Restored=$restored;Reused=$reused;Total=$downloadable.Count}
