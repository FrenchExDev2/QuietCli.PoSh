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
        if($useContainer){$native.Add(@{rid=$rid;platform=$platform;runner=$runner;image=$row.Reference;dotnet_root=$(if($platform -eq 'alpine'){'/opt/pwsh-runtime'}else{'/usr/share/dotnet'})})}
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
function Assert-GitHubCiImagePreparationContext {
    <#
    .SYNOPSIS
    Restricts cache-only preparation to explicit upstream develop dispatches.
    .PARAMETER ImagesOnly
    Selects preparation without qualification or a qualified revision receipt.
    .PARAMETER Event
    GitHub event name.
    .PARAMETER Ref
    Immutable event ref; never inferred from a caller checkout.
    .PARAMETER Repository
    GitHub repository identity.
    #>
    param([bool]$ImagesOnly,[string]$Event,[string]$Ref,[string]$Repository)
    if($ImagesOnly -and ($Event -cne 'workflow_dispatch' -or $Ref -cne 'refs/heads/develop' -or $Repository -cne 'FrenchExDev2/QuietCli.PoSh')){throw 'CiImagesOnlyRequiresUpstreamDevelopDispatch'}
}

function Get-GitHubCiWindowsMatrix {
    <#
    .SYNOPSIS
    Selects all native production rows and only explicitly requested next-version preview rows.
    .PARAMETER HostLock
    Reviewed host document with exact versions, hashes and availability.
    .PARAMETER IncludePreview
    Explicit opt-in; an unpublished requested preview fails before execution.
    #>
    param($HostLock,[bool]$IncludePreview=$false)
    if($HostLock.SchemaVersion -ne 1 -or $HostLock.StableVersion -cnotmatch '\A7\.\d+\.\d+\z'){throw 'PowerShellCiHostLockInvalid'}
    if($IncludePreview -and !$HostLock.Preview.Available){throw ('PowerShellPreviewNotPublished: '+$HostLock.Preview.Version)}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($channel in @('stable')+@('preview'|Where-Object {$IncludePreview})){
        foreach($rid in @('win-x64','win-arm64')){
            $spec=@($HostLock.Hosts|Where-Object {$_.Channel -ceq $channel -and $_.Rid -ceq $rid})
            if($spec.Count -ne 1 -or $spec[0].SHA256 -cnotmatch '\A[A-F0-9]{64}\z' -or $spec[0].RuntimeMajor -lt 10){throw 'PowerShellCiHostIdentityInvalid'}
            $spec=$spec[0]
            if($channel -ceq 'stable' -and $spec.Version -cne $HostLock.StableVersion){throw 'PowerShellCiStableVersionMismatch'}
            if($channel -ceq 'preview' -and ($spec.Version -cne $HostLock.Preview.Version -or $spec.Version -cnotmatch '\A7\.\d+\.\d+-(?:preview|rc)\.\d+\z' -or [Management.Automation.SemanticVersion]$spec.Version -le [Management.Automation.SemanticVersion]$HostLock.StableVersion)){throw 'PowerShellCiPreviewVersionInvalid'}
            foreach($mode in $(if($channel -ceq 'stable'){@('Process','InProcess')}else{@('InProcess')})){
                $rows.Add(@{image=$(if($rid -ceq 'win-arm64'){'windows-11-arm'}else{'windows-latest'});rid=$rid;channel=$channel;mode=$mode;host_version=$spec.Version;runtime_major=$spec.RuntimeMajor})
            }
        }
    }
    [pscustomobject]@{Matrix=@{include=$rows.ToArray()};WindowsTargets=$rows.Count;ExpectedReports=($rows.Count+4);PreviewRequested=$IncludePreview}
}

Export-ModuleMember -Function 'Get-GitHubCiExecutionMatrix','Assert-GitHubCiLinuxResults','Assert-GitHubCiImagePreparationContext','Get-GitHubCiWindowsMatrix'
