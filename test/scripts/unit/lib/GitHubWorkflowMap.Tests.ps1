#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -DisableNameChecking -ErrorAction Stop
    $mapModule = Import-QuietTestLibrary -Name GitHubWorkflowMap
    $null = Import-QuietTestLibrary -Name WorkflowDocumentation
}

Describe 'GitHub workflow map links' {
    It 'resolves local references case-sensitively and ignores external and missing paths' {
        $catalogue = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $catalogue.Add('.github/workflows/ci.yml','local')
        (& $mapModule { param($items) Get-QuietWorkflowMapTarget './.github/workflows/ci.yml' $items } $catalogue) | Should -BeExactly 'local'
        foreach ($reference in @('owner/repo/.github/workflows/ci.yml@main','./.github/workflows/CI.yml','./missing','')) {
            (& $mapModule { param($ref,$items) Get-QuietWorkflowMapTarget $ref $items } $reference $catalogue) | Should -BeNullOrEmpty
        }
    }

    It 'escapes labels for both Mermaid and Markdown' {
        (& $mapModule { Format-QuietWorkflowMapText '"<>#&;' -Mermaid }) | Should -BeExactly '#34;#60;#62;#35;#38;#59;'
        (& $mapModule { Format-QuietWorkflowMapText "élan|[vue]`r`nétape" }) | Should -BeExactly 'élan&#124;&#91;vue&#93; étape'
        (& $mapModule { Format-QuietWorkflowMapText 'plain' }) | Should -BeExactly 'plain'
    }
}

Describe 'Get-QuietWorkflowScriptPaths' {
    It 'retains literal scripts in first-seen order and normalizes slash direction' {
        $actual = @(Get-QuietWorkflowScriptPaths 'pwsh ./scripts/B.ps1; Import-Module scripts\lib\A.psm1; ./scripts/B.ps1')
        $actual -join '|' | Should -BeExactly 'scripts/B.ps1|scripts/lib/A.psm1'
    }

    It 'recognizes seeded valid names and ignores traversal and malformed script lookalikes' {
        $null = Invoke-QuietProperty -Name 'literal workflow script paths' -Seed (Get-QuietTestSeed) -Count 50 -Generator {
            param($random)
            'Build-'+$random.Next(1,10000)+'.ps1'
        } -Property {
            param($name)
            $literal = 'scripts/'+$name
            @(Get-QuietWorkflowScriptPaths "./$literal ; ./scripts/sub/../$name ; ./$literal.bak ; otherscripts/$name ; ./$literal") -join '|' | Should -BeExactly $literal
        }
    }

}
