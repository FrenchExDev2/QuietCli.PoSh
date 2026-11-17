#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name RunToolCache
    $newPackage={param([string]$Name,[string]$Entrypoint)
        $stage=[IO.Path]::Combine($TestDrive,'stage-'+[guid]::NewGuid().ToString('N'));$null=New-QuietTestFile ([IO.Path]::Combine($stage,$Entrypoint)) '@{}'
        $archive=$stage+'.zip';[IO.Compression.ZipFile]::CreateFromDirectory($stage,$archive)
        $bytes=[IO.File]::ReadAllBytes($archive)
        [pscustomobject]@{Bytes=$bytes;Package=@{Name=$Name;Version='1.0.0';Url="https://example.invalid/$Name";SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));Entrypoint=$Entrypoint}}
    }
}

Describe 'Get-RunTestToolPackages' {
    It 'pins Pester 6.2.0 and PSScriptAnalyzer 1.25.0 by SHA-256 in catalogue order' {
        $packages=@(Get-RunTestToolPackages)
        $packages.Name|Should -Be @('Pester','PSScriptAnalyzer')
        $packages[0].Version|Should -BeExactly '6.2.0'
        $packages[1].Version|Should -BeExactly '1.25.0'
        foreach($package in $packages){$package.SHA256|Should -Match '^[0-9A-F]{64}$';$package.Url|Should -BeLike 'https://www.powershellgallery.com/api/v2/package/*'}
    }
    It 'selects <Tool> once' -ForEach @(@{Tool=@('pester');Names=@('Pester')};@{Tool=@('scriptanalyzer','pester');Names=@('Pester','PSScriptAnalyzer')};@{Tool=@('scriptanalyzer');Names=@('PSScriptAnalyzer')}) {
        @(Get-RunTestToolPackages -Tool $Tool).Name|Should -Be $Names
    }
    It 'rejects an unknown tool' {
        {Get-RunTestToolPackages -Tool 'nunit'}|Should -Throw
    }
}

Describe 'Get-RunProfilerPackages' {
    It 'pins both diagnostic packages by SHA-256 in catalogue order' {
        $packages=@(Get-RunProfilerPackages)
        $packages.Name|Should -Be @('Profiler','dotnet-trace')
        foreach($package in $packages){
            $package.SHA256|Should -Match '^[0-9A-F]{64}$'
            $package.Url|Should -Match ('^https://[^ ]+/'+[regex]::Escape($package.Version)+'(/|$|/dotnet-trace\.)')
            $package.Entrypoint|Should -Not -BeNullOrEmpty
        }
    }
    It 'selects <Module> once in catalogue order' -ForEach @(@{Module=@('profiler');Names=@('Profiler')};@{Module=@('dottrace');Names=@('dotnet-trace')};@{Module=@('dottrace','profiler');Names=@('Profiler','dotnet-trace')}) {
        @(Get-RunProfilerPackages -Module $Module).Name|Should -Be $Names
    }
    It 'rejects <Case>' -ForEach @(@{Case='an unknown module';Module=@('perfview')};@{Case='three modules';Module=@('profiler','dottrace','profiler')};@{Case='an empty list';Module=@()}) {
        {Get-RunProfilerPackages -Module $Module}|Should -Throw
    }
}

