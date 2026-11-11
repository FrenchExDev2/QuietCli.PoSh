#requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'DotNetReadiness.psm1') -ErrorAction Stop

function Invoke-DotNetRegistryHttp {
    <# .SYNOPSIS Reads bounded official Docker metadata; anonymous bearer tokens never leave caller memory. #>
    param([uri]$Uri,[string]$Bearer)
    if($Uri.Scheme -ne 'https' -or $Uri.Host -notin @('auth.docker.io','registry-1.docker.io','hub.docker.com')){throw 'Untrusted registry metadata URL.'}
    $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(20);$client.MaxResponseContentBufferSize=8MB
    $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$Uri)
    $null=$request.Headers.TryAddWithoutValidation('Accept','application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/json')
    if($Bearer){$request.Headers.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Bearer)}
    $response=$null
    try{
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        if($response.RequestMessage.RequestUri.Host -ne $Uri.Host){throw 'Registry metadata redirected to a different host.'}
        if([int]$response.StatusCode -ne 200){throw "Registry metadata returned HTTP $([int]$response.StatusCode) from $($Uri.Host)."}
        $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $digest=if($response.Headers.Contains('Docker-Content-Digest')){@($response.Headers.GetValues('Docker-Content-Digest'))[0]}else{$null}
        [pscustomobject]@{Body=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);Digest=$digest;BodySha256=('sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant())}
    }finally{if($response){$response.Dispose()};$request.Dispose();$client.Dispose()}
}

function Resolve-DotNetBaseImage {
    <#
    .SYNOPSIS
    Resolves an official Docker Hub tag to its exact multi-platform index digest.
    .PARAMETER Image
    Official debian or alpine repository.
    .PARAMETER Tag
    Explicit tag; the script never chooses a new distribution version implicitly.
    .PARAMETER Platform
    Required OS/architecture pairs.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('debian','alpine')][string]$Image,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$Tag,
        [string[]]$Platform=@('linux/amd64','linux/arm64'))
    if(!$PSCmdlet.ShouldProcess("docker.io/library/${Image}:$Tag",'Resolve registry index digest and platform availability without pulling layers')){return}
    $auth=Invoke-DotNetRegistryHttp -Uri "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/${Image}:pull"
    $token=(ConvertFrom-Json $auth.Body -AsHashtable)['token']
    if(!$token){throw 'Anonymous registry token was not returned.'}
    $manifest=Invoke-DotNetRegistryHttp -Uri "https://registry-1.docker.io/v2/library/$Image/manifests/$Tag" -Bearer $token
    if($manifest.Digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or $manifest.Digest -cne $manifest.BodySha256){throw 'Registry index digest does not match the received bytes.'}
    $data=ConvertFrom-Json $manifest.Body -AsHashtable -Depth 64
    if($data['schemaVersion'] -ne 2 -or !$data['manifests']){throw 'A multi-platform registry index is required.'}
    $available=@(foreach($entry in $data.manifests){if($entry['platform']){"$($entry.platform.os)/$($entry.platform.architecture)"}})
    $missing=@($Platform|Where-Object {$_ -notin $available})
    if($missing.Count){throw ('Base image lacks required platforms: '+($missing -join ', '))}
    [pscustomobject]@{Image=$Image;Tag=$Tag;Digest=$manifest.Digest;Reference="docker.io/library/${Image}:${Tag}@$($manifest.Digest)";Platforms=$available}
}

function Get-DotNetBaseImageTags {
    <#
    .SYNOPSIS
    Lists a bounded page of available official Debian/Alpine tags and their reported platforms.
    .PARAMETER Image
    Official repository to inspect.
    .PARAMETER Name
    Docker Hub tag-name filter, for example bookworm or 3.24.
    .PARAMETER Limit
    Maximum returned entries, 1 through 100; listing is not an exhaustive registry inventory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('debian','alpine')][string]$Image='debian',[string]$Name,
        [ValidateRange(1,100)][int]$Limit=20)
    if(!$PSCmdlet.ShouldProcess("docker.io/library/$Image",'List available tag metadata without pulling images')){return}
    $url="https://hub.docker.com/v2/repositories/library/$Image/tags?page_size=$Limit&ordering=last_updated"
    if($Name){$url+='&name='+[uri]::EscapeDataString($Name)}
    $response=Invoke-DotNetRegistryHttp -Uri $url
    $data=ConvertFrom-Json $response.Body -AsHashtable -Depth 64
    if($data['results'] -isnot [array]){throw 'Invalid Docker Hub tag listing.'}
    foreach($tag in @($data.results|Select-Object -First $Limit)){
        [pscustomobject]@{Image=$Image;Tag=$tag.name;Digest=$tag['digest'];UpdatedUtc=$tag['last_updated'];Platforms=@($tag.images|ForEach-Object {"$($_.os)/$($_.architecture)"});HasMore=[bool]$data['next']}
    }
}

