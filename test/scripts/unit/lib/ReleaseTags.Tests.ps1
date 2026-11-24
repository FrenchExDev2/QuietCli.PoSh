#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name ReleaseTags
    $manifestPath = [IO.Path]::Combine($TestDrive,'module.psd1')
}

Describe 'Get-QuietReleaseManifestText' {
    It 'changes only the two selected value spans' {
        $text = @'
@{
    ModuleVersion = "1.2.3" # version précédente
    RequiredModules = @(@{ ModuleName='Other'; ModuleVersion='1.2.3' })
    PrivateData = @{
        PSData = @{ Prerelease = "beta2"; ReleaseNotes = 'beta2' }
    }
}
'@
        $expected = $text.Replace('"1.2.3"',"'2.0.0'").Replace('"beta2"',"'preview3'")
        Get-QuietReleaseManifestText -Text $text -Version 2.0.0-preview3 | Should -BeExactly $expected
    }

    It 'adds a prerelease within <Layout> without corrupting the literal data file' -ForEach @(
        @{ Layout = 'the root'; Metadata = '' }
        @{ Layout = 'an empty PrivateData map'; Metadata = 'PrivateData=@{}' }
        @{ Layout = 'an empty PSData map'; Metadata = 'PrivateData=@{ PSData=@{} }' }
        @{ Layout = 'PSData with a trailing comment'; Metadata = "PrivateData=@{ PSData=@{ Tags=@('QuietCli') # keep me`n } }" }
    ) {
        $text = "@{ ModuleVersion='1.2.3'; $Metadata }"
        $updated = Get-QuietReleaseManifestText -Text $text -Version 1.2.3-preview3
        $null = New-QuietTestFile -Path $manifestPath -Text $updated
        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        $data.ModuleVersion | Should -BeExactly '1.2.3'
        $data.PrivateData.PSData.Prerelease | Should -BeExactly 'preview3'
        if ($Layout -like '*comment*') {
            $updated | Should -Match '# keep me'
            $data.PrivateData.PSData.Tags | Should -Be @('QuietCli')
        }
    }

    It 'clears a prerelease for a stable version and preserves other PSData' {
        $text = "@{ ModuleVersion='1.2.3'; PrivateData=@{ PSData=@{ Prerelease='preview3'; Tags=@('QuietCli') } } }"
        $expected = $text.Replace("'1.2.3'","'1.2.4'").Replace("'preview3'","''")
        Get-QuietReleaseManifestText -Text $text -Version 1.2.4 | Should -BeExactly $expected
    }

    It 'keeps an absent prerelease absent when selecting a stable version' -ForEach @(
        @{ Metadata = '' }
        @{ Metadata = 'PrivateData=@{}' }
        @{ Metadata = 'PrivateData=@{ PSData=@{} }' }
    ) {
        $text = "@{ ModuleVersion='1.2.3'; $Metadata }"
        Get-QuietReleaseManifestText -Text $text -Version 1.2.4 | Should -BeExactly ($text.Replace('1.2.3','1.2.4'))
    }

    It 'keeps formatting when the version already matches and normalizes repository line endings' {
        $text = "@{`r`nModuleVersion=`"1.2.3`"; PrivateData=@{PSData=@{Prerelease=`"preview3`"}}`r}"
        $expected = $text.Replace("`r`n","`n").Replace("`r","`n")
        Get-QuietReleaseManifestText -Text $text -Version '1.2.3-preview3' | Should -BeExactly $expected
    }

    It 'rejects invalid manifest layout <Case>' -ForEach @(
        @{ Case = 'broken syntax'; Source = '@{'; ErrorCode = 'ReleaseManifestInvalid' }
        @{ Case = 'multiple statements'; Source = "@{ModuleVersion='1.2.3'}; 0"; ErrorCode = 'ReleaseManifestInvalid' }
        @{ Case = 'a pipeline'; Source = "@{ModuleVersion='1.2.3'} | Out-Null"; ErrorCode = 'ReleaseManifestInvalid' }
        @{ Case = 'control flow'; Source = 'if ($true) { @{} }'; ErrorCode = 'ReleaseManifestInvalid' }
        @{ Case = 'a scalar'; Source = '42'; ErrorCode = 'ReleaseManifestInvalid' }
        @{ Case = 'dynamic data'; Source = "@{ModuleVersion=(Get-Date)}"; ErrorCode = 'ReleaseManifestMustBeLiteral' }
        @{ Case = 'a missing version'; Source = '@{}'; ErrorCode = 'ReleaseManifestPublicationMetadataRequired' }
        @{ Case = 'scalar PrivateData'; Source = "@{ModuleVersion='1.2.3'; PrivateData='text'}"; ErrorCode = 'ReleaseManifestPublicationMetadataRequired' }
        @{ Case = 'scalar PSData'; Source = "@{ModuleVersion='1.2.3'; PrivateData=@{PSData='text'}}"; ErrorCode = 'ReleaseManifestPublicationMetadataRequired' }
    ) {
        { Get-QuietReleaseManifestText -Text $Source -Version 2.0.0-preview3 } | Should -Throw -ExpectedMessage $ErrorCode
    }

    It 'rejects invalid version <Version>' -ForEach @(
        @{ Version = '01.2.3' }
        @{ Version = '1.2' }
        @{ Version = '1.2.3.4' }
        @{ Version = '1.2.3-preview.3' }
        @{ Version = '1.2.3+build' }
        @{ Version = '1.2.2147483648' }
    ) {
        { Get-QuietReleaseManifestText -Text "@{ModuleVersion='1.2.3'}" -Version $Version } |
            Should -Throw -ExpectedMessage 'ReleaseVersionInvalid'
    }

    It 'rejects generated malformed version suffixes and trailing content' {
        $null = Invoke-QuietProperty -Name 'module-version-invalid-input' -Seed (Get-QuietTestSeed) -Count 90 -Generator { param($random)
            $version = "$($random.Next(100)).$($random.Next(100)).$($random.Next(100))"
            $separator = Get-QuietRandomItem $random @('-preview.','+build',' ',[string][char]10)
            $version + $separator + (New-QuietRandomString $random -Alphabet 'abc0123-_' -MinLength 1 -MaxLength 15)
        } -Property { param($case)
            try { $null = Get-QuietReleaseManifestText -Text "@{ModuleVersion='1.2.3'}" -Version $case }
            catch {
                if ($_.Exception.Message -ceq 'ReleaseVersionInvalid') { return $true }
                throw
            }
            return $false
        }
    }
}
