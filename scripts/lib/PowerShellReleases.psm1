Set-StrictMode -Version Latest

function Invoke-QuietPowerShellReleaseHttp {
    <# .SYNOPSIS Reads bounded official release evidence without retries or certificate bypasses.
    .PARAMETER Uri HTTPS GitHub, NuGet or Alpine resource.
    .PARAMETER Method GET metadata or HEAD availability probe.
    #>
    param([uri]$Uri,[ValidateSet('GET','HEAD')][string]$Method='GET')
    if($Uri.Scheme -cne 'https' -or $Uri.Host -cnotin @('api.github.com','github.com','raw.githubusercontent.com','api.nuget.org','dl-cdn.alpinelinux.org')){throw 'PowerShellReleaseSourceUntrusted'}
    $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(30);$client.MaxResponseContentBufferSize=16MB
    $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method),$Uri)
    [void]$request.Headers.TryAddWithoutValidation('User-Agent','QuietCli-PowerShell-Release-Readiness')
    $response=$null
    try{
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        [byte[]]$bytes=@()
        if($Method -ceq 'GET'){$bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()}
        [pscustomobject]@{Status=[int]$response.StatusCode;Bytes=$bytes;Length=$response.Content.Headers.ContentLength}
    }finally{if($response){$response.Dispose()};$request.Dispose();$client.Dispose()}
}

