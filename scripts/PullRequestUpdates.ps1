function Invoke-QuietPullRequestTool {
    <#
    .SYNOPSIS
    Reads bounded administrative Git/GitHub metadata through the CI process helper.
    .PARAMETER WorkspaceRoot
    Repository working directory.
    .PARAMETER FilePath
    Git or GitHub CLI executable.
    .PARAMETER ArgumentList
    Exact argument vector; no shell evaluation.
    #>
    param([string]$WorkspaceRoot,[ValidateSet('git','gh')][string]$FilePath,[string[]]$ArgumentList)
    $state=@{Text=[Text.StringBuilder]::new();Overflow=$false}
    $result=Invoke-CiProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 60 -State $state -OnOutput {
        param($event,$state)
        if($event.Stream -ne 'stdout'){return}
        if($state.Text.Length+$event.Text.Length -gt 262144){$state.Overflow=$true;return}
        [void]$state.Text.Append($event.Text)
        [void]$state.Text.Append("`n")
    }
    if($result.Outcome -ne 'Success' -or $state.Overflow){throw ('PullRequestMetadataUnavailable: '+$FilePath)}
    return $state.Text.ToString().Trim()
}
function Send-QuietPullRequestUpdate {
    <#
    .SYNOPSIS
    Adds a commit summary to the one existing open PR for an explicitly selected GitHub branch.
    .PARAMETER WorkspaceRoot
    Repository whose selected remote owns the PR.
    .PARAMETER Remote
    Remote name; non-GitHub URLs skip the update.
    .PARAMETER Branch
    Feature/fix branch; other branch families skip the update.
    .PARAMETER Body
    Optional reviewed Markdown explaining changes and actual validation; omitted uses PR commit titles.
    .PARAMETER Description
    Explicit reviewed PR description to replace through gh pr edit after checkpoint verification.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot,[string]$Remote,[string]$Branch,[AllowNull()][AllowEmptyString()][string]$Body,[AllowNull()][string]$Description)
    if($Branch -cnotmatch '^(feature|fix)/'){return}
    if(!$PSCmdlet.ShouldProcess($Branch,'Comment on the existing GitHub pull request')){return}
    $url=Invoke-QuietPullRequestTool $WorkspaceRoot git @('remote','get-url',$Remote)
    if($url -notmatch '\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?\z'){
        Write-Host 'PR update skipped: selected remote is not github.com.';return
    }
    $repository=$Matches.repo
    $items=@((Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','list','--repo',$repository,'--head',$Branch,'--state','open','--limit','2','--json','number,headRefName'))|ConvertFrom-Json)
    if(!$items.Count){Write-Host 'PR update skipped: no open PR exists for this branch.';return}
    if($items.Count -ne 1 -or $items[0].headRefName -cne $Branch){throw 'PullRequestUpdateAmbiguous'}
    $number=[string]$items[0].number
    $pr=(Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','view',$number,'--repo',$repository,'--json','headRefOid,commits'))|ConvertFrom-Json
    $revision=Invoke-QuietPullRequestTool $WorkspaceRoot git @('rev-parse','--verify',('refs/heads/'+$Branch))
    if($pr.headRefOid -cnotmatch '\A[0-9a-f]{40}\z' -or $pr.headRefOid -cne $revision){throw 'PullRequestCheckpointChanged'}
    if($PSBoundParameters.ContainsKey('Description')){
        if([string]::IsNullOrWhiteSpace($Description) -or $Description.Length -gt 60000){throw 'PullRequestDescriptionInvalid'}
        $descriptionPath=Join-Path ([IO.Path]::GetTempPath()) ('quietcli-pr-description-'+[guid]::NewGuid().ToString('N')+'.md')
        try{
            [IO.File]::WriteAllText($descriptionPath,$Description.Replace("`r`n","`n").Replace("`r","`n")+"`n",[Text.UTF8Encoding]::new($false))
            $edited=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','edit',$number,'--repo',$repository,'--body-file',$descriptionPath)
            Write-Host ('PR description updated: '+$edited)
        }finally{if([IO.File]::Exists($descriptionPath)){[IO.File]::Delete($descriptionPath)}}
    }
    $marker='<!-- quietcli:push-update:'+ $pr.headRefOid +' -->'
    $comments=(Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','view',$number,'--repo',$repository,'--json','comments'))|ConvertFrom-Json
    if(@($comments.comments|Where-Object {$_.body.Contains($marker)}).Count){Write-Host ('PR update already exists for '+$pr.headRefOid);return}
    if(!$Body){
        $lines=@('Pushed checkpoint `'+$pr.headRefOid+'` on `'+$Branch+'`.','','Current PR commits:','')
        $lines+=@($pr.commits|ForEach-Object {'- `'+$_.oid.Substring(0,7)+'` '+$_.messageHeadline})
        $lines+=@('','Validation: no local suite was launched by this push. GitHub checks determine qualification; this comment does not assert success.')
        $Body=$lines -join "`n"
    }
    $text=$marker+"`n"+$Body.Replace("`r`n","`n").Replace("`r","`n")+"`n"
    if($text.Length -gt 65000){throw 'PullRequestUpdateBodyTooLarge'}
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('quietcli-pr-update-'+[guid]::NewGuid().ToString('N')+'.md')
    try{
        [void][IO.File]::WriteAllTextAsync($temporary,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $result=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','comment',$number,'--repo',$repository,'--body-file',$temporary)
        Write-Host ('PR update: '+$result)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