function Read-DotNetLockJson {
    <# .SYNOPSIS Reads an existing UTF-8 object and rejects duplicate property loss. #>
    param([string]$Path)
    if((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Lock-file links are not followed.'}
    $bytes=[IO.File]::ReadAllBytesAsync($Path).GetAwaiter().GetResult()
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
    $document=[System.Text.Json.JsonDocument]::Parse($text)
    try{
        if($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object){throw 'A lock document must be a JSON object.'}
        $pending=[Collections.Generic.Stack[System.Text.Json.JsonElement]]::new();$pending.Push($document.RootElement)
        while($pending.Count){
            $element=$pending.Pop()
            if($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object){
                $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach($property in $element.EnumerateObject()){if(!$names.Add($property.Name)){throw 'Duplicate lock JSON property.'};$pending.Push($property.Value)}
            }elseif($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array){foreach($value in $element.EnumerateArray()){$pending.Push($value)}}
        }
    }finally{$document.Dispose()}
    [pscustomobject]@{Text=$text;Data=(ConvertFrom-Json $text -AsHashtable -Depth 64);Hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}

function Get-DotNetArchiveHash {
    <# .SYNOPSIS Requires one archive for the exact RID, format and canonical versioned URL. #>
    param($Files,[string]$Rid,[string]$Version,[ValidateSet('Sdk','Runtime')][string]$Kind,[string]$Extension='tar.gz')
    $prefix=if($Kind -eq 'Sdk'){'dotnet-sdk'}else{'dotnet-runtime'}
    $entries=@($Files|Where-Object {$_.rid -eq $Rid -and $_.name -eq "$prefix-$Rid.$Extension"})
    if($entries.Count -ne 1 -or $entries[0].hash -cnotmatch '^[a-fA-F0-9]{128}$'){throw "No unique valid $Kind archive hash for $Rid."}
    $expected="https://builds.dotnet.microsoft.com/dotnet/$Kind/$Version/$prefix-$Version-$Rid.$Extension"
    if($entries[0].url -cne $expected){throw "Archive metadata URL does not match the CI consumer: $Rid"}
    ([string]$entries[0].hash).ToLowerInvariant()
}

function Write-DotNetLockPlans {
    <# .SYNOPSIS Writes validated plans with original-byte backups and atomic per-file replacement. #>
    param([object[]]$Plans)
    foreach($plan in $Plans){
        if(!$plan.Changed){[pscustomobject]@{Path=$plan.Path;Status='Unchanged';BackupPath=$null};continue}
        if((Get-FileHash -LiteralPath $plan.Path -Algorithm SHA256).Hash -cne $plan.Hash){throw "Source changed after planning: $($plan.Path)"}
        $backup=$plan.Path+'.bak-'+[guid]::NewGuid().ToString('N')
        $temporary=$plan.Path+'.writing-'+[guid]::NewGuid().ToString('N')
        try{
            [IO.File]::Copy($plan.Path,$backup,$false)
            $null=[IO.File]::WriteAllTextAsync($temporary,$plan.Text.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if((Get-FileHash -LiteralPath $plan.Path -Algorithm SHA256).Hash -cne $plan.Hash){throw 'Source changed before replacement.'}
            [IO.File]::Move($temporary,$plan.Path,$true)
            [pscustomobject]@{Path=$plan.Path;Status='Updated';BackupPath=$backup}
        }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    }
}

function Update-DotNetCiLock {
    <#
    .SYNOPSIS
    Refreshes .NET archive hashes and optional base-image digests for the SDK pinned by global.json.
    .PARAMETER WorkspaceRoot
    Checkout containing global.json and existing reviewed CI locks.
    .PARAMETER IncludeDevelopmentLock
    Also refreshes Windows SDK ZIP hashes in development-workstation.lock.json.
    .PARAMETER RefreshBaseImages
    Resolves current Debian/Alpine tag digests and verifies all required platforms.
    .PARAMETER DebianTag
    Explicit alternate Debian tag. Distribution-package compatibility requires a separate build.
    .PARAMETER AlpineTag
    Explicit alternate Alpine tag. PowerShell package compatibility requires a separate build.
    .PARAMETER AlpineRuntimeVersion
    Optional exact .NET 10 runtime for Alpine PowerShell; otherwise preserve its existing pin.
    .PARAMETER Preleases
    Permits preview/RC SDK metadata.
    .PARAMETER PlanOnly
    Performs metadata queries and returns plans without writing files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot=(Join-Path $PSScriptRoot '../..'),[switch]$IncludeDevelopmentLock,
        [switch]$RefreshBaseImages,[ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$DebianTag,
        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$AlpineTag,
        [ValidatePattern('^10\.0\.\d+$')][string]$AlpineRuntimeVersion,
        [Alias('Prerelease','Prereleases')][switch]$Preleases,[switch]$PlanOnly)
    $root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceRoot)
    if(!$PSCmdlet.ShouldProcess($root,'Resolve official SDK/runtime metadata and requested base digests; update selected locks with backups')){return}
    $global=(Read-DotNetLockJson (Join-Path $root 'global.json')).Data
    $version=[string]$global.sdk.version
    $semantic=[System.Management.Automation.SemanticVersion]$version
    $release=Get-DotNetSdkRelease -Channel "$($semantic.Major).$($semantic.Minor)" -Version $version -Preleases:$Preleases -Confirm:$false
    if($release.Version -cne $version){throw 'SDK metadata did not resolve the exact global.json pin.'}
    $ciPath=Join-Path $root 'build/ci-images.lock.json'
    $original=Read-DotNetLockJson $ciPath;$ci=$original.Data
    if($ci.SchemaVersion -ne 2 -or $ci.Platforms -isnot [array]){throw 'Invalid CI image lock schema.'}
    $before=$ci|ConvertTo-Json -Depth 64 -Compress
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if($AlpineRuntimeVersion){$ci.AlpineRuntime=$AlpineRuntimeVersion}
    if($ci.AlpineRuntime -notmatch '^10\.0\.\d+$'){throw 'Alpine PowerShell runtime must remain an explicit .NET 10 patch.'}
    $runtime=Get-DotNetRuntimeRelease -Version $ci.AlpineRuntime -Confirm:$false
    $baseCache=@{}
    foreach($entry in $ci.Platforms){
        if($entry.Rid -notin @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64') -or !$seen.Add($entry.Rid)){throw 'Unsupported or duplicate CI RID.'}
        $image=if($entry.Rid.StartsWith('linux-musl-')){'alpine'}else{'debian'}
        $arch=if($entry.Rid.EndsWith('arm64')){'arm64'}else{'x64'}
        if($entry.Platform -cne $image -or $entry.Architecture -cne $arch){throw 'CI platform/RID mismatch.'}
        $entry.SDK_SHA512=Get-DotNetArchiveHash -Files $release.Files -Rid $entry.Rid -Version $version -Kind Sdk
        if($image -eq 'alpine'){$entry.Runtime_SHA512=Get-DotNetArchiveHash -Files $runtime.Files -Rid $entry.Rid -Version $ci.AlpineRuntime -Kind Runtime}
        if($entry.Base -cnotmatch '^docker\.io/library/(?<image>debian|alpine):(?<tag>[A-Za-z0-9_.-]+)@sha256:[a-f0-9]{64}$'){throw 'Invalid pinned base-image reference.'}
        if($Matches.image -cne $image){throw 'CI base-image repository does not match its platform.'}
        $tag=$Matches.tag
        $override=if($image -eq 'debian'){$DebianTag}else{$AlpineTag}
        if($override){$tag=$override}
        if($RefreshBaseImages -or $override){
            $key="$image/$tag"
            if(!$baseCache.ContainsKey($key)){$baseCache[$key]=Resolve-DotNetBaseImage -Image $image -Tag $tag -Confirm:$false}
            $entry.Base=$baseCache[$key].Reference
        }
    }
    if($seen.Count -ne 4){throw 'The CI lock must retain all four supported Linux RIDs.'}
    $ci.SDK=$version
    $plans=[Collections.Generic.List[object]]::new()
    $plans.Add([pscustomobject]@{Path=$ciPath;Hash=$original.Hash;Changed=($before -cne ($ci|ConvertTo-Json -Depth 64 -Compress));Text=($ci|ConvertTo-Json -Depth 64)+"`n"})
    if($IncludeDevelopmentLock){
        $path=Join-Path $root 'build/development-workstation.lock.json';$old=Read-DotNetLockJson $path;$dev=$old.Data
        if($dev.SchemaVersion -ne 1 -or $dev.WindowsSdks -isnot [array]){throw 'Invalid development lock schema.'}
        $before=$dev|ConvertTo-Json -Depth 64 -Compress
        $seenWindows=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in $dev.WindowsSdks){
            if($entry.Rid -notin @('win-x64','win-arm64') -or !$seenWindows.Add($entry.Rid)){throw 'Unsupported or duplicate Windows SDK RID.'}
            $entry.SHA512=Get-DotNetArchiveHash -Files $release.Files -Rid $entry.Rid -Version $version -Kind Sdk -Extension zip
        }
        if($seenWindows.Count -ne 2){throw 'Both Windows SDK architectures are required.'}
        $dev.SdkVersion=$version
        $plans.Add([pscustomobject]@{Path=$path;Hash=$old.Hash;Changed=($before -cne ($dev|ConvertTo-Json -Depth 64 -Compress));Text=($dev|ConvertTo-Json -Depth 64)+"`n"})
    }
    if($PlanOnly){$plans.ToArray();return}
    Write-DotNetLockPlans -Plans $plans.ToArray()
}

function Get-DotNetRuntimeFrameworkPlan {
    <#
    .SYNOPSIS
    Plans exact runtime property changes while preserving project XML and other target frameworks.
    .PARAMETER WorkspaceRoot
    Selected source checkout.
    .PARAMETER Version
    Exact runtime version, not an SDK version.
    .PARAMETER Path
    Optional exact project/props files; otherwise discover source projects under this checkout.
    .PARAMETER Framework
    Framework whose runtime property may change, default net11.0.
    .PARAMETER Preleases
    Permits preview/RC runtime targets.
    .PARAMETER AllowDowngrade
    Explicitly permits lowering an existing runtime version.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot=(Join-Path $PSScriptRoot '../..'),[Parameter(Mandatory)][string]$Version,
        [string[]]$Path,[ValidatePattern('^net\d+\.\d+$')][string]$Framework='net11.0',
        [switch]$Preleases,[switch]$AllowDowngrade)
    $semantic=[System.Management.Automation.SemanticVersion]$Version
    if("net$($semantic.Major).$($semantic.Minor)" -ne $Framework -or ($semantic.PreReleaseLabel -and !$Preleases)){throw 'Runtime version/framework/prerelease policy mismatch.'}
    $root=[IO.Path]::TrimEndingDirectorySeparator($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceRoot))
    if(!$Path){
        $found=[Collections.Generic.List[string]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
        while($pending.Count){foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if($item.Name -in @('.git','.dotnet','bin','obj','lib','artifacts','.cache','.vs','.profilers')){continue}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source project links are not followed.'}
            if($item.PSIsContainer){$pending.Push($item.FullName)}elseif($item.Extension -in @('.csproj','.props')){$found.Add($item.FullName)}
        }}
        $Path=$found.ToArray()
    }
    foreach($target in @($Path|Select-Object -Unique)){
        $target=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($target)
        if([IO.Path]::GetExtension($target) -notin @('.csproj','.props')){throw 'Runtime targets must be .csproj or .props files.'}
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        if(!$target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,$comparison)){throw 'Project target is outside the selected checkout.'}
        if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source project links are not followed.'}
        $bytes=[IO.File]::ReadAllBytesAsync($target).GetAwaiter().GetResult()
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
        $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($text),$settings)
        $document=[Xml.XmlDocument]::new();$document.XmlResolver=$null
        try{$document.Load($reader)}finally{$reader.Dispose()}
        $nodes=@($document.SelectNodes('//*[local-name()="RuntimeFrameworkVersion"]'))
        $propertyMatches=[regex]::Matches($text,'<RuntimeFrameworkVersion\b[^>]*>(?<value>[^<]*)</RuntimeFrameworkVersion>')
        if($nodes.Count -ne $propertyMatches.Count){throw 'Runtime property XML form cannot be safely edited.'}
        $edits=[Collections.Generic.List[object]]::new()
        for($index=0;$index -lt $nodes.Count;$index++){
            $node=$nodes[$index];$condition=$node.GetAttribute('Condition')
            if(!$condition -and $node.ParentNode -is [Xml.XmlElement]){$condition=$node.ParentNode.GetAttribute('Condition')}
            $selected=$false
            if($condition){
                $pattern='^\s*[''" ]*\$\(TargetFramework\)[''" ]*\s*==\s*[''"]'+[regex]::Escape($Framework)+'[''"]\s*$'
                $selected=$condition -match $pattern
                if(!$selected -and $condition.Contains($Framework)){throw 'Ambiguous runtime property condition requires manual review.'}
            }else{
                $tfms=@($document.SelectNodes('//*[local-name()="TargetFramework" or local-name()="TargetFrameworks"]')|ForEach-Object { $_.InnerText -split ';' }|Select-Object -Unique)
                $selected=$tfms.Count -eq 1 -and $tfms[0] -ceq $Framework
                if(!$selected -and $Framework -in $tfms){throw 'An unconditional runtime pin in a multi-target project is ambiguous.'}
            }
            if(!$selected){continue}
            $previous=[System.Management.Automation.SemanticVersion]$node.InnerText.Trim()
            if(!$AllowDowngrade -and $semantic -lt $previous){throw 'Runtime downgrade requires -AllowDowngrade.'}
            $value=$propertyMatches[$index].Groups['value']
            $edits.Add([pscustomobject]@{Start=$value.Index;Length=$value.Length;Previous=$node.InnerText;Version=$Version})
        }
        if(!$edits.Count){continue}
        $updated=$text
        foreach($edit in @($edits|Sort-Object Start -Descending)){$updated=$updated.Remove($edit.Start,$edit.Length).Insert($edit.Start,$Version)}
        [pscustomobject]@{Path=$target;Hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));Changed=($text -cne $updated);Text=$updated;Edits=$edits.ToArray()}
    }
}

