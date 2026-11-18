#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name MergedBranches
    $seed=Get-QuietTestSeed
    $alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $newName={param([Random]$Random)
        (Get-QuietRandomItem $Random @('fix','feature','chore','perf'))+'/'+(New-QuietRandomString $Random -Alphabet $alphabet -MinLength 1 -MaxLength 8)+(Get-QuietRandomItem $Random @('','.x','-y','_z','/sub'))
    }
    $sha={param([Random]$Random)(New-QuietRandomSha256 $Random).ToLowerInvariant().Substring(0,40)}
    $pr={param([long]$Number,[string]$Head,[string]$Oid,[string]$Base='develop',$MergedAt='2026-11-18T10:00:00Z',$Fork=$false)
        [ordered]@{number=$Number;headRefName=$Head;headRefOid=$Oid;baseRefName=$Base;mergedAt=$MergedAt;isCrossRepository=$Fork}
    }
    $toJson={param([object[]]$Items)ConvertTo-Json -InputObject @($Items) -Depth 3 -Compress}
    $branch={param([string]$Name,[string]$Tip=('a'*40),[string]$Worktree='')[pscustomobject]@{Name=$Name;Tip=$Tip;WorktreePath=$Worktree}}
}

Describe 'Get-QuietMergedBranchRepository' {
    It 'reads <Repository> from <Url>' -ForEach @(
        @{Url='https://github.com/FrenchExDev2/QuietCli.PoSh.git';Repository='FrenchExDev2/QuietCli.PoSh'}
        @{Url='https://github.com/FrenchExDev2/QuietCli.PoSh';Repository='FrenchExDev2/QuietCli.PoSh'}
        @{Url='https://github.com/owner/repo/';Repository='owner/repo'}
        @{Url='git@github.com:owner/repo.git';Repository='owner/repo'}
        @{Url='ssh://git@github.com/owner/re_po-1.git';Repository='owner/re_po-1'}
        @{Url='https://GitHub.com/Owner/Repo.git';Repository='Owner/Repo'}
    ) {
        Get-QuietMergedBranchRepository -RemoteUrl $Url|Should -BeExactly $Repository
    }

    It 'returns nothing for the URL <Url>' -ForEach @(
        @{Url=''},@{Url=$null},@{Url='C:/repos/origin.git'},@{Url='/srv/origin.git'},@{Url='https://gitlab.com/owner/repo.git'},
        @{Url='https://github.com/owner'},@{Url='https://github.com/owner/repo/extra'},@{Url='https://github.com.evil.example/owner/repo'},
        @{Url=' https://github.com/owner/repo'},@{Url='https://github.com/own er/repo'}
    ) {
        $repository=Get-QuietMergedBranchRepository -RemoteUrl $Url
        $null -eq $repository|Should -BeTrue -Because 'no repository is not an empty repository name'
    }
}

