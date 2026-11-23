#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CampaignReports
}

Describe 'Write-QuietCampaignReport' {
    It 'renders mutation verdicts while retaining the detailed Markdown and original JSON' {
        $directory=[IO.Path]::Combine($TestDrive,'scripts')
        $json='{"Passed":false,"Incomplete":false,"Seed":27,"Targets":[{"Name":"Example","Module":"lib/Example.psm1","Killed":3,"Survived":1,"Timeout":0,"CompileError":0,"Equivalent":2,"Cached":0,"Mutants":6,"Score":75,"Break":100,"Passed":false}]}'
        $evidence=New-QuietTestFile ([IO.Path]::Combine($directory,'report.json')) $json
        $summary=[IO.Path]::Combine($directory,'github-summary.md')
        $arguments=@{Directory=$directory;Kind='scriptmutation';Title='Script mutation Example';Outcome='failure';SummaryPath=$summary}
        Write-QuietCampaignReport @arguments
        $markdown=[IO.Path]::Combine($directory,'report.md')
        $text=[IO.File]::ReadAllText($markdown,[Text.Encoding]::UTF8)
        $text|Should -Match '## Example'
        $text|Should -Match '```mermaid'
        $text|Should -Match '\| Item \| Mutants \|'
        $text|Should -Match 'bar \[3, 1, 0, 0, 2\]'
        $text|Should -Match '75 %'
        [IO.File]::ReadAllText($evidence,[Text.Encoding]::UTF8)|Should -BeExactly $json
        [IO.File]::ReadAllText($summary,[Text.Encoding]::UTF8)|Should -Match 'Campaign outcome \*\*failure\*\*'
        [IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.html'),[Text.Encoding]::UTF8)|Should -Match '<meter min="0" max="3" value="3">'
        Write-QuietCampaignReport @arguments
        [IO.File]::ReadAllText($markdown,[Text.Encoding]::UTF8)|Should -BeExactly $text
    }

    It 'reports a partial run-profile shard using observed outcomes' {
        $directory=[IO.Path]::Combine($TestDrive,'shard')
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'run-profiles-mutation.json')) '{"Partial":true,"ShardIndex":0,"ShardCount":2,"Results":[{"Outcome":"Killed"},{"Outcome":"Timeout"},{"Outcome":"Killed"}]}'
        Write-QuietCampaignReport -Directory $directory -Kind RunProfilesMutation -Title 'Run profiles' -Outcome failure
        $md=[IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.md'),[Text.Encoding]::UTF8)
        $md|Should -Match 'Run profiles \(shard 1/2\)'
        $md|Should -Match '\| Item \| Mutants \|'
        $md|Should -Match '\| Killed \| 2 \|'
        $md|Should -Match '\| Timeout \| 1 \|'
    }

    It 'labels an unsharded Core campaign and omits a chart for absent evidence' {
        $directory=[IO.Path]::Combine($TestDrive,'core')
        $module=Get-Module CampaignReports
        & $module {param($path) @(Get-QuietCampaignCharts -Directory $path -Kind Component).Count} $directory|Should -Be 0
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'run-profiles-mutation.json')) '{"Partial":false,"Results":[{"Outcome":"Killed"}]}'
        Write-QuietCampaignReport -Directory $directory -Kind Component -Title 'Core mutation' -Outcome success
        $md=[IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.md'),[Text.Encoding]::UTF8)
        $md|Should -Match '(?m)^## Run profiles\r?$'
        $md|Should -Match '\| Killed \| 1 \|'
    }

    It 'renders companion mutation counts and profile metrics in the same report' {
        $directory=[IO.Path]::Combine($TestDrive,'component')
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'mutation-evidence','git-Query.json')) '{"Selected":3,"Completed":2,"Results":[{"State":"Killed"},{"State":"Survived"}]}'
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'mutation-evidence','vagrant-parser.json')) '{"Selected":1,"Completed":1,"Cases":[{"Outcome":"InfrastructureFailure"}]}'
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'mutation-evidence','ignore.log')) 'not JSON'
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'profiling','Git.profile.json')) '{"TopFunctionsBySelfDuration":[{"Function":"<script>example</script>","SelfMs":2.5}],"TopLinesBySelfDuration":[{"Function":"Test-Runner","File":"sample.ps1","Line":10,"SelfMs":0.25}]}'
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'profiling','ignore.json')) 'not profile JSON'
        Write-QuietCampaignReport -Directory $directory -Kind Component -Title 'Git profiled-mutation' -Outcome failure -ErrorAction Stop
        $md=[IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.md'),[Text.Encoding]::UTF8)
        $md|Should -Match '\| Item \| Mutants \|'
        $md|Should -Match '\| Survived \| 1 \|'
        $md|Should -Match '\| Pending \| 1 \|'
        $md|Should -Not -Match '\| Pending \| 0 \|'
        $md|Should -Match '\| InfrastructureFailure \| 1 \|'
        $md|Should -Match '## Top lines'
        $md|Should -Match 'Self time \(ms\)'
        $md|Should -Match 'sample\.ps1:10'
        $md|Should -Match 'bar \[0\.25\]'
        $html=[IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.html'),[Text.Encoding]::UTF8)
        $html|Should -Match '&lt;script&gt;'
        $html|Should -Not -Match '<script>'
    }

    It 'previews without creating files and marks missing evidence on failure' {
        $directory=[IO.Path]::Combine($TestDrive,'missing')
        Write-QuietCampaignReport -Directory $directory -Kind Component -Title 'Missing evidence' -Outcome cancelled -WhatIf
        [IO.Directory]::Exists($directory)|Should -BeFalse
        Write-QuietCampaignReport -Directory $directory -Kind Component -Title 'Missing evidence' -Outcome cancelled
        [IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.md'),[Text.Encoding]::UTF8)|Should -Match 'No campaign measurements were produced'
        [IO.File]::ReadAllText([IO.Path]::Combine($directory,'report.html'),[Text.Encoding]::UTF8)|Should -Match '<strong>cancelled</strong>'
    }

    It 'rejects malformed UTF-8 in evidence before writing either report' {
        $directory=[IO.Path]::Combine($TestDrive,'malformed')
        $evidence=New-QuietTestFile ([IO.Path]::Combine($directory,'report.json')) '{"Targets":[],"Note":"~"}'
        $bytes=[IO.File]::ReadAllBytes($evidence)
        $bytes[[Array]::IndexOf($bytes,[byte]126)]=255
        [IO.File]::WriteAllBytes($evidence,$bytes)
        {Write-QuietCampaignReport -Directory $directory -Kind ScriptMutation -Title 'Invalid evidence' -Outcome failure -ErrorAction Stop}|Should -Throw '*Unable to translate bytes*'
        [IO.File]::Exists([IO.Path]::Combine($directory,'report.md'))|Should -BeFalse
        [IO.File]::Exists([IO.Path]::Combine($directory,'report.html'))|Should -BeFalse
    }
}