function Update-DotNetRuntimeFrameworkVersion {
    <#
    .SYNOPSIS
    Updates matching runtime pins to an explicit version or the current SDK release's runtime.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER Version
    Exact runtime version; omitted resolves the runtime paired with global.json's SDK.
    .PARAMETER Path
    Optional exact source project/props targets.
    .PARAMETER Framework
    Target framework, default net11.0.
    .PARAMETER Preleases
    Permits preview/RC runtime versions.
    .PARAMETER AllowDowngrade
    Explicit downgrade permission.
    .PARAMETER PlanOnly
    Return validated plans without writing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot=(Join-Path $PSScriptRoot '../..'),[string]$Version,[string[]]$Path,
        [ValidatePattern('^net\d+\.\d+$')][string]$Framework='net11.0',
        [Alias('Prerelease','Prereleases')][switch]$Preleases,[switch]$AllowDowngrade,[switch]$PlanOnly)
    $WorkspaceRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceRoot)
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,"Resolve and update $Framework runtime properties with backups")){return}
    if(!$Version){
        $global=(Read-DotNetLockJson (Join-Path $WorkspaceRoot 'global.json')).Data
        $sdk=[System.Management.Automation.SemanticVersion]$global.sdk.version
        $Version=(Get-DotNetSdkRelease -Channel "$($sdk.Major).$($sdk.Minor)" -Version $sdk.ToString() -Preleases:$Preleases -Confirm:$false).RuntimeVersion
    }else{
        $published=Get-DotNetRuntimeRelease -Version $Version -Preleases:$Preleases -Confirm:$false
        if($published.Version -cne $Version){throw 'Runtime metadata did not resolve the exact requested version.'}
    }
    $plans=@(Get-DotNetRuntimeFrameworkPlan -WorkspaceRoot $WorkspaceRoot -Version $Version -Path $Path -Framework $Framework -Preleases:$Preleases -AllowDowngrade:$AllowDowngrade)
    if(!$plans.Count){throw 'No unambiguous matching runtime property was found.'}
    if($PlanOnly){$plans;return}
    Write-DotNetLockPlans -Plans $plans
}

Export-ModuleMember -Function Resolve-DotNetBaseImage,Get-DotNetBaseImageTags,Update-DotNetCiLock,Get-DotNetRuntimeFrameworkPlan,Update-DotNetRuntimeFrameworkVersion
