#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptsInventory
    $seed=Get-QuietTestSeed
    $upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ';$lower='abcdefghijklmnopqrstuvwxyz0123456789'
    $newRoot={[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))}
    $newName={param([Random]$Random)(New-QuietRandomString $Random $upper 1 1)+(New-QuietRandomString $Random $lower 0 4)+'-'+(New-QuietRandomString $Random $upper 1 1)+(New-QuietRandomString $Random $lower 0 4)}
    # Writes scripts/lib/<File> for each {File, Text} and returns the scripts root.
    $newScripts={param([object[]]$Libraries)
        $root=& $newRoot
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root,'lib'))
        foreach($library in $Libraries){$null=New-QuietTestFile ([IO.Path]::Combine($root,'lib',$library.File)) $library.Text}
        $root
    }
    $moduleText={param([string[]]$Names,[string]$Export)
        (($Names|ForEach-Object {"function $_ { 'x' }"}) -join "`n")+"`n"+$Export+"`n"
    }
    $newBaseline={param($Value)
        $path=[IO.Path]::Combine((& $newRoot),'coverage.inventory.json')
        $null=New-QuietTestFile $path $(if($Value -is [string]){$Value}else{ConvertTo-Json -InputObject $Value -Depth 4})
        $path
    }
    $newKey={param([Random]$Random)'lib/'+(New-QuietRandomString $Random $upper 1 1)+(New-QuietRandomString $Random $lower 0 6)+'.psm1::'+(& $newName $Random)}
}

