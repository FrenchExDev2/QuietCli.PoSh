#requires -Version 7.6
Set-StrictMode -Version Latest

function Invoke-QuietGitHubActionApi {
    <#
    .SYNOPSIS
    Sends one bounded GET to the GitHub REST API and returns {Status, Body}, Body being the parsed JSON or null.
    .DESCRIPTION
    Only https://api.github.com/repos/... paths are accepted (GitHubActionApiPathInvalid otherwise). The request
    uses GH_TOKEN, else GITHUB_TOKEN, as a bearer token when one is set, and anonymous access otherwise; the
    token is never printed. HTTP errors are returned as a status, not thrown, so the caller decides; a transport
    failure (DNS, TLS, timeout) throws GitHubActionApiUnavailable.
    .PARAMETER Path
    API path starting with /repos/, for example /repos/actions/checkout/releases/latest.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if($Path -cnotmatch '\A/repos/[A-Za-z0-9._/%-]+\z' -or $Path.Contains('..')){throw ('GitHubActionApiPathInvalid: '+$Path)}
    $headers=@{Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28';'User-Agent'='QuietCli-GitHub-Action-Updates'}
    $token=if(![string]::IsNullOrWhiteSpace($env:GH_TOKEN)){$env:GH_TOKEN}elseif(![string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)){$env:GITHUB_TOKEN}
    if($token){$headers.Authorization='Bearer '+$token}
    try{
        $response=Invoke-WebRequest -Uri ('https://api.github.com'+$Path) -Method Get -Headers $headers -SkipHttpErrorCheck -TimeoutSec 30 -MaximumRetryCount 2 -RetryIntervalSec 2 -ErrorAction Stop
    }catch{throw ('GitHubActionApiUnavailable: '+$Path+': '+$_.Exception.Message)}
    $status=[int]$response.StatusCode
    $body=$null
    if($status -ge 200 -and $status -lt 300 -and ![string]::IsNullOrWhiteSpace([string]$response.Content)){
        try{$body=[string]$response.Content|ConvertFrom-Json -Depth 16 -ErrorAction Stop}catch{throw ('GitHubActionApiResponseInvalid: '+$Path)}
    }
    [pscustomobject]@{Status=$status;Body=$body}
}

function Get-QuietGitHubActionLatestRelease {
    <#
    .SYNOPSIS
    Resolves the latest published release of an action repository to its tag and commit id.
    .DESCRIPTION
    Reads /releases/latest, which GitHub defines as the most recent non-draft, non-prerelease release, then
    peels its tag ref to a commit, through at most four annotated tag objects. Returns
    {Action, Status, Tag, Sha, Source}: Status Resolved, or NoRelease when the repository has no release (HTTP
    404). Any other HTTP status, an invalid tag or id, or a tag that does not peel to a commit throws
    GitHubActionReleaseUnknown: an unreachable or rate-limited API never reads as "no release".
    .PARAMETER Action
    owner/repository.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}\z')][string]$Action)
    $latest=Invoke-QuietGitHubActionApi -Path ('/repos/'+$Action+'/releases/latest')
    if($latest.Status -eq 404){return [pscustomobject]@{Action=$Action;Status='NoRelease';Tag=$null;Sha=$null;Source='GitHub'}}
    if($latest.Status -ne 200 -or $null -eq $latest.Body){throw ('GitHubActionReleaseUnknown: '+$Action+' latest release HTTP '+$latest.Status)}
    $tag=[string]$latest.Body.tag_name
    Assert-QuietGitHubActionTag -Action $Action -Tag $tag
    $reference=Invoke-QuietGitHubActionApi -Path ('/repos/'+$Action+'/git/ref/tags/'+[Uri]::EscapeDataString($tag))
    if($reference.Status -ne 200 -or $null -eq $reference.Body){throw ('GitHubActionReleaseUnknown: '+$Action+' tag '+$tag+' HTTP '+$reference.Status)}
    $target=$reference.Body.object
    for($depth=0;[string]$target.type -ceq 'tag' -and $depth -lt 4;$depth++){
        if([string]$target.sha -cnotmatch '\A[0-9a-f]{40}\z'){throw ('GitHubActionReleaseUnknown: '+$Action+' tag object id invalid')}
        $tagObject=Invoke-QuietGitHubActionApi -Path ('/repos/'+$Action+'/git/tags/'+$target.sha)
        if($tagObject.Status -ne 200 -or $null -eq $tagObject.Body){throw ('GitHubActionReleaseUnknown: '+$Action+' tag object HTTP '+$tagObject.Status)}
        $target=$tagObject.Body.object
    }
    if([string]$target.type -cne 'commit' -or [string]$target.sha -cnotmatch '\A[0-9a-f]{40}\z'){throw ('GitHubActionReleaseUnknown: '+$Action+' tag '+$tag+' does not peel to a commit')}
    [pscustomobject]@{Action=$Action;Status='Resolved';Tag=$tag;Sha=[string]$target.sha;Source='GitHub'}
}

