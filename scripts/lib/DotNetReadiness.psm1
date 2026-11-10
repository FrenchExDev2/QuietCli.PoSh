#Requires -Version 7.6
Set-StrictMode -Version Latest

function Invoke-DotNetReadinessHttp {
    <#
    .SYNOPSIS
    Reads bounded public HTTP evidence without retries or certificate bypasses.
    .PARAMETER Uri
    HTTPS metadata, archive or registry resource to inspect.
    .PARAMETER Method
    GET reads JSON; HEAD checks archive availability without downloading it.
    .PARAMETER TimeoutSeconds
    Maximum duration of one HTTP request.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri, [ValidateSet('GET','HEAD')][string]$Method = 'GET',
        [ValidateRange(1,120)][int]$TimeoutSeconds = 20)
    if ($Uri.Scheme -ne 'https') { throw 'Only HTTPS evidence is accepted.' }
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $client.MaxResponseContentBufferSize = 8MB
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    $null = $request.Headers.TryAddWithoutValidation('Accept', 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/json')
    $response = $null
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $body = if ($Method -eq 'GET') { $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } else { '' }
        $digest = if ($response.Headers.Contains('Docker-Content-Digest')) { @($response.Headers.GetValues('Docker-Content-Digest'))[0] } else { $null }
        [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $body; Digest = $digest }
    }
    finally { if ($response) { $response.Dispose() }; $request.Dispose(); $client.Dispose() }
}

function Select-DotNetReadinessSdk {
    <#
    .SYNOPSIS
    Selects the highest published semantic SDK version in one channel.
    .PARAMETER Metadata
    Parsed Microsoft releases.json hashtable.
    .PARAMETER Channel
    Requested major.minor channel.
    .PARAMETER Preleases
    Includes preview and RC versions; stable versions still participate.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Metadata, [Parameter(Mandatory)][string]$Channel,
        [switch]$Preleases)
    if ($Metadata['channel-version'] -ne $Channel -or $Metadata['releases'] -isnot [array]) { throw 'Invalid release metadata channel or releases.' }
    $candidates = @(foreach ($release in $Metadata.releases) {
        foreach ($sdk in @($release['sdks']) + @($release['sdk'])) {
            if ($null -eq $sdk) { continue }
            $version = [System.Management.Automation.SemanticVersion]$sdk.version
            if ("$($version.Major).$($version.Minor)" -ne $Channel) { continue }
            if (!$Preleases -and $version.PreReleaseLabel) { continue }
            if ($sdk['files'] -isnot [array]) { throw 'Invalid SDK files.' }
            [pscustomobject]@{ Version = [string]$sdk.version; SemanticVersion = $version;
                RuntimeVersion = [string]$release['release-version']; ReleaseDate = [string]$release['release-date']; Files = $sdk.files }
        }
    })
    $candidates | Sort-Object SemanticVersion -Descending | Select-Object -First 1
}

