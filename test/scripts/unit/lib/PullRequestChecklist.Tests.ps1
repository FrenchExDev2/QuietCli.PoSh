#requires -Version 7.6

Describe 'Expandable companion checklist rows' {
    BeforeAll {
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
        $null=Import-QuietTestLibrary -Name PullRequestChecklist
        $template=@'
<!-- quietcli-ci:begin -->
- [ ] Repository scripts <!-- ci:script-mutation -->
- [ ] Sequential <!-- ci:mutation-serial -->
- [ ] ReadyToRun <!-- ci:readytorun -->
- [ ] Preview <!-- ci:preview -->
<!-- quietcli-ci:end -->
'@
    }

    It 'renders a new companion with a digit in its name and leaves generated items unchecked' {
        $catalogue=@{Companions=[ordered]@{Box2=@{Name='Box2';Mutation=$true};Extra=@{Name='Extra'}}}
        $expanded=Expand-QuietPullRequestTemplate -Template $template -Configuration $catalogue
        $parsed=Read-QuietPullRequestChecklist $expanded
        $parsed.Available|Should -Contain 'run-profile-mutation-box2'
        $parsed.Available|Should -Contain 'profiling-extra'
        $parsed.Available|Should -Not -Contain 'run-profile-mutation-extra'
        $parsed.Selected.Count|Should -Be 0
        $body=New-QuietPullRequestBody -Body 'Description' -Template $expanded -CiOption @('profiling-box2','run-profile-mutation-box2')
        (Read-QuietPullRequestChecklist $body).Selected|Should -BeExactly @('profiling-box2','run-profile-mutation-box2')
    }

    It 'requires every shared option and preserves its canonical position' {
        $catalogue=@{Companions=[ordered]@{Box2=@{Name='Box2';Mutation=$true}}}
        $expanded=Expand-QuietPullRequestTemplate -Template $template -Configuration $catalogue
        $parsed=Read-QuietPullRequestChecklist $expanded
        $parsed.Available|Should -BeExactly @('script-mutation','profiling-box2','run-profile-mutation-box2','mutation-serial','readytorun','preview')
        foreach($id in 'script-mutation','mutation-serial','readytorun','preview'){
            $incomplete=$template -creplace ("(?m)^- .* ci:$id -->\r?\n"),''
            {Read-QuietPullRequestChecklist $incomplete}|Should -Throw '*PullRequestCiChecklistIncomplete*'
        }
        $mixed=$template.Replace('<!-- quietcli-ci:end -->',"- [ ] Legacy <!-- ci:mutation -->`n<!-- quietcli-ci:end -->")
        {Read-QuietPullRequestChecklist $mixed}|Should -Throw '*PullRequestCiChecklistIncomplete*'
    }

    It 'migrates a legacy selection to script and Core mutation, retaining the other selected options' {
        $catalogue=@{Companions=[ordered]@{Core=@{Name='Core';Mutation=$true}}}
        $expanded=Expand-QuietPullRequestTemplate -Template $template -Configuration $catalogue
        $legacy=$template -creplace '(?m)^- .* ci:mutation-serial -->\r?\n',''
        $legacy=$legacy.Replace('- [ ] Repository scripts <!-- ci:script-mutation -->','- [x] Legacy <!-- ci:mutation -->').Replace('- [ ] Preview','- [x] Preview')
        $body=New-QuietPullRequestBody -Body $legacy -Template $expanded
        (Read-QuietPullRequestChecklist $body).Selected|Should -BeExactly @('script-mutation','run-profile-mutation-core','preview')
        {Expand-QuietPullRequestTemplate -Template $legacy -Configuration $catalogue}|Should -Throw '*PullRequestCiChecklistTemplateInvalid*'
    }

    It 'replaces every old companion row and refreshes the captions from the catalogue' {
        $catalogue=@{Companions=[ordered]@{Box2=@{Name='Box2';Mutation=$true}}}
        $obsolete=$template.Replace('<!-- quietcli-ci:end -->',"- [ ] Old <!-- ci:profiling-old -->`n- [ ] Old mutation <!-- ci:run-profile-mutation-old -->`n<!-- quietcli-ci:end -->")
        $expanded=Expand-QuietPullRequestTemplate -Template $obsolete -Configuration $catalogue
        $expanded|Should -Match 'Run Box2 mutation testing'
        $expanded|Should -Match 'Profile the Box2 PowerShell tests'
        $expanded|Should -Not -Match 'ci:.*-old'
    }
}
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name PullRequestChecklist
    $null=Import-QuietTestLibrary -Name PullRequestCi
    $null=Import-QuietTestLibrary -Name CiImpact
    $root=Get-QuietTestWorkspaceRoot
    $template=@'
