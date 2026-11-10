function Get-GitHubCiExecutionMatrix {
    <#
    .SYNOPSIS
    Partitions all four native Linux targets between verified GitHub containers and Docker fallback.
    .PARAMETER Images
    Four resolved image records with Rid, Platform, Runner and optional immutable Reference.
    #>
    param([Parameter(Mandatory)][object[]]$Images)
    $required=@('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')
    if($Images.Count -ne 4 -or @($Images|Group-Object Rid|Where-Object Count -NE 1).Count){throw 'GitHubCiMatrixTargetsInvalid'}
    $native=[Collections.Generic.List[object]]::new();$fallback=[Collections.Generic.List[object]]::new()
    foreach($rid in $required){
        $row=@($Images|Where-Object Rid -CEQ $rid)
        if($row.Count -ne 1){throw 'GitHubCiMatrixTargetMissing'}
        $row=$row[0]
        $platform=if($rid.Contains('-musl-')){'alpine'}else{'debian'}
        $runner=if($rid.EndsWith('arm64')){'ubuntu-24.04-arm'}else{'ubuntu-latest'}
        if($row.Platform -cne $platform -or $row.Runner -cne $runner){throw 'GitHubCiNativeRunnerMismatch'}
        if($row.Reference -and $row.Reference -cnotmatch '^ghcr\.io/frenchexdev2/quietcli2-ci-[a-z0-9-]+@sha256:[a-f0-9]{64}$'){throw 'GitHubCiMutableImageRejected'}
        # GitHub's Node action host rejects Alpine ARM64; execute those actions on Ubuntu and tests in Docker.
        $useContainer=$row.Reference -and $rid -cne 'linux-musl-arm64'
        if($useContainer){$native.Add(@{rid=$rid;platform=$platform;runner=$runner;image=$row.Reference;dotnet_root=$(if($platform -eq 'alpine'){'/usr/lib/dotnet'}else{'/usr/share/dotnet'})})}
        else{$fallback.Add(@{rid=$rid;platform=$platform;runner=$runner;reason=$(if(!$row.Reference){'Verified image unavailable; build locally without publication'}else{'GitHub JavaScript actions do not support Alpine ARM64'})})}
    }
    [pscustomobject]@{Container=@{include=$native.ToArray()};Fallback=@{include=$fallback.ToArray()};HasContainer=($native.Count -gt 0);HasFallback=($fallback.Count -gt 0)}
}
function Assert-GitHubCiLinuxResults {
    <#
    .SYNOPSIS
    Requires both selected execution paths to succeed and rejects an unexpectedly skipped matrix.
    .PARAMETER SelectionResult
    GitHub result of the matrix/image selection job.
    .PARAMETER ContainerResult
    Aggregate native container matrix result.
    .PARAMETER FallbackResult
    Aggregate Docker fallback matrix result.
    .PARAMETER HasContainer
    Whether the selected revision has native container rows.
    .PARAMETER HasFallback
    Whether the selected revision has Docker fallback rows.
    #>
    param([string]$SelectionResult,[string]$ContainerResult,[string]$FallbackResult,[bool]$HasContainer,[bool]$HasFallback)
    if($SelectionResult -cne 'success' -or (!$HasContainer -and !$HasFallback)){throw 'GitHubCiLinuxSelectionFailed'}
    if($ContainerResult -cne $(if($HasContainer){'success'}else{'skipped'}) -or $FallbackResult -cne $(if($HasFallback){'success'}else{'skipped'})){throw 'GitHubCiLinuxMatrixFailed'}
}
