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