Describe 'ConvertFrom-QuietMergedBranchRefs' {
    It 'returns nothing for empty output' -ForEach @(@{Text=''},@{Text=$null},@{Text="`n`r`n"}) {
        @(ConvertFrom-QuietMergedBranchRefs -Text $Text).Count|Should -Be 0
    }

    It 'reads each branch with its tip and worktree, with LF or CRLF and SHA-1 or SHA-256 ids' {
        $text="refs/heads/develop`t$('a'*40)`tC:/work`r`nrefs/heads/feature/x.y`t$('b'*64)`t`nrefs/heads/fix/a b`t$('c'*40)`t"
        {ConvertFrom-QuietMergedBranchRefs -Text $text}|Should -Throw -ExpectedMessage 'MergedBranchRefsInvalid*' -Because 'a branch name never holds a space'
        $branches=@(ConvertFrom-QuietMergedBranchRefs -Text ("refs/heads/develop`t$('a'*40)`tC:/my work`r`nrefs/heads/feature/x.y`t$('b'*64)`t"))
        $branches.Count|Should -Be 2
        $branches[0].Name|Should -BeExactly 'develop'
        $branches[0].Tip|Should -BeExactly ('a'*40)
        $branches[0].WorktreePath|Should -BeExactly 'C:/my work'
        $branches[1].Name|Should -BeExactly 'feature/x.y'
        $branches[1].Tip|Should -BeExactly ('b'*64)
        $branches[1].WorktreePath|Should -BeExactly ''
    }

    It 'rejects the line <Line>' -ForEach @(
        @{Line="refs/heads/develop`t$('a'*40)"},@{Line="refs/tags/v1`t$('a'*40)`t"},@{Line="develop`t$('a'*40)`t"},
        @{Line="refs/heads/`t$('a'*40)`t"},@{Line="refs/heads/develop`t$('A'*40)`t"},@{Line="refs/heads/develop`t$('a'*39)`t"},
        @{Line="refs/heads/develop $('a'*40) "},@{Line="refs/heads/develop`t$('a'*40)`tx`ty"},@{Line='fatal: not a git repository'}
    ) {
        {ConvertFrom-QuietMergedBranchRefs -Text $Line}|Should -Throw -ExpectedMessage 'MergedBranchRefsInvalid*'
    }

    It 'rejects a branch listed twice' {
        {ConvertFrom-QuietMergedBranchRefs -Text ("refs/heads/x`t$('a'*40)`t`nrefs/heads/x`t$('a'*40)`t")}|Should -Throw -ExpectedMessage 'MergedBranchRefsInvalid: x listed twice'
    }

    It 'round-trips any generated listing' {
        $null=Invoke-QuietProperty -Name 'merged-branch-refs-roundtrip' -Seed $seed -Count 60 -Generator {param($random)
            $names=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
            foreach($index in 0..($random.Next(0,6))){[void]$names.Add((& $newName $random))}
            @(foreach($name in $names){[pscustomobject]@{Name=$name;Tip=(& $sha $random);WorktreePath=$(if($random.Next(4)){''}else{'C:/w/'+$random.Next(100)})}})
        } -Property {param($case)
            $text=(@($case|ForEach-Object {'refs/heads/'+$_.Name+"`t"+$_.Tip+"`t"+$_.WorktreePath}) -join "`n")
            $parsed=@(ConvertFrom-QuietMergedBranchRefs -Text $text)
            if($parsed.Count -ne @($case).Count){return $false}
            for($index=0;$index -lt $parsed.Count;$index++){
                if($parsed[$index].Name -cne $case[$index].Name -or $parsed[$index].Tip -cne $case[$index].Tip -or $parsed[$index].WorktreePath -cne $case[$index].WorktreePath){return $false}
            }
            $true
        }
    }
}