function Get-DotNetReadinessImage {
    <#
    .SYNOPSIS
    Resolves an MCR manifest and verifies each requested OS/architecture.
    .PARAMETER Repository
    Official dotnet repository name.
    .PARAMETER Tag
    Exact floating or versioned image tag to query.
    .PARAMETER Platform
    Required OCI platforms. Windows build compatibility is outside this check.
    .PARAMETER TimeoutSeconds
    Maximum duration of each registry request.
    #>
    [CmdletBinding()]
    param([ValidateSet('sdk','runtime','aspnet','runtime-deps')][string]$Repository,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$Tag,
        [Parameter(Mandatory)][string[]]$Platform, [int]$TimeoutSeconds = 20)
    $url = "https://mcr.microsoft.com/v2/dotnet/$Repository/manifests/$Tag"
    try {
        $response = Invoke-DotNetReadinessHttp -Uri $url -TimeoutSeconds $TimeoutSeconds
        if ($response.StatusCode -eq 404) { $status = 'Missing'; $detail = 'Registry returned HTTP 404.'; $platforms = @() }
        elseif ($response.StatusCode -ne 200) { throw "Registry returned HTTP $($response.StatusCode)." }
        else {
            $manifest = ConvertFrom-Json -InputObject $response.Body -AsHashtable -Depth 64 -ErrorAction Stop
            if ($manifest['schemaVersion'] -ne 2) { throw 'Invalid manifest schema.' }
            $platforms = @(if ($manifest['manifests']) {
                foreach ($entry in $manifest.manifests) {
                    if ($entry['digest'] -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Invalid child manifest digest.' }
                    if ($entry['platform'] -and $entry.platform['os'] -and $entry.platform['architecture']) {
                        "$($entry.platform.os)/$($entry.platform.architecture)"
                    }
                }
            }
            elseif ($manifest['config'] -and $manifest.config['digest'] -match '^sha256:[a-f0-9]{64}$') {
                $configResponse = Invoke-DotNetReadinessHttp -Uri "https://mcr.microsoft.com/v2/dotnet/$Repository/blobs/$($manifest.config.digest)" -TimeoutSeconds $TimeoutSeconds
                if ($configResponse.StatusCode -ne 200) { throw "Config returned HTTP $($configResponse.StatusCode)." }
                $config = ConvertFrom-Json -InputObject $configResponse.Body -AsHashtable -Depth 64 -ErrorAction Stop
                if (!$config['os'] -or !$config['architecture']) { throw 'Missing image config platform.' }
                "$($config.os)/$($config.architecture)"
            }
            else { throw 'Manifest contains no platform evidence.' })
            if (!$platforms.Count) { throw 'Manifest contains no platform evidence.' }
            $missing = @($Platform | Where-Object { $_ -notin $platforms })
            $status = if ($missing.Count) { 'Missing' } else { 'Available' }
            $detail = if ($missing.Count) { 'Missing platforms: ' + ($missing -join ', ') } else { 'All requested platforms are present in the manifest.' }
        }
        [pscustomobject]@{ Category = 'Image'; Target = "mcr.microsoft.com/dotnet/${Repository}:$Tag";
            Status = $status; Detail = $detail; Evidence = $url; Digest = $response.Digest; Platforms = @($platforms) }
    }
    catch {
        [pscustomobject]@{ Category = 'Image'; Target = "mcr.microsoft.com/dotnet/${Repository}:$Tag";
            Status = 'Unknown'; Detail = $_.Exception.Message; Evidence = $url; Digest = $null; Platforms = @() }
    }
}

function ConvertFrom-DotNetReadinessRecord {
    <#
    .SYNOPSIS
    Parses a single documented dotnet discovery record, accepting CRLF and LF.
    .PARAMETER Text
    One stdout record; unrelated output is rejected.
    .PARAMETER Kind
    Installed SDK, installed runtime or selected SDK version.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [ValidateSet('Sdk','Runtime','Selected')][string]$Kind)
    $line = $Text.Trim()
    if (!$line) { return }
    $versionPattern = '\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?'
    $pattern = switch ($Kind) {
        Sdk { "^(?<version>$versionPattern) \[(?<path>.+)\]$" }
        Runtime { "^(?<name>Microsoft\.[A-Za-z0-9.]+) (?<version>$versionPattern) \[(?<path>.+)\]$" }
        Selected { "^(?<version>$versionPattern)$" }
    }
    if ($line -notmatch $pattern) { throw "Unexpected dotnet $Kind record." }
    $parsed = [System.Management.Automation.SemanticVersion]$Matches.version
    [pscustomobject]@{ Version = $parsed.ToString(); Name = if ($Kind -eq 'Runtime') { $Matches.name } else { 'SDK' } }
}

function Import-DotNetProcessHelper {
    <# .SYNOPSIS Loads the engine-independent process helper into the dot-sourcing caller. #>
    param([string]$QuietCliRoot)
    $QuietCliRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($QuietCliRoot)
    . (Join-Path $QuietCliRoot 'scripts/Ci.Process.ps1')
}