## Additional CI validation

<!-- quietcli-ci:begin -->
- [ ] Run extended mutation testing <!-- ci:mutation -->
- [ ] Compare IL and ReadyToRun cold-start performance <!-- ci:readytorun -->
- [ ] Add PowerShell Preview hosts to the Core matrix <!-- ci:preview -->
<!-- quietcli-ci:end -->
'@
}

Describe 'Pull request CI checklist' {
    It 'writes the description, checked options and footer in order with Unicode intact' {
        $body=New-QuietPullRequestBody -Body 'Résumé : café' -Template $template -Footer 'Pièce jointe' -CiOption preview,mutation
        $body | Should -Match '(?s)Résumé : café.*quietcli-ci:begin.*quietcli-ci:end.*Pièce jointe'
        ((Read-QuietPullRequestChecklist $body).Selected -join ',') | Should -BeExactly 'mutation,preview'
    }

    It 'preserves an existing selection with CRLF and uppercase X and replaces it when explicitly supplied' {
        $body=New-QuietPullRequestBody -Body 'Description' -Template $template -CiOption readytorun
        $changed=$body.Replace('[x]','[X]').Replace("`n","`r`n")
        ((Read-QuietPullRequestChecklist (New-QuietPullRequestBody -Body $changed -Template $template)).Selected -join ',') | Should -BeExactly 'readytorun'
        $updated=New-QuietPullRequestBody -Body $changed -Template $template -CiOption @()
        ([regex]::Matches($updated,'quietcli-ci:begin')).Count | Should -Be 1
        (Read-QuietPullRequestChecklist $updated).Selected.Count | Should -Be 0
    }

    It 'ignores a fenced checklist and ordinary tasks outside the managed block' {
        $body="~~~markdown`n$template`n~~~`n- [x] ordinary task"
        $result=Read-QuietPullRequestChecklist $body
        $result.StartLine | Should -Be -1
        $result.Selected.Count | Should -Be 0
        $real=New-QuietPullRequestBody -Body '' -Template $template -CiOption mutation
        $mixed=Read-QuietPullRequestChecklist ("~~~~markdown`n~~~`nxxx~~~~`n$template`n  ~~~~~ `n"+$real)
        $mixed.Selected | Should -BeExactly 'mutation'
        $mixed.StartLine | Should -BeGreaterThan 5
    }

    It 'requires a fence closer to end the line and recognizes the managed block by its exact line range' {
        $text="~~~markdown`n~~~~ extra text`n$template`n~~~`n"
        $example=Read-QuietPullRequestChecklist $text
        $example.StartLine | Should -Be -1
        $block=$template.Substring($template.IndexOf('<!-- quietcli-ci:begin -->')).TrimEnd()
        $result=Read-QuietPullRequestChecklist ($block.Replace(" -->`n- [", " -->`n`n- ["))
        $result.StartLine | Should -Be 0
        $result.EndLine | Should -Be 7
    }

    It 'rejects duplicate checklists, repeated options and unknown options' {
        {Read-QuietPullRequestChecklist "$template`n$template"} | Should -Throw '*PullRequestCiChecklistDuplicate*'
        {Read-QuietPullRequestChecklist ($template.Replace('ci:preview','ci:mutation'))} | Should -Throw '*PullRequestCiChecklistDuplicateOption*'
        {Read-QuietPullRequestChecklist ($template.Replace('ci:preview','ci:new-option'))} | Should -Throw '*PullRequestCiChecklistUnknownOption*'
    }

    It 'rejects missing rows and delimiters and rejects ordinary text inside the block' {
        {Read-QuietPullRequestChecklist ($template -creplace '(?m)^- .* ci:preview -->\r?\n?','')} | Should -Throw '*PullRequestCiChecklistIncomplete*'
        {Read-QuietPullRequestChecklist ($template.Replace('<!-- quietcli-ci:end -->',''))} | Should -Throw '*PullRequestCiChecklistIncomplete*'
        {Read-QuietPullRequestChecklist ($template.Replace('<!-- quietcli-ci:begin -->',''))} | Should -Throw '*PullRequestCiChecklistIncomplete*'
        {Read-QuietPullRequestChecklist ($template+"`n<!-- quietcli-ci:end -->`n")} | Should -Throw '*PullRequestCiChecklistIncomplete*'
        {Read-QuietPullRequestChecklist ($template.Replace('- [ ]','- [o]'))} | Should -Throw '*PullRequestCiChecklistInvalidRow*'
        {Read-QuietPullRequestChecklist ($template.Replace('<!-- quietcli-ci:begin -->',"<!-- quietcli-ci:begin -->`n~~~markdown"))} |
            Should -Throw '*PullRequestCiChecklistInvalidRow*'
    }

    It 'retains the original text above and below a checklist when replacing its selection' {
        $block=$template.Substring($template.IndexOf('<!-- quietcli-ci:begin -->')).TrimEnd()
        $body="Résumé du changement`n`n$block`n`nPièces existantes"
        $expected=$body.Replace('- [ ] Add PowerShell Preview','- [x] Add PowerShell Preview')+"`n`nFooter`n"
        New-QuietPullRequestBody -Body $body -Template $template -Footer 'Footer' -CiOption preview | Should -BeExactly $expected
    }

    It 'validates footer and template inputs and refuses an unclosed Markdown fence' {
        {New-QuietPullRequestBody -Body '' -Template 'No checklist'} | Should -Throw '*PullRequestCiChecklistTemplateInvalid*'
        {New-QuietPullRequestBody -Body '' -Template ($template.Replace('[ ]','[x]'))} | Should -Throw '*PullRequestCiChecklistTemplateInvalid*'
        $onlyBlock=$template.Substring($template.IndexOf('<!-- quietcli-ci:begin -->')).TrimEnd()
        {New-QuietPullRequestBody -Body '' -Template $template -Footer $onlyBlock} | Should -Throw '*PullRequestCiChecklistFooterDuplicate*'
        {New-QuietPullRequestBody -Body '' -Template $template -CiOption invalid} | Should -Throw '*PullRequestCiChecklistUnknownOption*'
        {New-QuietPullRequestBody -Body '~~~markdown' -Template $template} | Should -Throw '*PullRequestCiChecklistNotVisible*'
        (New-QuietPullRequestBody -Body $onlyBlock -Template $onlyBlock) | Should -BeExactly ($onlyBlock+"`n")
        (New-QuietPullRequestBody -Body ($onlyBlock+"`nnotes") -Template $onlyBlock) | Should -BeExactly ($onlyBlock+"`nnotes`n")
    }

    It 'invalidates prior evidence when only a checkbox changes on the same SHA' {
        $snapshot=@{number=7;head=@{sha='a'*40};base=@{sha='b'*40};merge_commit_sha='c'*40;body=$template}
        $evidence=@{Number=7;Head='a'*40;Base='b'*40;Revision='c'*40;Options=@()}
        (Test-QuietPullRequestCiSelection $snapshot $evidence) | Should -BeTrue
        $snapshot.body=New-QuietPullRequestBody -Body 'Description' -Template $template -CiOption preview
        (Test-QuietPullRequestCiSelection $snapshot $evidence) | Should -BeFalse
        $evidence.Options=@('preview')
        (Test-QuietPullRequestCiSelection $snapshot $evidence) | Should -BeTrue
    }

    It 'rejects any individually changed receipt identity field' {
        $snapshot=@{number=7;head=@{sha='a'*40};base=@{sha='b'*40};merge_commit_sha='c'*40;body=$template}
        $original=@{Number=7;Head='a'*40;Base='b'*40;Revision='c'*40;Options=@()}
        foreach($field in 'Number','Head','Base','Revision'){
            $evidence=$original.Clone()
            $evidence[$field]='different'
            (Test-QuietPullRequestCiSelection $snapshot $evidence) | Should -BeFalse -Because $field
        }
    }

    It 'adds Preview, ReadyToRun and full Tooling without replacing the mandatory suite and distribution' {
        $plan=Get-QuietCiDispatchImpact -WorkspaceRoot $root -Suite Git
        $plan.RunDistribution=$true
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $root -Options mutation,readytorun,preview
        $plan.FullSuites | Should -Contain 'Git'
        $plan.FullSuites | Should -Contain 'Core'
        $plan.RunTooling | Should -BeTrue
        $plan.RunDistribution | Should -BeTrue
        $plan.RunReadyToRun | Should -BeTrue
        $plan.RunPreview | Should -BeTrue
        $plan.Reasons.Reason | Should -Contain 'RequestedByPullRequestChecklist'
    }
}