function Get-QuietAlpinePowerShellPackage {
    <# .SYNOPSIS Reads the native Alpine package index and probes the declared PowerShell APK.
    .PARAMETER Branch Existing Alpine repository branch, without changing the base image.
    .PARAMETER Architecture Native package architecture.
    #>
    param([ValidatePattern('\A(?:v\d+\.\d+|edge)\z')][string]$Branch='v3.24',[ValidateSet('x86_64','aarch64')][string]$Architecture)
    $indexUrl="https://dl-cdn.alpinelinux.org/alpine/$Branch/community/$Architecture/APKINDEX.tar.gz"
    $response=Invoke-QuietPowerShellReleaseHttp $indexUrl
    if($response.Status -ne 200){throw "AlpinePackageIndexUnavailable: HTTP $($response.Status)"}
    $input=[IO.MemoryStream]::new([byte[]]$response.Bytes)
    $gzip=[IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
    $tar=[System.Formats.Tar.TarReader]::new($gzip)
    $text=$null
    try{
        while($entry=$tar.GetNextEntry()){
            if($entry.Name -cne 'APKINDEX'){continue}
            if($entry.Length -gt 64MB){throw 'AlpinePackageIndexOversized'}
            $reader=[IO.StreamReader]::new($entry.DataStream,[Text.UTF8Encoding]::new($false,$true))
            try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
            break
        }
    }finally{$tar.Dispose();$gzip.Dispose();$input.Dispose()}
    if(!$text){throw 'AlpinePackageIndexMissing'}
    $packages=@($text -split '\n\n'|Where-Object {$_ -cmatch '(?m)^P:powershell$'})
    if($packages.Count -ne 1){throw 'AlpinePowerShellPackageNotUnique'}
    $version=[regex]::Match($packages[0],'(?m)^V:([^\r\n]+)$').Groups[1].Value
    if($version -cnotmatch '\A7\.\d+\.\d+-r\d+\z'){throw 'AlpinePowerShellVersionInvalid'}
    $url="https://dl-cdn.alpinelinux.org/alpine/$Branch/community/$Architecture/powershell-$version.apk"
    $probe=Invoke-QuietPowerShellReleaseHttp $url -Method HEAD
    [pscustomobject]@{Branch=$Branch;Architecture=$Architecture;Version=$version;Available=($probe.Status -eq 200);Status=$probe.Status;Url=$url;Index=$indexUrl;Dependencies=[regex]::Match($packages[0],'(?m)^D:([^\r\n]+)$').Groups[1].Value}
}

function Get-QuietPowerShellReleaseResources {
    <# .SYNOPSIS Resolves GA and next-preview resources, exact hashes and native Alpine availability.
    .PARAMETER AlpineBranch Existing repository branch to inspect without upgrading the distribution.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$AlpineBranch='v3.24')
    if(!$PSCmdlet.ShouldProcess('Official PowerShell resources','Read release metadata and probe archive/package availability')){return}
    $metadataResponse=Invoke-QuietPowerShellReleaseHttp 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/metadata.json'
    $releaseResponse=Invoke-QuietPowerShellReleaseHttp 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    if($metadataResponse.Status -ne 200 -or $releaseResponse.Status -ne 200){throw 'PowerShellReleaseMetadataUnavailable'}
    $metadata=[Text.Encoding]::UTF8.GetString($metadataResponse.Bytes)|ConvertFrom-Json
    $release=[Text.Encoding]::UTF8.GetString($releaseResponse.Bytes)|ConvertFrom-Json
    if($release.draft -or $release.prerelease -or $release.tag_name -cne $metadata.StableReleaseTag -or $release.tag_name -cnotmatch '\Av(7\.\d+\.\d+)\z'){throw 'PowerShellStableReleaseInvalid'}
    $version=$Matches[1]
    $sdkResponse=Invoke-QuietPowerShellReleaseHttp "https://raw.githubusercontent.com/PowerShell/PowerShell/v$version/global.json"
    if($sdkResponse.Status -ne 200){throw 'PowerShellReleaseSdkIdentityUnavailable'}
    $sdk=[Text.Encoding]::UTF8.GetString($sdkResponse.Bytes)|ConvertFrom-Json
    $runtimeMajor=([Management.Automation.SemanticVersion]$sdk.sdk.version).Major
    $assets=@(foreach($name in @("PowerShell-$version-win-x64.zip","PowerShell-$version-win-arm64.zip","powershell-$version-linux-x64.tar.gz","powershell-$version-linux-arm64.tar.gz","powershell-$version-linux-musl-x64.tar.gz","powershell-$version-linux-musl-arm64.tar.gz")){
        $asset=@($release.assets|Where-Object name -CEQ $name)
        if(!$asset.Count){[pscustomobject]@{Name=$name;Available=$false;Status='NotPublished';SHA256=$null;Url=$null};continue}
        if($asset.Count -ne 1 -or $asset[0].digest -cnotmatch '\Asha256:([a-f0-9]{64})\z'){throw 'PowerShellReleaseDigestInvalid'}
        $sha=$Matches[1];$url="https://github.com/PowerShell/PowerShell/releases/download/v$version/$name"
        if($asset[0].browser_download_url -cne $url){throw 'PowerShellReleaseAssetUrlInvalid'}
        $probe=Invoke-QuietPowerShellReleaseHttp $url -Method HEAD
        [pscustomobject]@{Name=$name;Available=($probe.Status -eq 200);Status=$probe.Status;SHA256=$sha;Url=$url}
    })
    $listingResponse=Invoke-QuietPowerShellReleaseHttp 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=50'
    if($listingResponse.Status -ne 200){throw 'PowerShellPreviewListingUnavailable'}
    $listing=@([Text.Encoding]::UTF8.GetString($listingResponse.Bytes)|ConvertFrom-Json)
    $published=@($listing|Where-Object {!$_.draft -and $_.prerelease -and $_.tag_name -cmatch '\Av7\.\d+\.\d+-(?:preview|rc)\.\d+\z' -and [Management.Automation.SemanticVersion]$_.tag_name.Substring(1) -gt [Management.Automation.SemanticVersion]$version}|Sort-Object {[Management.Automation.SemanticVersion]$_.tag_name.Substring(1)} -Descending)
    $next=if($published.Count){[string]$published[0].tag_name}else{[string]$metadata.NextReleaseTag}
    if($next -cnotmatch '\Av7\.\d+\.\d+-(?:preview|rc)\.\d+\z' -or [Management.Automation.SemanticVersion]$next.Substring(1) -le [Management.Automation.SemanticVersion]$version){throw 'PowerShellNextPreviewInvalid'}
    $previewResponse=Invoke-QuietPowerShellReleaseHttp ('https://api.github.com/repos/PowerShell/PowerShell/releases/tags/'+$next)
    if($previewResponse.Status -notin @(200,404)){throw 'PowerShellNextPreviewAvailabilityUnknown'}
    $preview=if($previewResponse.Status -eq 200){[Text.Encoding]::UTF8.GetString($previewResponse.Bytes)|ConvertFrom-Json}else{$null}
    if($preview -and ($preview.draft -or !$preview.prerelease -or $preview.tag_name -cne $next)){throw 'PowerShellNextPreviewReleaseInvalid'}
    $previewRuntime=$null
    if($preview){
        $previewSdkResponse=Invoke-QuietPowerShellReleaseHttp "https://raw.githubusercontent.com/PowerShell/PowerShell/$next/global.json"
        if($previewSdkResponse.Status -ne 200){throw 'PowerShellPreviewSdkIdentityUnavailable'}
        $previewSdk=[Text.Encoding]::UTF8.GetString($previewSdkResponse.Bytes)|ConvertFrom-Json
        $previewRuntime=([Management.Automation.SemanticVersion]$previewSdk.sdk.version).Major
        foreach($rid in @('win-x64','win-arm64')){
            $asset=@($preview.assets|Where-Object name -CEQ "PowerShell-$($next.Substring(1))-$rid.zip")
            if($asset.Count -ne 1 -or $asset[0].browser_download_url -cne "https://github.com/PowerShell/PowerShell/releases/download/$next/PowerShell-$($next.Substring(1))-$rid.zip" -or (Invoke-QuietPowerShellReleaseHttp $asset[0].browser_download_url -Method HEAD).Status -ne 200){throw 'PowerShellPreviewAssetUnavailable'}
        }
    }
    $packages=@(foreach($architecture in @('x86_64','aarch64')){Get-QuietAlpinePowerShellPackage -Branch $AlpineBranch -Architecture $architecture})
    $nugetUrl="https://api.nuget.org/v3-flatcontainer/system.management.automation/$version/system.management.automation.$version.nupkg"
    $nuget=Invoke-QuietPowerShellReleaseHttp $nugetUrl -Method HEAD
    [pscustomobject]@{Stable=$version;RuntimeMajor=$runtimeMajor;PublishedAt=$release.published_at;Assets=$assets;Alpine=$packages;AutomationPackage=@{Version=$version;Available=($nuget.Status -eq 200);Status=$nuget.Status;Url=$nugetUrl};NextPreview=@{Version=$next.Substring(1);RuntimeMajor=$previewRuntime;Available=($null -ne $preview);Release=$preview};MetadataSource='https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/metadata.json';ReleaseSource=$release.html_url}
}

