#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name GitHubActionReferences
    $seed=Get-QuietTestSeed
    $sha='0123456789abcdef0123456789abcdef01234567'
    $parse={param([string]$Line)@(ConvertFrom-QuietGitHubActionUses -Text $Line -Path 'w.yml')}
    # A random valid remote reference line: indentation, optional list dash, optional quote, sub path, ref and comment.
    $newLine={param([Random]$Random)
        $name='abcdefghijklmnopqrstuvwxyz0123456789'
        $owner=New-QuietRandomString $Random -Alphabet $name -MinLength 1 -MaxLength 10
        $repository=New-QuietRandomString $Random -Alphabet ($name+'._-') -MinLength 1 -MaxLength 12
        if($repository -cin @('.','..')){$repository='r'+$repository}
        $sub=if($Random.Next(3) -eq 0){'/'+(New-QuietRandomString $Random -Alphabet $name -MinLength 1 -MaxLength 8)}else{''}
        $ref=switch($Random.Next(3)){0{(New-QuietRandomSha256 $Random).ToLowerInvariant().Substring(0,40)}1{'v'+$Random.Next(0,20)+'.'+$Random.Next(0,9)}default{'main'}}
        $quote=Get-QuietRandomItem $Random @('','"',"'")
        $comment=if($Random.Next(2)){'v'+$Random.Next(1,9)+(Get-QuietRandomItem $Random @('',', reviewed','.2.1'))}else{$null}
        $prefix=(' '*$Random.Next(0,12))+(Get-QuietRandomItem $Random @('','- '))+'uses:'+(' '*$Random.Next(1,3))
        $line=$prefix+$quote+$owner+'/'+$repository+$sub+'@'+$ref+$quote+$(if($null -ne $comment){' # '+$comment}else{''})
        [pscustomobject]@{Line=$line;Action=$owner+'/'+$repository;SubPath=$(if($sub){$sub.Substring(1)}else{$null});Ref=$ref;Comment=$comment}
    }
}

Describe 'Get-QuietGitHubActionRefKind' {
    It 'classifies <Ref> as <Kind>' -ForEach @(
        @{Ref='0123456789abcdef0123456789abcdef01234567';Kind='Sha'}
        @{Ref='0123456789ABCDEF0123456789ABCDEF01234567';Kind='Other'}
        @{Ref='0123456789abcdef0123456789abcdef0123456';Kind='Other'}
        @{Ref='0123456789abcdef0123456789abcdef012345678';Kind='Other'}
        @{Ref='v4';Kind='Version'}
        @{Ref='v4.3';Kind='Version'}
        @{Ref='v4.3.0';Kind='Version'}
        @{Ref='v4.3.0.1';Kind='Other'}
        @{Ref='4.3.0';Kind='Other'}
        @{Ref='v4-beta';Kind='Other'}
        @{Ref='main';Kind='Other'}
        @{Ref='';Kind='Other'}
    ) {
        Get-QuietGitHubActionRefKind -Ref $Ref|Should -BeExactly $Kind
    }
}