Describe 'Freshness of the PR CI receipt' {
    BeforeEach {
        $script:head='a'*40
        $script:base='b'*40
        $script:merge='c'*40
        $script:apiBody=$template
        $script:receiptOptions=@()
        $script:attempt=2
        $script:receiptAttempt=2
        $script:conclusion='success'
        $script:apiState='open'
        $script:draft=$false
        $script:runId=123
        $script:runStatus='completed'
        $script:runHead=$script:head
        $script:runBranch='chore/work'
        $script:runEvent='pull_request'
        $script:runPulls=@(7)
        $script:apiOverride=@{}
        $script:editDuringDownload=$false
        $script:captureDirectory=$null
        $script:oversizedReceipt=$false
        $script:receiptAtLimit=$false
        $script:receiptOverride=@{}
        Mock Invoke-QuietPullRequestTool -ModuleName PullRequestCi {
            if($FilePath -cne 'gh'){throw 'Unexpected executable'}
            if($ArgumentList[1] -ceq 'download'){
                $headArguments=$ArgumentList[0..7] -join '|'
                if($headArguments -cne "run|download|123|--repo|example/QuietCli|--name|quietcli-ci-plan-results-attempt-$script:attempt|--dir"){throw 'Unexpected download arguments'}
                $script:captureDirectory=$ArgumentList[-1]
                $receipt=@{
                    Result=@{Ready=$true};RunId='123';RunAttempt=$script:receiptAttempt;Revision=$script:merge
                    PullRequest=@{Number=7;Head=$script:head;Base=$script:base;Revision=$script:merge;Options=$script:receiptOptions}
                }
                foreach($key in $script:receiptOverride.Keys){$receipt[$key]=$script:receiptOverride[$key]}
                $json=if($script:oversizedReceipt){' '* (1MB+1)}else{ConvertTo-Json $receipt -Depth 6}
                if($script:receiptAtLimit){$json=$json.PadRight(1MB)}
                [IO.File]::WriteAllText([IO.Path]::Combine($ArgumentList[-1],'receipt.json'),$json)
                if($script:editDuringDownload){$script:apiBody=$script:apiBody.Replace('[ ]','[x]')}
            }elseif($ArgumentList[1] -ceq '--method'){
                if(($ArgumentList[0..10] -join '|') -cne "api|--method|GET|repos/example/QuietCli/actions/workflows/companions-ci.yml/runs|-f|event=pull_request|-f|head_sha=$script:head|-f|per_page=30|--jq" -or !$ArgumentList[11]){
                    throw 'Unexpected workflow lookup arguments'
                }
                ConvertTo-Json -InputObject @(@{id=$script:runId;head_sha=$script:runHead;head_branch=$script:runBranch;event=$script:runEvent;status=$script:runStatus;conclusion=$script:conclusion;run_attempt=$script:attempt;pulls=$script:runPulls})
            }else{
                if(($ArgumentList[0..2] -join '|') -cne 'api|repos/example/QuietCli/pulls/7|--jq' -or !$ArgumentList[3]){throw 'Unexpected pull request lookup arguments'}
                $data=@{number=7;state=$script:apiState;draft=$script:draft;body=$script:apiBody;merge_commit_sha=$script:merge;head=@{sha=$script:head;ref='chore/work'};base=@{sha=$script:base;ref='develop'}}
                foreach($key in $script:apiOverride.Keys){
                    if($null -eq $script:apiOverride[$key]){$data.Remove($key)}
                    else{$data[$key]=$script:apiOverride[$key]}
                }
                ConvertTo-Json -Depth 5 $data
            }
        }
    }

    It 'returns the exact open PR snapshot and distinguishes a missing merge revision or a closed PR' {
        $snapshot=Read-QuietPullRequestCiSnapshot $root 'example/QuietCli' 7
        $snapshot.body | Should -BeExactly $template
        $snapshot.head.ref | Should -BeExactly 'chore/work'
        $snapshot.merge_commit_sha | Should -BeExactly $script:merge
        $script:apiState='closed'
        {Read-QuietPullRequestCiSnapshot $root 'example/QuietCli' 7} | Should -Throw '*PullRequestCiSnapshotUnavailable*'
        $script:apiState='open'
        $script:merge=''
        {Read-QuietPullRequestCiSnapshot $root 'example/QuietCli' 7} | Should -Throw '*PullRequestCiSnapshotUnavailable*'
    }

    It 'rejects snapshot field <Key> when it cannot identify the checked revision' -ForEach @(
        @{Key='body';Value=$null},@{Key='number';Value=8},@{Key='head';Value=@{sha='bad'}},@{Key='base';Value=@{sha='bad'}}
    ) {
        $script:apiOverride[$Key]=$Value
        {Read-QuietPullRequestCiSnapshot $root 'example/QuietCli' 7} | Should -Throw '*PullRequestCiSnapshotUnavailable*'
    }

    It 'accepts exact evidence and rereads the PR' {
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Not -Throw
        Test-Path -LiteralPath $script:captureDirectory | Should -BeFalse
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName PullRequestCi -Exactly -Times 2 -ParameterFilter {$ArgumentList[1] -like 'repos/*/pulls/7'}
    }

    It 'uses the injected GitHub adapter for the snapshot, run lookup, artifact and final reread' {
        $snapshotJson=ConvertTo-Json -Compress -Depth 5 @{
            number=7;state='open';draft=$false;body=$template;merge_commit_sha=$script:merge
            head=@{sha=$script:head;ref='chore/work'};base=@{sha=$script:base;ref='develop'}
        }
        $runJson=ConvertTo-Json -Compress -InputObject @(
            @{id=123;head_sha=$script:head;head_branch='chore/work';event='pull_request';status='completed';conclusion='success';run_attempt=2;pulls=@(7)}
        )
        $receiptJson=ConvertTo-Json -Compress -Depth 5 @{
            Result=@{Ready=$true};RunId='123';RunAttempt=2;Revision=$script:merge
            PullRequest=@{Number=7;Head=$script:head;Base=$script:base;Revision=$script:merge;Options=@()}
        }
        $calls=[Collections.Generic.List[string]]::new()
        $adapter={
            param($arguments)
            $calls.Add($arguments[1])
            switch ($arguments[1]) {
                'repos/example/QuietCli/pulls/7' {$snapshotJson}
                '--method' {$runJson}
                'download' {[IO.File]::WriteAllText([IO.Path]::Combine($arguments[-1],'receipt.json'),$receiptJson)}
                default {throw 'Unexpected adapter call'}
            }
        }.GetNewClosure()
        Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head -GitHubCommand $adapter
        ($calls -join ',') | Should -BeExactly 'repos/example/QuietCli/pulls/7,--method,download,repos/example/QuietCli/pulls/7'
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName PullRequestCi -Exactly -Times 0
    }

    It 'accepts a valid receipt at the exact size limit' {
        $script:receiptAtLimit=$true
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Not -Throw
    }

    It 'rejects a receipt with invalid <Key> despite a successful workflow run' -ForEach @(
        @{Key='PullRequest';Value=$null},@{Key='Result';Value=@{Ready=$false}},@{Key='RunId';Value='456'}
    ) {
        $script:receiptOverride[$Key]=$Value
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiReceiptStale*'
    }

    It 'rejects a green run for a different checklist or a different attempt' {
        $script:apiBody=New-QuietPullRequestBody -Body '' -Template $template -CiOption preview
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiReceiptStale*'
        $script:receiptOptions=@('preview')
        $script:receiptAttempt=1
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiReceiptStale*'
    }

    It 'rejects a cancelled latest run without downloading an artifact' {
        $script:conclusion='cancelled'
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiLatestRunNotSuccessful*'
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName PullRequestCi -Exactly -Times 0 -ParameterFilter {$ArgumentList[1] -ceq 'download'}
    }

    It 'rejects <Field> on a superficially similar successful run' -ForEach @(
        @{Field='runId';Value=0},@{Field='runHead';Value=('d'*40)},@{Field='runBranch';Value='chore/other'},
        @{Field='runEvent';Value='workflow_dispatch'},@{Field='runStatus';Value='in_progress'},@{Field='attempt';Value=0}
    ) {
        Set-Variable -Name $Field -Scope Script -Value $Value
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiLatestRunNotSuccessful*'
    }

    It 'associates an empty PR list only with an exact check link' {
        $script:runPulls=@()
        $link=@([pscustomobject]@{detailsUrl='https://github.com/example/QuietCli/actions/runs/123/job/1'})
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head -CheckRollup $link} | Should -Not -Throw
        $link[0].detailsUrl='https://github.com/example/QuietCli/actions/runs/1234/job/1'
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head -CheckRollup $link} | Should -Throw '*PullRequestCiLatestRunNotSuccessful*'
        $link[0].detailsUrl='https://example.invalid/?redirect=https://github.com/example/QuietCli/actions/runs/123/job/1'
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head -CheckRollup $link} | Should -Throw '*PullRequestCiLatestRunNotSuccessful*'
        $link[0].detailsUrl='https://github.com/example/QuietCli/actions/runs/123/job/1'
        $script:runPulls=@(8)
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head -CheckRollup $link} | Should -Throw '*PullRequestCiLatestRunNotSuccessful*'
    }

    It 'checks the requested SHA and rejects draft, mid-download change and oversized evidence' {
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 ('x'*40)} | Should -Throw '*PullRequestCiCheckpointChanged*'
        $script:draft=$true
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiCheckpointChanged*'
        $script:draft=$false
        $script:editDuringDownload=$true
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiCheckpointChanged*'
        $script:editDuringDownload=$false
        $script:oversizedReceipt=$true
        {Assert-QuietPullRequestCiEvidence $root 'example/QuietCli' 7 $script:head} | Should -Throw '*PullRequestCiReceiptInvalid*'
    }
}
