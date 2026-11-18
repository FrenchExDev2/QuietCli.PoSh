#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name GitHubActionReleases
    $seed=Get-QuietTestSeed
    $commit='3d3c42e5aac5ba805825da76410c181273ba90b1'
    $tagObject='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $savedTokens=@{GH=$env:GH_TOKEN;GITHUB=$env:GITHUB_TOKEN}
    # The API double: Responses maps a path to {Status, Content}; an unknown path answers 404.
    $script:Responses=@{}
    $respond={param([string]$Path,[int]$Status,[object]$Body)$script:Responses[$Path]=[pscustomobject]@{StatusCode=$Status;Content=$(if($null -ne $Body){$Body|ConvertTo-Json -Depth 8 -Compress}else{''})}}
}

AfterAll {
    $env:GH_TOKEN=$savedTokens.GH
    $env:GITHUB_TOKEN=$savedTokens.GITHUB
}

Describe 'Invoke-QuietGitHubActionApi' {
    BeforeEach {
        $env:GH_TOKEN=$null;$env:GITHUB_TOKEN=$null
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {[pscustomobject]@{StatusCode=200;Content='{"tag_name":"v1"}'}}
    }

    It 'sends a bounded anonymous GET to api.github.com and parses the JSON body' {
        $result=Invoke-QuietGitHubActionApi -Path '/repos/actions/checkout/releases/latest'
        $result.Status|Should -Be 200
        $result.Body.tag_name|Should -BeExactly 'v1'
        Should -Invoke -ModuleName GitHubActionReleases Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.github.com/repos/actions/checkout/releases/latest' -and $Method -eq 'Get' -and $SkipHttpErrorCheck -and $TimeoutSec -eq 30 -and !$Headers.ContainsKey('Authorization') -and $Headers['X-GitHub-Api-Version'] -eq '2022-11-28' -and $Headers.Accept -ceq 'application/vnd.github+json' -and $Headers['User-Agent'] -ceq 'QuietCli-GitHub-Action-Updates'
        }
    }

    It 'sends no Authorization header for blank tokens' {
        $env:GH_TOKEN=' ';$env:GITHUB_TOKEN=' '
        $null=Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'
        Should -Invoke -ModuleName GitHubActionReleases Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {!$Headers.ContainsKey('Authorization')}
    }

    It 'parses no body outside 2xx: HTTP <Status>' -ForEach @(@{Status=199},@{Status=300},@{Status=304}) {
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {[pscustomobject]@{StatusCode=$Status;Content='{"tag_name":"v1"}'}}
        $result=Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'
        $result.Status|Should -Be $Status
        $result.Body|Should -BeNullOrEmpty
    }

    It 'parses the body of HTTP 299' {
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {[pscustomobject]@{StatusCode=299;Content='{"tag_name":"v1"}'}}
        (Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest').Body.tag_name|Should -BeExactly 'v1'
    }

    It 'authenticates with <Variable>, GH_TOKEN first' -ForEach @(
        @{Variable='GH_TOKEN';GH='gh-secret';GitHub='other';Expected='Bearer gh-secret'}
        @{Variable='GITHUB_TOKEN';GH='';GitHub='github-secret';Expected='Bearer github-secret'}
    ) {
        $env:GH_TOKEN=$GH;$env:GITHUB_TOKEN=$GitHub
        $null=Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'
        Should -Invoke -ModuleName GitHubActionReleases Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$Headers.Authorization -ceq $Expected}
    }

    It 'returns an HTTP error as a status without a body' {
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {[pscustomobject]@{StatusCode=403;Content='{"message":"rate limited"}'}}
        $result=Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'
        $result.Status|Should -Be 403
        $result.Body|Should -BeNullOrEmpty
    }

    It 'turns a transport failure into GitHubActionApiUnavailable' {
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {throw 'No such host is known.'}
        {Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'}|Should -Throw -ExpectedMessage 'GitHubActionApiUnavailable: /repos/a/b/releases/latest: No such host is known.'
    }

    It 'rejects an invalid JSON body' {
        Mock -ModuleName GitHubActionReleases Invoke-WebRequest {[pscustomobject]@{StatusCode=200;Content='{not json'}}
        {Invoke-QuietGitHubActionApi -Path '/repos/a/b/releases/latest'}|Should -Throw -ExpectedMessage 'GitHubActionApiResponseInvalid*'
    }

    It 'refuses the path <Path> without sending anything' -ForEach @(
        @{Path='/user'},@{Path='repos/a/b'},@{Path='/repos/a/../../user'},@{Path='https://evil.example/repos/a'},@{Path='/repos/a/b?x=1'},@{Path='/repos/a b'}
    ) {
        {Invoke-QuietGitHubActionApi -Path $Path}|Should -Throw -ExpectedMessage 'GitHubActionApiPathInvalid*'
        Should -Invoke -ModuleName GitHubActionReleases Invoke-WebRequest -Times 0 -Exactly
    }
}

