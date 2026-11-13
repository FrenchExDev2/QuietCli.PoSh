#requires -Version 7.6
function Send-QuietGitHubReleaseRequest {
    <#
    .SYNOPSIS
    Sends one authenticated GitHub request without retries or credential output.
    .PARAMETER Method
    REST method.
    .PARAMETER Uri
    GitHub API or release-upload endpoint selected by the caller.
    .PARAMETER Body
    Optional JSON request object.
    .PARAMETER InFile
    Optional verified asset streamed from disk.
    #>
    param([string]$Method,[string]$Uri,[object]$Body,[string]$InFile)
    if([string]::IsNullOrWhiteSpace($env:GH_TOKEN)){throw 'GitHubReleaseTokenRequired'}
    $options=@{Method=$Method;Uri=$Uri;Headers=@{Authorization='Bearer '+$env:GH_TOKEN;Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'};ErrorAction='Stop';MaximumRetryCount=0;TimeoutSec=300}
    if($InFile){$options.InFile=$InFile;$options.ContentType='application/octet-stream'}
    elseif($null -ne $Body){$options.Body=[Text.Encoding]::UTF8.GetBytes(($Body|ConvertTo-Json -Depth 8 -Compress));$options.ContentType='application/json; charset=utf-8'}
    Invoke-RestMethod @options
}

function Publish-QuietGitHubRelease {
    <#
    .SYNOPSIS
    Publishes one tag-bound release only after all verified assets have been uploaded to a draft.
    .PARAMETER Tag
    Existing independently versioned module tag.
    .PARAMETER Revision
    Exact qualified commit to which the remote tag must peel.
    .PARAMETER Assets
    Verified local files to attach without rebuilding or replacing existing assets.
    .PARAMETER Version
    Exact package version determining prerelease status.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Tag,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
        [Parameter(Mandatory)][string[]]$Assets,[Parameter(Mandatory)][string]$Version)
    if($Tag -cnotmatch '\AFrenchExDev2\.QuietCli\.[A-Za-z0-9_.-]+\.PoSh/v(.+)\z' -or $Matches[1] -cne $Version){throw 'GitHubReleaseTagVersionMismatch'}
    $null=[semver]$Version
    if(!$Assets.Count -or $Assets.Count -gt 10){throw 'GitHubReleaseAssetsInvalid'}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files=@(foreach($path in $Assets){
        $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($file.PSIsContainer -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint -or $file.Length -ge 2GB -or !$names.Add($file.Name)){throw 'GitHubReleaseAssetsInvalid'}
        [pscustomobject]@{Path=$file.FullName;Name=$file.Name;Size=$file.Length;Digest='sha256:'+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    if(!$PSCmdlet.ShouldProcess($Tag,'Create GitHub release with verified Gallery assets')){return}
    $api='https://api.github.com/repos/FrenchExDev2/QuietCli.PoSh'
    $escaped=[Uri]::EscapeDataString($Tag)
    $reference=Send-QuietGitHubReleaseRequest -Method GET -Uri "$api/git/ref/tags/$escaped"
    $target=$reference.object
    for($depth=0;$target.type -ceq 'tag' -and $depth -lt 4;$depth++){
        if($target.sha -cnotmatch '\A[a-f0-9]{40}\z'){throw 'GitHubReleaseTagInvalid'}
        $target=(Send-QuietGitHubReleaseRequest -Method GET -Uri "$api/git/tags/$($target.sha)").object
    }
    if($target.type -cne 'commit' -or $target.sha -cne $Revision){throw 'GitHubReleaseRevisionMismatch'}
    $release=$null
    try{$release=Send-QuietGitHubReleaseRequest -Method GET -Uri "$api/releases/tags/$escaped"}catch{
        if([int]$_.Exception.Response.StatusCode -ne 404){throw}
    }
    # Existing releases/drafts require deliberate recovery; never replace published bytes.
    if($null -ne $release){throw 'GitHubReleaseAlreadyExists'}
    $body="Verified PowerShell Gallery package for ``$Tag``.`n`nQualified revision: ``$Revision``.`n`nThe attached nupkg is the exact package published on PowerShell Gallery. package-set.json records its SHA-256; publication.json records successful publication."
    $release=Send-QuietGitHubReleaseRequest -Method POST -Uri "$api/releases" -Body @{
        tag_name=$Tag;target_commitish=$Revision;name=$Tag;body=$body;draft=$true;prerelease=$Version.Contains('-');make_latest='false'
    }
    if($release.id -isnot [long] -and $release.id -isnot [int] -or $release.id -le 0 -or !$release.draft -or $release.tag_name -cne $Tag){throw 'GitHubReleaseDraftInvalid'}
    foreach($file in $files){
        $asset=Send-QuietGitHubReleaseRequest -Method POST -Uri ('https://uploads.github.com/repos/FrenchExDev2/QuietCli.PoSh/releases/'+$release.id+'/assets?name='+[Uri]::EscapeDataString($file.Name)) -InFile $file.Path
        if($asset.name -cne $file.Name -or $asset.state -cne 'uploaded' -or $asset.size -ne $file.Size -or $asset.digest -cne $file.Digest){throw 'GitHubReleaseAssetMismatch'}
    }
    $published=Send-QuietGitHubReleaseRequest -Method PATCH -Uri "$api/releases/$($release.id)" -Body @{draft=$false;make_latest='false'}
    if($published.draft -or $published.tag_name -cne $Tag -or $published.prerelease -ne $Version.Contains('-')){throw 'GitHubReleasePublicationMismatch'}
    [pscustomobject]@{Tag=$Tag;Revision=$Revision;Url=$published.html_url;Assets=@($files.Name);State='Published'}
}
Export-ModuleMember -Function Publish-QuietGitHubRelease