function New-QuietPowerShellResourcePlan {
    <# .SYNOPSIS Builds reviewed lock documents only from available official assets and explicit exceptions.
    .PARAMETER Availability Verified release evidence.
    .PARAMETER ImageLock Current image lock; unrelated SDK, runtime and OS pins are preserved.
    .PARAMETER AllowAlpineVersionLag Explicitly retain the existing native Alpine package when GA is unavailable.
    #>
    param($Availability,$ImageLock,[switch]$AllowAlpineVersionLag)
    $version=[string]$Availability.Stable
    if($version -cnotmatch '\A7\.\d+\.\d+\z' -or !$Availability.AutomationPackage.Available -or $Availability.AutomationPackage.Status -ne 200 -or $Availability.AutomationPackage.Version -cne $version -or $Availability.RuntimeMajor -lt 10){throw 'PowerShellProductionResourcesUnavailable'}
    $hosts=[Collections.Generic.List[object]]::new()
    foreach($rid in @('win-x64','win-arm64','linux-x64','linux-arm64')){
        $name=if($rid.StartsWith('win-')){"PowerShell-$version-$rid.zip"}else{"powershell-$version-$rid.tar.gz"}
        $asset=@($Availability.Assets|Where-Object Name -CEQ $name)
        if($asset.Count -ne 1 -or !$asset[0].Available -or $asset[0].Status -ne 200 -or $asset[0].SHA256 -cnotmatch '\A[a-f0-9]{64}\z' -or $asset[0].Url -cne "https://github.com/PowerShell/PowerShell/releases/download/v$version/$name"){throw ('PowerShellProductionAssetUnavailable: '+$name)}
        $hosts.Add([ordered]@{Channel='stable';Version=$version;RuntimeMajor=$Availability.RuntimeMajor;Rid=$rid;SHA256=$asset[0].SHA256.ToUpperInvariant()})
    }
    $next=[string]$Availability.NextPreview.Version
    if($next -cnotmatch '\A7\.\d+\.\d+-(?:preview|rc)\.\d+\z' -or [Management.Automation.SemanticVersion]$next -le [Management.Automation.SemanticVersion]$version){throw 'PowerShellNextPreviewInvalid'}
    if($Availability.NextPreview.Available){
        foreach($rid in @('win-x64','win-arm64')){
            $name="PowerShell-$next-$rid.zip"
            $asset=@($Availability.NextPreview.Release.assets|Where-Object name -CEQ $name)
            if($asset.Count -ne 1 -or $asset[0].browser_download_url -cne "https://github.com/PowerShell/PowerShell/releases/download/v$next/$name" -or $asset[0].digest -cnotmatch '\Asha256:([a-f0-9]{64})\z'){throw 'PowerShellPreviewAssetUnavailable'}
            if($Availability.NextPreview.RuntimeMajor -lt 10){throw 'PowerShellPreviewRuntimeInvalid'}
            $hosts.Add([ordered]@{Channel='preview';Version=$next;RuntimeMajor=$Availability.NextPreview.RuntimeMajor;Rid=$rid;SHA256=$Matches[1].ToUpperInvariant()})
        }
    }
    $image=$ImageLock|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
    foreach($rid in @('linux-x64','linux-arm64')){
        $target=@($image.Platforms|Where-Object Rid -CEQ $rid)
        if($target.Count -ne 1){throw 'PowerShellImageTargetInvalid'}
        $asset=@($Availability.Assets|Where-Object Name -CEQ "powershell-$version-$rid.tar.gz")[0]
        $target[0].PowerShell=$version;$target[0].PowerShell_SHA256=$asset.SHA256
    }
    $alpine=@($Availability.Alpine)
    if((@($alpine.Architecture|Sort-Object) -join '|') -cne 'aarch64|x86_64'){throw 'AlpinePowerShellArchitecturesInvalid'}
    $matching=$alpine.Count -eq 2 -and @($alpine|Where-Object {!$_.Available -or $_.Version -cnotmatch ('\A'+[regex]::Escape($version)+'-r\d+\z')}).Count -eq 0 -and @($alpine.Version|Sort-Object -Unique).Count -eq 1
    if($matching){
        if($image.AlpineRuntime -cnotmatch ('\A'+[regex]::Escape([string]$Availability.RuntimeMajor)+'\.0\.\d+\z')){throw 'AlpinePowerShellRuntimeUpgradeRequired'}
        $image.AlpinePowerShellPackage=$alpine[0].Version;$null=$image.Remove('PowerShellException')
    }
    elseif(!$AllowAlpineVersionLag){throw 'AlpinePowerShellGaUnavailable: explicit AllowAlpineVersionLag is required to retain the existing package.'}
    else{
        if($alpine.Count -ne 2 -or @($alpine|Where-Object {!$_.Available -or $_.Version -cne $image.AlpinePowerShellPackage}).Count){throw 'AlpinePowerShellFallbackUnavailable'}
        $image.PowerShellException=[ordered]@{Requested=$version;Platform='alpine';Retained=$image.AlpinePowerShellPackage;Reason='Official musl ARM64 archive and native GA APK are not published; retain the available native package explicitly.'}
    }
    [pscustomobject]@{HostLock=[ordered]@{SchemaVersion=1;Source='https://github.com/PowerShell/PowerShell/releases';StableVersion=$version;Preview=[ordered]@{Version=$next;Available=[bool]$Availability.NextPreview.Available};Hosts=$hosts.ToArray()};ImageLock=$image;Stable=$version;PreviewAvailable=[bool]$Availability.NextPreview.Available;AlpineException=!$matching}
}