function Assert-QuietGitHubActionTag {
    <#
    .SYNOPSIS
    Rejects a release tag that cannot be written as a uses: ref or a comment: GitHubActionReleaseUnknown.
    .PARAMETER Action
    owner/repository, reported in the error.
    .PARAMETER Tag
    Release tag name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Action,[AllowEmptyString()][AllowNull()][string]$Tag)
    if([string]$Tag -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._+-]{0,127}\z'){throw ('GitHubActionReleaseUnknown: '+$Action+' release tag invalid: '+$Tag)}
}

function Read-QuietGitHubActionReleaseCatalog {
    <#
    .SYNOPSIS
    Reads a reviewed JSON release catalog, {"owner/repository": {"Tag": "v1.2.3", "Sha": "<40 hex>"}}, into release objects.
    .DESCRIPTION
    The catalog replaces the GitHub API: offline runs, reproducible reviews and tests. Each entry becomes
    {Action, Status Resolved, Tag, Sha, Source Catalog}; an entry whose value is null becomes Status NoRelease.
    Keys are compared ordinally (GitHub names are case-insensitive, references in this repository are not
    mixed-case duplicates). Malformed JSON, a key that is not owner/repository, a duplicate key, an invalid tag
    or an id that is not 40 lowercase hexadecimal digits throws GitHubActionCatalogInvalid.
    .PARAMETER Path
    UTF-8 JSON file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $utf8=[Text.Encoding]::GetEncoding(65001,[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
    try{$text=[IO.File]::ReadAllText($Path,$utf8)}
    catch [Text.DecoderFallbackException]{throw ('GitHubActionCatalogInvalid: '+$Path+' is not UTF-8')}
    try{$catalog=ConvertFrom-Json -InputObject $text -AsHashtable -Depth 4 -ErrorAction Stop}catch{throw ('GitHubActionCatalogInvalid: '+$Path+' is not JSON')}
    if($catalog -isnot [Collections.IDictionary]){throw ('GitHubActionCatalogInvalid: '+$Path+' must be an object')}
    $releases=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($key in $catalog.Keys){
        if([string]$key -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}\z'){throw ('GitHubActionCatalogInvalid: key '+$key)}
        $entry=$catalog[$key]
        if($null -eq $entry){$releases[$key]=[pscustomobject]@{Action=$key;Status='NoRelease';Tag=$null;Sha=$null;Source='Catalog'};continue}
        if($entry -isnot [Collections.IDictionary] -or !$entry.Contains('Tag') -or !$entry.Contains('Sha')){throw ('GitHubActionCatalogInvalid: '+$key+' needs Tag and Sha')}
        try{Assert-QuietGitHubActionTag -Action $key -Tag ([string]$entry['Tag'])}catch{throw ('GitHubActionCatalogInvalid: '+$key+' tag '+$entry['Tag'])}
        if([string]$entry['Sha'] -cnotmatch '\A[0-9a-f]{40}\z'){throw ('GitHubActionCatalogInvalid: '+$key+' sha '+$entry['Sha'])}
        $releases[$key]=[pscustomobject]@{Action=$key;Status='Resolved';Tag=[string]$entry['Tag'];Sha=[string]$entry['Sha'];Source='Catalog'}
    }
    $releases
}

function Resolve-QuietGitHubActionReleases {
    <#
    .SYNOPSIS
    Resolves the latest release of each distinct action, from a catalog when one is given, else from GitHub.
    .DESCRIPTION
    Returns an ordinal dictionary from owner/repository to the release object. Every action is resolved before
    the caller decides anything, so one unknown release fails the whole batch (GitHubActionReleaseUnknown) and no
    file is half updated. With a catalog, an action missing from it throws GitHubActionReleaseUnknown too.
    .PARAMETER Actions
    owner/repository names; duplicates are resolved once.
    .PARAMETER Catalog
    Optional dictionary returned by Read-QuietGitHubActionReleaseCatalog.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Actions,[Collections.Generic.Dictionary[string,object]]$Catalog)
    $releases=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($action in $Actions){
        if($releases.ContainsKey($action)){continue}
        if($null -ne $Catalog){
            $entry=$null
            if(!$Catalog.TryGetValue($action,[ref]$entry)){throw ('GitHubActionReleaseUnknown: '+$action+' is not in the release catalog')}
            $releases[$action]=$entry
        }else{
            $releases[$action]=Get-QuietGitHubActionLatestRelease -Action $action
        }
    }
    $releases
}

Export-ModuleMember -Function 'Invoke-QuietGitHubActionApi','Get-QuietGitHubActionLatestRelease','Assert-QuietGitHubActionTag','Read-QuietGitHubActionReleaseCatalog','Resolve-QuietGitHubActionReleases'