Describe 'Test-RunToolTransientDownloadError' {
    BeforeAll {
        $http={param([AllowNull()]$Code,[Exception]$Inner=$null) if($null -eq $Code){[Net.Http.HttpRequestException]::new('no status',$Inner)}else{[Net.Http.HttpRequestException]::new('status',$Inner,[Enum]::ToObject([Net.HttpStatusCode],[int]$Code))}}
    }
    It 'reads HTTP <Code> as transient: <Expected>' -ForEach @(
        @{Code=407;Expected=$false};@{Code=408;Expected=$true};@{Code=409;Expected=$false}
        @{Code=428;Expected=$false};@{Code=429;Expected=$true};@{Code=430;Expected=$false}
        @{Code=404;Expected=$false};@{Code=499;Expected=$false};@{Code=500;Expected=$true}
        @{Code=503;Expected=$true};@{Code=599;Expected=$true};@{Code=600;Expected=$false}
    ) {
        Test-RunToolTransientDownloadError -Exception (& $http $Code)|Should -Be $Expected
    }
    It 'reads <Case> as transient: <Expected>' -ForEach @(
        @{Case='a connection failure without a status';Expected=$true;Make={& $http $null}}
        @{Case='a timeout';Expected=$true;Make={[TimeoutException]::new('slow')}}
        @{Case='a cancelled request';Expected=$true;Make={[Threading.Tasks.TaskCanceledException]::new('cancelled')}}
        @{Case='a 503 wrapped by a .NET method call';Expected=$true;Make={[Management.Automation.MethodInvocationException]::new('Exception calling "GetResult"',(& $http 503))}}
        @{Case='a 404 wrapped by a .NET method call';Expected=$false;Make={[Management.Automation.MethodInvocationException]::new('Exception calling "GetResult"',(& $http 404))}}
        @{Case='a timeout wrapped twice';Expected=$true;Make={[InvalidOperationException]::new('outer',[AggregateException]::new([TimeoutException]::new('slow')))}}
        @{Case='a 404 whose inner exception is a timeout';Expected=$false;Make={& $http 404 ([TimeoutException]::new('slow'))}}
        @{Case='a timeout whose inner exception is a 404';Expected=$true;Make={[TimeoutException]::new('slow',(& $http 404))}}
        @{Case='an unrelated failure';Expected=$false;Make={[InvalidOperationException]::new('broken')}}
        @{Case='a script error';Expected=$false;Make={[Management.Automation.RuntimeException]::new('ProfilerDownloadDigestMismatch')}}
        @{Case='no exception';Expected=$false;Make={$null}}
    ) {
        Test-RunToolTransientDownloadError -Exception (& $Make)|Should -Be $Expected
    }
}

