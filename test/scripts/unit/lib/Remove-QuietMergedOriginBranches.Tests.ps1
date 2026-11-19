#requires -Version 7.6
BeforeAll {
    $support = [IO.Path]::Combine($PSScriptRoot, '..', '..', 'support')
    Import-Module ([IO.Path]::Combine($support, 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($support, 'Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    $module = Import-QuietTestLibrary -Name Remove-QuietMergedOriginBranches
    $base = 'a' * 40
    $tip = 'b' * 40
    $moved = 'c' * 40
    $default = 'd' * 40
    $refs = "ref: refs/heads/stable`tHEAD`n$default`tHEAD`n$default`trefs/heads/stable`n$base`trefs/heads/develop"
    $pr = {
        param($Number, $Branch, $Oid, $Base = 'develop', $Fork = $false)
        @{ number = $Number; headRefName = $Branch; headRefOid = $Oid; baseRefName = $Base; mergedAt = '2026-11-19T09:00:00Z'; isCrossRepository = $Fork }
    }
    $plan = {
        param($Text, $Records)
        $json = ConvertTo-Json -InputObject @($Records) -Compress
        & $module {
            param($Text, $Json)
            $prs = ConvertFrom-QuietMergedBranchPullRequests -Json $Json
            Get-QuietMergedOriginBranchPlan -RemoteRefs $Text -PullRequests $prs
        } $Text $json
    }
}

Describe 'Merged origin policy' {
    It 'requires exact same-repository merge evidence in develop and protects delivery branches' {
        $text = "$refs`n$tip`trefs/heads/feature/squashed`n$moved`trefs/heads/feature/advanced`n$tip`trefs/heads/fix/fork`n$tip`trefs/heads/fix/other-base`n$tip`trefs/heads/main`n$tip`trefs/heads/master"
        $prs = @(
            & $pr 1 'feature/squashed' $tip
            & $pr 2 'feature/advanced' $tip
            & $pr 3 'fix/fork' $tip 'develop' $true
            & $pr 4 'fix/other-base' $tip 'main'
            & $pr 5 'stable' $default
            & $pr 6 'develop' $base
            & $pr 7 'main' $tip
            & $pr 8 'master' $tip
        )
        $rows = & $plan $text $prs
        $eligible = @($rows | Where-Object State -eq 'Eligible')
        $eligible.Count | Should -Be 1
        $eligible[0].Branch | Should -BeExactly 'feature/squashed'
        $eligible[0].PullRequest | Should -Be 1
        $eligible[0].Tip | Should -BeExactly $tip
        ($rows | Where-Object Branch -eq 'feature/advanced').Reason | Should -BeExactly 'TipDiffersFromPullRequest'
        ($rows | Where-Object Branch -eq 'fix/fork').Reason | Should -BeExactly 'NoMergedPullRequest'
        ($rows | Where-Object Branch -eq 'fix/other-base').Reason | Should -BeExactly 'NoMergedPullRequest'
        @($rows | Where-Object Reason -eq 'Protected').Branch | Should -Be @('develop', 'main', 'master', 'stable')
        @($rows | Where-Object State -eq 'Kept').Count | Should -Be 7
    }

    It 'keeps a branch whose only eligible-looking PR has a different case' {
        $rows = & $plan "$refs`n$tip`trefs/heads/fix/Speed" @(& $pr 1 'fix/speed' $tip)
        ($rows | Where-Object Branch -ceq 'fix/Speed').Reason | Should -BeExactly 'NoMergedPullRequest'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'missing develop'; Pattern = 'MergedOriginDevelopMissing'; Transform = { param($s) $s -replace '[^\n]+refs/heads/develop', '' } }
        @{ Case = 'missing symbolic HEAD'; Pattern = 'MergedOriginDefaultUnknown'; Transform = { param($s) $s -replace 'ref: [^\n]+\n', '' } }
        @{ Case = 'missing HEAD hash'; Pattern = 'MergedOriginDefaultUnknown'; Transform = { param($s) $s -replace '[a-f0-9]{40}\tHEAD\n', '' } }
        @{ Case = 'mismatched HEAD'; Pattern = 'MergedOriginDefaultUnknown'; Transform = { param($s) $s -replace '[a-f0-9]{40}\tHEAD', (('f' * 40) + "`tHEAD") } }
        @{ Case = 'missing default branch'; Pattern = 'MergedOriginDefaultUnknown'; Transform = { param($s) $s -replace '[a-f0-9]{40}\trefs/heads/stable\n', '' } }
        @{ Case = 'unexpected tag'; Pattern = 'MergedOriginUnexpectedRef'; Transform = { param($s) "$s`n$('a' * 40)`trefs/tags/v1" } }
        @{ Case = 'duplicate symbolic HEAD'; Pattern = 'MergedOriginDefaultAmbiguous'; Transform = { param($s) "$s`nref: refs/heads/develop`tHEAD" } }
        @{ Case = 'duplicate HEAD hash'; Pattern = 'MergedOriginDefaultAmbiguous'; Transform = { param($s) "$s`n$('a' * 40)`tHEAD" } }
    ) {
        { & $plan (& $Transform $refs) @() } | Should -Throw -ExpectedMessage "$Pattern*"
    }

    It 'accepts only matching tips across generated branch and PR names' {
        $random = [Random]::new((Get-QuietTestSeed))
        $records = @()
        $lines = @($refs)
        $expected = @()
        foreach ($index in 1..40) {
            $name = "fix/$index-$($random.Next())"
            $head = if ($random.Next(2)) { $tip } else { $moved }
            $lines += "$tip`trefs/heads/$name"
            $records += & $pr $index $name $head
            if ($head -eq $tip) { $expected += $name }
        }
        @((& $plan ($lines -join "`r`n") $records | Where-Object State -eq 'Eligible').Branch | Sort-Object) | Should -Be @($expected | Sort-Object)
    }

    It 'fails closed on generated malformed ref lines' {
        $random = [Random]::new((Get-QuietTestSeed))
        foreach ($index in 1..20) {
            $oid = 'a' * $random.Next(1, 39)
            { & $plan "$refs`n$oid`trefs/heads/fix/$index" @() } | Should -Throw -ExpectedMessage 'WorkBranchRemoteOutputInvalid*'
        }
    }
}

Describe 'Merged origin orchestration' {
    BeforeEach {
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { throw 'Unexpected native invocation' }
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { 'https://github.com/owner/repo.git' } -ParameterFilter { $ArgumentList[0] -eq 'remote' }
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { "ref: refs/heads/develop`tHEAD`n$('a'*40)`tHEAD`n$('a'*40)`trefs/heads/develop`n$('b'*40)`trefs/heads/fix/old" } -ParameterFilter { $ArgumentList[0] -eq 'ls-remote' }
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { '[{"number":42,"headRefName":"fix/old","headRefOid":"' + ('b'*40) + '","baseRefName":"develop","mergedAt":"2026-11-19T09:00:00Z","isCrossRepository":false}]' } -ParameterFilter {
            $FilePath -eq 'gh' -and ($ArgumentList -join ' ') -like 'pr list --repo github.com/owner/repo --state merged --base develop *'
        }
    }

    It 'queries the plan by default without pushing' {
        $result = Invoke-QuietScriptRemoveQuietMergedOriginBranches -WorkspaceRoot $TestDrive
        ($result | Where-Object Branch -eq 'fix/old').State | Should -BeExactly 'Eligible'
        Should -Invoke Invoke-QuietOriginBranchTool -ModuleName $module.Name -Times 0 -Exactly -ParameterFilter { 'push' -in $ArgumentList }
    }

    It 'does not invoke Git or GitHub with WhatIf' {
        Invoke-QuietScriptRemoveQuietMergedOriginBranches -WorkspaceRoot $TestDrive -Apply -WhatIf
        Should -Invoke Invoke-QuietOriginBranchTool -ModuleName $module.Name -Times 0 -Exactly
    }

    It 'deletes only the proven remote ref with an explicit SHA lease and atomic push' {
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name {} -ParameterFilter { 'push' -in $ArgumentList }
        $result = Invoke-QuietScriptRemoveQuietMergedOriginBranches -WorkspaceRoot $TestDrive -Apply -Confirm:$false
        ($result | Where-Object Branch -eq 'fix/old').State | Should -BeExactly 'Deleted'
        Should -Invoke Invoke-QuietOriginBranchTool -ModuleName $module.Name -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'git' -and ($ArgumentList -join ' ') -ceq (
                '-c remote.origin.mirror=false push --atomic --no-follow-tags --recurse-submodules=no --force-with-lease=refs/heads/fix/old:' + ('b'*40) + ' origin :refs/heads/fix/old'
            )
        }
    }

    It 'refuses a different push destination before reading the network' {
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { 'https://github.com/other/repo' } -ParameterFilter { '--push' -in $ArgumentList }
        { Invoke-QuietScriptRemoveQuietMergedOriginBranches -WorkspaceRoot $TestDrive -Apply -Confirm:$false } | Should -Throw -ExpectedMessage 'MergedOriginRepositoryMismatch*'
        Should -Invoke Invoke-QuietOriginBranchTool -ModuleName $module.Name -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -in 'ls-remote', 'pr' -or 'push' -in $ArgumentList }
    }

    It 'reports an unconfirmed push without retrying' {
        Mock Invoke-QuietOriginBranchTool -ModuleName $module.Name { throw 'stale lease' } -ParameterFilter { 'push' -in $ArgumentList }
        { Invoke-QuietScriptRemoveQuietMergedOriginBranches -WorkspaceRoot $TestDrive -Apply -Confirm:$false } | Should -Throw -ExpectedMessage 'MergedOriginDeletionUnconfirmed*stale lease*'
        Should -Invoke Invoke-QuietOriginBranchTool -ModuleName $module.Name -Times 1 -Exactly -ParameterFilter { 'push' -in $ArgumentList }
    }
}