function Get-DotNetReadinessLocal {
    <#
    .SYNOPSIS
    Reads SDK/runtime inventories and actual SDK resolution through Ci.Process.ps1.
    .PARAMETER ProjectPath
    Existing directory used for actual dotnet --version and global.json resolution.
    .PARAMETER QuietCliRoot
    Exact checkout whose engine-independent process helper must be used.
    .PARAMETER DotNetPath
    Exact dotnet host to inspect; defaults to PATH lookup.
    .PARAMETER InventoryOnly
    Does not resolve the selected SDK, which can be constrained by global.json.
    #>
    [CmdletBinding()]
    param([string]$ProjectPath, [string]$QuietCliRoot, [string]$DotNetPath = 'dotnet', [switch]$InventoryOnly)
    . Import-DotNetProcessHelper -QuietCliRoot $QuietCliRoot
    $results = @{}
    $kinds = if ($InventoryOnly) { @('Sdk','Runtime') } else { @('Sdk','Runtime','Selected') }
    foreach ($kind in $kinds) {
        $argument = switch ($kind) { Sdk { '--list-sdks' }; Runtime { '--list-runtimes' }; Selected { '--version' } }
        $state = @{ Kind = $kind; Records = [Collections.Generic.List[object]]::new() }
        $result = Invoke-CiProcess -WorkingDirectory $ProjectPath -TimeoutSeconds 30 -State $state -OnOutput {
            param($event, $data)
            if ($event.Stream -eq 'stdout') {
                $record = ConvertFrom-DotNetReadinessRecord -Text $event.Text -Kind $data.Kind
                if ($record) { [void]$data.Records.Add($record) }
            }
        } -FilePath $DotNetPath -ArgumentList @($argument)
        $ok = $result.Outcome -eq 'Success' -and $result.ExitCode -eq 0
        $results[$kind] = [pscustomobject]@{ Success = $ok; Records = @($state.Records.ToArray()); Outcome = $result.Outcome }
    }
    $results
}