Describe 'Get-QuietGitHubActionLatestRelease' {
    BeforeEach {
        $script:Responses=@{}
        Mock -ModuleName GitHubActionReleases Invoke-QuietGitHubActionApi {
            $response=$script:Responses[$Path]
            if($null -eq $response){return [pscustomobject]@{Status=404;Body=$null}}
            [pscustomobject]@{Status=$response.StatusCode;Body=$(if($response.Content){$response.Content|ConvertFrom-Json}else{$null})}
        }
    }

    It 'peels a lightweight release tag to its commit' {
        & $respond '/repos/actions/checkout/releases/latest' 200 @{tag_name='v7.0.1'}
        & $respond '/repos/actions/checkout/git/ref/tags/v7.0.1' 200 @{object=@{type='commit';sha=$commit}}
        $release=Get-QuietGitHubActionLatestRelease -Action 'actions/checkout'
        $release.Status|Should -BeExactly 'Resolved'
        $release.Tag|Should -BeExactly 'v7.0.1'
        $release.Sha|Should -BeExactly $commit
        $release.Action|Should -BeExactly 'actions/checkout'
        $release.Source|Should -BeExactly 'GitHub'
    }

    It 'peels an annotated release tag through its tag object' {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha=$tagObject}}
        & $respond ('/repos/a/b/git/tags/'+$tagObject) 200 @{object=@{type='commit';sha=$commit}}
        (Get-QuietGitHubActionLatestRelease -Action 'a/b').Sha|Should -BeExactly $commit
    }

    It 'gives up on a tag chain longer than four objects' {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha=$tagObject}}
        & $respond ('/repos/a/b/git/tags/'+$tagObject) 200 @{object=@{type='tag';sha=$tagObject}}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b tag v2 does not peel to a commit'
    }

    It 'follows a chain of <Hops> tag objects: <Outcome>' -ForEach @(@{Hops=4;Outcome='resolved'},@{Hops=5;Outcome='refused'}) {
        $ids=@(1..$Hops|ForEach-Object {([string]$_)*40})
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha=$ids[0]}}
        for($i=0;$i -lt $Hops;$i++){
            $next=if($i+1 -lt $Hops){@{type='tag';sha=$ids[$i+1]}}else{@{type='commit';sha=$commit}}
            & $respond ('/repos/a/b/git/tags/'+$ids[$i]) 200 @{object=$next}
        }
        if($Outcome -ceq 'resolved'){(Get-QuietGitHubActionLatestRelease -Action 'a/b').Sha|Should -BeExactly $commit}
        else{{Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b tag v2 does not peel to a commit'}
    }

    It 'reports NoRelease for a repository without a release' {
        $release=Get-QuietGitHubActionLatestRelease -Action 'a/none'
        $release.Status|Should -BeExactly 'NoRelease'
        $release.Tag|Should -BeNullOrEmpty
        $release.Sha|Should -BeNullOrEmpty
        $release.Source|Should -BeExactly 'GitHub'
    }

    It 'fails on HTTP 500 for the <Step> even with a body' -ForEach @(
        @{Step='tag ref';Expected='GitHubActionReleaseUnknown: a/b tag v2 HTTP 500'}
        @{Step='tag object';Expected='GitHubActionReleaseUnknown: a/b tag object HTTP 500'}
    ) {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        if($Step -ceq 'tag ref'){& $respond '/repos/a/b/git/ref/tags/v2' 500 @{object=@{type='commit';sha=$commit}}}
        else{
            & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha=$tagObject}}
            & $respond ('/repos/a/b/git/tags/'+$tagObject) 500 @{object=@{type='commit';sha=$commit}}
        }
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage $Expected
    }

    It 'refuses an invalid tag object id before requesting it' {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha='zz'}}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b tag object id invalid'
    }

    It 'never reads HTTP <Status> on the latest release as no release' -ForEach @(@{Status=401},@{Status=403},@{Status=429},@{Status=500},@{Status=502}) {
        & $respond '/repos/a/b/releases/latest' $Status @{message='x'}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage ('GitHubActionReleaseUnknown: a/b latest release HTTP '+$Status)
    }

    It 'fails when the release tag ref is unreadable' {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b tag v2 HTTP 404'
    }

    It 'fails when a tag object is unreadable' {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=@{type='tag';sha=$tagObject}}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b tag object HTTP 404'
    }

    It 'rejects the peeled object <Name>' -ForEach @(
        @{Name='tree';Object=@{type='tree';sha='3d3c42e5aac5ba805825da76410c181273ba90b1'}}
        @{Name='short id';Object=@{type='commit';sha='3d3c42e'}}
        @{Name='uppercase id';Object=@{type='commit';sha='3D3C42E5AAC5BA805825DA76410C181273BA90B1'}}
        @{Name='tag with invalid id';Object=@{type='tag';sha='zz'}}
    ) {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name='v2'}
        & $respond '/repos/a/b/git/ref/tags/v2' 200 @{object=$Object}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b*'
    }

    It 'rejects the release tag <Tag>' -ForEach @(@{Tag=''},@{Tag='v1 2'},@{Tag="v1`n"},@{Tag='-v1'},@{Tag='v1/x'},@{Tag='v1#x'}) {
        & $respond '/repos/a/b/releases/latest' 200 @{tag_name=$Tag}
        {Get-QuietGitHubActionLatestRelease -Action 'a/b'}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b release tag invalid*'
    }

    It 'refuses the action name <Action>' -ForEach @(@{Action='a'},@{Action='a/b/c'},@{Action='../b'},@{Action='a/b@v1'}) {
        {Get-QuietGitHubActionLatestRelease -Action $Action}|Should -Throw
        Should -Invoke -ModuleName GitHubActionReleases Invoke-QuietGitHubActionApi -Times 0 -Exactly
    }
}

