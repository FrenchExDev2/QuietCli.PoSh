#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name WorkBranch
    $seed=Get-QuietTestSeed
    $segmentAlphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    # A valid name: 1 to 3 segments, each alphanumeric at both ends with ., _ or - inside.
    $newName={param([Random]$Random)
        @(foreach($index in 1..($Random.Next(1,4))){
            $segment=New-QuietRandomString $Random -Alphabet $segmentAlphabet -MinLength 1 -MaxLength 6
            if($Random.Next(2)){$segment+=(Get-QuietRandomItem $Random @('.','_','-'))+(New-QuietRandomString $Random -Alphabet $segmentAlphabet -MinLength 1 -MaxLength 6)}
            $segment
        }) -join '/'
    }
    $sha={param([Random]$Random)(New-QuietRandomSha256 $Random).ToLowerInvariant().Substring(0,40)}
}

Describe 'Get-QuietWorkBranchKinds' {
    It 'lists the three work branch kinds in order, without release' {
        Get-QuietWorkBranchKinds|Should -BeExactly @('fix','feature','chore') -Because 'releases are tags; release/* branches belong to Invoke-QuietRelease.ps1'
    }
}

Describe 'Resolve-QuietWorkBranchName' {
    It 'splits <Branch> into its kind and name' -ForEach @(
        @{Branch='feature/script-tests';Kind='feature';Name='script-tests'}
        @{Branch='fix/suite-image-concurrency';Kind='fix';Name='suite-image-concurrency'}
        @{Branch='chore/bump.pester_6';Kind='chore';Name='bump.pester_6'}
        @{Branch='feature/ci/split-images';Kind='feature';Name='ci/split-images'}
        @{Branch='fix/A';Kind='fix';Name='A'}
    ) {
        $resolved=Resolve-QuietWorkBranchName -Branch $Branch
        $resolved.Branch|Should -BeExactly $Branch
        $resolved.Kind|Should -BeExactly $Kind
        $resolved.Name|Should -BeExactly $Name
        (Resolve-QuietWorkBranchName -Kind $Kind -Name $Name).Branch|Should -BeExactly $Branch
    }

    It 'rejects the kind of <Branch>' -ForEach @(
        @{Branch='hotfix/x'},@{Branch='Feature/x'},@{Branch='FIX/x'},@{Branch='develop'},@{Branch='/x'},@{Branch=''},@{Branch='features/x'},@{Branch=' feature/x'},@{Branch='release/core-1.2.0'}
    ) {
        {Resolve-QuietWorkBranchName -Branch $Branch}|Should -Throw -ExpectedMessage 'WorkBranchKindInvalid*'
    }

    It 'rejects the name <Name>' -ForEach @(
        @{Name=''},@{Name='..'},@{Name='a..b'},@{Name='x.lock'},@{Name='a/x.lock'},@{Name='-x'},@{Name='x-'},@{Name='.x'},@{Name='x.'},
        @{Name='a//b'},@{Name='a/'},@{Name='/a'},@{Name='a b'},@{Name='caf'+[char]0xE9},@{Name='a~b'},@{Name='a:b'},@{Name='a^b'},
        @{Name='a?b'},@{Name='a*b'},@{Name='a[b'},@{Name='a\b'},@{Name='a@{b'},@{Name=('a'*101)}
    ) {
        {Resolve-QuietWorkBranchName -Kind feature -Name $Name}|Should -Throw -ExpectedMessage 'WorkBranchNameInvalid*'
    }

    # Kept out of the table above: a NUL in the test name would make the JUnit report invalid XML.
    It 'rejects a name with a NUL character' {
        {Resolve-QuietWorkBranchName -Kind feature -Name ('a'+[char]0+'b')}|Should -Throw -ExpectedMessage 'WorkBranchNameInvalid*'
    }

    It 'explains why <Branch> is refused' -ForEach @(
        @{Branch='develop';Message='WorkBranchKindInvalid: develop has no kind/ prefix'}
        @{Branch='/x';Message='WorkBranchKindInvalid: ; expected one of fix, feature, chore'}
        @{Branch='feature/';Message='WorkBranchNameInvalid: empty name'}
        @{Branch='feature/a b';Message='WorkBranchNameInvalid: segment ''a b'' must start and end with a letter or digit and contain only letters, digits, ., _ and -'}
        @{Branch='feature/ok/a..b';Message='WorkBranchNameInvalid: segment ''a..b'' contains .. or ends with .lock'}
        @{Branch=('fix/'+('a'*101));Message='WorkBranchNameInvalid: longer than 100 characters'}
    ) {
        {Resolve-QuietWorkBranchName -Branch $Branch}|Should -Throw -ExpectedMessage $Message
    }

    It 'accepts a name of exactly 100 characters' {
        (Resolve-QuietWorkBranchName -Kind chore -Name ('a'*100)).Name.Length|Should -Be 100
    }

    It 'resolves the same branch from the whole name and from its kind and name' {
        $null=Invoke-QuietProperty -Name 'work-branch-forms' -Seed $seed -Count 80 -Generator {param($random)
            @{Kind=(Get-QuietRandomItem $random (Get-QuietWorkBranchKinds));Name=(& $newName $random)}
        } -Property {param($case)
            $whole=Resolve-QuietWorkBranchName -Branch ($case.Kind+'/'+$case.Name)
            $split=Resolve-QuietWorkBranchName -Kind $case.Kind -Name $case.Name
            $whole.Branch -ceq $split.Branch -and $whole.Kind -ceq $case.Kind -and $whole.Name -ceq $case.Name
        }
    }

    It 'only fails with a typed error and only accepts names that satisfy the rules' {
        $null=Invoke-QuietProperty -Name 'work-branch-fuzz' -Seed $seed -Count 300 -Generator {param($random)
            (Get-QuietRandomItem $random @('fix','feature','chore','release','hotfix','','Feature'))+(Get-QuietRandomItem $random @('/','','//'))+(New-QuietRandomString $random -Alphabet ('ab9.-_/ ~^:?*[\@{}'+[char]0xE9) -MinLength 0 -MaxLength 14)
        } -Property {param($case)
            try{$resolved=Resolve-QuietWorkBranchName -Branch $case}catch{
                if($_.Exception.Message -cnotmatch '\AWorkBranch(Kind|Name)Invalid: '){throw ('untyped: '+$_.Exception.Message)}
                return $true
            }
            $resolved.Branch -ceq $case -and (Get-QuietWorkBranchKinds) -ccontains $resolved.Kind -and
                @($resolved.Name.Split('/')|Where-Object {$_ -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?\z' -or $_.Contains('..')}).Count -eq 0
        }
    }
}

Describe 'Assert-QuietWorkBranchBase' {
    It 'accepts the delivery branch <Base>' -ForEach @(@{Base='develop'},@{Base='main'},@{Base='release-train'},@{Base='team/develop'},@{Base='fix'}) {
        {Assert-QuietWorkBranchBase -BaseBranch $Base}|Should -Not -Throw
    }

    # A transient release/* branch of Invoke-QuietRelease.ps1 is no delivery branch either.
    It 'rejects the work or release branch <Base> as a base' -ForEach @(@{Base='feature/x'},@{Base='fix/suite-image'},@{Base='chore/a/b'},@{Base='release/1.0.0'}) {
        {Assert-QuietWorkBranchBase -BaseBranch $Base}|Should -Throw -ExpectedMessage ('WorkBranchBaseIsWorkBranch: '+$Base+'; start from the delivery branch, for example develop')
    }

    It 'rejects the malformed base <Base>' -ForEach @(@{Base=''},@{Base='-develop'},@{Base='develop/'},@{Base='a..b'},@{Base='a//b'},@{Base='dev elop'},@{Base='dev~1'}) {
        {Assert-QuietWorkBranchBase -BaseBranch $Base}|Should -Throw -ExpectedMessage 'WorkBranchBaseInvalid*'
    }
}

Describe 'Get-QuietWorkBranchStatusProblems' {
    BeforeAll {
        $clean={@{Branch='develop';Detached=$false;Unborn=$false;Counts=@{Conflicted=0L};Operations=@();Entries=@()}}
    }

    It 'finds nothing on a checkout that is on a branch, even with pending changes' {
        $status=& $clean
        $status.Entries=@([pscustomobject]@{Path='a.txt';Status='.M'})
        @(Get-QuietWorkBranchStatusProblems -Status $status).Count|Should -Be 0
    }

    It 'reports <Expected>' -ForEach @(
        @{Key='Detached';Value=$true;Expected='Detached'}
        @{Key='Unborn';Value=$true;Expected='Unborn'}
        @{Key='Counts';Value=@{Conflicted=2L};Expected='Conflicted'}
        # The Git companion's shape: one hashtable per operation, named by its Kind key.
        @{Key='Operations';Value=@(@{Kind='Merge';Head=('a'*40);Conflicts=1L});Expected='Operation:Merge'}
        @{Key='Operations';Value=@([ordered]@{Kind='Rebase';Step=1});Expected='Operation:Rebase'}
        @{Key='Operations';Value=@([pscustomobject]@{Kind='CherryPick'});Expected='Operation:CherryPick'}
        @{Key='Operations';Value=@('bisect');Expected='Operation:bisect'}
        @{Key='Operations';Value=@([pscustomobject]@{Name='Revert'});Expected='Operation:@{Name=Revert}'}
    ) {
        $status=& $clean
        $status[$Key]=$Value
        Get-QuietWorkBranchStatusProblems -Status $status|Should -BeExactly @($Expected)
    }

    It 'reports a missing status as Unavailable' {
        Get-QuietWorkBranchStatusProblems -Status $null|Should -BeExactly @('Unavailable')
    }

    It 'reports every problem at once, in a stable order' {
        $status=& $clean
        $status.Detached=$true;$status.Unborn=$true;$status.Counts=@{Conflicted=1L};$status.Operations=@(@{Kind='Merge'},$null,@{Kind='Bisect'})
        Get-QuietWorkBranchStatusProblems -Status $status|Should -BeExactly @('Detached','Unborn','Conflicted','Operation:Merge','Operation:Bisect')
    }

    It 'ignores a status without counts' {
        $status=& $clean
        $status.Remove('Counts')
        @(Get-QuietWorkBranchStatusProblems -Status $status).Count|Should -Be 0
    }
}

Describe 'ConvertFrom-QuietWorkBranchLsRemote' {
    It 'returns an empty map for empty output' -ForEach @(@{Text=''},@{Text=$null},@{Text="`n`r`n"}) {
        (ConvertFrom-QuietWorkBranchLsRemote -Text $Text).Count|Should -Be 0
    }

    It 'maps each ref to its id, with LF or CRLF line ends and SHA-1 or SHA-256 ids' {
        $long='b'*64
        $heads=ConvertFrom-QuietWorkBranchLsRemote -Text ("$('a'*40)`trefs/heads/develop`r`n$long`trefs/heads/feature/x`n")
        $heads.Count|Should -Be 2
        $heads['refs/heads/develop']|Should -BeExactly ('a'*40)
        $heads['refs/heads/feature/x']|Should -BeExactly $long
        $heads.ContainsKey('refs/heads/Develop')|Should -BeFalse -Because 'ref names are compared ordinally'
    }

    It 'keeps a ref listed twice with the same id' {
        (ConvertFrom-QuietWorkBranchLsRemote -Text ("$('c'*40)`trefs/heads/develop`n$('c'*40)`trefs/heads/develop")).Count|Should -Be 1
    }

    It 'rejects the line <Line>' -ForEach @(
        @{Line=('a'*40)+' refs/heads/develop'},@{Line=('A'*40)+"`trefs/heads/develop"},@{Line=('a'*39)+"`trefs/heads/develop"},
        @{Line=('a'*41)+"`trefs/heads/develop"},@{Line=('a'*40)+"`tdevelop"},@{Line=('a'*40)+"`trefs/heads/de velop"},@{Line='fatal: unable to access'},
        # Only the CR of a CRLF line end is dropped; other trailing whitespace is malformed output.
        @{Line=('a'*40)+"`trefs/heads/develop "},@{Line=('a'*40)+"`trefs/heads/develop`t"}
    ) {
        {ConvertFrom-QuietWorkBranchLsRemote -Text $Line}|Should -Throw -ExpectedMessage 'WorkBranchRemoteOutputInvalid*'
    }

    It 'rejects a ref listed twice with different ids' {
        {ConvertFrom-QuietWorkBranchLsRemote -Text ("$('a'*40)`trefs/heads/develop`n$('b'*40)`trefs/heads/develop")}|Should -Throw -ExpectedMessage 'WorkBranchRemoteOutputInvalid: refs/heads/develop listed twice'
    }

    It 'round-trips any generated listing' {
        $null=Invoke-QuietProperty -Name 'ls-remote-roundtrip' -Seed $seed -Count 50 -Generator {param($random)
            $map=[ordered]@{}
            foreach($index in 0..($random.Next(0,6))){$map['refs/heads/'+(& $newName $random)]=& $sha $random}
            $map
        } -Property {param($case)
            $text=(@($case.GetEnumerator()|ForEach-Object {$_.Value+"`t"+$_.Key}) -join "`n")
            $heads=ConvertFrom-QuietWorkBranchLsRemote -Text $text
            $heads.Count -eq $case.Count -and @($case.Keys|Where-Object {$heads[$_] -cne $case[$_]}).Count -eq 0
        }
    }
}

Describe 'Compare-QuietWorkBranchShelf' {
    BeforeAll {
        $newEntries={param([Random]$Random)
            $paths=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
            foreach($index in 0..($Random.Next(0,8))){[void]$paths.Add((& $newName $Random)+'.txt')}
            @(foreach($path in $paths){[pscustomobject]@{Path=$path;Status=(Get-QuietRandomItem $Random @('.M','M.','A.','??','.D'));Hash=$(if($Random.Next(5)){& $sha $Random}else{$null})}})
        }
    }

    It 'finds nothing when every path comes back unchanged, in any order' {
        $null=Invoke-QuietProperty -Name 'shelf-identity' -Seed $seed -Count 60 -Generator {param($random)
            $before=& $newEntries $random
            @{Before=$before;After=[object[]](Get-QuietShuffle $random $before)}
        } -Property {param($case)@(Compare-QuietWorkBranchShelf -Before $case.Before -After $case.After).Count -eq 0}
    }

    It 'reports exactly the path that changed' {
        $null=Invoke-QuietProperty -Name 'shelf-change' -Seed $seed -Count 80 -Generator {param($random)
            $before=@(& $newEntries $random)
            if(!$before.Count){$before=@([pscustomobject]@{Path='only.txt';Status='.M';Hash=(& $sha $random)})}
            $victim=Get-QuietRandomItem $random $before
            $mode=Get-QuietRandomItem $random @('Status','Hash','Missing','Duplicate')
            $after=[Collections.Generic.List[object]]::new()
            foreach($entry in $before){
                if($entry.Path -cne $victim.Path){$after.Add($entry);continue}
                switch($mode){
                    'Status'{$after.Add([pscustomobject]@{Path=$entry.Path;Status=$entry.Status+'X';Hash=$entry.Hash})}
                    'Hash'{$after.Add([pscustomobject]@{Path=$entry.Path;Status=$entry.Status;Hash='0'*64})}
                    'Missing'{}
                    'Duplicate'{$after.Add($entry);$after.Add($entry)}
                }
            }
            @{Before=$before;After=@($after);Expected=$victim.Path}
        } -Property {param($case)
            $changed=@(Compare-QuietWorkBranchShelf -Before $case.Before -After $case.After)
            $changed.Count -eq 1 -and $changed[0] -ceq $case.Expected
        }
    }

    It 'ignores paths that only appear after the restore and sorts what it reports ordinally' {
        $before=@([pscustomobject]@{Path='b.txt';Status='.M';Hash='1'},[pscustomobject]@{Path='B.txt';Status='.M';Hash='1'},[pscustomobject]@{Path='a.txt';Status='??';Hash=$null})
        $after=@([pscustomobject]@{Path='new.txt';Status='??';Hash='2'},[pscustomobject]@{Path='a.txt';Status='??';Hash=$null})
        Compare-QuietWorkBranchShelf -Before $before -After $after|Should -BeExactly @('B.txt','b.txt')
    }

    It 'treats a path whose case differs as another path' {
        $entry=[pscustomobject]@{Path='Readme.md';Status='.M';Hash='1'}
        Compare-QuietWorkBranchShelf -Before @($entry) -After @([pscustomobject]@{Path='README.md';Status='.M';Hash='1'})|Should -BeExactly @('Readme.md')
    }

    It 'finds nothing for an empty shelf' {
        @(Compare-QuietWorkBranchShelf -Before @() -After @([pscustomobject]@{Path='x';Status='??';Hash='1'})).Count|Should -Be 0
    }
}
