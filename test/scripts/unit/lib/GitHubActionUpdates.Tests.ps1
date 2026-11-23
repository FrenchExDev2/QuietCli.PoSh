#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name GitHubActionReferences
    $null=Import-QuietTestLibrary -Name GitHubActionUpdates
    $seed=Get-QuietTestSeed
    $old='11d5960a326750d5838078e36cf38b85af677262'
    $new='3d3c42e5aac5ba805825da76410c181273ba90b1'
    $reference={param([string]$Line)(ConvertFrom-QuietGitHubActionUses -Text $Line -Path 'w.yml')[0]}
    $release={param([string]$Tag,[string]$Sha=$new,[string]$Action='actions/checkout')[pscustomobject]@{Action=$Action;Status='Resolved';Tag=$Tag;Sha=$Sha;Source='Catalog'}}
}

Describe 'ConvertTo-QuietGitHubActionVersion' {
    It 'reads <Text> as <Expected>' -ForEach @(
        @{Text='v4';Expected='4.0.0'}
        @{Text='v4.3';Expected='4.3.0'}
        @{Text='v4.3.1';Expected='4.3.1'}
        @{Text='4.3.1';Expected='4.3.1'}
        @{Text='v10.0.0';Expected='10.0.0'}
    ) {
        ConvertTo-QuietGitHubActionVersion -Text $Text|Should -Be ([version]$Expected)
    }

    It 'returns null for <Text>' -ForEach @(@{Text=''},@{Text='main'},@{Text='v'},@{Text='v4.3.1.2'},@{Text='v4-beta'},@{Text='V4'},@{Text=' v4'}) {
        @(ConvertTo-QuietGitHubActionVersion -Text $Text).Count|Should -Be 1
        ConvertTo-QuietGitHubActionVersion -Text $Text|Should -BeNullOrEmpty
    }

    It 'orders versions numerically, not as text (property)' {
        Invoke-QuietProperty -Name 'numeric order' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            @(1..2|ForEach-Object {@($Random.Next(0,30),$Random.Next(0,30),$Random.Next(0,30))})
        } -Property {param($case)
            $left=ConvertTo-QuietGitHubActionVersion -Text ('v'+($case[0] -join '.'))
            $right=ConvertTo-QuietGitHubActionVersion -Text ('v'+($case[1] -join '.'))
            $expected=[Math]::Sign(($case[0][0]-$case[1][0])*10000+($case[0][1]-$case[1][1])*100+($case[0][2]-$case[1][2]))
            [Math]::Sign($left.CompareTo($right))|Should -Be $expected
        }|Should -Be 200
    }
}

Describe 'Get-QuietGitHubActionComment' {
    It 'turns <Comment> into <Expected>' -ForEach @(
        @{Comment=$null;Expected='v7.0.1'}
        @{Comment='';Expected='v7.0.1'}
        @{Comment='  ';Expected='v7.0.1'}
        @{Comment='v4';Expected='v7.0.1'}
        @{Comment='v4.3.0';Expected='v7.0.1'}
        @{Comment='4.3';Expected='v7.0.1'}
        @{Comment='v4, reviewed upstream reference';Expected='v7.0.1, reviewed upstream reference'}
        @{Comment='v4 pinned';Expected='v7.0.1 pinned'}
        @{Comment='reviewed';Expected='v7.0.1, reviewed'}
        @{Comment='v4x';Expected='v7.0.1, v4x'}
        @{Comment='v4.3.0.1';Expected='v7.0.1, v4.3.0.1'}
    ) {
        Get-QuietGitHubActionComment -Comment $Comment -Tag 'v7.0.1'|Should -BeExactly $Expected
    }

    It 'is idempotent: a second update with the same tag changes nothing (property)' {
        Invoke-QuietProperty -Name 'comment idempotence' -Seed $seed -Count 300 -Generator {param([Random]$Random)
            [pscustomobject]@{
                Comment=(Get-QuietRandomItem $Random @('','v4','v4.3.0','reviewed','v4, reviewed','v12 pinned'))+(New-QuietRandomString $Random -Alphabet ' ,.abv12' -MinLength 0 -MaxLength 6)
                Tag='v'+$Random.Next(1,20)+'.'+$Random.Next(0,9)+'.'+$Random.Next(0,9)
            }
        } -Property {param($case)
            $once=Get-QuietGitHubActionComment -Comment $case.Comment -Tag $case.Tag
            $once.StartsWith($case.Tag,[StringComparison]::Ordinal)|Should -BeTrue
            Get-QuietGitHubActionComment -Comment $once -Tag $case.Tag|Should -BeExactly $once
        }|Should -Be 300
    }
}