Describe 'Read-QuietGitHubActionReleaseCatalog' {
    It 'reads resolved and release-less entries' {
        $path=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'catalog.json')) ('{"actions/checkout":{"Tag":"v7.0.1","Sha":"'+$commit+'"},"a/none":null}')
        $catalog=Read-QuietGitHubActionReleaseCatalog -Path $path
        $catalog.Count|Should -Be 2
        $catalog['actions/checkout'].Status|Should -BeExactly 'Resolved'
        $catalog['actions/checkout'].Tag|Should -BeExactly 'v7.0.1'
        $catalog['actions/checkout'].Sha|Should -BeExactly $commit
        $catalog['actions/checkout'].Source|Should -BeExactly 'Catalog'
        $catalog['a/none'].Status|Should -BeExactly 'NoRelease'
        $catalog['a/none'].Source|Should -BeExactly 'Catalog'
        $catalog.ContainsKey('Actions/Checkout')|Should -BeFalse -Because 'keys are ordinal'
    }

    It 'rejects the catalog <Name>' -ForEach @(
        @{Name='not JSON';Json='{';Message='<path> is not JSON'}
        @{Name='an array';Json='[]';Message='<path> must be an object'}
        @{Name='a bad key';Json='{"checkout":null}';Message='key checkout'}
        @{Name='a missing Sha';Json='{"a/b":{"Tag":"v1"}}';Message='a/b needs Tag and Sha'}
        @{Name='a missing Tag';Json='{"a/b":{"Sha":"3d3c42e5aac5ba805825da76410c181273ba90b1"}}';Message='a/b needs Tag and Sha'}
        @{Name='a short Sha';Json='{"a/b":{"Tag":"v1","Sha":"3d3c42e"}}';Message='a/b sha 3d3c42e'}
        @{Name='a bad Tag';Json='{"a/b":{"Tag":"v1 x","Sha":"3d3c42e5aac5ba805825da76410c181273ba90b1"}}';Message='a/b tag v1 x'}
        @{Name='a scalar entry';Json='{"a/b":"v1"}';Message='a/b needs Tag and Sha'}
    ) {
        $path=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'bad.json')) $Json
        {Read-QuietGitHubActionReleaseCatalog -Path $path}|Should -Throw -ExpectedMessage ('GitHubActionCatalogInvalid: '+$Message.Replace('<path>',$path))
    }

    It 'rejects a catalog that is not UTF-8' {
        $path=[IO.Path]::Combine($TestDrive,'latin1.json')
        [IO.File]::WriteAllBytes($path,[byte[]]@(0x7B,0x22,0xE9,0x22,0x3A,0x6E,0x75,0x6C,0x6C,0x7D))
        {Read-QuietGitHubActionReleaseCatalog -Path $path}|Should -Throw -ExpectedMessage ('GitHubActionCatalogInvalid: '+$path+' is not UTF-8')
    }
}