Describe 'ConvertFrom-QuietMergedBranchPullRequests' {
    It 'keeps only pull requests merged into the base from the repository itself' {
        $json=& $toJson @(
            & $pr 1 'feature/merged' ('1'*40)
            & $pr 2 'feature/open' ('2'*40) -MergedAt $null
            & $pr 3 'feature/main' ('3'*40) -Base 'main'
            & $pr 4 'feature/fork' ('4'*40) -Fork $true
            & $pr 5 'feature/empty-date' ('5'*40) -MergedAt ''
        )
        $map=ConvertFrom-QuietMergedBranchPullRequests -Json $json
        @($map.Keys)|Should -BeExactly @('feature/merged')
        $map['feature/merged'].Number|Should -Be 1
        $map['feature/merged'].HeadRefOid|Should -BeExactly ('1'*40)
        $map['feature/merged'].MergedAt|Should -BeExactly '2026-11-18T10:00:00Z' -Because 'dates are kept as the text GitHub sent'
        (ConvertFrom-QuietMergedBranchPullRequests -Json $json -BaseBranch main).Keys|Should -BeExactly @('feature/main')
    }

    It 'keeps the latest merged pull request of a reused branch, whatever the order' {
        $items=@((& $pr 7 'fix/reused' ('7'*40)),(& $pr 19 'fix/reused' ('9'*40)),(& $pr 20 'fix/reused' ('0'*40) -MergedAt $null))
        foreach($order in @($items),@($items[2],$items[1],$items[0])){
            (ConvertFrom-QuietMergedBranchPullRequests -Json (& $toJson $order))['fix/reused'].Number|Should -Be 19
        }
    }

    It 'compares branch names ordinally' {
        $map=ConvertFrom-QuietMergedBranchPullRequests -Json (& $toJson @((& $pr 1 'Fix/x' ('1'*40))))
        $map.ContainsKey('fix/x')|Should -BeFalse
        $map.ContainsKey('Fix/x')|Should -BeTrue
    }

    It 'returns an empty map for an empty array' {
        (ConvertFrom-QuietMergedBranchPullRequests -Json '[]').Count|Should -Be 0
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='text that is not JSON';Json='not json';Expected='not JSON'}
        @{Case='empty output';Json='';Expected='*'}
        @{Case='an object';Json='{"number":1}';Expected='expected an array'}
        @{Case='null';Json='null';Expected='expected an array'}
        @{Case='an array of numbers';Json='[1]';Expected='expected objects'}
        @{Case='a missing field';Json='[{"number":1,"headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":null}]';Expected='missing isCrossRepository'}
        @{Case='a text number';Json='[{"number":"1","headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":null,"isCrossRepository":false}]';Expected='number'}
        @{Case='a zero number';Json='[{"number":0,"headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":null,"isCrossRepository":false}]';Expected='number'}
        @{Case='an empty head';Json='[{"number":1,"headRefName":"","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":null,"isCrossRepository":false}]';Expected='headRefName of #1'}
        @{Case='an uppercase oid';Json='[{"number":1,"headRefName":"a","headRefOid":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","baseRefName":"develop","mergedAt":null,"isCrossRepository":false}]';Expected='headRefOid of #1'}
        @{Case='a numeric base';Json='[{"number":1,"headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":1,"mergedAt":null,"isCrossRepository":false}]';Expected='baseRefName of #1'}
        @{Case='a numeric date';Json='[{"number":1,"headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":5,"isCrossRepository":false}]';Expected='mergedAt of #1'}
        @{Case='a text fork flag';Json='[{"number":1,"headRefName":"a","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"develop","mergedAt":null,"isCrossRepository":"false"}]';Expected='isCrossRepository of #1'}
    ) {
        {ConvertFrom-QuietMergedBranchPullRequests -Json $Json}|Should -Throw -ExpectedMessage ('MergedBranchPullRequestsInvalid: '+$Expected)
    }

    It 'rejects a number listed twice' {
        {ConvertFrom-QuietMergedBranchPullRequests -Json (& $toJson @((& $pr 3 'a' ('1'*40)),(& $pr 3 'b' ('2'*40))))}|Should -Throw -ExpectedMessage 'MergedBranchPullRequestsInvalid: #3 listed twice'
    }

    It 'maps every head to its highest merged number into the base' {
        $null=Invoke-QuietProperty -Name 'merged-pull-requests-latest' -Seed $seed -Count 80 -Generator {param($random)
            $heads=@(foreach($index in 0..($random.Next(0,4))){& $newName $random})
            $numbers=@((Get-QuietShuffle $random @(1..40))|ForEach-Object {$_})
            @(foreach($index in 0..($random.Next(0,12))){
                & $pr ([long]$numbers[$index]) (Get-QuietRandomItem $random $heads) (& $sha $random) (Get-QuietRandomItem $random @('develop','develop','main')) (Get-QuietRandomItem $random @('2026-01-01T00:00:00Z','2026-01-01T00:00:00Z',$null)) ($random.Next(5) -eq 0)
            })
        } -Property {param($case)
            $map=ConvertFrom-QuietMergedBranchPullRequests -Json (& $toJson $case)
            $eligible=@($case|Where-Object {$_.mergedAt -and $_.baseRefName -ceq 'develop' -and !$_.isCrossRepository})
            # Ordinal, as Git branch names: a PowerShell hashtable would merge heads that only differ in case.
            $expected=[Collections.Generic.Dictionary[string,long]]::new([StringComparer]::Ordinal)
            foreach($item in $eligible){if(!$expected.ContainsKey($item.headRefName) -or $expected[$item.headRefName] -lt $item.number){$expected[$item.headRefName]=$item.number}}
            $map.Count -eq $expected.Count -and @($expected.Keys|Where-Object {$map[$_].Number -ne $expected[$_]}).Count -eq 0
        }
    }

    It 'only fails with a typed error on hostile JSON' {
        $null=Invoke-QuietProperty -Name 'merged-pull-requests-fuzz' -Seed $seed -Count 200 -Generator {param($random)
            $fields=@('number','headRefName','headRefOid','baseRefName','mergedAt','isCrossRepository')
            $values=@(1,0,-3,'1',$null,'',$true,'develop',('a'*40),('A'*40),@(),@{x=1},'2026-01-01T00:00:00Z',2147483648)
            $items=@(foreach($index in 0..($random.Next(0,4))){
                $item=[ordered]@{}
                foreach($field in $fields){if($random.Next(8)){$item[$field]=Get-QuietRandomItem $random $values}}
                $item
            })
            $json=& $toJson $items
            if($random.Next(6) -eq 0){$json=$json.Substring(0,$random.Next(0,$json.Length+1))}
            $json
        } -Property {param($case)
            try{$null=ConvertFrom-QuietMergedBranchPullRequests -Json $case}catch{
                if($_.Exception.Message -cnotmatch '\AMergedBranchPullRequestsInvalid: '){throw ('untyped: '+$_.Exception.Message)}
            }
            $true
        }
    }
}

