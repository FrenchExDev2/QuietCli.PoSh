#requires -Version 7.6
<#
.SYNOPSIS
Checks runtime XML and SDK/base-image lock synchronization with bounded offline evidence.
.PARAMETER ModulePath
Lock library under test.
.PARAMETER NoMutations
Disables recursive mutant generation.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$ModulePath=(Join-Path $PSScriptRoot '../scripts/lib/DotNetLocks.psm1'),[switch]$NoMutations)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Run offline .NET lock properties, malformed documents and targeted mutants')){return}
$ErrorActionPreference='Stop'
$module=Import-Module $ModulePath -Force -PassThru
$root=Join-Path ([IO.Path]::GetTempPath()) ('quiet-dotnet-locks-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $root 'build'))
$assertions=0
function Assert-DotNetLocks {
    <#
    .SYNOPSIS
    Requires an independently specified lock or runtime invariant.
    #>
    param([bool]$Condition,[string]$Message)
    $script:assertions++
    if(!$Condition){throw "Assertion failed: $Message"}
}
function Assert-LockRejection {
    <#
    .SYNOPSIS
    Requires invalid input or unavailable evidence to fail before acceptance.
    #>
    param([scriptblock]$Operation,[string]$Message)
    $failed=$false;try{$null=& $Operation}catch{$failed=$true}
    Assert-DotNetLocks $failed $Message
}
function Write-LockFixture {
    <#
    .SYNOPSIS
    Writes owned deterministic UTF-8/LF fixture data.
    #>
    param([string]$Path,$Value)
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}
try {
    & $module {
        $script:Calls=0;$script:BadHash=$false;$script:BadUri=$false;$script:MissingArchive=$false
        $script:RegistryFailure=$false;$script:BadDigest=$false;$script:MissingPlatform=$false
        function script:Get-DotNetSdkRelease {
            <#
            .SYNOPSIS
            Supplies canonical official-shaped SDK archive records without network access.
            #>
            param($Channel,$Version,$Preleases,$Confirm)
            $script:Calls++
            $files=@(foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64','win-x64','win-arm64')){
                if($script:MissingArchive -and $rid -eq 'linux-arm64'){continue}
                $ext=if($rid.StartsWith('win-')){'zip'}else{'tar.gz'}
                @{rid=$rid;name="dotnet-sdk-$rid.$ext";url=$(if($script:BadUri){'https://untrusted.invalid/sdk'}else{"https://builds.dotnet.microsoft.com/dotnet/Sdk/$Version/dotnet-sdk-$Version-$rid.$ext"});hash=$(if($script:BadHash){'invalid'}else{'a'*128})}
            })
            @{Version=$Version;RuntimeVersion='11.0.0';Files=$files}
        }
        function script:Get-DotNetRuntimeRelease {
            <#
            .SYNOPSIS
            Supplies the separately pinned Alpine PowerShell runtime archive records.
            #>
            param($Version,$Confirm)
            $script:Calls++
            @{Version=$Version;Files=@(foreach($rid in @('linux-musl-x64','linux-musl-arm64')){
                @{rid=$rid;name="dotnet-runtime-$rid.tar.gz";url="https://builds.dotnet.microsoft.com/dotnet/Runtime/$Version/dotnet-runtime-$Version-$rid.tar.gz";hash=('b'*128)}
            })}
        }
        function script:Invoke-DotNetRegistryHttp {
            <#
            .SYNOPSIS
            Models authenticated multi-platform index and bounded tag-list metadata.
            #>
            param($Uri,$Bearer)
            $script:Calls++
            if($script:RegistryFailure){throw 'Synthetic registry HTTP 429.'}
            if(([uri]$Uri).Host -eq 'auth.docker.io'){return @{Body='{"token":"fixture-token"}';Digest=$null;BodySha256=$null}}
            if(([uri]$Uri).Host -eq 'hub.docker.com'){return @{Body='{"results":[{"name":"bookworm-slim","digest":"sha256:fixture","images":[{"os":"linux","architecture":"amd64"}],"last_updated":"2026-11-10T00:00:00Z"}],"next":null}'}}
            if($Bearer -cne 'fixture-token'){throw 'Registry fixture did not receive its scoped token.'}
            $platforms=@(@{platform=@{os='linux';architecture='amd64'};digest=('sha256:'+('c'*64))})
            if(!$script:MissingPlatform){$platforms+=@{platform=@{os='linux';architecture='arm64'};digest=('sha256:'+('d'*64))}}
            $body=@{schemaVersion=2;manifests=$platforms}|ConvertTo-Json -Depth 10 -Compress
            $hash='sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($body)))).ToLowerInvariant()
            @{Body=$body;BodySha256=$hash;Digest=$(if($script:BadDigest){'sha256:'+('0'*64)}else{$hash})}
        }
    }
    $ciPath=Join-Path $root 'build/ci-images.lock.json';$devPath=Join-Path $root 'build/development-workstation.lock.json'
    Write-LockFixture (Join-Path $root 'global.json') @{sdk=@{version='11.0.100'}}
    $ci=@{SchemaVersion=2;SDK='11.0.100-rc.3';AlpineRuntime='10.0.14';AlpinePowerShellPackage='7.6.9-r0';Custom='été';Platforms=@(foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
        $image=if($rid.StartsWith('linux-musl-')){'alpine'}else{'debian'};$tag=if($image -eq 'alpine'){'3.24'}else{'bookworm-slim'}
        @{Rid=$rid;Platform=$image;Architecture=$(if($rid.EndsWith('arm64')){'arm64'}else{'x64'});Base="docker.io/library/${image}:${tag}@sha256:$('0'*64)";SDK_SHA512=('0'*128);Runtime_SHA512=('0'*128);PowerShell='7.6.7';PowerShell_SHA256=('c'*64)}
    })}
    $dev=@{SchemaVersion=1;SdkVersion='11.0.100-rc.3';GitVersion='keep-me';WindowsSdks=@(@{Rid='win-x64';SHA512=('0'*128)},@{Rid='win-arm64';SHA512=('0'*128)})}
    Write-LockFixture $ciPath $ci;Write-LockFixture $devPath $dev
    $old=(Get-FileHash $ciPath -Algorithm SHA256).Hash;$calls=& $module {$script:Calls}
    $previewError=$null;try{$null=Update-DotNetCiLock -WorkspaceRoot $root -RefreshBaseImages -IncludeDevelopmentLock -WhatIf}catch{$previewError=$_}
    Assert-DotNetLocks (!$previewError -and (& $module {$script:Calls}) -eq $calls -and (Get-FileHash $ciPath -Algorithm SHA256).Hash -eq $old) 'WhatIf performs no metadata/registry calls or lock writes.'
    $plans=@(Update-DotNetCiLock -WorkspaceRoot $root -RefreshBaseImages -IncludeDevelopmentLock -PlanOnly -Confirm:$false)
    Assert-DotNetLocks ($plans.Count -eq 2 -and (Get-FileHash $ciPath -Algorithm SHA256).Hash -eq $old) 'PlanOnly resolves evidence without writing.'
    $result=@(Update-DotNetCiLock -WorkspaceRoot $root -RefreshBaseImages -IncludeDevelopmentLock -Confirm:$false)
    $saved=Get-Content $ciPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    $savedDev=Get-Content $devPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    Assert-DotNetLocks ($result.Count -eq 2 -and $saved.SDK -eq '11.0.100' -and $savedDev.SdkVersion -eq '11.0.100') 'Both selected SDK locks match the exact global.json SDK.'
    Assert-DotNetLocks (@($saved.Platforms|Where-Object SDK_SHA512 -ne ('a'*128)).Count -eq 0 -and @($savedDev.WindowsSdks|Where-Object SHA512 -ne ('a'*128)).Count -eq 0) 'All four Linux archives and both Windows ZIP hashes use the correct metadata.'
    Assert-DotNetLocks ($saved.Custom -eq 'été' -and $saved.AlpineRuntime -eq '10.0.14' -and $savedDev.GitVersion -eq 'keep-me' -and $saved.Platforms[0].PowerShell -eq '7.6.7') 'SDK updates preserve independently pinned PowerShell, OS tags and unrelated tools.'
    Assert-DotNetLocks ((Get-FileHash $result[0].BackupPath -Algorithm SHA256).Hash -eq $old) 'Lock backup preserves exact original bytes.'
    $again=@(Update-DotNetCiLock -WorkspaceRoot $root -RefreshBaseImages -IncludeDevelopmentLock -Confirm:$false)
    Assert-DotNetLocks (@($again|Where-Object Status -ne Unchanged).Count -eq 0) 'Idempotent lock synchronization makes no backup or rewrite.'
    foreach($flag in @('BadHash','BadUri','MissingArchive','RegistryFailure','BadDigest','MissingPlatform')){
        & $module {param($name) Set-Variable -Scope Script -Name $name -Value $true} $flag
        $before=(Get-FileHash $ciPath -Algorithm SHA256).Hash
        Assert-LockRejection {Update-DotNetCiLock -WorkspaceRoot $root -RefreshBaseImages -IncludeDevelopmentLock -Confirm:$false} "Invalid or unavailable $flag evidence blocks the selected batch."
        Assert-DotNetLocks ((Get-FileHash $ciPath -Algorithm SHA256).Hash -eq $before) 'Failed validation preserves current locks.'
        & $module {param($name) Set-Variable -Scope Script -Name $name -Value $false} $flag
    }
    $tags=@(Get-DotNetBaseImageTags -Image debian -Name bookworm -Limit 2 -Confirm:$false)
    Assert-DotNetLocks ($tags.Count -eq 1 -and $tags[0].Tag -eq 'bookworm-slim' -and !$tags[0].HasMore) 'Tag discovery returns bounded metadata without layers.'
    $project=Join-Path $root 'fixture.csproj'
    $text=@'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net10.0;net11.0</TargetFrameworks>