Describe 'ConvertFrom-QuietGitHubActionUses' {
    It 'parses a commit pin with its comment, prefix and sub path' {
        $reference=(& $parse ('      - uses: actions/cache/restore@'+$sha+' # v4.3.0'))[0]
        $reference.Kind|Should -BeExactly 'Remote'
        $reference.Action|Should -BeExactly 'actions/cache'
        $reference.Owner|Should -BeExactly 'actions'
        $reference.Repository|Should -BeExactly 'cache'
        $reference.SubPath|Should -BeExactly 'restore'
        $reference.Ref|Should -BeExactly $sha
        $reference.RefKind|Should -BeExactly 'Sha'
        $reference.Comment|Should -BeExactly 'v4.3.0'
        $reference.Prefix|Should -BeExactly '      - uses: '
        $reference.Quote|Should -BeExactly ''
        $reference.LineNumber|Should -Be 1
        $reference.Path|Should -BeExactly 'w.yml'
    }

    It 'reads <Line> as <Kind>' -ForEach @(
        @{Line='      - uses: ./.github/actions/cache-resources';Kind='Local'}
        @{Line='    uses: ./.github/workflows/ci.yml';Kind='Local'}
        @{Line='  - uses: ../shared/action';Kind='Local'}
        @{Line='  - uses: docker://alpine:3.20';Kind='Docker'}
        @{Line='    uses: octo-org/repo/.github/workflows/ci.yml@v2';Kind='Remote'}
    ) {
        (& $parse $Line)[0].Kind|Should -BeExactly $Kind
    }

    It 'leaves no comment when there is none, and an empty one for a bare #' {
        (& $parse 'uses: a/b@v1')[0].Comment|Should -BeNullOrEmpty
        $null -eq (& $parse 'uses: a/b@v1')[0].Comment|Should -BeTrue
        (& $parse 'uses: a/b@v1 #')[0].Comment|Should -BeExactly ''
    }

    It 'keeps the quote of <Line>' -ForEach @(
        @{Line='- uses: "a/b@v1"';Quote='"'}
        @{Line="- uses: 'a/b@v1' # v1";Quote="'"}
    ) {
        (& $parse $Line)[0].Quote|Should -BeExactly $Quote
    }

    It 'ignores lines that are not a uses: key: <Line>' -ForEach @(
        @{Line='      - name: uses: a/b@v1'}
        @{Line='      # uses: a/b@v1'}
        @{Line='      run: echo uses: a/b@v1'}
        @{Line='      uses:'}
        @{Line='      uses: a/b@v1 trailing'}
        @{Line='      uses: "a/b@v1'}
        @{Line='      reuses: a/b@v1'}
    ) {
        @(& $parse $Line).Count|Should -Be 0
    }

    It 'rejects the malformed remote reference <Line>' -ForEach @(
        @{Line='uses: actions/checkout'}
        @{Line='uses: actions@v1'}
        @{Line='uses: actions/checkout@'}
        @{Line='uses: actions/checkout@v1@v2'}
        @{Line='uses: -actions/checkout@v1'}
        @{Line='uses: actions/../checkout@v1'}
        @{Line='uses: actions/checkout/@v1'}
        @{Line='uses: actions/checkout@v1;rm'}
    ) {
        {& $parse $Line}|Should -Throw -ExpectedMessage 'GitHubActionReferenceInvalid: w.yml:1*'
    }

    It 'numbers lines across LF and CRLF endings and strips the CR from Line' {
        $references=@(ConvertFrom-QuietGitHubActionUses -Text ("on: push`r`njobs:`n  a:`r`n    steps:`r`n      - uses: a/b@v1`r`n      - uses: c/d@v2`n") -Path 'x.yml')
        $references.LineNumber|Should -Be @(5,6)
        $references[0].Line|Should -BeExactly '      - uses: a/b@v1'
        $references[0].Ref|Should -BeExactly 'v1'
    }

    It 'parses every generated line to its parts, and renders it back unchanged (property)' {
        Invoke-QuietProperty -Name 'uses round trip' -Seed $seed -Count 300 -Generator $newLine -Property {param($case)
            $reference=(& $parse $case.Line)[0]
            $reference.Action|Should -BeExactly $case.Action
            $reference.SubPath|Should -BeExactly $case.SubPath
            $reference.Ref|Should -BeExactly $case.Ref
            $reference.Comment|Should -BeExactly $case.Comment
            Format-QuietGitHubActionUses -Reference $reference -Ref $reference.Ref -Comment $reference.Comment|Should -BeExactly $case.Line
        }|Should -Be 300
    }

    It 'fails only with its typed error on hostile lines (fuzz)' {
        $random=New-QuietRandom $seed
        $pieces=@('uses:','- ','  ','"',"'",'#',' # v1','@','@v1','/','a','actions/checkout','./x','docker://','..','`t',[string][char]0,[string][char]0xE9,'$(x)',';','|','*')
        for($index=0;$index -lt 500;$index++){
            $text=-join @(foreach($part in 1..($random.Next(1,10))){Get-QuietRandomItem $random $pieces})
            try{$null=ConvertFrom-QuietGitHubActionUses -Text $text -Path 'f.yml'}catch{$_.Exception.Message|Should -BeLike 'GitHubActionReferenceInvalid:*' -Because $text}
        }
    }
}

