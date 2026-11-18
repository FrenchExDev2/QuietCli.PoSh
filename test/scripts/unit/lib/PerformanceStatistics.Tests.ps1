#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name PerformanceStatistics
    $seed=Get-QuietTestSeed
    $sample={param([Random]$Random)
        $count=$Random.Next(1,60)
        $scale=@(0.001,1,1000,1e9)[$Random.Next(4)]
        @{Values=[double[]]@(for($i=0;$i -lt $count;$i++){[Math]::Round(($Random.NextDouble()*2-0.2)*$scale,3)})}
    }
}

Describe 'Get-QuietPerformanceRank' {
    It 'returns rank <Expected> for q=<Quantile> of <Count>' -ForEach @(
        @{Count=1;Quantile=0.25;Expected=1}
        @{Count=1;Quantile=1;Expected=1}
        @{Count=4;Quantile=0.25;Expected=1}
        @{Count=4;Quantile=0.5;Expected=2}
        @{Count=7;Quantile=0.25;Expected=2}
        @{Count=7;Quantile=0.75;Expected=6}
        @{Count=7;Quantile=0.95;Expected=7}
        @{Count=19;Quantile=0.95;Expected=19}
        @{Count=20;Quantile=0.95;Expected=19}
        @{Count=100;Quantile=0.95;Expected=95}
        @{Count=100;Quantile=0.951;Expected=96}
        @{Count=3;Quantile=0.0001;Expected=1}
    ) {
        Get-QuietPerformanceRank -Count $Count -Quantile $Quantile|Should -Be $Expected
    }

    It 'rejects quantile <Quantile>' -ForEach @(@{Quantile=0},@{Quantile=-0.5},@{Quantile=1.0000001},@{Quantile=2},@{Quantile=[double]::NaN},@{Quantile=[double]::PositiveInfinity}) {
        {Get-QuietPerformanceRank -Count 5 -Quantile $Quantile}|Should -Throw 'PerformanceQuantileInvalid'
    }

    It 'rejects an empty sample size' {
        {Get-QuietPerformanceRank -Count 0 -Quantile 0.5}|Should -Throw
    }

    It 'stays in 1..n and grows with the quantile (property)' {
        Invoke-QuietProperty -Name 'rank bounds and monotony' -Seed $seed -Count 300 -Generator {param([Random]$Random)
            @{Count=$Random.Next(1,5000);Low=$Random.NextDouble();High=$Random.NextDouble()}
        } -Property {param($case)
            $low=[Math]::Max(1e-9,[Math]::Min($case.Low,$case.High));$high=[Math]::Max($low,[Math]::Max($case.Low,$case.High))
            $a=Get-QuietPerformanceRank -Count $case.Count -Quantile $low
            $b=Get-QuietPerformanceRank -Count $case.Count -Quantile $high
            $a -ge 1 -and $b -le $case.Count -and $a -le $b
        }|Should -Be 300
    }

    It 'puts p95 on the largest observation exactly below 20 observations (property)' {
        foreach($count in 1..200){
            ((Get-QuietPerformanceRank -Count $count -Quantile 0.95) -eq $count)|Should -Be ($count -lt 20) -Because "n=$count"
        }
    }
}