Describe 'ConvertTo-QuietMergedBranchRelation' {
    It 'names <Expected> for exit code <Code>' -ForEach @(
        @{Code=0;Expected='Contained'},@{Code=1;Expected='Diverged'},@{Code=128;Expected='Unknown'},@{Code=-1;Expected='Unknown'},@{Code=2;Expected='Unknown'}
    ) {
        ConvertTo-QuietMergedBranchRelation -Tip ('a'*40) -Head ('b'*40) -AncestorExitCode $Code|Should -BeExactly $Expected
    }

    It 'names Same for equal ids, whatever the exit code' -ForEach @(@{Code=0},@{Code=1},@{Code=128}) {
        ConvertTo-QuietMergedBranchRelation -Tip ('a'*40) -Head ('a'*40) -AncestorExitCode $Code|Should -BeExactly 'Same'
    }

    It 'never names Same for empty or differently cased ids' {
        ConvertTo-QuietMergedBranchRelation -Tip '' -Head '' -AncestorExitCode 1|Should -BeExactly 'Diverged'
        ConvertTo-QuietMergedBranchRelation -Tip ('a'*40) -Head ('A'*40) -AncestorExitCode 1|Should -BeExactly 'Diverged'
    }
}

Describe 'Get-QuietMergedBranchDecision' {
    BeforeAll {
        $merged=[pscustomobject]@{Number=31;HeadRefName='feature/x';HeadRefOid=('a'*40)}
    }

    It 'decides <Action>/<Reason> for <Case>' -ForEach @(
        @{Case='a merged pull request with the same tip';Name='feature/x';HasPr=$true;Relation='Same';Action='Delete';Reason='MergedPullRequest'}
        @{Case='a merged pull request that contains the tip';Name='feature/x';HasPr=$true;Relation='Contained';Action='Delete';Reason='MergedPullRequest'}
        @{Case='local commits after the merge';Name='feature/x';HasPr=$true;Relation='Diverged';Action='Keep';Reason='AheadOfPullRequest'}
        @{Case='an unavailable pull request head';Name='feature/x';HasPr=$true;Relation='Unknown';Action='Keep';Reason='PullRequestHeadUnknown'}
        @{Case='a checked-out merged branch';Name='feature/x';HasPr=$true;Relation='Same';Worktree='C:/work';Action='Keep';Reason='CheckedOut'}
        @{Case='the base';Name='develop';HasPr=$true;Relation='Same';Action='Keep';Reason='Protected'}
        @{Case='a protected name';Name='main';HasPr=$true;Relation='Same';Action='Keep';Reason='Protected'}
        @{Case='a protected name in another case';Name='Main';HasPr=$true;Relation='Same';Action='Keep';Reason='Protected'}
        @{Case='no pull request, in the base';Name='chore/y';Contained=$true;Action='Keep';Reason='ContainedInBaseOnly'}
        @{Case='no pull request, in the base, included';Name='chore/y';Contained=$true;Include=$true;Action='Delete';Reason='ContainedInBase'}
        @{Case='no pull request, out of the base, included';Name='chore/y';Include=$true;Action='Keep';Reason='NoMergedPullRequest'}
        @{Case='no pull request';Name='chore/y';Action='Keep';Reason='NoMergedPullRequest'}
        @{Case='a checked-out branch in the base, included';Name='chore/y';Contained=$true;Include=$true;Worktree='/w';Action='Keep';Reason='CheckedOut'}
        @{Case='the base in the base, included';Name='develop';Contained=$true;Include=$true;Action='Keep';Reason='Protected'}
    ) {
        $arguments=@{Branch=(& $branch $Name ('b'*40) ([string]$Worktree));BaseBranch='develop';Protected=@('main','master');PullRequest=$(if($HasPr){$merged}else{$null});ContainedInBase=[bool]$Contained;IncludeContainedInBase=[bool]$Include}
        if($Relation){$arguments.Relation=$Relation}
        $decision=Get-QuietMergedBranchDecision @arguments
        $decision.Action|Should -BeExactly $Action
        $decision.Reason|Should -BeExactly $Reason
        $decision.Branch|Should -BeExactly $Name
        $decision.Tip|Should -BeExactly ('b'*40)
        $decision.PullRequest|Should -Be $(if($HasPr){31}else{$null})
    }

    It 'reads the relation only when there is a pull request, and containment only when there is none' {
        (Get-QuietMergedBranchDecision -Branch (& $branch 'chore/y') -BaseBranch develop -Relation Same).Reason|Should -BeExactly 'NoMergedPullRequest'
        (Get-QuietMergedBranchDecision -Branch (& $branch 'feature/x') -BaseBranch develop -PullRequest $merged -Relation Diverged -ContainedInBase -IncludeContainedInBase).Reason|Should -BeExactly 'AheadOfPullRequest' -Because 'unpushed commits outweigh a tip that is also in the base'
    }

    It 'defaults the relation to Unknown, so a pull request alone never deletes' {
        (Get-QuietMergedBranchDecision -Branch (& $branch 'feature/x') -BaseBranch develop -PullRequest $merged).Action|Should -BeExactly 'Keep'
    }

    It 'never deletes a checked-out, base or protected branch, and only deletes with evidence' {
        $null=Invoke-QuietProperty -Name 'merged-branch-safety' -Seed $seed -Count 300 -Generator {param($random)
            $protected=@(Get-QuietRandomSubset $random @('main','master','release-train'))
            @{
                Name=(Get-QuietRandomItem $random @('develop','main','master','release-train',(& $newName $random),(& $newName $random)))
                Worktree=(Get-QuietRandomItem $random @('','','C:/work','/srv/w'))
                Protected=[string[]]$protected
                Pr=[bool]$random.Next(2)
                Relation=(Get-QuietRandomItem $random @('Same','Contained','Diverged','Unknown'))
                Contained=[bool]$random.Next(2)
                Include=[bool]$random.Next(2)
            }
        } -Property {param($case)
            $decision=Get-QuietMergedBranchDecision -Branch (& $branch $case.Name ('c'*40) $case.Worktree) -BaseBranch develop -Protected $case.Protected -PullRequest $(if($case.Pr){$merged}else{$null}) -Relation $case.Relation -ContainedInBase:$case.Contained -IncludeContainedInBase:$case.Include
            if($decision.Action -cnotin 'Delete','Keep'){return $false}
            if($decision.Action -ceq 'Keep'){return $true}
            $guarded=$case.Worktree -or (@('develop')+$case.Protected) -contains $case.Name
            $evidence=if($case.Pr){$case.Relation -in 'Same','Contained'}else{$case.Contained -and $case.Include}
            !$guarded -and $evidence
        }
    }
}

Describe 'Get-QuietMergedBranchConfigSections' {
    It 'returns nothing for empty output' -ForEach @(@{Text=''},@{Text=$null}) {
        @(Get-QuietMergedBranchConfigSections -Text $Text).Count|Should -Be 0
    }

    It 'lists each configured branch once, sorted ordinally' {
        $text="branch.develop.remote`nbranch.develop.merge`nbranch.feature/x.y.remote`r`nBRANCH.Fix/A.merge`nbranch.develop.vscode-merge-base`nremote.origin.url`nbranch.nodot`n"
        Get-QuietMergedBranchConfigSections -Text $text|Should -BeExactly @('Fix/A','develop','feature/x.y') -Because 'feature/x.y only appears on a CRLF line'
    }
}