function Get-DotNetReadiness {
    <#
    .SYNOPSIS
    Checks published SDKs, archive URLs, MCR platforms and local .NET readiness.
    .DESCRIPTION
    Read-only probes are gated by ShouldProcess: WhatIf makes no HTTP/native calls,
    imports no engine and writes no report. No SDK/image is installed or pulled.
    .PARAMETER Channel
    Microsoft major.minor release channel. Defaults to 11.0.
    .PARAMETER Preleases
    Includes prerelease and RC SDK candidates. Alias: Prerelease or Prereleases.
    .PARAMETER Rid
    SDK archive runtime identifiers. Defaults to the current PowerShell host RID.
    .PARAMETER Platform
    Required container OS/architecture pairs. Defaults to linux/amd64 and linux/arm64.
    .PARAMETER ImageVariant
    Optional official tag suffix, for example alpine or resolute.
    .PARAMETER ProjectPath
    Directory in which dotnet resolves the SDK, including ancestor global.json.
    .PARAMETER SkipLocal
    Checks publication only; local readiness remains unassessed.
    .PARAMETER ReportPath
    Optional UTF-8/LF JSON report. Parent directory must already exist.
    .PARAMETER TimeoutSeconds
    Timeout for each HTTP request; requests are never automatically retried.
    .PARAMETER QuietCliRoot
    Exact local QuietCli2 checkout, required only for local native discovery.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel = '11.0',
        [Alias('Prerelease','Prereleases')][switch]$Preleases,
        [ValidateNotNullOrEmpty()][ValidatePattern('^(win|linux|linux-musl|osx)-(x64|x86|arm64|arm)$')][string[]]$Rid = @([Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier),
        [ValidateNotNullOrEmpty()][ValidateSet('linux/amd64','linux/arm64','windows/amd64','windows/arm64')][string[]]$Platform = @('linux/amd64','linux/arm64'),
        [ValidatePattern('^$|^[a-z0-9][a-z0-9.-]*$')][string]$ImageVariant = '',
        [string]$ProjectPath = (Join-Path $PSScriptRoot '../..'),
        [switch]$SkipLocal, [string]$ReportPath,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 20,
        [string]$QuietCliRoot = (Join-Path $PSScriptRoot '../..')
    )
    $ProjectPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectPath)
    if($ReportPath){$ReportPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)}
    if (!$SkipLocal -and !(Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw 'ProjectPath must be an existing directory.' }
    if ($ReportPath -and !(Test-Path -LiteralPath (Split-Path ([IO.Path]::GetFullPath($ReportPath)) -Parent) -PathType Container)) { throw 'ReportPath parent must exist.' }
    $checks = [Collections.Generic.List[object]]::new()
    $metadataUrl = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json"
    $candidate = $null
    if ($PSCmdlet.ShouldProcess(".NET $Channel ($metadataUrl)", 'Read release metadata, HEAD SDK archives and query MCR manifests')) {
        try {
            $response = Invoke-DotNetReadinessHttp -Uri $metadataUrl -TimeoutSeconds $TimeoutSeconds
            if ($response.StatusCode -eq 404) {
                $checks.Add([pscustomobject]@{Category='Publication';Target=$Channel;Status='Missing';Detail='Channel metadata returned HTTP 404.';Evidence=$metadataUrl})
            }
            elseif ($response.StatusCode -ne 200) { throw "Release metadata returned HTTP $($response.StatusCode)." }
            else {
                $metadata = ConvertFrom-Json -InputObject $response.Body -AsHashtable -Depth 64 -ErrorAction Stop
                $candidate = Select-DotNetReadinessSdk -Metadata $metadata -Channel $Channel -Preleases:$Preleases
                $status = if ($candidate) { 'Available' } else { 'Missing' }
                $detail = if ($candidate) { "SDK $($candidate.Version), released $($candidate.ReleaseDate)." } else { 'No eligible SDK published. Use -Preleases to include preview and RC.' }
                $checks.Add([pscustomobject]@{Category='Publication';Target=$Channel;Status=$status;Detail=$detail;Evidence=$metadataUrl})
            }
        }
        catch { $checks.Add([pscustomobject]@{Category='Publication';Target=$Channel;Status='Unknown';Detail=$_.Exception.Message;Evidence=$metadataUrl}) }
        if ($candidate) {
            foreach ($targetRid in @($Rid | Select-Object -Unique)) {
                $file = $candidate.Files | Where-Object { $_.rid -eq $targetRid -and $_.name -match '^dotnet-sdk-.*\.(tar\.gz|zip)$' } | Sort-Object name | Select-Object -First 1
                $url = $null
                try {
                    if (!$file) { $status = 'Missing'; $detail = 'No SDK archive published for this RID.' }
                    else {
                        $url = [string]$file.url
                        if (([uri]$url).Scheme -ne 'https' -or ([uri]$url).Host -notin @('builds.dotnet.microsoft.com','download.visualstudio.microsoft.com','ci.dot.net','dotnetcli.azureedge.net')) { throw 'Untrusted SDK archive URL.' }
                        if ($file.hash -notmatch '^[a-fA-F0-9]{128}$') { throw 'Missing or invalid published SHA-512.' }
                        $head = Invoke-DotNetReadinessHttp -Uri $url -Method HEAD -TimeoutSeconds $TimeoutSeconds
                        $status = if ($head.StatusCode -ge 200 -and $head.StatusCode -lt 300) { 'Available' } elseif ($head.StatusCode -eq 404) { 'Missing' } else { 'Unknown' }
                        $detail = "Archive HEAD returned HTTP $($head.StatusCode); published SHA-512 is metadata only, archive bytes were not downloaded or verified."
                    }
                }
                catch { $status = 'Unknown'; $detail = $_.Exception.Message }
                $checks.Add([pscustomobject]@{Category='SdkArchive';Target=$targetRid;Status=$status;Detail=$detail;Evidence=$url})
            }
            $tag = $Channel + $(if ($candidate.SemanticVersion.PreReleaseLabel) { '-preview' }) + $(if ($ImageVariant) { "-$ImageVariant" })
            foreach ($repository in @('sdk','runtime','aspnet','runtime-deps')) {
                $checks.Add((Get-DotNetReadinessImage -Repository $repository -Tag $tag -Platform $Platform -TimeoutSeconds $TimeoutSeconds))
            }
        }
    }
    else { $checks.Add([pscustomobject]@{Category='Publication';Target=$Channel;Status='NotChecked';Detail='Publication probes were declined or previewed.';Evidence=$metadataUrl}) }
    $globalJson = $null
    if (!$SkipLocal -and $PSCmdlet.ShouldProcess($ProjectPath, 'Read local dotnet SDK/runtime inventories and resolve the selected SDK')) {
        $directory = Get-Item -LiteralPath $ProjectPath
        while ($directory) {
            $pin = Join-Path $directory.FullName 'global.json'
            if (Test-Path -LiteralPath $pin -PathType Leaf) { $globalJson = $pin; break }
            $directory = $directory.Parent
        }
        try {
            $local = Get-DotNetReadinessLocal -ProjectPath $ProjectPath -QuietCliRoot $QuietCliRoot
            foreach ($kind in @('Sdk','Runtime','Selected')) {
                $records = @($local[$kind].Records)
                $eligible = @($records | Where-Object {
                    $v = [System.Management.Automation.SemanticVersion]$_.Version
                    "$($v.Major).$($v.Minor)" -eq $Channel -and ($Preleases -or !$v.PreReleaseLabel) -and
                    ($kind -ne 'Runtime' -or $_.Name -eq 'Microsoft.NETCore.App')
                })
                $status = if (!$local[$kind].Success) { 'Unknown' } elseif ($eligible.Count) { 'Available' } else { 'Missing' }
                $detail = if (!$local[$kind].Success) { "dotnet $kind discovery failed or was incomplete." } else { ($records | ForEach-Object { "$($_.Name) $($_.Version)" }) -join '; ' }
                $checks.Add([pscustomobject]@{Category="Local$kind";Target=$ProjectPath;Status=$status;Detail=$detail;Evidence=$globalJson})
            }
        }
        catch { $checks.Add([pscustomobject]@{Category='Local';Target=$ProjectPath;Status='Unknown';Detail=$_.Exception.Message;Evidence=$globalJson}) }
    }
    else { $checks.Add([pscustomobject]@{Category='Local';Target=$ProjectPath;Status='NotChecked';Detail='Local probes were skipped, declined or previewed.';Evidence=$null}) }
    $publicationChecks = @($checks | Where-Object Category -in @('Publication','SdkArchive','Image'))
    $localChecks = @($checks | Where-Object Category -like 'Local*')
    $publicationReady = $publicationChecks.Count -eq (5 + @($Rid | Select-Object -Unique).Count) -and @($publicationChecks | Where-Object Status -ne Available).Count -eq 0
    $localReady = $localChecks.Count -eq 3 -and @($localChecks | Where-Object Status -ne Available).Count -eq 0
    $report = [pscustomobject]@{
        SchemaVersion = 1; CheckedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); Channel = $Channel
        IncludesPrereleases = [bool]$Preleases; SelectedSdk = if ($candidate) { $candidate.Version } else { $null }
        RequestedRids = $Rid; RequestedPlatforms = $Platform; GlobalJson = $globalJson
        PublicationReady = $publicationReady; LocalReady = $localReady; Ready = $publicationReady -and $localReady
        Scope = 'Availability only. Local checks accept eligible channel versions; they do not require the latest patch. No restore, build, workload, image pull/run or application compatibility test.'
        Checks = $checks.ToArray()
    }
    if ($ReportPath -and $PSCmdlet.ShouldProcess($ReportPath, 'Write readiness JSON report (replace existing file)')) {
        $json = ($report | ConvertTo-Json -Depth 16).Replace("`r`n", "`n") + "`n"
        $null = [IO.File]::WriteAllTextAsync([IO.Path]::GetFullPath($ReportPath), $json, [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    $report
}

function Get-DotNetSdkRelease {
    <#
    .SYNOPSIS
    Resolves an official SDK release and its published archive hashes.
    .PARAMETER Channel
    Microsoft major.minor channel.
    .PARAMETER Version
    Optional exact SDK version within the channel.
    .PARAMETER Preleases
    Includes preview and RC releases; required for an explicit prerelease version.
    .PARAMETER TimeoutSeconds
    Per-request metadata timeout.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel = '11.0',
        [string]$Version, [Alias('Prerelease','Prereleases')][switch]$Preleases,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 20)
    if ($Version) {
        $v = [System.Management.Automation.SemanticVersion]$Version
        if ("$($v.Major).$($v.Minor)" -ne $Channel -or (!$Preleases -and $v.PreReleaseLabel)) { throw 'Version must belong to Channel and satisfy the prerelease policy.' }
    }
    if (!$PSCmdlet.ShouldProcess(".NET $Channel",'Read official SDK release metadata')) { return }
    $url = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json"
    $response = Invoke-DotNetReadinessHttp -Uri $url -TimeoutSeconds $TimeoutSeconds
    if ($response.StatusCode -ne 200) { throw "Release metadata returned HTTP $($response.StatusCode)." }
    $metadata = ConvertFrom-Json -InputObject $response.Body -AsHashtable -Depth 64 -ErrorAction Stop
    if ($Version) {
        $metadata['releases'] = @(foreach ($release in $metadata['releases']) {
            $matches = @(@($release['sdks']) + @($release['sdk']) | Where-Object { $_ -and $_.version -eq $Version })
            if ($matches.Count) { $copy = @{} + $release; $copy['sdk'] = $null; $copy['sdks'] = $matches; $copy }
        })
    }
    $selected = Select-DotNetReadinessSdk -Metadata $metadata -Channel $Channel -Preleases:$Preleases
    if (!$selected) { throw 'No published SDK satisfies the requested version policy.' }
    $selected
}

function Get-DotNetInstallation {
    <#
    .SYNOPSIS
    Reads SDK/runtime inventories from an exact host, independently of SDK pins.
    .PARAMETER DotNetPath
    Absolute installed host path, or dotnet for PATH lookup.
    .PARAMETER ProjectPath
    Existing working directory. No --version selection is performed.
    .PARAMETER QuietCliRoot
    Selected built QuietCli2 checkout.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$DotNetPath = 'dotnet', [string]$ProjectPath = (Get-Location).Path,
        [string]$QuietCliRoot = (Join-Path $PSScriptRoot '../..'))
    $ProjectPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectPath)
    if($DotNetPath -ne 'dotnet'){$DotNetPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DotNetPath)}
    if ($PSCmdlet.ShouldProcess($DotNetPath,'Read complete installed SDK and runtime inventories')) {
        Get-DotNetReadinessLocal -ProjectPath $ProjectPath -QuietCliRoot $QuietCliRoot -DotNetPath $DotNetPath -InventoryOnly
    }
}