Describe 'Get-QuietScriptsLibraryExports' {
    It 'returns every literal export in file-name order then declaration order' {
        $null=Invoke-QuietProperty -Name 'inventory-exports' -Seed $seed -Count 40 -Generator {param($random)
            $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $count=$random.Next(0,5)
            while($files.Count -lt $count){[void]$files.Add((New-QuietRandomString $random $upper 1 1)+(New-QuietRandomString $random $lower 0 6)+$(if($random.Next(0,2)){'-X'}else{''})+'.psm1')}
            $libraries=foreach($file in $files){
                $names=[string[]]@(1..($random.Next(1,5))|ForEach-Object {& $newName $random})
                $quoted=foreach($name in $names){switch($random.Next(0,3)){0{$name}1{"'$name'"}2{'"'+$name+'"'}}}
                $flag=Get-QuietRandomItem $random @('-Function','-function','-Alias a -Function')
                [pscustomobject]@{File=$file;Names=$names;Text=(& $moduleText $names ('Export-ModuleMember '+$flag+' '+($quoted -join ',')))}
            }
            ,[object[]]@($libraries)
        } -Property {param($libraries)
            $root=& $newScripts $libraries
            $null=New-QuietTestFile ([IO.Path]::Combine($root,'lib','notes.ps1')) 'Export-ModuleMember -Function Not-Counted'
            $null=New-QuietTestFile ([IO.Path]::Combine($root,'lib','nested','Inner.psm1')) 'Export-ModuleMember -Function Not-Counted'
            $expected=foreach($library in @($libraries|Sort-Object File)){foreach($name in $library.Names){'lib/'+$library.File+'::'+$name}}
            $actual=@(Get-QuietScriptsLibraryExports -ScriptsRoot $root)
            ($actual|ForEach-Object Key) -join '|' | Should -BeExactly (@($expected) -join '|')
            foreach($row in $actual){$row.Key | Should -BeExactly ($row.Library+'::'+$row.Name)}
        }
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='no Export-ModuleMember';Export='';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 has 0 Export-ModuleMember'}
        @{Case='two Export-ModuleMember';Export="Export-ModuleMember -Function Get-A`nExport-ModuleMember -Function Get-B";Message='ScriptsInventoryExportsInvalid: lib/M.psm1 has 2 Export-ModuleMember'}
        @{Case='an Export-ModuleMember nested in a function';Export="function Get-B { Export-ModuleMember -Function Get-B }`nExport-ModuleMember -Function Get-A";Message='ScriptsInventoryExportsInvalid: lib/M.psm1 has 2 Export-ModuleMember'}
        @{Case='no -Function';Export='Export-ModuleMember -Variable x';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 exports no -Function list'}
        @{Case='a trailing -Function';Export='Export-ModuleMember -Function';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 exports no -Function list'}
        @{Case='a wildcard';Export="Export-ModuleMember -Function 'Get-*'";Message="ScriptsInventoryExportsInvalid: lib/M.psm1 exports 'Get-*'"}
        @{Case='a variable';Export='Export-ModuleMember -Function $names';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 exports $names'}
        @{Case='an array expression';Export="Export-ModuleMember -Function @('Get-A')";Message="ScriptsInventoryExportsInvalid: lib/M.psm1 exports @('Get-A')"}
        @{Case='an expandable string';Export='Export-ModuleMember -Function Get-A,"$x-B"';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 exports "$x-B"'}
        @{Case='a name without a dash';Export='Export-ModuleMember -Function GetA';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 exports GetA'}
        @{Case='a parse error';Export='Export-ModuleMember -Function Get-A }';Message='ScriptsInventoryExportsInvalid: lib/M.psm1 does not parse'}
    ) {
        $root=& $newScripts @([pscustomobject]@{File='M.psm1';Text=(& $moduleText @('Get-A') $Export)})
        {Get-QuietScriptsLibraryExports -ScriptsRoot $root} | Should -Throw -ExpectedMessage $Message
    }

    It 'rejects a scripts root without lib' {
        {Get-QuietScriptsLibraryExports -ScriptsRoot (& $newRoot)} | Should -Throw -ExpectedMessage 'ScriptsInventoryPathInvalid: scripts-root'
    }

    It 'returns nothing for an empty lib directory' {
        @(Get-QuietScriptsLibraryExports -ScriptsRoot (& $newScripts @())).Count | Should -Be 0
    }

    It 'raises only ScriptsInventoryExportsInvalid on fuzzed modules' {
        $null=Invoke-QuietProperty -Name 'inventory-exports-fuzz' -Seed $seed -Count 80 -Generator {param($random)
            $parts=@('Export-ModuleMember',' -Function ',' -Alias ','Get-A',',',"'",'"','$x','@(',')','{','}','*',"`n",'#',' ','function Get-A {}','-Variable')
            -join @(1..($random.Next(0,14))|ForEach-Object {Get-QuietRandomItem $random $parts})
        } -Property {param($text)
            $root=& $newScripts @([pscustomobject]@{File='F.psm1';Text=$text})
            try{$null=@(Get-QuietScriptsLibraryExports -ScriptsRoot $root)}catch{$_.Exception.Message | Should -Match '\AScriptsInventoryExportsInvalid: lib/F\.psm1 '}
        }
    }

    It 'reads the repository libraries' {
        $rows=@(Get-QuietScriptsLibraryExports -ScriptsRoot (Get-QuietTestScriptsRoot))
        $rows.Count | Should -BeGreaterThan 300
        @($rows|Where-Object Key -CEQ 'lib/ScriptsInventory.psm1::Get-QuietScriptsLibraryExports').Count | Should -Be 1
        @($rows.Key|Sort-Object -Unique).Count | Should -Be $rows.Count
    }
}

Describe 'Get-QuietScriptsTestInventory' {
    It 'lists exactly the test files that name each export as a whole command word' {
        $null=Invoke-QuietProperty -Name 'inventory-references' -Seed $seed -Count 40 -Generator {param($random)
            $names=[string[]]@(1..($random.Next(1,7))|ForEach-Object {& $newName $random}|Sort-Object -Unique)
            $tests=foreach($index in 1..($random.Next(0,5))){
                $tokens=foreach($pick in 1..($random.Next(0,6))){
                    $name=Get-QuietRandomItem $random $names
                    switch($random.Next(0,6)){0{$name}1{$name.ToLowerInvariant()}2{$name+'x'}3{'x'+$name}4{$name+'-Z'}5{'_'+$name}}
                }
                [pscustomobject]@{Path=$(if($random.Next(0,2)){"unit/T$index.Tests.ps1"}else{"integration/d/T$index.Tests.ps1"});Tokens=[string[]]@($tokens);Separator=(Get-QuietRandomItem $random @(' ',';',"`n",'(',"'",'|'))}
            }
            [pscustomobject]@{Names=$names;Tests=[object[]]@($tests)}
        } -Property {param($case)
            $scripts=& $newScripts @([pscustomobject]@{File='L.psm1';Text=(& $moduleText $case.Names ('Export-ModuleMember -Function '+($case.Names -join ',')))})
            $tests=& $newRoot
            foreach($test in $case.Tests){$null=New-QuietTestFile ([IO.Path]::Combine($tests,$test.Path)) ('x'+$test.Separator+($test.Tokens -join $test.Separator)+$test.Separator)}
            $null=New-QuietTestFile ([IO.Path]::Combine($tests,'support','Helper.ps1')) ($case.Names -join ' ')
            $rows=@(Get-QuietScriptsTestInventory -ScriptsRoot $scripts -TestsRoot $tests)
            ($rows|ForEach-Object Name) -join '|' | Should -BeExactly ($case.Names -join '|')
            foreach($row in $rows){
                $tokenSet=$null
                $expected=@($case.Tests|Where-Object {$tokenSet=[Collections.Generic.HashSet[string]]::new([string[]]$_.Tokens,[StringComparer]::OrdinalIgnoreCase);$tokenSet.Contains($row.Name)}|ForEach-Object Path|Sort-Object)
                @($row.Tests|Sort-Object) -join '|' | Should -BeExactly ($expected -join '|') -Because $row.Name
                $row.Key | Should -BeExactly ('lib/L.psm1::'+$row.Name)
            }
        }
    }

    It 'matches <Text> as <Matched>' -ForEach @(
        @{Text='(Get-Foo -X 1)';Matched=$true}
        @{Text="'Get-Foo'";Matched=$true}
        @{Text='get-foo';Matched=$true}
        @{Text='Mock Get-Foo -ModuleName L';Matched=$true}
        @{Text='Get-FooBar';Matched=$false}
        @{Text='Get-Foo-Bar';Matched=$false}
        @{Text='My-Get-Foo';Matched=$false}
        @{Text='$Get-Foo_';Matched=$false}
        @{Text='Get-Fo';Matched=$false}
    ) {
        $scripts=& $newScripts @([pscustomobject]@{File='L.psm1';Text=(& $moduleText @('Get-Foo') 'Export-ModuleMember -Function Get-Foo')})
        $tests=& $newRoot
        $null=New-QuietTestFile ([IO.Path]::Combine($tests,'A.Tests.ps1')) $Text
        @((Get-QuietScriptsTestInventory -ScriptsRoot $scripts -TestsRoot $tests).Tests).Count -eq 1 | Should -Be $Matched
    }

    It 'rejects a missing tests root' {
        $scripts=& $newScripts @()
        {Get-QuietScriptsTestInventory -ScriptsRoot $scripts -TestsRoot (& $newRoot)} | Should -Throw -ExpectedMessage 'ScriptsInventoryPathInvalid: tests-root'
    }
}

Describe 'Read-QuietScriptsTestInventoryBaseline' {
    It 'round-trips sorted unique keys' {
        $null=Invoke-QuietProperty -Name 'inventory-baseline' -Seed $seed -Count 60 -Generator {param($random)
            [string[]]@(1..($random.Next(0,12))|ForEach-Object {& $newKey $random}|Sort-Object -Unique -CaseSensitive)
        } -Property {param($keys)
            $baseline=Read-QuietScriptsTestInventoryBaseline -Path (& $newBaseline ([ordered]@{SchemaVersion=1;Untested=[string[]]@($keys)}))
            $baseline.SchemaVersion | Should -Be 1
            ,$baseline.Untested | Should -BeOfType [string[]]
            $baseline.Untested -join '|' | Should -BeExactly (@($keys) -join '|')
        }
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='invalid JSON';Value='{';Message='ScriptsInventoryBaselineInvalid: syntax'}
        @{Case='invalid UTF-8';Value=$null;Message='ScriptsInventoryBaselineInvalid: syntax'}
        @{Case='an array document';Value='[1,2]';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='a missing Untested';Value='{"SchemaVersion":1,"Other":[]}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='an extra key';Value='{"SchemaVersion":1,"Untested":[],"X":1}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='schema 2';Value='{"SchemaVersion":2,"Untested":[]}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='a string schema';Value='{"SchemaVersion":"1","Untested":[]}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='a decimal schema';Value='{"SchemaVersion":1.0,"Untested":[]}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='a missing schema';Value='{"Version":1,"Untested":[]}';Message='ScriptsInventoryBaselineInvalid: shape'}
        @{Case='a null key';Value='{"SchemaVersion":1,"Untested":null}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='a number key';Value='{"SchemaVersion":1,"Untested":[1]}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='a key outside lib';Value='{"SchemaVersion":1,"Untested":["X.psm1::Get-A"]}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='a nested library';Value='{"SchemaVersion":1,"Untested":["lib/a/X.psm1::Get-A"]}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='a key without function';Value='{"SchemaVersion":1,"Untested":["lib/X.psm1::"]}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='a key with a trailing newline';Value='{"SchemaVersion":1,"Untested":["lib/X.psm1::Get-A\n"]}';Message='ScriptsInventoryBaselineInvalid: key'}
        @{Case='unsorted keys';Value='{"SchemaVersion":1,"Untested":["lib/X.psm1::Get-B","lib/X.psm1::Get-A"]}';Message='ScriptsInventoryBaselineInvalid: order'}
        @{Case='duplicate keys';Value='{"SchemaVersion":1,"Untested":["lib/X.psm1::Get-A","lib/X.psm1::Get-A"]}';Message='ScriptsInventoryBaselineInvalid: order'}
    ) {
        $path=if($null -eq $Value){
            $file=[IO.Path]::Combine((& $newRoot),'coverage.inventory.json')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
            # Valid JSON once decoded leniently: only strict UTF-8 decoding rejects it.
            $bytes=[Text.Encoding]::ASCII.GetBytes('{"SchemaVersion":1,"Untested":["lib/A.psm1::Get-A')+[byte[]](0xFF)+[Text.Encoding]::ASCII.GetBytes('"]}')
            [IO.File]::WriteAllBytes($file,[byte[]]$bytes);$file
        }else{& $newBaseline $Value}
        {Read-QuietScriptsTestInventoryBaseline -Path $path} | Should -Throw -ExpectedMessage $Message
    }

    It 'reports a missing baseline' {
        {Read-QuietScriptsTestInventoryBaseline -Path ([IO.Path]::Combine((& $newRoot),'none.json'))} | Should -Throw -ExpectedMessage 'ScriptsInventoryBaselineMissing'
    }

    It 'raises only typed baseline errors on fuzzed documents' {
        $null=Invoke-QuietProperty -Name 'inventory-baseline-fuzz' -Seed $seed -Count 100 -Generator {param($random)
            $parts=@('{','}','[',']','"SchemaVersion"','"Untested"',':',',','1','2','null','"lib/A.psm1::Get-A"','"lib/B.psm1::Get-B"','"x"','true',' ')
            -join @(1..($random.Next(0,16))|ForEach-Object {Get-QuietRandomItem $random $parts})
        } -Property {param($text)
            try{$null=Read-QuietScriptsTestInventoryBaseline -Path (& $newBaseline $text)}catch{$_.Exception.Message | Should -Match '\AScriptsInventoryBaselineInvalid: (syntax|shape|key|order)\z'}
        }
    }
}

Describe 'Compare-QuietScriptsTestInventory' {
    It 'reports new untested exports and stale entries, and prunes without growing' {
        $null=Invoke-QuietProperty -Name 'inventory-compare' -Seed $seed -Count 150 -Generator {param($random)
            $keys=[string[]]@(1..($random.Next(0,10))|ForEach-Object {& $newKey $random}|Sort-Object -Unique -CaseSensitive)
            # 1..0 is (1,0), so the test count is drawn first: a third of the exports stay untested.
            $rows=foreach($key in $keys){$count=$random.Next(0,3);[pscustomobject]@{Key=$key;Tests=[string[]]@(if($count){1..$count|ForEach-Object {"T$_.Tests.ps1"}})}}
            $extra=[string[]]@(1..($random.Next(0,4))|ForEach-Object {& $newKey $random})
            $listed=[string[]]@(@([object[]](Get-QuietRandomSubset $random $keys))+$extra|Sort-Object -Unique -CaseSensitive)
            [pscustomobject]@{Rows=[object[]]@($rows);Listed=$listed}
        } -Property {param($case)
            $untested=@($case.Rows|Where-Object {$_.Tests.Count -eq 0}|ForEach-Object Key)
            $expectedNew=@($untested|Where-Object {$case.Listed -cnotcontains $_}|Sort-Object -CaseSensitive)
            $expectedStale=@($case.Listed|Where-Object {$untested -cnotcontains $_})
            $expectedKept=@($case.Listed|Where-Object {$untested -ccontains $_})
            $result=Compare-QuietScriptsTestInventory -Inventory $case.Rows -Baseline ([pscustomobject]@{SchemaVersion=1;Untested=$case.Listed})
            $result.New -join '|' | Should -BeExactly ($expectedNew -join '|')
            $result.Stale -join '|' | Should -BeExactly ($expectedStale -join '|')
            $result.Pruned.Untested -join '|' | Should -BeExactly ($expectedKept -join '|')
            $result.Pruned.SchemaVersion | Should -Be 1
            $result.Passed | Should -Be ($expectedNew.Count -eq 0 -and $expectedStale.Count -eq 0)
            $result.Exports | Should -Be $case.Rows.Count
            $result.Tested | Should -Be ($case.Rows.Count-$untested.Count)
            $result.Baselined | Should -Be $expectedKept.Count
            foreach($key in $result.Pruned.Untested){$case.Listed | Should -Contain $key}
        }
    }

    It 'compares keys case-sensitively' {
        $result=Compare-QuietScriptsTestInventory -Inventory @([pscustomobject]@{Key='lib/A.psm1::Get-A';Tests=[string[]]@()}) -Baseline ([pscustomobject]@{SchemaVersion=1;Untested=[string[]]@('lib/a.psm1::Get-A')})
        $result.New | Should -BeExactly @('lib/A.psm1::Get-A')
        $result.Stale | Should -BeExactly @('lib/a.psm1::Get-A')
        $result.Passed | Should -BeFalse
    }

    It 'passes on an empty inventory and baseline' {
        $result=Compare-QuietScriptsTestInventory -Inventory @() -Baseline ([pscustomobject]@{SchemaVersion=1;Untested=[string[]]@()})
        $result.Passed | Should -BeTrue
        $result.Exports | Should -Be 0
        @($result.Pruned.Untested).Count | Should -Be 0
    }
}