Describe 'Get-QuietGitHubActionCurrentVersion' {
    It 'reads the version of <Line>' -ForEach @(
        @{Line='uses: a/b@v4.2';Expected='4.2.0'}
        @{Line='uses: a/b@11d5960a326750d5838078e36cf38b85af677262 # v4.3.0';Expected='4.3.0'}
        @{Line='uses: a/b@11d5960a326750d5838078e36cf38b85af677262 # v4, reviewed';Expected='4.0.0'}
    ) {
        Get-QuietGitHubActionCurrentVersion -Reference (& $reference $Line)|Should -Be ([version]$Expected)
    }

    It 'has no version for <Line>' -ForEach @(
        @{Line='uses: a/b@11d5960a326750d5838078e36cf38b85af677262'}
        @{Line='uses: a/b@11d5960a326750d5838078e36cf38b85af677262 # reviewed v4'}
        @{Line='uses: a/b@11d5960a326750d5838078e36cf38b85af677262 # v4x'}
    ) {
        Get-QuietGitHubActionCurrentVersion -Reference (& $reference $Line)|Should -BeNullOrEmpty
    }
}

Describe 'Get-QuietGitHubActionUpdate' {
    It 'moves a commit pin to the release commit and its comment to the tag' {
        $decision=Get-QuietGitHubActionUpdate -Reference (& $reference ('      - uses: actions/checkout@'+$old+' # v4')) -Release (& $release 'v7.0.1')
        $decision.Status|Should -BeExactly 'Update'
        $decision.Reason|Should -BeNullOrEmpty
        $decision.Ref|Should -BeExactly $new
        $decision.Comment|Should -BeExactly 'v7.0.1'
        $decision.NewLine|Should -BeExactly ('      - uses: actions/checkout@'+$new+' # v7.0.1')
    }

    It 'adds the tag as comment to an uncommented commit pin' {
        (Get-QuietGitHubActionUpdate -Reference (& $reference ('- uses: actions/checkout@'+$old)) -Release (& $release 'v7.0.1')).NewLine|Should -BeExactly ('- uses: actions/checkout@'+$new+' # v7.0.1')
    }

    It 'updates only the comment of a pin already on the release commit' {
        $decision=Get-QuietGitHubActionUpdate -Reference (& $reference ('- uses: actions/checkout@'+$new+' # v7')) -Release (& $release 'v7.0.1')
        $decision.Status|Should -BeExactly 'Update'
        $decision.NewLine|Should -BeExactly ('- uses: actions/checkout@'+$new+' # v7.0.1')
    }

    It 'reports an exact pin as up to date' {
        $line='- uses: actions/checkout@'+$new+' # v7.0.1'
        $decision=Get-QuietGitHubActionUpdate -Reference (& $reference $line) -Release (& $release 'v7.0.1')
        $decision.Status|Should -BeExactly 'UpToDate'
        $decision.NewLine|Should -BeExactly $line
    }

    It 'moves a version tag to the release tag and keeps its comment' {
        $decision=Get-QuietGitHubActionUpdate -Reference (& $reference '- uses: "actions/checkout@v4" # main checkout') -Release (& $release 'v7.0.1')
        $decision.Status|Should -BeExactly 'Update'
        $decision.NewLine|Should -BeExactly '- uses: "actions/checkout@v7.0.1" # main checkout'
        (Get-QuietGitHubActionUpdate -Reference (& $reference '- uses: actions/checkout@v7.0.1') -Release (& $release 'v7.0.1')).Status|Should -BeExactly 'UpToDate'
    }

    It 'keeps the sub path of a composite action' {
        (Get-QuietGitHubActionUpdate -Reference (& $reference ('uses: actions/checkout/restore@'+$old+' # v4.3.0')) -Release (& $release 'v6.1.0')).NewLine|Should -BeExactly ('uses: actions/checkout/restore@'+$new+' # v6.1.0')
    }

    It 'skips <Name> with reason <Reason> and keeps the line' -ForEach @(
        @{Name='a branch';Line='- uses: actions/checkout@main';Tag='v7.0.1';Status='Resolved';Reason='NotReleasePinned'}
        @{Name='a repository without release';Line='- uses: actions/checkout@v4';Tag=$null;Status='NoRelease';Reason='NoRelease'}
        @{Name='a version above the latest';Line='- uses: actions/checkout@v8';Tag='v7.0.1';Status='Resolved';Reason='NewerThanLatest'}
        @{Name='a commit pin commented above the latest';Line='- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v8.0.0-rc';Tag='v7.0.1';Status='Resolved';Reason='NewerThanLatest'}
    ) {
        $source=[pscustomobject]@{Action='actions/checkout';Status=$Status;Tag=$Tag;Sha=$(if($Tag){$new}else{$null});Source='Catalog'}
        $decision=Get-QuietGitHubActionUpdate -Reference (& $reference $Line) -Release $source
        $decision.Status|Should -BeExactly 'Skipped'
        $decision.Reason|Should -BeExactly $Reason
        $decision.NewLine|Should -BeExactly $Line
    }

    It 'updates a pin whose version only differs in an equal prefix' {
        # v7 and v7.0.0 compare equal: not newer, so the pin follows the release.
        (Get-QuietGitHubActionUpdate -Reference (& $reference '- uses: actions/checkout@v7') -Release (& $release 'v7.0.0')).Status|Should -BeExactly 'Update'
    }

    It 'updates even when the release tag is not a version' {
        (Get-QuietGitHubActionUpdate -Reference (& $reference '- uses: actions/checkout@v4') -Release (& $release 'release-2025')).NewLine|Should -BeExactly '- uses: actions/checkout@release-2025'
    }

    It 'refuses a <Name>' -ForEach @(
        @{Name='local reference';Line='- uses: ./x';Action='actions/checkout';Message='GitHubActionReferenceInvalid: Local references have no release'}
        @{Name='release of another action';Line='- uses: actions/checkout@v4';Action='actions/cache';Message='GitHubActionReleaseMismatch: actions/cache for actions/checkout'}
    ) {
        {Get-QuietGitHubActionUpdate -Reference (& $reference $Line) -Release (& $release 'v7' $new $Action)}|Should -Throw -ExpectedMessage $Message
    }

    It 'converges: the updated line is up to date for the same release (property)' {
        Invoke-QuietProperty -Name 'update convergence' -Seed $seed -Count 300 -Generator {param([Random]$Random)
            $sha={(New-QuietRandomSha256 $Random).ToLowerInvariant().Substring(0,40)}
            $ref=switch($Random.Next(2)){0{& $sha}default{'v'+$Random.Next(1,6)}}
            $comment=Get-QuietRandomItem $Random @('',' # v1',' # v2.1.0',' # v3, reviewed',' # reviewed')
            [pscustomobject]@{Line=(' '*$Random.Next(0,8))+'- uses: actions/checkout@'+$ref+$comment;Tag='v'+$Random.Next(6,9)+'.'+$Random.Next(0,4)+'.'+$Random.Next(0,4);Sha=& $sha}
        } -Property {param($case)
            $first=Get-QuietGitHubActionUpdate -Reference (& $reference $case.Line) -Release (& $release $case.Tag $case.Sha)
            $first.Status|Should -BeIn @('Update','UpToDate')
            $second=Get-QuietGitHubActionUpdate -Reference (& $reference $first.NewLine) -Release (& $release $case.Tag $case.Sha)
            $second.Status|Should -BeExactly 'UpToDate'
            $second.NewLine|Should -BeExactly $first.NewLine
            (& $reference $first.NewLine).Ref|Should -BeIn @($case.Sha,$case.Tag)
        }|Should -Be 300
    }
}