function Update-QuietPowerShellCiLock {
    <# .SYNOPSIS Verifies current releases before writing only PowerShell locks and version-bound backups.
    .PARAMETER WorkspaceRoot Checkout owning the lock files.
    .PARAMETER AllowAlpineVersionLag Explicitly preserve the existing native Alpine package.
    .PARAMETER PlanOnly Query availability and return the proposed documents without writes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot,[switch]$AllowAlpineVersionLag,[switch]$PlanOnly)
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Verify published PowerShell resources and update selected locks')){return}
    $imagePath=Join-Path $WorkspaceRoot 'build/ci-images.lock.json'
    $hostPath=Join-Path $WorkspaceRoot 'build/powershell-hosts.lock.json'
    $image=Get-Content -LiteralPath $imagePath -Raw -Encoding utf8|ConvertFrom-Json
    $availability=Get-QuietPowerShellReleaseResources -Confirm:$false
    $plan=New-QuietPowerShellResourcePlan -Availability $availability -ImageLock $image -AllowAlpineVersionLag:$AllowAlpineVersionLag
    if($PlanOnly){return $plan}
    foreach($item in @(@{Path=$hostPath;Data=$plan.HostLock},@{Path=$imagePath;Data=$plan.ImageLock})){
        $original=[IO.File]::ReadAllBytes($item.Path)
        $text=($item.Data|ConvertTo-Json -Depth 20).Replace("`r`n","`n")+"`n"
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
        if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($original)) -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))){continue}
        $backup=$item.Path+'.bak-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmssfff')
        [IO.File]::WriteAllBytes($backup,$original)
        $temporary=$item.Path+'.tmp-'+[guid]::NewGuid().ToString('N')
        try{[IO.File]::WriteAllBytes($temporary,$bytes);[IO.File]::Move($temporary,$item.Path,$true)}finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    }
    [pscustomobject]@{Stable=$plan.Stable;PreviewAvailable=$plan.PreviewAvailable;AlpineException=$plan.AlpineException;Updated=$true}
}

Export-ModuleMember -Function Get-QuietPowerShellReleaseResources,Get-QuietAlpinePowerShellPackage,New-QuietPowerShellResourcePlan,Update-QuietPowerShellCiLock