Describe 'Resolve-QuietGitHubActionReleases' {
    BeforeEach {
        Mock -ModuleName GitHubActionReleases Get-QuietGitHubActionLatestRelease {[pscustomobject]@{Action=$Action;Status='Resolved';Tag='v1';Sha=$commit;Source='GitHub'}}
    }

    It 'resolves each distinct action once from GitHub' {
        $releases=Resolve-QuietGitHubActionReleases -Actions @('a/b','c/d','a/b')
        @($releases.Keys)|Should -BeExactly @('a/b','c/d')
        Should -Invoke -ModuleName GitHubActionReleases Get-QuietGitHubActionLatestRelease -Times 2 -Exactly
    }

    It 'uses the catalog instead of GitHub' {
        $catalog=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $catalog['a/b']=[pscustomobject]@{Action='a/b';Status='Resolved';Tag='v9';Sha=$commit;Source='Catalog'}
        (Resolve-QuietGitHubActionReleases -Actions @('a/b') -Catalog $catalog)['a/b'].Tag|Should -BeExactly 'v9'
        Should -Invoke -ModuleName GitHubActionReleases Get-QuietGitHubActionLatestRelease -Times 0 -Exactly
    }

    It 'fails for an action missing from the catalog' {
        $catalog=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        {Resolve-QuietGitHubActionReleases -Actions @('a/b') -Catalog $catalog}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown: a/b is not in the release catalog'
    }

    It 'returns an empty dictionary for no action' {
        (Resolve-QuietGitHubActionReleases -Actions @()).Count|Should -Be 0
    }

    It 'propagates an unknown release instead of skipping the action' {
        Mock -ModuleName GitHubActionReleases Get-QuietGitHubActionLatestRelease {throw 'GitHubActionReleaseUnknown: a/b latest release HTTP 403'}
        {Resolve-QuietGitHubActionReleases -Actions @('a/b')}|Should -Throw -ExpectedMessage 'GitHubActionReleaseUnknown*'
    }
}

Describe 'Assert-QuietGitHubActionTag' {
    It 'accepts the tag <Tag>' -ForEach @(@{Tag='v1'},@{Tag='v7.0.1'},@{Tag='1.2.3+build'},@{Tag='release-2024_01'}) {
        {Assert-QuietGitHubActionTag -Action 'a/b' -Tag $Tag}|Should -Not -Throw
    }

    It 'accepts only tags that a uses: ref can carry (fuzz)' {
        $random=New-QuietRandom $seed
        for($index=0;$index -lt 300;$index++){
            $tag=New-QuietRandomString $random -Alphabet ('av1.-_+/# @:'+[char]0xE9) -MinLength 0 -MaxLength 8
            $accepted=try{Assert-QuietGitHubActionTag -Action 'a/b' -Tag $tag;$true}catch{$_.Exception.Message|Should -BeLike 'GitHubActionReleaseUnknown: a/b release tag invalid*';$false}
            $accepted|Should -Be ($tag -cmatch '\A[A-Za-z0-9][A-Za-z0-9._+-]{0,127}\z') -Because $tag
        }
    }
}
