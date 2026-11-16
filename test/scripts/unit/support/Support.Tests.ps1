#requires -Version 7.6
BeforeAll {
    foreach($name in @('TestWorkspace','Generators','Property')){Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support',$name+'.psm1')) -Force -DisableNameChecking -ErrorAction Stop}
    $seed=Get-QuietTestSeed
}

Describe 'Generators' {
    It 'replays the same sequence for the same seed and differs for another seed' {
        $first=@(1..20|ForEach-Object -Begin {$random=New-QuietRandom 99} -Process {New-QuietFuzzPath $random})
        $again=@(1..20|ForEach-Object -Begin {$random=New-QuietRandom 99} -Process {New-QuietFuzzPath $random})
        $other=@(1..20|ForEach-Object -Begin {$random=New-QuietRandom 100} -Process {New-QuietFuzzPath $random})
        $again|Should -Be $first
        ($other -join '|')|Should -Not -Be ($first -join '|')
    }
    It 'reads a positive QUIETCLI_TEST_SEED and falls back to the fixed seed otherwise' {
        $saved=$env:QUIETCLI_TEST_SEED
        try{
            $env:QUIETCLI_TEST_SEED='17';Get-QuietTestSeed|Should -Be 17
            foreach($value in @('','x','-3','0')){$env:QUIETCLI_TEST_SEED=$value;Get-QuietTestSeed|Should -Be 61207}
        }finally{$env:QUIETCLI_TEST_SEED=$saved}
    }
    It 'shuffles into a permutation and keeps subsets ordered' {
        $null=Invoke-QuietProperty -Name 'shuffle is a permutation' -Seed $seed -Count 100 -Generator {param($random)[pscustomobject]@{Random=$random;Items=@($count=$random.Next(0,12);if($count -gt 0){1..$count})}} -Property {param($case)
            $shuffled=Get-QuietShuffle $case.Random $case.Items
            $subset=Get-QuietRandomSubset $case.Random $case.Items
            (@($shuffled|Sort-Object) -join ',') -eq (@($case.Items) -join ',') -and (@($subset) -join ',') -eq (@($subset|Sort-Object) -join ',')
        }
    }
    It 'builds acyclic graphs rooted at Core' {
        $null=Invoke-QuietProperty -Name 'dag is acyclic' -Seed $seed -Count 100 -Generator {param($random)New-QuietRandomDag $random -Count $random.Next(1,9)} -Property {param($nodes)
            $nodes[0].Name -ceq 'Core' -and @($nodes[0].Requires).Count -eq 0 -and @(for($index=1;$index -lt $nodes.Count;$index++){
                $earlier=@($nodes[0..($index-1)].Name)
                if(@($nodes[$index].Requires|Where-Object {$earlier -notcontains $_}).Count -gt 0 -or $nodes[$index].Requires -notcontains 'Core'){'bad'}
            }).Count -eq 0
        }
    }
    It 'returns 64 hexadecimal characters for digests' {
        New-QuietRandomSha256 (New-QuietRandom 1)|Should -Match '^[0-9A-F]{64}$'
    }
    It 'rejects an empty candidate list' {
        {Get-QuietRandomItem (New-QuietRandom 1) @()}|Should -Throw -ExpectedMessage 'QuietRandomItemsEmpty'
    }
}

Describe 'Invoke-QuietProperty' {
    It 'returns the case count when the property holds' {
        Invoke-QuietProperty -Name 'holds' -Seed 1 -Count 25 -Generator {param($random)$random.Next()} -Property {param($value)$value -ge 0}|Should -Be 25
    }
    It 'shrinks to a minimal counterexample and names a replayable seed' {
        $failure={Invoke-QuietProperty -Name 'below 50' -Seed 3 -Count 200 -Generator {param($random)$random.Next(0,1000)} -Property {param($value)$value -lt 50} -Shrink {param($value)if($value -gt 0){$value-1}}}
        $failure|Should -Throw -ExpectedMessage '*PropertyFailed: below 50 seed=3 *counterexample=50:*'
    }
    It 'reports the same failing case for the same seed' {
        $capture={param($runSeed)try{Invoke-QuietProperty -Name 'odd' -Seed $runSeed -Count 50 -Generator {param($random)$random.Next(0,100)} -Property {param($value)$value % 7 -ne 3};'none'}catch{$_.Exception.Message}}
        (& $capture 11)|Should -BeExactly (& $capture 11)
    }
    It 'treats a thrown exception as a violation' {
        {Invoke-QuietProperty -Name 'throws' -Seed 1 -Count 1 -Generator {param($random)1} -Property {param($value)throw 'nope'}}|Should -Throw -ExpectedMessage '*: nope'
    }
}

Describe 'TestWorkspace' {
    It 'resolves the scripts root from QUIETCLI_SCRIPTS_ROOT or the repository' {
        $saved=$env:QUIETCLI_SCRIPTS_ROOT
        try{
            $env:QUIETCLI_SCRIPTS_ROOT=$TestDrive;Get-QuietTestScriptsRoot|Should -Be ([IO.Path]::GetFullPath($TestDrive))
            $env:QUIETCLI_SCRIPTS_ROOT=$null;[IO.File]::Exists([IO.Path]::Combine((Get-QuietTestScriptsRoot),'Invoke-ScriptsTests.ps1'))|Should -BeTrue
        }finally{$env:QUIETCLI_SCRIPTS_ROOT=$saved}
    }
    It 'writes LF fixture files without a BOM' {
        $path=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'a','b.txt')) "x`r`ny"
        [IO.File]::ReadAllBytes($path)|Should -Be ([byte[]]@(120,10,121))
    }
    It 'rejects an unsafe or missing library name' {
        {Import-QuietTestLibrary -Name '../Common'}|Should -Throw
        {Import-QuietTestLibrary -Name 'DoesNotExist'}|Should -Throw -ExpectedMessage 'QuietTestLibraryMissing: DoesNotExist'
    }
    It 'returns the child exit code and output' {
        $script=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'child.ps1')) 'param($Value) Write-Output "got $Value $env:QUIET_CHILD"; exit 3'
        $result=Invoke-QuietTestScript -ScriptPath $script -ArgumentList @('v') -Environment @{QUIET_CHILD='e'}
        $result.ExitCode|Should -Be 3
        $result.Output|Should -Match 'got v e'
        $result.TimedOut|Should -BeFalse
    }
}