Describe 'Format-QuietGitHubActionUses' {
    It 'renders a new ref and comment with the original prefix and quote' {
        $reference=(& $parse '        - uses: "actions/cache/save@v4" # old')[0]
        Format-QuietGitHubActionUses -Reference $reference -Ref $sha -Comment 'v6.1.0'|Should -BeExactly ('        - uses: "actions/cache/save@'+$sha+'" # v6.1.0')
    }

    It 'drops the comment when it is <Name>' -ForEach @(@{Name='null';Comment=$null},@{Name='empty';Comment=''},@{Name='blank';Comment='  '}) {
        $reference=(& $parse '- uses: a/b@v1 # v1')[0]
        Format-QuietGitHubActionUses -Reference $reference -Ref 'v2' -Comment $Comment|Should -BeExactly '- uses: a/b@v2'
    }

    It 'trims the comment' {
        Format-QuietGitHubActionUses -Reference (& $parse 'uses: a/b@v1')[0] -Ref 'v2' -Comment '  v2  '|Should -BeExactly 'uses: a/b@v2 # v2'
    }

    It 'refuses a <Kind> reference' -ForEach @(@{Kind='Local';Line='uses: ./x'},@{Kind='Docker';Line='uses: docker://x'}) {
        {Format-QuietGitHubActionUses -Reference (& $parse $Line)[0] -Ref 'v1' -Comment ''}|Should -Throw -ExpectedMessage 'GitHubActionReferenceInvalid*'
    }

    It 'refuses a ref or comment that would break the line: <Name>' -ForEach @(
        @{Name='ref with newline';Ref="v1`nrun: x";Comment=''}
        @{Name='ref with space';Ref='v1 x';Comment=''}
        @{Name='comment with LF';Ref='v1';Comment="a`nb"}
        @{Name='comment with CR';Ref='v1';Comment="a`rb"}
        @{Name='comment starting with LF';Ref='v1';Comment="`nb"}
    ) {
        {Format-QuietGitHubActionUses -Reference (& $parse 'uses: a/b@v1')[0] -Ref $Ref -Comment $Comment}|Should -Throw -ExpectedMessage 'GitHubActionReferenceInvalid: ref or comment cannot be rendered on one line'
    }

    It 'refuses an empty ref' {
        {Format-QuietGitHubActionUses -Reference (& $parse 'uses: a/b@v1')[0] -Ref '' -Comment ''}|Should -Throw
    }
}

