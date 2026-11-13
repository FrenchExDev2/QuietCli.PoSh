function Test-QuietGitHubReleaseLifecycle {
    <#
    .SYNOPSIS
    Checks offline release lifecycle properties, malformed responses and meaningful policy mutants.
    .PARAMETER WorkspaceRoot
    Checkout containing the production release helper and workflows.
    .PARAMETER RunDirectory
    Owned external fixture/report directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $source=Get-Content (Join-Path $WorkspaceRoot scripts/lib/GitHubRelease.psm1) -Raw -Encoding utf8
    $directory=Join-Path $RunDirectory github-release
    [void][IO.Directory]::CreateDirectory($directory)
    $properties=0;$malformed=0
    function Invoke-ReleaseFixture {
        param([string]$Text,[string]$Scenario='success',[string]$Version='0.2.0-preview1',[int]$Length=9,[switch]$Preview)
        $asset=Join-Path $directory ('module '+$Length+'.nupkg')
        [IO.File]::WriteAllBytes($asset,[byte[]]::new($Length))
        $state=@{Calls=[Collections.Generic.List[object]]::new();Scenario=$Scenario;Version=$Version;Revision='a'*40;Tag='FrenchExDev2.QuietCli.Core.PoSh/v'+$Version;Uploaded=0;Published=$false}
        $transport={
            param([string]$Method,[string]$Uri,[object]$Body,[string]$InFile)
            [void]$state.Calls.Add(@{Method=$Method;Uri=$Uri;Body=$Body;InFile=$InFile})
            if($Uri -like '*/git/ref/tags/*'){
                if($state.Scenario -eq 'annotated'){return @{object=@{type='tag';sha='b'*40}}}
                return @{object=@{type='commit';sha=$(if($state.Scenario -eq 'wrong revision'){'c'*40}else{$state.Revision})}}
            }
            if($Uri -like '*/git/tags/*'){return @{object=@{type='commit';sha=$state.Revision}}}
            if($Method -eq 'GET' -and $Uri -like '*/releases/tags/*'){
                if($state.Scenario -eq 'exists'){return @{id=7;draft=$false}}
                $code=if($state.Scenario -eq 'denied'){403}else{404}
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('fixture',[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$code))
            }
            if($Method -eq 'POST' -and $Uri -like '*/releases'){
                if(!$Body.draft -or $Body.tag_name -cne $state.Tag -or $Body.target_commitish -cne $state.Revision -or $Body.prerelease -ne $state.Version.Contains('-') -or $Body.make_latest -cne 'false'){throw 'ReleaseCreatePolicyChanged'}
                return @{id=7;draft=$true;tag_name=$state.Tag}
            }
            if($InFile){
                if($state.Scenario -eq 'upload failure'){throw 'FixtureUploadFailed'}
                $state.Uploaded++
                return @{name=[IO.Path]::GetFileName($InFile);size=$(if($state.Scenario -eq 'wrong size'){-1}else{(Get-Item -LiteralPath $InFile).Length});state='uploaded';digest=$(if($state.Scenario -eq 'wrong digest'){'sha256:bad'}else{'sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($InFile)))).ToLowerInvariant()})}
            }
            if($Method -eq 'PATCH'){
                if($state.Uploaded -ne 1 -or $Body.draft -ne $false -or $Body.make_latest -cne 'false'){throw 'ReleasePublishedBeforeAssets'}
                $state.Published=$true
                return @{id=7;draft=$false;tag_name=$state.Tag;prerelease=$state.Version.Contains('-');html_url='https://github.com/FrenchExDev2/QuietCli.PoSh/releases/tag/fixture'}
            }
            throw 'UnexpectedReleaseRequest'
        }.GetNewClosure()
        $module=New-Module -ScriptBlock ([scriptblock]::Create($Text))
        & $module {param($handler) Set-Item Function:script:Send-QuietGitHubReleaseRequest -Value $handler} $transport
        try{
            $failed=$false
            try{$result=& $module {param($tag,$revision,$path,$version,$preview) Publish-QuietGitHubRelease -Tag $tag -Revision $revision -Assets $path -Version $version -WhatIf:$preview -Confirm:$false} $state.Tag $state.Revision $asset $Version ([bool]$Preview)}catch{$failed=$true}
            if($Preview){if($failed -or $state.Calls.Count){throw 'ReleaseWhatIfMadeRequest'};return}
            if($Scenario -in @('success','annotated')){
                if($failed -or !$state.Published -or $result.State -cne 'Published' -or $state.Calls[-1].Method -cne 'PATCH'){throw 'ReleaseSuccessMissing'}
            }elseif(!$failed -or $state.Published){throw ('ReleaseUnsafeFailure: '+$Scenario)}
            if($Scenario -in @('wrong revision','exists','denied') -and @($state.Calls|Where-Object Method -NE 'GET').Count){throw 'ReleaseWroteBeforePreflight'}
        }finally{Remove-Module $module -ErrorAction SilentlyContinue}
    }
    foreach($version in @('0.2.0-preview1','1.0.0','2.3.4-rc9','10.20.30')){
        foreach($length in @(0,1,127,1024)){
            Invoke-ReleaseFixture $source -Version $version -Length $length
            $properties++
        }
    }
    Invoke-ReleaseFixture $source -Scenario annotated;$properties++
    Invoke-ReleaseFixture $source -Preview;$properties++
    foreach($scenario in @('wrong revision','exists','denied','upload failure','wrong size','wrong digest')){
        Invoke-ReleaseFixture $source -Scenario $scenario;$malformed++
    }
    $mutations=@(
        @{Name='ignore remote revision';Before='$target.sha -cne $Revision';After='$false';Scenario='wrong revision'},
        @{Name='ignore asset digest';Before='$asset.digest -cne $file.Digest';After='$false';Scenario='wrong digest'},
        @{Name='ignore asset size';Before='$asset.size -ne $file.Size';After='$false';Scenario='wrong size'},
        @{Name='publish before upload';Before='draft=$true;prerelease=';After='draft=$false;prerelease=';Scenario='success'},
        @{Name='preview as stable';Before="prerelease=`$Version.Contains('-');make_latest=";After='prerelease=$false;make_latest=';Scenario='success'},
        @{Name='replace existing release';Before="if(`$null -ne `$release){throw 'GitHubReleaseAlreadyExists'}";After='';Scenario='exists'}
    )
    foreach($mutant in $mutations){
        if(!$source.Contains($mutant.Before)){throw ('ReleaseMutantAnchorMissing: '+$mutant.Name)}
        $killed=$false;try{Invoke-ReleaseFixture ($source.Replace($mutant.Before,$mutant.After)) -Scenario $mutant.Scenario}catch{$killed=$true}
        if(!$killed){throw ('GitHubReleaseMutantSurvived: '+$mutant.Name)}
    }
    # Exercise the executable's preview/context/receipt boundary without real packages or credentials.
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/GalleryRelease.psm1)
    $targets=@(Select-QuietGalleryReleaseTargets $WorkspaceRoot -Module Core,Git)
    $operator=Join-Path $WorkspaceRoot scripts/Publish-QuietGitHubRelease.ps1
    $tag=$targets[0].Module+'/v'+$targets[0].Version
    $output=Join-Path $directory preview-must-not-exist
    $null=& $operator -TriggerTag $tag -Revision ('a'*40) -PackageDirectory $output -WhatIf
    if(Test-Path -LiteralPath $output){throw 'GitHubReleasePreviewWroteFiles'}
    $observed=[Collections.Generic.List[string]]::new()
    function Read-ReleaseFixturePackage {
        <# .SYNOPSIS
        Supplies already-validated package metadata at the publication boundary.
        #>
        param([string]$PackageDirectory,[string]$Version)
        $name=Split-Path $PackageDirectory -Leaf
        [pscustomobject]@{Module=$name;Packages=@([pscustomobject]@{Module=$name;SHA256='D'*64;File=$name+'.nupkg'})}
    }
    function Send-ReleaseFixture {
        <# .SYNOPSIS
        Observes a release request without accessing a network or token.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param([string]$Tag,[string]$Revision,[string[]]$Assets,[string]$Version)
        [void]$observed.Add($Tag)
    }
    Set-Alias Test-QuietGalleryPackageSet Read-ReleaseFixturePackage -Scope Local
    Set-Alias Publish-QuietGitHubRelease Send-ReleaseFixture -Scope Local
    $keys=@('GITHUB_REPOSITORY','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_SHA')
    $saved=@{};foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
    $options=@{TriggerTag=$tag;Revision='a'*40;PackageDirectory=$directory;ReleaseTagsJson=(@($targets|ForEach-Object {$_.Module+'/v'+$_.Version})|ConvertTo-Json -Compress);Confirm=$false}
    try{
        $context=@{GITHUB_REPOSITORY='FrenchExDev2/QuietCli.PoSh';GITHUB_EVENT_NAME='push';GITHUB_REF='refs/tags/'+$tag;GITHUB_SHA='a'*40}
        foreach($key in $keys){
            foreach($name in $keys){[Environment]::SetEnvironmentVariable($name,$context[$name],'Process')}
            [Environment]::SetEnvironmentVariable($key,'invalid','Process')
            $rejected=$false;try{$null=& $operator @options}catch{$rejected=$_.Exception.Message -eq 'GitHubReleaseWorkflowContextRequired'}
            if(!$rejected -or $observed.Count){throw 'GitHubReleaseAcceptedForeignContext'}
            $malformed++
        }
        foreach($name in $keys){[Environment]::SetEnvironmentVariable($name,$context[$name],'Process')}
        foreach($target in $targets){
            $folder=Join-Path $directory $target.Module;[void][IO.Directory]::CreateDirectory($folder)
            Write-WorkspaceJson (Join-Path $folder publication.json) @{SchemaVersion=1;Repository='PSGallery';State='Published';Version=$target.Version;Modules=@(@{Module=$target.Module;State='Published';SHA256='D'*64})}
        }
        $last=Join-Path (Join-Path $directory $targets[-1].Module) publication.json
        $good=Get-Content -LiteralPath $last -Raw -Encoding utf8
        foreach($damage in @('Failed','HashMismatch')){
            $broken=if($damage -eq 'Failed'){$good.Replace('Published','Failed')}else{$good.Replace(('D'*64),('E'*64))}
            [IO.File]::WriteAllText($last,$broken,[Text.UTF8Encoding]::new($false))
            $rejected=$false;try{$null=& $operator @options}catch{$rejected=$_.Exception.Message -eq 'GitHubReleasePublicationReceiptInvalid'}
            if(!$rejected -or $observed.Count){throw 'GitHubReleasePublishedBeforeValidatingEveryReceipt'}
            $malformed++
        }
        [IO.File]::WriteAllText($last,$good,[Text.UTF8Encoding]::new($false))
        $null=& $operator @options
        if(($observed -join ',') -cne (($targets|ForEach-Object {$_.Module+'/v'+$_.Version}) -join ',')){throw 'GitHubReleaseBatchOrderChanged'}
        $properties++
    }finally{foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $yaml=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $workflow=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/release-tags.yml'),[Text.Encoding]::UTF8))
    $reusable=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/publish-psgallery.yml'),[Text.Encoding]::UTF8))
    $job=$workflow['jobs']['github-release'];$steps=@($job['steps'])
    if(($job['needs'] -join ',') -cne 'plan,release' -or $job['permissions']['contents'] -cne 'write' -or $workflow['jobs']['release']['permissions']['contents'] -cne 'read' -or $reusable['permissions']['contents'] -cne 'read'){throw 'GitHubReleasePermissionOrDependencyChanged'}
    if($workflow['on'].ContainsKey('workflow_dispatch') -or !$workflow['on']['push']['tags']){throw 'GitHubReleaseTagBoundaryChanged'}
    if($reusable['on']['workflow_call']['outputs']['artifact_name']['value'] -cne '${{ jobs.package.outputs.artifact_name }}' -or $reusable['on']['workflow_call']['outputs']['publication_artifact_name']['value'] -cne '${{ jobs.publish.outputs.artifact_name }}'){throw 'GitHubReleaseArtifactOutputsChanged'}
    $downloads=@($steps|Where-Object {$_['uses'] -like 'actions/download-artifact@*'})
    if($downloads.Count -ne 2 -or $downloads[0]['with']['name'] -cne '${{ needs.release.outputs.artifact_name }}' -or $downloads[1]['with']['name'] -cne '${{ needs.release.outputs.publication_artifact_name }}'){throw 'GitHubReleaseMustReusePublishingAttemptArtifacts'}
    $run=($steps|ForEach-Object {$_['run']}) -join "`n"
    if($run -match 'Build-Workspace|Publish-QuietGallery' -or $run -notmatch 'Publish-QuietGitHubRelease.ps1'){throw 'GitHubReleaseRebuiltOrRepublishedGallery'}
    function Assert-ReleaseWorkflowCondition {
        param([string]$Condition)
        if($Condition -cnotmatch "\A(?:needs\.release\.result|needs\.plan\.outputs\.is_leader|'success'|'true'|\s|==|&&)+\z"){throw 'GitHubReleaseConditionInvalid'}
        $expression=$Condition.Replace('needs.release.result','$result').Replace('needs.plan.outputs.is_leader','$leader').Replace('==',' -ceq ').Replace('&&',' -and ')
        $evaluate=[scriptblock]::Create($expression)
        foreach($result in @('success','failure','skipped','cancelled')){foreach($leader in @('true','false')){
            if([bool](& $evaluate) -ne ($result -ceq 'success' -and $leader -ceq 'true')){throw 'GitHubReleaseConditionChanged'}
        }}
    }
    Assert-ReleaseWorkflowCondition $job['if'];$properties+=8
    $workflowMutants=0
    foreach($condition in @("needs.release.result == 'success'","needs.plan.outputs.is_leader == 'true'")){
        $killed=$false;try{Assert-ReleaseWorkflowCondition $condition}catch{$killed=$true}
        if(!$killed){throw 'GitHubReleaseConditionMutantSurvived'};$workflowMutants++
    }
    Write-WorkspaceJson (Join-Path $directory summary.json) @{Properties=$properties;Malformed=$malformed;MutantsKilled=$mutations.Count;WorkflowMutantsKilled=$workflowMutants;NetworkRequests=0;HostedPublication=$false}
}