<!-- preserve the old version in comments: 11.0.0-rc.3 -->
<RuntimeFrameworkVersion Condition="'$(TargetFramework)' == 'net10.0'">10.0.14</RuntimeFrameworkVersion>
<RuntimeFrameworkVersion Condition="'$(TargetFramework)' == 'net11.0'">11.0.0-rc.3</RuntimeFrameworkVersion>
</PropertyGroup></Project>
'@
    [IO.File]::WriteAllText($project,$text,[Text.UTF8Encoding]::new($false))
    $plan=Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $root -Path $project -Version 11.0.0
    Assert-DotNetLocks ($plan.Edits.Count -eq 1 -and $plan.Text.Contains('>10.0.14</RuntimeFrameworkVersion>') -and $plan.Text.Contains('comments: 11.0.0-rc.3')) 'Only the selected runtime property value changes, preserving other frameworks and comments.'
    $before=(Get-FileHash $project -Algorithm SHA256).Hash
    $calls=& $module {$script:Calls}
    $null=Update-DotNetRuntimeFrameworkVersion -WorkspaceRoot $root -WhatIf
    Assert-DotNetLocks ((& $module {$script:Calls}) -eq $calls -and (Get-FileHash $project -Algorithm SHA256).Hash -eq $before) 'Runtime preview makes no metadata query or project write.'
    $updated=@(Update-DotNetRuntimeFrameworkVersion -WorkspaceRoot $root -Path $project -Version 11.0.0 -Confirm:$false)
    Assert-DotNetLocks ($updated[0].Status -eq 'Updated' -and (Get-FileHash $updated[0].BackupPath -Algorithm SHA256).Hash -eq $before) 'Runtime updater backs up original project bytes before replacement.'
    Assert-DotNetLocks ((Update-DotNetRuntimeFrameworkVersion -WorkspaceRoot $root -Path $project -Version 11.0.0 -Confirm:$false).Status -eq 'Unchanged') 'Runtime update is idempotent.'
    [IO.File]::WriteAllText($project,$text.Replace('11.0.0-rc.3','11.0.2'),[Text.UTF8Encoding]::new($false))
    Assert-LockRejection {Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $root -Path $project -Version 11.0.0} 'Runtime downgrades require explicit permission.'
    $random=[Random]::new(110105)
    foreach($case in 1..60){
        $number=$random.Next();$xml="<Project><PropertyGroup><TargetFramework>net11.0</TargetFramework><Custom>été-$number</Custom><RuntimeFrameworkVersion>11.0.0-rc.3</RuntimeFrameworkVersion></PropertyGroup></Project>"
        [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
        $p=Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $root -Path $project -Version 11.0.0
        Assert-DotNetLocks ($p.Text -ceq $xml.Replace('>11.0.0-rc.3<','>11.0.0<')) "Generated XML preservation property seed 110105 case $case."
    }
    $badXml=@('<Project>','<Project><RuntimeFrameworkVersion>broken</RuntimeFrameworkVersion>', '<!DOCTYPE Project [<!ENTITY x SYSTEM "file:///forbidden">]><Project>&x;</Project>',
        '<Project><PropertyGroup><TargetFrameworks>net10.0;net11.0</TargetFrameworks><RuntimeFrameworkVersion>11.0.0-rc.3</RuntimeFrameworkVersion></PropertyGroup></Project>')
    foreach($bad in $badXml){[IO.File]::WriteAllText($project,$bad,[Text.UTF8Encoding]::new($false));Assert-LockRejection {Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $root -Path $project -Version 11.0.0} 'Malformed, external-entity or ambiguous XML cannot be updated.'}
    foreach($case in 1..100){
        [IO.File]::WriteAllText($project,('<Project><Broken'+$random.Next()),[Text.UTF8Encoding]::new($false))
        Assert-LockRejection {Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $root -Path $project -Version 11.0.0} "Generated malformed XML seed 110105 case $case."
    }
    # A portable SDK must never become a source/build identity input.
    . (Join-Path $PSScriptRoot '../scripts/SourceIdentity.ps1')
    $ignored=Join-Path $root '.dotnet';$null=[IO.Directory]::CreateDirectory($ignored)
    [IO.File]::WriteAllText((Join-Path $ignored 'sdk-marker'),'ignored',[Text.UTF8Encoding]::new($false))
    Assert-DotNetLocks (@(Get-QuietSourceFiles $root|Where-Object Path -Like '.dotnet/*').Count -eq 0) 'Portable SDK payloads are pruned before source hashing.'
    Assert-DotNetLocks (@(Get-QuietSourceFiles $root|Where-Object Path -Match '\.(json|csproj|props)\.bak-').Count -eq 0) 'Generated original-byte backups are excluded from source/build identities.'
    $metadataRoot=Join-Path $root 'workspace-lock'
    $null=[IO.Directory]::CreateDirectory((Join-Path $metadataRoot 'scripts'))
    $null=[IO.Directory]::CreateDirectory((Join-Path $metadataRoot 'FrenchExDev2.QuietCli.Core.PoSh/engine'))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../scripts/Update-WorkspaceLock.ps1') -Destination (Join-Path $metadataRoot 'scripts/Update-WorkspaceLock.ps1')
    $common=@'
function Get-QuietWorkspaceIdentity { param($WorkspaceRoot) @{Projects=@();Repository=@{Name='fixture';Remote='fixture';SourceSHA256=('a'*64)}} }
function Get-QuietWorkspaceProjects { param($WorkspaceRoot) }
function Write-WorkspaceJson { param($Path,$Value) [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false)) }
'@
    [IO.File]::WriteAllText((Join-Path $metadataRoot 'scripts/Common.ps1'),$common,[Text.UTF8Encoding]::new($false))
    foreach($case in 1..60){
        $sdkVersion='11.0.'+$random.Next(100,900);$runtimeVersion='11.0.'+$random.Next(0,99)
        Write-LockFixture (Join-Path $metadataRoot 'global.json') @{sdk=@{version=$sdkVersion}}
        $xml='<Project><PropertyGroup><RuntimeFrameworkVersion Condition="''$(TargetFramework)'' == ''net11.0''">'+$runtimeVersion+'</RuntimeFrameworkVersion></PropertyGroup></Project>'
        [IO.File]::WriteAllText((Join-Path $metadataRoot 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'),$xml,[Text.UTF8Encoding]::new($false))
        $null=& (Join-Path $metadataRoot 'scripts/Update-WorkspaceLock.ps1') -WorkspaceRoot $metadataRoot -Confirm:$false
        $generated=Get-Content (Join-Path $metadataRoot 'repositories.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
        Assert-DotNetLocks ($generated.SDK -eq $sdkVersion -and $generated.Runtime -eq $runtimeVersion) "Generated workspace lock follows SDK/runtime source pins case $case."
    }
    $killed=0
    if(!$NoMutations){
        $source=Get-Content $ModulePath -Raw -Encoding utf8
        $mutations=@(
            @('digest-integrity','$manifest.Digest -cne $manifest.BodySha256','$false'),
            @('runtime-scope','$selected=$condition -match $pattern','$selected=$true'),
            @('downgrade','if(!$AllowDowngrade -and $semantic -lt $previous)','if($false)'),
            @('preview',"if(!`$PSCmdlet.ShouldProcess(`$root,'Resolve official SDK/runtime metadata and requested base digests; update selected locks with backups'))",'if($false)'),
            @('idempotence','if(!$plan.Changed)','if($false)')
        )
        foreach($mutation in $mutations){
            if(!$source.Contains($mutation[1])){throw "Invalid lock mutation anchor: $($mutation[0])"}
            $mutantRoot=Join-Path $root ('mutant-'+$mutation[0]);$null=[IO.Directory]::CreateDirectory($mutantRoot)
            $mutant=Join-Path $mutantRoot 'DotNetLocks.psm1'
            Copy-Item -LiteralPath (Join-Path (Split-Path $ModulePath -Parent) 'DotNetReadiness.psm1') -Destination $mutantRoot
            [IO.File]::WriteAllText($mutant,$source.Replace($mutation[1],$mutation[2]),[Text.UTF8Encoding]::new($false))
            $detected=$false
            try{$null=& $PSCommandPath -ModulePath $mutant -NoMutations -Confirm:$false}catch{
                if($_.Exception.Message -notlike 'Assertion failed:*'){throw "Invalid/crashed lock mutant $($mutation[0]): $($_.Exception.Message)"}
                $detected=$true
            }
            if(!$detected){throw "Surviving lock mutant: $($mutation[0])"}
            $killed++;Write-Output "Killed lock mutant: $($mutation[0])"
        }
    }
    [pscustomobject]@{State='Passed';Assertions=$assertions;PropertyCases=120;FuzzCases=104;MutantsKilled=$killed;Seed=110105}
}finally{
    Remove-Module $module -Force -ErrorAction SilentlyContinue
    $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path $resolved -Parent) -ne $temp -or (Split-Path $resolved -Leaf) -notmatch '^quiet-dotnet-locks-[a-f0-9]{32}$'){throw 'Unsafe lock fixture cleanup.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
