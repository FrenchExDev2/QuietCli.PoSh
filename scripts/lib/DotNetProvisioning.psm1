#Requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'DotNetReadiness.psm1') -ErrorAction Stop

function Assert-DotNetSdkVersion {
    <# .SYNOPSIS Rejects incomplete SDK versions, wrong channels and unapproved prereleases. #>
    param([string]$Version,[string]$Channel,[switch]$Preleases)
    if ($Version -notmatch '^[1-9][0-9]*\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') { throw 'Version must be a complete SDK version.' }
    $parsed=[System.Management.Automation.SemanticVersion]$Version
    if ("$($parsed.Major).$($parsed.Minor)" -ne $Channel) { throw 'Version does not belong to Channel.' }
    if ($parsed.PreReleaseLabel -and !$Preleases) { throw 'A prerelease SDK requires -Preleases.' }
}

function Assert-DotNetJsonKeys {
    <# .SYNOPSIS Rejects duplicate JSON properties before a document can lose information. #>
    param([System.Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Element.EnumerateObject()) {
            if(!$names.Add($property.Name)){throw "Duplicate JSON property: $($property.Name)"}
            Assert-DotNetJsonKeys -Element $property.Value
        }
    }
    elseif($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach($elementItem in $Element.EnumerateArray()){Assert-DotNetJsonKeys -Element $elementItem}
    }
}

function Get-DotNetGlobalJsonPlan {
    <#
    .SYNOPSIS
    Builds a validated global.json update without changing any files.
    .PARAMETER Path
    Exact files; discovery and ancestor traversal are never implicit.
    .PARAMETER Version
    Complete target SDK version.
    .PARAMETER Channel
    Expected major.minor channel.
    .PARAMETER Preleases
    Sets sdk.allowPrerelease and permits preview/RC versions.
    .PARAMETER RollForward
    Optional replacement; existing policy is preserved when omitted.
    .PARAMETER SdkDirectory
    Optional portable SDK directory, added as a relative sdk.paths entry.
    .PARAMETER Create
    Permits creation of explicitly named missing global.json files.
    .PARAMETER AllowDowngrade
    Permits lowering an existing SDK pin.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Path,[Parameter(Mandatory)][string]$Version,
        [ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel='11.0',
        [Alias('Prerelease','Prereleases')][switch]$Preleases,
        [ValidateSet('patch','feature','minor','major','latestPatch','latestFeature','latestMinor','latestMajor','disable')][string]$RollForward,
        [string]$SdkDirectory,[switch]$Create,[switch]$AllowDowngrade)
    Assert-DotNetSdkVersion -Version $Version -Channel $Channel -Preleases:$Preleases
    foreach($target in @($Path|ForEach-Object {$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_)}|Select-Object -Unique)) {
        if([IO.Path]::GetFileName($target) -cne 'global.json'){throw 'Targets must be exact global.json paths.'}
        $parent=Split-Path $target -Parent
        if(!(Test-Path -LiteralPath $parent -PathType Container)){throw "Missing target parent: $parent"}
        $exists=Test-Path -LiteralPath $target -PathType Leaf
        if(!$exists -and !$Create){throw "Missing global.json; use -Create to create it: $target"}
        $original=$null
        $originalHash=$null
        if($exists) {
            if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'A global.json target cannot be a symbolic link.'}
            $bytes=[IO.File]::ReadAllBytes($target)
            $originalHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            $original=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
            $parseOptions=[System.Text.Json.JsonDocumentOptions]::new()
            $parseOptions.CommentHandling=[System.Text.Json.JsonCommentHandling]::Skip
            $parseOptions.AllowTrailingCommas=$true
            $document=[System.Text.Json.JsonDocument]::Parse($original,$parseOptions)
            try {
                if($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object){throw 'global.json root must be an object.'}
                Assert-DotNetJsonKeys -Element $document.RootElement
            }finally{$document.Dispose()}
            $data=ConvertFrom-Json -InputObject $original -AsHashtable -Depth 64 -ErrorAction Stop
        }else{$data=[ordered]@{}}
        if($data.Contains('sdk') -and $data['sdk'] -isnot [Collections.IDictionary]){throw 'sdk must be a JSON object.'}
        if(!$data.Contains('sdk')){$data['sdk']=[ordered]@{}}
        $before=$data|ConvertTo-Json -Depth 64 -Compress
        $sdk=$data['sdk']
        $previous=$sdk['version']
        if($previous) {
            $old=[System.Management.Automation.SemanticVersion]$previous
            if(!$AllowDowngrade -and [System.Management.Automation.SemanticVersion]$Version -lt $old){throw "Downgrade blocked: $previous -> $Version ($target). Use -AllowDowngrade explicitly."}
        }
        $sdk['version']=$Version
        $sdk['allowPrerelease']=[bool]$Preleases
        if($RollForward){$sdk['rollForward']=$RollForward}
        elseif(!$sdk.Contains('rollForward')){$sdk['rollForward']='latestFeature'}
        if($SdkDirectory) {
            $relative=[IO.Path]::GetRelativePath($parent,$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SdkDirectory)).Replace('\','/')
            if($sdk.Contains('paths') -and $sdk['paths'] -isnot [array]){throw 'sdk.paths must be a JSON array.'}
            $oldPaths=if($sdk.Contains('paths')){@($sdk['paths'])}else{@()}
            if(@($oldPaths|Where-Object {$_ -isnot [string]}).Count){throw 'sdk.paths must contain strings.'}
            $sdk['paths']=@(@($relative)+@($oldPaths)+@('$host$')|Select-Object -Unique)
        }
        $after=$data|ConvertTo-Json -Depth 64 -Compress
        [pscustomobject]@{Path=$target;Version=$Version;PreviousVersion=$previous;Changed=(!$exists -or $before -cne $after);
            Exists=$exists;OriginalHash=$originalHash;Json=($data|ConvertTo-Json -Depth 64).Replace("`r`n","`n")+"`n"}
    }
}