Describe 'Get-QuietPerformanceStatistics' {
    It 'returns null for an empty or absent sample' {
        Get-QuietPerformanceStatistics -Values @()|Should -BeNullOrEmpty
        Get-QuietPerformanceStatistics -Values $null|Should -BeNullOrEmpty
        Get-QuietPerformanceStatistics|Should -BeNullOrEmpty
        # Nothing reaches the pipeline, so collecting several samples never counts an empty one.
        @(Get-QuietPerformanceStatistics -Values @()).Count|Should -Be 0
    }

    It 'describes seven import samples with a p95 that is the maximum' {
        $s=Get-QuietPerformanceStatistics -Values @(7,1,6,2,5,3,4)
        $s.Count|Should -Be 7
        $s.Min|Should -Be 1
        $s.Q1|Should -Be 2
        $s.Median|Should -Be 4
        $s.Q3|Should -Be 6
        $s.Max|Should -Be 7
        $s.Iqr|Should -Be 4
        $s.P95|Should -Be 7
        $s.P95Rank|Should -Be 7
        $s.P95IsMax|Should -BeTrue
    }

    It 'averages the two middle values of an even sample' {
        (Get-QuietPerformanceStatistics -Values @(4,1,3,2)).Median|Should -Be 2.5
        (Get-QuietPerformanceStatistics -Values @(10,20)).Median|Should -Be 15
    }

    It 'takes the middle value of an odd, skewed sample' {
        # A symmetric sample cannot tell the middle value from the mean of its two neighbours.
        (Get-QuietPerformanceStatistics -Values @(10,1,2)).Median|Should -Be 2
        (Get-QuietPerformanceStatistics -Values @(1,2,3,50,100)).Median|Should -Be 3
    }

    It 'reports a p95 below the maximum from 20 observations' {
        $s=Get-QuietPerformanceStatistics -Values ([double[]](1..20))
        $s.P95|Should -Be 19
        $s.P95Rank|Should -Be 19
        $s.P95IsMax|Should -BeFalse
        $s.Q1|Should -Be 5
        $s.Q3|Should -Be 15
    }

    It 'describes a single observation' {
        $s=Get-QuietPerformanceStatistics -Values @(3.5)
        @($s.Min,$s.Q1,$s.Median,$s.Q3,$s.Max,$s.P95)|Should -Be @(3.5,3.5,3.5,3.5,3.5,3.5)
        $s.Iqr|Should -Be 0
        $s.P95IsMax|Should -BeTrue
    }

    It 'rejects <Name>' -ForEach @(
        @{Name='NaN';Values=@(1,[double]::NaN)}
        @{Name='positive infinity';Values=@([double]::PositiveInfinity)}
        @{Name='negative infinity';Values=@(2,3,[double]::NegativeInfinity)}
    ) {
        {Get-QuietPerformanceStatistics -Values $Values}|Should -Throw 'PerformanceStatisticsNonFinite'
    }

    It 'does not reorder the caller array' {
        $values=[double[]]@(3,1,2)
        $null=Get-QuietPerformanceStatistics -Values $values
        $values|Should -Be @(3,1,2)
    }

    It 'keeps Min, Q1, Median, Q3 and Max ordered, P95 at or above Median, and quantiles taken from the sample (property)' {
        Invoke-QuietProperty -Name 'statistics order' -Seed $seed -Count 300 -Generator $sample -Property {param($case)
            $s=Get-QuietPerformanceStatistics -Values $case.Values
            $s.Count -eq $case.Values.Count -and $s.Min -le $s.Q1 -and $s.Q1 -le $s.Median -and $s.Median -le $s.Q3 -and $s.Q3 -le $s.Max -and
            $s.P95 -ge $s.Median -and $s.P95 -le $s.Max -and $s.Iqr -eq ($s.Q3-$s.Q1) -and
            $case.Values -contains $s.Q1 -and $case.Values -contains $s.Q3 -and $case.Values -contains $s.P95 -and
            $s.Min -eq ($case.Values|Measure-Object -Minimum).Minimum -and $s.Max -eq ($case.Values|Measure-Object -Maximum).Maximum -and
            $s.P95IsMax -eq ($s.P95Rank -eq $s.Count)
        }|Should -Be 300
    }

    It 'does not depend on the input order (property)' {
        Invoke-QuietProperty -Name 'order invariance' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            $case=& $sample $Random
            $shuffled=[double[]]$case.Values.Clone()
            for($i=$shuffled.Length-1;$i -gt 0;$i--){$j=$Random.Next($i+1);$swap=$shuffled[$i];$shuffled[$i]=$shuffled[$j];$shuffled[$j]=$swap}
            @{Values=$case.Values;Shuffled=$shuffled}
        } -Property {param($case)
            # Numeric equality: -0.0 and 0.0 are the same observation even if a sort keeps either one.
            $a=Get-QuietPerformanceStatistics -Values $case.Values;$b=Get-QuietPerformanceStatistics -Values $case.Shuffled
            @(foreach($name in 'Count','Min','Q1','Median','Q3','Max','Iqr','P95','P95Rank','P95IsMax'){$a.$name -eq $b.$name}) -notcontains $false
        }|Should -Be 200
    }

    It 'shifts every location statistic with the data and keeps the spread (property)' {
        Invoke-QuietProperty -Name 'translation' -Seed $seed -Count 200 -Generator {param([Random]$Random)
            @{Values=[double[]]@(1..$Random.Next(1,40)|ForEach-Object {[double]$Random.Next(0,10000)});Shift=[double]$Random.Next(-500,500)}
        } -Property {param($case)
            $a=Get-QuietPerformanceStatistics -Values $case.Values
            $b=Get-QuietPerformanceStatistics -Values ([double[]]@($case.Values|ForEach-Object {$_+$case.Shift}))
            $b.Min -eq $a.Min+$case.Shift -and $b.Q1 -eq $a.Q1+$case.Shift -and $b.Median -eq $a.Median+$case.Shift -and $b.Q3 -eq $a.Q3+$case.Shift -and $b.Max -eq $a.Max+$case.Shift -and $b.P95 -eq $a.P95+$case.Shift -and $b.Iqr -eq $a.Iqr
        }|Should -Be 200
    }

    It 'never throws on finite fuzz and always throws on a planted non-finite value (fuzz)' {
        Invoke-QuietProperty -Name 'finite fuzz' -Seed $seed -Count 300 -Generator {param([Random]$Random)
            $values=[double[]]@(1..$Random.Next(1,30)|ForEach-Object {[BitConverter]::Int64BitsToDouble([long]($Random.NextDouble()*[long]::MaxValue))})
            $planted=[double[]]$values.Clone()
            $planted[$Random.Next($planted.Length)]=@([double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)[$Random.Next(3)]
            @{Values=@($values|Where-Object {[double]::IsFinite($_)});Planted=$planted}
        } -Property {param($case)
            if($case.Values.Count){$s=Get-QuietPerformanceStatistics -Values ([double[]]$case.Values);if($s.Count -ne $case.Values.Count){return $false}}
            try{$null=Get-QuietPerformanceStatistics -Values $case.Planted;$false}catch{$_.Exception.Message -ceq 'PerformanceStatisticsNonFinite'}
        }|Should -Be 300
    }
}