Describe 'Invoke-RunToolDownload' {
    BeforeAll {
        # Fails with the given exceptions in turn, then returns the bytes; records each URL it is called with.
        $newProvider={param([object[]]$Failures,[byte[]]$Bytes)
            $state=[pscustomobject]@{Urls=[Collections.Generic.List[string]]::new();Sleeps=[Collections.Generic.List[int]]::new()}
            $download={param($url) $state.Urls.Add($url);$index=$state.Urls.Count-1;if($index -lt $Failures.Count){throw $Failures[$index]};,$Bytes}.GetNewClosure()
            $sleep={param($ms) $state.Sleeps.Add($ms)}.GetNewClosure()
            [pscustomobject]@{State=$state;Download=$download;Sleep=$sleep}
        }
        $unavailable={[Net.Http.HttpRequestException]::new('Response status code does not indicate success: 503 (Service Unavailable).',$null,[Net.HttpStatusCode]::ServiceUnavailable)}
    }
    It 'returns the bytes as one array after a single call when the first attempt succeeds' {
        $provider=& $newProvider @() ([byte[]]@(7,8,9))
        $result=@(Invoke-RunToolDownload -Url 'https://example.invalid/a' -Download $provider.Download -Sleep $provider.Sleep -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count|Should -Be 1
        ,$result[0]|Should -BeOfType [byte[]]
        $result[0]|Should -Be @(7,8,9)
        @($provider.State.Urls)|Should -Be @('https://example.invalid/a')
        $provider.State.Sleeps.Count|Should -Be 0
        @($warnings).Count|Should -Be 0
    }
    It 'retries transient failures with a doubling delay and warns each time' {
        $provider=& $newProvider @((& $unavailable),[TimeoutException]::new('slow')) ([byte[]]@(1))
        $result=Invoke-RunToolDownload -Url 'https://example.invalid/b' -Download $provider.Download -Sleep $provider.Sleep -InitialDelayMilliseconds 100 -WarningVariable warnings -WarningAction SilentlyContinue
        $result|Should -Be @(1)
        @($provider.State.Urls)|Should -Be @('https://example.invalid/b','https://example.invalid/b','https://example.invalid/b')
        @($provider.State.Sleeps)|Should -Be @(100,200)
        @($warnings).Count|Should -Be 2
        "$($warnings[0])"|Should -BeExactly 'Download of https://example.invalid/b failed (attempt 1 of 5), retrying in 100 ms: Response status code does not indicate success: 503 (Service Unavailable).'
        "$($warnings[1])"|Should -BeExactly 'Download of https://example.invalid/b failed (attempt 2 of 5), retrying in 200 ms: slow'
    }
    It 'rethrows a failure that is not transient at once, unchanged' {
        $provider=& $newProvider @([Net.Http.HttpRequestException]::new('gone',$null,[Net.HttpStatusCode]::NotFound)) ([byte[]]@(1))
        $caught=$null
        try{Invoke-RunToolDownload -Url 'https://example.invalid/c' -Download $provider.Download -Sleep $provider.Sleep -WarningAction SilentlyContinue}catch{$caught=$_.Exception}
        $caught|Should -BeOfType [Net.Http.HttpRequestException]
        $caught.Message|Should -BeExactly 'gone'
        $provider.State.Urls.Count|Should -Be 1
        $provider.State.Sleeps.Count|Should -Be 0
    }
    It 'rethrows the last transient failure after <Attempts> attempts' -ForEach @(@{Attempts=1;Sleeps=@()};@{Attempts=3;Sleeps=@(10,20)}) {
        $provider=& $newProvider @((& $unavailable),(& $unavailable),(& $unavailable),(& $unavailable)) ([byte[]]@(1))
        {Invoke-RunToolDownload -Url 'https://example.invalid/d' -Download $provider.Download -Sleep $provider.Sleep -MaxAttempts $Attempts -InitialDelayMilliseconds 10 -WarningAction SilentlyContinue}|Should -Throw -ExceptionType ([Net.Http.HttpRequestException]) -ExpectedMessage '*503*'
        $provider.State.Urls.Count|Should -Be $Attempts
        @($provider.State.Sleeps)|Should -Be $Sleeps
    }
    It 'defaults to five attempts with delays of 2, 4, 8 and 16 seconds' {
        $provider=& $newProvider @(1..5|ForEach-Object{& $unavailable}) ([byte[]]@(1))
        {Invoke-RunToolDownload -Url 'https://example.invalid/e' -Download $provider.Download -Sleep $provider.Sleep -WarningAction SilentlyContinue}|Should -Throw -ExpectedMessage '*503*'
        $provider.State.Urls.Count|Should -Be 5
        @($provider.State.Sleeps)|Should -Be @(2000,4000,8000,16000)
    }
    It 'waits with Start-Sleep by default' {
        Mock Start-Sleep -ModuleName RunToolCache {}
        $provider=& $newProvider @((& $unavailable)) ([byte[]]@(5))
        Invoke-RunToolDownload -Url 'https://example.invalid/f' -Download $provider.Download -InitialDelayMilliseconds 60 -WarningAction SilentlyContinue|Should -Be @(5)
        Should -Invoke Start-Sleep -ModuleName RunToolCache -Times 1 -Exactly -ParameterFilter {$Milliseconds -eq 60}
    }
    It 'rejects <Case>' -ForEach @(
        @{Case='zero attempts';Arguments=@{MaxAttempts=0}};@{Case='eleven attempts';Arguments=@{MaxAttempts=11}}
        @{Case='a negative delay';Arguments=@{InitialDelayMilliseconds=-1}};@{Case='a delay over a minute';Arguments=@{InitialDelayMilliseconds=60001}}
        @{Case='an empty URL';Arguments=@{Url=''}}
    ) {
        $call=@{Url='https://example.invalid/g';Download={param($url),([byte[]]@(1))}}
        foreach($key in $Arguments.Keys){$call[$key]=$Arguments[$key]}
        {Invoke-RunToolDownload @call}|Should -Throw
    }
    It 'accepts the bounds <MaxAttempts> attempts and <Delay> ms' -ForEach @(@{MaxAttempts=1;Delay=0};@{MaxAttempts=10;Delay=60000}) {
        Invoke-RunToolDownload -Url 'https://example.invalid/h' -Download {param($url),([byte[]]@(3))} -MaxAttempts $MaxAttempts -InitialDelayMilliseconds $Delay|Should -Be @(3)
    }
}

Describe 'Initialize-RunToolCache download retries' {
    It 'caches a package whose first download hit a 503' {
        Mock Start-Sleep -ModuleName RunToolCache {}
        $one=& $newPackage 'Gamma' 'Gamma.psd1'
        $calls=[Collections.Generic.List[string]]::new()
        $provider={param($url) $calls.Add($url);if($calls.Count -eq 1){throw [Net.Http.HttpRequestException]::new('busy',$null,[Net.HttpStatusCode]::ServiceUnavailable)};,$one.Bytes}.GetNewClosure()
        $result=Initialize-RunToolCache -OutputDirectory ([IO.Path]::Combine($TestDrive,'retry')) -Packages @($one.Package) -DownloadBytes $provider -WarningAction SilentlyContinue
        [IO.File]::Exists($result.Paths['Gamma'])|Should -BeTrue
        $calls.Count|Should -Be 2
        Should -Invoke Start-Sleep -ModuleName RunToolCache -Times 1 -Exactly -ParameterFilter {$Milliseconds -eq 2000}
    }
}

Describe 'Initialize-RunToolCache generic paths' {
    It 'returns every package entrypoint in Paths and keeps the profiler fields' {
        $one=& $newPackage 'Alpha' 'Alpha.psd1';$two=& $newPackage 'Beta' 'tools/Beta.dll'
        $catalogue=@{'https://example.invalid/Alpha'=$one.Bytes;'https://example.invalid/Beta'=$two.Bytes}
        $result=Initialize-RunToolCache -OutputDirectory ([IO.Path]::Combine($TestDrive,'cache')) -Packages @($one.Package,$two.Package) -DownloadBytes {param($url),$catalogue[$url]}
        [IO.File]::Exists($result.Paths['Alpha'])|Should -BeTrue
        $result.Paths['Beta']|Should -BeLike '*Beta.dll'
        $result.ProfilerModulePath|Should -BeNullOrEmpty
        (Get-Content -LiteralPath $result.Receipt -Raw|ConvertFrom-Json).Paths.Alpha|Should -Be $result.Paths['Alpha']
    }
}

Describe 'Initialize-QuietTestTools' {
    It 'defaults to the ignored workspace cache directory' {
        Get-QuietTestToolDirectory -WorkspaceRoot $TestDrive|Should -Be ([IO.Path]::Combine([IO.Path]::GetFullPath($TestDrive),'.cache','test-tools'))
    }
    It 'fails offline on a cache miss without calling the provider' {
        {Initialize-QuietTestTools -WorkspaceRoot $TestDrive -Offline -DownloadBytes {throw 'ProviderMustNotRun'}}|Should -Throw -ExpectedMessage 'ProfilerOfflineCacheMiss'
    }
    It 'rejects a download whose digest differs from the pin' {
        {Initialize-QuietTestTools -WorkspaceRoot $TestDrive -Tool pester -DownloadBytes {param($url),([byte[]]@(1,2,3))}}|Should -Throw -ExpectedMessage 'ProfilerDownloadDigestMismatch'
    }
    It 'returns verified module manifests from the pinned archives' {
        $cache=Get-QuietTestToolDirectory -WorkspaceRoot (Get-QuietTestWorkspaceRoot)
        $archive=[IO.Path]::Combine($cache,'Pester','Pester.6.2.0.nupkg')
        if(![IO.File]::Exists($archive)){Set-ItResult -Skipped -Because 'the pinned Pester archive is not cached';return}
        $target=[IO.Path]::Combine($TestDrive,'pinned');[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($target,'Pester'))
        [IO.File]::Copy($archive,[IO.Path]::Combine($target,'Pester','Pester.6.2.0.nupkg'))
        $tools=Initialize-QuietTestTools -WorkspaceRoot $TestDrive -OutputDirectory $target -Tool pester -Offline
        $tools.PesterModulePath|Should -BeLike '*Pester.psd1'
        $tools.ScriptAnalyzerModulePath|Should -BeNullOrEmpty
        (Import-PowerShellDataFile -LiteralPath $tools.PesterModulePath).ModuleVersion|Should -BeExactly '6.2.0'
    }
}