function Write-DotNetGlobalJsonPlan {
    <# .SYNOPSIS Backs up original bytes and atomically writes one prevalidated document. #>
    param([Parameter(Mandatory)]$Plan)
    $temporary=$Plan.Path+'.writing-'+[guid]::NewGuid().ToString('N')
    $backup=$null
    try {
        if($Plan.Exists) {
            $current=(Get-FileHash -LiteralPath $Plan.Path -Algorithm SHA256).Hash
            if($current -ne $Plan.OriginalHash){throw "global.json changed after planning: $($Plan.Path)"}
            $backup=$Plan.Path+'.bak-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'-'+[guid]::NewGuid().ToString('N')
            [IO.File]::Copy($Plan.Path,$backup,$false)
        }
        elseif(Test-Path -LiteralPath $Plan.Path){throw 'A global.json target was created after planning.'}
        $null=[IO.File]::WriteAllTextAsync($temporary,$Plan.Json,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        if($Plan.Exists -and (Get-FileHash -LiteralPath $Plan.Path -Algorithm SHA256).Hash -ne $Plan.OriginalHash){throw 'global.json changed before replacement.'}
        [IO.File]::Move($temporary,$Plan.Path,$Plan.Exists)
        [pscustomobject]@{Path=$Plan.Path;Version=$Plan.Version;PreviousVersion=$Plan.PreviousVersion;Status='Updated';BackupPath=$backup}
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}

function Update-DotNetGlobalJson {
    <#
    .SYNOPSIS
    Verifies an installed SDK, then backs up and updates exact global.json targets.
    .DESCRIPTION
    WhatIf does no HTTP/native probes or writes. Explicit versions can be planned offline.
    Unrelated JSON values and an existing rollForward policy are preserved.
    .PARAMETER Path
    Exact global.json files. Defaults to this checkout's root global.json.
    .PARAMETER Version
    Complete SDK version; omitted means latest eligible published SDK in Channel.
    .PARAMETER Channel
    Requested channel, default 11.0.
    .PARAMETER Preleases
    Permits preview/RC versions and sets allowPrerelease to true.
    .PARAMETER RollForward
    Optional policy override; otherwise preserved or latestFeature for a new policy.
    .PARAMETER SdkDirectory
    Optional local SDK search directory; adds a relative sdk.paths entry and $host$.
    .PARAMETER DotNetPath
    Host used to verify that the exact SDK version is installed.
    .PARAMETER SkipInstalledCheck
    Explicitly permits a pin without verifying local installation, for CI preparation.
    .PARAMETER Create
    Permits creating an explicitly named missing file.
    .PARAMETER AllowDowngrade
    Explicitly permits lowering existing SDK versions.
    .PARAMETER QuietCliRoot
    Selected checkout providing engine-independent process infrastructure.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([ValidateNotNullOrEmpty()][string[]]$Path=@((Join-Path $PSScriptRoot '../../global.json')),
        [string]$Version,[ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel='11.0',
        [Alias('Prerelease','Prereleases')][switch]$Preleases,
        [ValidateSet('patch','feature','minor','major','latestPatch','latestFeature','latestMinor','latestMajor','disable')][string]$RollForward,
        [string]$SdkDirectory,[string]$DotNetPath='dotnet',[switch]$SkipInstalledCheck,[switch]$Create,[switch]$AllowDowngrade,
        [string]$QuietCliRoot=(Join-Path $PSScriptRoot '../..'))
    $planOptions=@{Path=$Path;Channel=$Channel;Preleases=$Preleases;Create=$Create;AllowDowngrade=$AllowDowngrade}
    if($SdkDirectory){$planOptions.SdkDirectory=$SdkDirectory}
    if($RollForward){$planOptions.RollForward=$RollForward}
    $plans=if($Version){@(Get-DotNetGlobalJsonPlan @planOptions -Version $Version)}else{@()}
    if(!$PSCmdlet.ShouldProcess(($Path -join ', '),"Verify SDK $(if($Version){$Version}else{"latest eligible $Channel"}); back up and update global.json")) {
        foreach($target in $Path){[pscustomobject]@{Path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($target);Version=$Version;Status='NotApplied';BackupPath=$null}}
        return
    }
    if(!$Version){$Version=(Get-DotNetSdkRelease -Channel $Channel -Preleases:$Preleases -Confirm:$false).Version; $plans=@(Get-DotNetGlobalJsonPlan @planOptions -Version $Version)}
    if(!$SkipInstalledCheck) {
        $inventory=Get-DotNetInstallation -DotNetPath $DotNetPath -QuietCliRoot $QuietCliRoot -Confirm:$false
        if(!$inventory.Sdk.Success -or $Version -notin @($inventory.Sdk.Records|ForEach-Object Version)){throw "Exact SDK $Version is not verified as installed using $DotNetPath. Install it first or explicitly use -SkipInstalledCheck."}
    }
    foreach($plan in $plans) {
        if(!$plan.Changed){[pscustomobject]@{Path=$plan.Path;Version=$Version;PreviousVersion=$plan.PreviousVersion;Status='Unchanged';BackupPath=$null};continue}
        Write-DotNetGlobalJsonPlan -Plan $plan
    }
}

function Save-DotNetSdkArchive {
    <# .SYNOPSIS Streams a trusted SDK archive to a new file with a bounded download duration. #>
    param([uri]$Uri,[string]$Destination,[int]$TimeoutSeconds)
    if($Uri.Scheme -ne 'https' -or $Uri.Host -notin @('builds.dotnet.microsoft.com','download.visualstudio.microsoft.com','dotnetcli.azureedge.net')){throw 'Untrusted SDK archive URL.'}
    $client=[Net.Http.HttpClient]::new()
    $cancel=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
    $response=$null;$stream=$null;$file=$null
    try {
        $response=$client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token).GetAwaiter().GetResult()
        $null=$response.EnsureSuccessStatusCode()
        if($response.RequestMessage.RequestUri.Scheme -ne 'https' -or $response.RequestMessage.RequestUri.Host -notin @('builds.dotnet.microsoft.com','download.visualstudio.microsoft.com','dotnetcli.azureedge.net')){throw 'Untrusted SDK download redirect.'}
        $stream=$response.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
        $file=[IO.FileStream]::new($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,81920,$true)
        $null=$stream.CopyToAsync($file,$cancel.Token).GetAwaiter().GetResult()
    }finally{if($file){$file.Dispose()};if($stream){$stream.Dispose()};if($response){$response.Dispose()};$cancel.Dispose();$client.Dispose()}
}

function Expand-DotNetSdkArchive {
    <# .SYNOPSIS Extracts a verified SDK archive into an isolated empty staging directory. #>
    param([string]$Archive,[string]$Destination)
    if($Archive.EndsWith('.zip')) {
        $null=[IO.Compression.ZipFile]::ExtractToDirectoryAsync($Archive,$Destination,$false,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    else {
        $file=[IO.File]::OpenRead($Archive)
        $gzip=[IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionMode]::Decompress)
        try{$null=[System.Formats.Tar.TarFile]::ExtractToDirectoryAsync($gzip,$Destination,$false,[Threading.CancellationToken]::None).GetAwaiter().GetResult()}
        finally{$gzip.Dispose();$file.Dispose()}
    }
}

function Assert-DotNetInstalledPayload {
    <# .SYNOPSIS Requires complete SDK/core/ASP.NET inventories and Windows Desktop where applicable. #>
    param([string]$DotNetPath,[string]$Version,[string]$RuntimeVersion,[string]$QuietCliRoot)
    $inventory=Get-DotNetInstallation -DotNetPath $DotNetPath -QuietCliRoot $QuietCliRoot -Confirm:$false
    if(!$inventory.Sdk.Success -or !$inventory.Runtime.Success -or $Version -notin @($inventory.Sdk.Records|ForEach-Object Version)){throw 'Installed SDK verification failed or was incomplete.'}
    $required=@('Microsoft.NETCore.App','Microsoft.AspNetCore.App')
    if($IsWindows){$required+='Microsoft.WindowsDesktop.App'}
    foreach($name in $required) {
        if(!@($inventory.Runtime.Records|Where-Object {$_.Name -eq $name -and $_.Version -eq $RuntimeVersion}).Count){throw "Required runtime not verified: $name $RuntimeVersion"}
    }
}

function Resolve-DotNetContainerRuntime {
    <#
    .SYNOPSIS
    Reuses the checkout's explicit/dotenv/discovery contract without starting a daemon.
    .PARAMETER ContainerRuntime
    Optional explicit docker/podman override.
    .PARAMETER WorkspaceRoot
    Checkout owning Common.ps1 and the runtime dotenv setting.
    #>
    param([AllowEmptyString()][string]$ContainerRuntime,[string]$WorkspaceRoot)
    $WorkspaceRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceRoot)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -Available -WorkspaceRoot $WorkspaceRoot
}

function Install-DotNetEnvironment {
    <#
    .SYNOPSIS
    Installs a verified portable SDK, optionally pulls images and updates SDK pins.
    .DESCRIPTION
    Each SDK has its own version directory. SHA-512 is checked before extraction;
    SDK/core/ASP.NET/Desktop inventories must succeed before promotion. WhatIf has
    no HTTP/native calls, staging directories, environment edits or source writes.
    .PARAMETER Channel
    Requested major.minor channel, default 11.0.
    .PARAMETER Version
    Optional exact published SDK version, otherwise latest eligible version.
    .PARAMETER Preleases
    Permits published preview/RC SDKs.
    .PARAMETER InstallRoot
    Parent for isolated version directories. Defaults to this checkout's .dotnet.
    .PARAMETER UpdateGlobalJson
    Updates only GlobalJsonPath after installation and optional image pulls succeed.
    .PARAMETER GlobalJsonPath
    Exact pin files, defaults to this checkout's root global.json.
    .PARAMETER PullImages
    Pulls SDK/runtime/ASP.NET/runtime-deps using shared runtime configuration.
    .PARAMETER ContainerRuntime
    Optional docker/podman override; otherwise checkout dotenv and discovery apply.
    .PARAMETER Platform
    Platforms to pull. Defaults to Linux amd64.
    .PARAMETER ImageVariant
    Optional official image tag suffix.
    .PARAMETER ActivateSession
    Prepends the installed SDK directory to this process PATH and sets DOTNET_ROOT.
    .PARAMETER AllowDowngrade
    Explicitly permits lowering selected global.json pins.
    .PARAMETER DownloadTimeoutSeconds
    Bounded SDK download duration; default 900 seconds.
    .PARAMETER QuietCliRoot
    Selected checkout providing the shared process and runtime-resolution helpers.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel='11.0',[string]$Version,
        [Alias('Prerelease','Prereleases')][switch]$Preleases,
        [string]$InstallRoot=(Join-Path $PSScriptRoot '../../.dotnet'),
        [switch]$UpdateGlobalJson,[string[]]$GlobalJsonPath=@((Join-Path $PSScriptRoot '../../global.json')),
        [switch]$PullImages,[ValidateSet('docker','podman')][string]$ContainerRuntime,
        [ValidateNotNullOrEmpty()][ValidateSet('linux/amd64','linux/arm64','windows/amd64','windows/arm64')][string[]]$Platform=@('linux/amd64'),
        [ValidatePattern('^$|^[a-z0-9][a-z0-9.-]*$')][string]$ImageVariant='',
        [switch]$ActivateSession,[switch]$AllowDowngrade,
        [ValidateRange(30,7200)][int]$DownloadTimeoutSeconds=900,
        [string]$QuietCliRoot=(Join-Path $PSScriptRoot '../..'))
    if($Version){Assert-DotNetSdkVersion -Version $Version -Channel $Channel -Preleases:$Preleases}
    $root=[IO.Path]::TrimEndingDirectorySeparator($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot))
    $requested=if($Version){$Version}else{"latest eligible $Channel"}
    $action="Install SDK $requested (includes .NET/ASP.NET/Desktop where supported); images=$PullImages; global.json=$UpdateGlobalJson; activate session=$ActivateSession"
    if(!$PSCmdlet.ShouldProcess($root,$action)) {
        [pscustomobject]@{Status='NotApplied';Version=$Version;InstallRoot=$root;GlobalJsonPath=$GlobalJsonPath;PullImages=[bool]$PullImages}
        return
    }
    if($PullImages){$ContainerRuntime=Resolve-DotNetContainerRuntime -ContainerRuntime $ContainerRuntime -WorkspaceRoot $QuietCliRoot}
    $release=Get-DotNetSdkRelease -Channel $Channel -Version $Version -Preleases:$Preleases -Confirm:$false
    $Version=$release.Version
    Assert-DotNetSdkVersion -Version $Version -Channel $Channel -Preleases:$Preleases
    $rid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $extension=if($IsWindows){'.zip'}else{'.tar.gz'}
    $archiveInfo=@($release.Files|Where-Object {$_.rid -eq $rid -and $_.name.EndsWith($extension)})
    if($archiveInfo.Count -ne 1){throw "No unique SDK archive for this PowerShell host RID: $rid"}
    $archiveInfo=$archiveInfo[0]
    if($archiveInfo.hash -notmatch '^[a-fA-F0-9]{128}$'){throw 'No valid published SDK SHA-512.'}
    $target=Join-Path $root $Version
    $hostName=if($IsWindows){'dotnet.exe'}else{'dotnet'}
    $dotnet=Join-Path $target $hostName
    if($UpdateGlobalJson) {
        # Validate the entire batch before installation or any source modification.
        $null=@(Get-DotNetGlobalJsonPlan -Path $GlobalJsonPath -Version $Version -Channel $Channel -Preleases:$Preleases -SdkDirectory $target -AllowDowngrade:$AllowDowngrade)
    }
    $installationState='AlreadyInstalled'
    if(Test-Path -LiteralPath $target) {
        Assert-DotNetInstalledPayload -DotNetPath $dotnet -Version $Version -RuntimeVersion $release.RuntimeVersion -QuietCliRoot $QuietCliRoot
    }
    else {
        $null=[IO.Directory]::CreateDirectory($root)
        $staging=Join-Path $root ('.staging-'+[guid]::NewGuid().ToString('N'))
        $null=[IO.Directory]::CreateDirectory($staging)
        try {
            $archive=Join-Path $staging ('sdk'+$extension)
            Write-Progress -Activity '.NET SDK installation' -Status "Downloading SDK $Version ($rid)"
            Save-DotNetSdkArchive -Uri $archiveInfo.url -Destination $archive -TimeoutSeconds $DownloadTimeoutSeconds
            if((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash -ine $archiveInfo.hash){throw 'SDK archive SHA-512 mismatch; nothing was extracted or promoted.'}
            $payload=Join-Path $staging 'payload'
            $null=[IO.Directory]::CreateDirectory($payload)
            Write-Progress -Activity '.NET SDK installation' -Status 'Extracting verified archive and checking SDK/runtimes'
            Expand-DotNetSdkArchive -Archive $archive -Destination $payload
            Assert-DotNetInstalledPayload -DotNetPath (Join-Path $payload $hostName) -Version $Version -RuntimeVersion $release.RuntimeVersion -QuietCliRoot $QuietCliRoot
            $receipt=@{SdkVersion=$Version;RuntimeVersion=$release.RuntimeVersion;Rid=$rid;ArchiveUrl=$archiveInfo.url;Sha512=$archiveInfo.hash;InstalledUtc=[DateTimeOffset]::UtcNow.ToString('O')}
            $null=[IO.File]::WriteAllTextAsync((Join-Path $payload 'frenchexdev-install.json'),($receipt|ConvertTo-Json).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            [IO.Directory]::Move($payload,$target)
            $installationState='Installed'
        }
        finally {
            Write-Progress -Activity '.NET SDK installation' -Completed
            $resolved=[IO.Path]::GetFullPath($staging)
            if((Split-Path $resolved -Parent) -ne $root -or (Split-Path $resolved -Leaf) -notmatch '^\.staging-[a-f0-9]{32}$'){throw 'Unsafe staging cleanup target.'}
            if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
        }
    }
    $images=@()
    if($PullImages) {
        $tag=$Channel+$(if(([System.Management.Automation.SemanticVersion]$Version).PreReleaseLabel){'-preview'})+$(if($ImageVariant){"-$ImageVariant"})
        foreach($repository in @('sdk','runtime','aspnet','runtime-deps')) {
            foreach($imagePlatform in @($Platform|Select-Object -Unique)) {
                $images+=Invoke-DotNetContainerPull -ContainerRuntime $ContainerRuntime -Image "mcr.microsoft.com/dotnet/${repository}:$tag" -Platform $imagePlatform -QuietCliRoot $QuietCliRoot -Confirm:$false
            }
        }
    }
    $pins=@()
    if($UpdateGlobalJson) {
        $pins=@(Update-DotNetGlobalJson -Path $GlobalJsonPath -Version $Version -Channel $Channel -Preleases:$Preleases -SdkDirectory $target -DotNetPath $dotnet -AllowDowngrade:$AllowDowngrade -QuietCliRoot $QuietCliRoot -Confirm:$false)
    }
    if($ActivateSession){$env:DOTNET_ROOT=$target;$env:PATH=$target+[IO.Path]::PathSeparator+$env:PATH}
    [pscustomobject]@{Status=$installationState;Version=$Version;RuntimeVersion=$release.RuntimeVersion;SdkDirectory=$target;DotNetPath=$dotnet;Images=$images;ContainerRuntime=$ContainerRuntime;GlobalJson=$pins;SessionActivated=[bool]$ActivateSession}
}

Export-ModuleMember -Function Get-DotNetGlobalJsonPlan,Update-DotNetGlobalJson,Install-DotNetEnvironment