Describe 'Get-QuietGitHubActionWorkflowDocumentPath' {
    It 'maps <Path> to <Expected>' -ForEach @(
        @{Path='.github/workflows/ci.yml';Expected='docs/ci/github/script-ci.md'}
        @{Path='.github/workflows/companions-ci.yaml';Expected='docs/ci/github/script-companions-ci.md'}
        @{Path='.github/workflows/a.b.yml';Expected='docs/ci/github/script-a.b.md'}
    ) {
        Get-QuietGitHubActionWorkflowDocumentPath -RelativePath $Path|Should -BeExactly $Expected
    }

    It 'has no document for <Path>' -ForEach @(@{Path='.github/actions/cache-resources/action.yml'},@{Path='.github/workflows/nested/ci.yml'},@{Path='.github/workflows/ci.json'},@{Path='x/.github/workflows/ci.yml'}) {
        @(Get-QuietGitHubActionWorkflowDocumentPath -RelativePath $Path).Count|Should -Be 1
        Get-QuietGitHubActionWorkflowDocumentPath -RelativePath $Path|Should -BeNullOrEmpty
    }
}

Describe 'Get-QuietGitHubActionReceiptText' {
    BeforeAll {
        $before='A'*64
        $after='B'*64
    }

    It 'moves a current receipt to the new hash and changes nothing else' {
        $text="# ci.yml`r`n`r`n<!-- workflow-source-sha256: $before -->`r`n`r`n## Purpose`r`n"
        Get-QuietGitHubActionReceiptText -Text $text -PreviousSha256 $before -NewSha256 $after|Should -BeExactly ($text.Replace($before,$after))
    }

    It 'refuses a receipt that <Name>' -ForEach @(
        @{Name='is missing';Text='# ci.yml'}
        @{Name='records another revision';Text=('<!-- workflow-source-sha256: '+('C'*64)+' -->')}
        @{Name='is lowercase';Text=('<!-- workflow-source-sha256: '+('a'*64)+' -->')}
        @{Name='is duplicated';Text=('<!-- workflow-source-sha256: '+('A'*64)+" -->`n<!-- workflow-source-sha256: "+('A'*64)+' -->')}
        @{Name='is indented';Text=(' <!-- workflow-source-sha256: '+('A'*64)+' -->')}
    ) {
        {Get-QuietGitHubActionReceiptText -Text $Text -PreviousSha256 $before -NewSha256 $after}|Should -Throw -ExpectedMessage 'GitHubActionReceiptNotCurrent'
    }

    It 'refuses the hash <Hash> as <Which> before reading the text' -ForEach @(
        @{Which='previous';Hash='x'},@{Which='previous';Hash=('a'*64)},@{Which='new';Hash=('b'*64)},@{Which='new';Hash=('B'*63)},@{Which='new';Hash=('G'*64)}
    ) {
        $text='<!-- workflow-source-sha256: '+$before+' -->'
        $previous=if($Which -eq 'previous'){$Hash}else{$before}
        $next=if($Which -eq 'new'){$Hash}else{$after}
        {Get-QuietGitHubActionReceiptText -Text $text -PreviousSha256 $previous -NewSha256 $next}|Should -Throw -ExpectedMessage 'GitHubActionReceiptHashInvalid*'
    }
}