Describe 'Get-QuietGitHubActionRewrittenText' {
    It 'replaces the given lines only, keeping each line ending' {
        $text="a`r`nuses: x/y@v1`r`nb`nuses: x/y@v1`nc"
        $changes=@([pscustomobject]@{LineNumber=2;Line='uses: x/y@v1';NewLine='uses: x/y@v2'},[pscustomobject]@{LineNumber=4;Line='uses: x/y@v1';NewLine='uses: x/y@v3'})
        Get-QuietGitHubActionRewrittenText -Text $text -Changes $changes|Should -BeExactly "a`r`nuses: x/y@v2`r`nb`nuses: x/y@v3`nc"
    }

    It 'returns the text unchanged without changes, including a final newline' {
        Get-QuietGitHubActionRewrittenText -Text "a`nb`n" -Changes @()|Should -BeExactly "a`nb`n"
        Get-QuietGitHubActionRewrittenText -Text '' -Changes @()|Should -BeExactly ''
    }

    It 'refuses a stale or misplaced change: <Name>' -ForEach @(
        @{Name='other text';Number=1;Line='uses: x/y@v0';Message='GitHubActionSourceChanged: line 1 no longer holds the parsed reference'}
        @{Name='line 0';Number=0;Line='a';Message='GitHubActionSourceChanged: line 0 is outside the file'}
        @{Name='past the end';Number=4;Line='a';Message='GitHubActionSourceChanged: line 4 is outside the file'}
    ) {
        {Get-QuietGitHubActionRewrittenText -Text "uses: x/y@v1`nb`nc" -Changes @([pscustomobject]@{LineNumber=$Number;Line=$Line;NewLine='z'})}|Should -Throw -ExpectedMessage $Message
    }

    It 'refuses two changes of one line' {
        $change=[pscustomobject]@{LineNumber=1;Line='a';NewLine='b'}
        {Get-QuietGitHubActionRewrittenText -Text 'a' -Changes @($change,$change)}|Should -Throw -ExpectedMessage 'GitHubActionChangeDuplicated: line 1'
    }

    It 'refuses a replacement spanning several lines: <Name>' -ForEach @(@{Name='inner LF';NewLine="b`nc"},@{Name='leading LF';NewLine="`nc"},@{Name='leading CR';NewLine="`rc"}) {
        {Get-QuietGitHubActionRewrittenText -Text 'a' -Changes @([pscustomobject]@{LineNumber=1;Line='a';NewLine=$NewLine})}|Should -Throw -ExpectedMessage 'GitHubActionReferenceInvalid: line 1 replacement spans several lines'
    }

    It 'changes exactly the selected lines of a generated file (property)' {
        Invoke-QuietProperty -Name 'rewrite locality' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            $lines=@(foreach($index in 1..($Random.Next(1,15))){(New-QuietRandomString $Random -MinLength 0 -MaxLength 10)+(Get-QuietRandomItem $Random @('',"`r"))})
            $selected=Get-QuietRandomSubset $Random @(1..$lines.Count)
            [pscustomobject]@{Lines=$lines;Selected=$selected;Final=(Get-QuietRandomItem $Random @('',"`n"))}
        } -Property {param($case)
            $text=($case.Lines -join "`n")+$case.Final
            $all=$text.Split("`n")
            $changes=@(foreach($number in $case.Selected){[pscustomobject]@{LineNumber=$number;Line=$all[$number-1].TrimEnd("`r");NewLine='new'+$number}})
            $result=(Get-QuietGitHubActionRewrittenText -Text $text -Changes $changes).Split("`n")
            $result.Count|Should -Be $all.Count
            for($index=0;$index -lt $all.Count;$index++){
                $ending=if($all[$index].EndsWith("`r")){"`r"}else{''}
                $expected=if($case.Selected -contains ($index+1)){'new'+($index+1)+$ending}else{$all[$index]}
                $result[$index]|Should -BeExactly $expected
            }
        }|Should -Be 200
    }
}

Describe 'Get-QuietGitHubActionFiles' {
    It 'lists workflows and composite actions in ordinal order, ignoring other files' {
        $root=[IO.Path]::Combine($TestDrive,'files')
        foreach($path in @('.github/workflows/b.yml','.github/workflows/A.yaml','.github/workflows/notes.md','.github/workflows/nested/c.yml','.github/actions/z/action.yml','.github/actions/a/b/action.yaml','.github/actions/a/README.md','.github/actions/a/other.yml','.github/dependabot.yml','.github/other/action.yml','action.yml')){
            $null=New-QuietTestFile ([IO.Path]::Combine($root,$path)) 'x'
        }
        $files=@(Get-QuietGitHubActionFiles -WorkspaceRoot $root)
        $files.RelativePath|Should -BeExactly @('.github/actions/a/b/action.yaml','.github/actions/z/action.yml','.github/workflows/A.yaml','.github/workflows/b.yml')
        $files[0].FullPath|Should -BeExactly ([IO.Path]::Combine($root,'.github','actions','a','b','action.yaml'))
    }

    It 'returns nothing for a checkout without .github' {
        @(Get-QuietGitHubActionFiles -WorkspaceRoot ([IO.Path]::Combine($TestDrive,'empty'))).Count|Should -Be 0
    }
}
