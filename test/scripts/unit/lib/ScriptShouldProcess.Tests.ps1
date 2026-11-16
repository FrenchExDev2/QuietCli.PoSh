#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptShouldProcess
    $write={param($relative,$text)New-QuietTestFile ([IO.Path]::Combine($TestDrive,'ws',$relative)) $text}
    $null=& $write 'build/script-shouldprocess.json' '{"SchemaVersion":1,"ReadOnlyExceptions":[],"LegacyPaths":[]}'
}

Describe 'Get-QuietScriptShouldProcess test containers' {
    It 'classifies a Pester file with only Pester blocks at top level as TestContainer' {
        $path=& $write 'a/Only.Tests.ps1' "#requires -Version 7.6`nBeforeAll { Remove-Item x }`nDescribe d { It i { } }`nAfterAll { }"
        Get-QuietScriptShouldProcess $path|Should -BeExactly 'TestContainer'
    }
    It 'does not classify <Case> as TestContainer' -ForEach @(
        @{Case='a top-level effect';Name='Effect.Tests.ps1';Text="Remove-Item x`nDescribe d { It i { } }"}
        @{Case='a param block';Name='Param.Tests.ps1';Text="param(`$x)`nDescribe d { It i { } }"}
        @{Case='a non-test file name';Name='Helper.ps1';Text='Describe d { It i { } }'}
        @{Case='a pipeline after Describe';Name='Pipe.Tests.ps1';Text='Describe d { It i { } } | Out-File x'}
    ) {
        Get-QuietScriptShouldProcess (& $write ('b/'+$Name) $Text)|Should -Not -Be 'TestContainer'
    }
}

Describe 'Test-QuietScriptShouldProcessPolicy test containers' {
    It 'accepts containers under test/scripts and counts them' {
        $null=& $write 'test/scripts/unit/x/Ok.Tests.ps1' 'Describe d { It i { } }'
        (Test-QuietScriptShouldProcessPolicy -WorkspaceRoot ([IO.Path]::Combine($TestDrive,'ws'))).TestContainers|Should -BeGreaterOrEqual 1
    }
    It 'still requires ShouldProcess for a container outside test/scripts' {
        $root=[IO.Path]::Combine($TestDrive,'outside');$null=New-QuietTestFile ([IO.Path]::Combine($root,'build','script-shouldprocess.json')) '{"SchemaVersion":1,"ReadOnlyExceptions":[],"LegacyPaths":[]}'
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'tools','Elsewhere.Tests.ps1')) 'Describe d { It i { } }'
        {Test-QuietScriptShouldProcessPolicy -WorkspaceRoot $root}|Should -Throw -ExpectedMessage 'ScriptShouldProcessRequired: tools/Elsewhere.Tests.ps1*'
    }
}