function Invoke-DotNetContainerPull {
    <#
    .SYNOPSIS
    Pulls one explicit MCR image/platform through the independent process helper.
    .PARAMETER ContainerRuntime
    Explicit docker or podman; no daemon is started and no runtime is inferred.
    .PARAMETER Image
    Fully qualified official dotnet image reference.
    .PARAMETER Platform
    Explicit OCI platform to download.
    .PARAMETER QuietCliRoot
    Selected built QuietCli2 checkout.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('docker','podman')][string]$ContainerRuntime,
        [Parameter(Mandatory)][ValidatePattern('^mcr\.microsoft\.com/dotnet/(sdk|runtime|aspnet|runtime-deps):[A-Za-z0-9_.-]+$')][string]$Image,
        [ValidateSet('linux/amd64','linux/arm64','windows/amd64','windows/arm64')][string]$Platform = 'linux/amd64',
        [string]$QuietCliRoot = (Join-Path $PSScriptRoot '../..'))
    if (!$PSCmdlet.ShouldProcess("$Image ($Platform)","Pull image using $ContainerRuntime")) { return }
    . Import-DotNetProcessHelper -QuietCliRoot $QuietCliRoot
    $arguments = @('pull','--quiet','--platform',$Platform)
    if ($ContainerRuntime -eq 'podman') { $arguments += '--retry=0' }
    $arguments += $Image
    $data=@{Records=0;Digest=$null}
    $result = Invoke-CiProcess -TimeoutSeconds 1800 -State $data -OnOutput {
        param($event,$state)
        $state.Records++
        if ($event.Text.Trim() -match '^sha256:[a-f0-9]{64}$') { $state.Digest = $event.Text.Trim() }
    } -FilePath $ContainerRuntime -ArgumentList $arguments
    if ($result.Outcome -ne 'Success' -or $result.ExitCode -ne 0) { throw "Image pull failed or was incomplete: $Image ($Platform), outcome $($result.Outcome)." }
    [pscustomobject]@{Image=$Image;Platform=$Platform;Status='Pulled';Digest=$data.Digest}
}

Export-ModuleMember -Function Get-DotNetReadiness,Get-DotNetSdkRelease,Get-DotNetInstallation,Invoke-DotNetContainerPull
