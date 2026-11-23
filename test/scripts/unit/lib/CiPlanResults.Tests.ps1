#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CiPlanResults
    $seed=Get-QuietTestSeed
    $prerequisites=@('plan','source-checks')
    $scoped=[ordered]@{'layout-tests'='run_layout';products='run_products';smokes='run_smokes';'tooling-only'='run_tooling';'companion-checks'='run_companion_checks';distribution='run_distribution';readytorun='run_readytorun'}
    $results=@('success','skipped','failure','cancelled','Success',$null)
    $flags=@('true','false','True','',$null,'<absent>')
    # Builds a needs object; '<absent>' removes the job or the flag.
    $newNeeds={param([hashtable]$Prerequisite,[hashtable]$Flag,[hashtable]$Result,[hashtable]$Extra=@{})
        $needs=[ordered]@{}
        foreach($name in $prerequisites){if($Prerequisite[$name] -cne '<absent>'){$needs[$name]=[pscustomobject]@{result=$Prerequisite[$name]}}}
        if($needs.Contains('plan')){
            $outputs=[ordered]@{};foreach($name in $scoped.Keys){if($Flag[$name] -cne '<absent>'){$outputs[$scoped[$name]]=$Flag[$name]}}
            $needs['plan']=[pscustomobject]@{result=$Prerequisite['plan'];outputs=$outputs}
        }
        foreach($name in $scoped.Keys){if($Result[$name] -cne '<absent>'){$needs[$name]=[pscustomobject]@{result=$Result[$name]}}}
        foreach($name in $Extra.Keys){$needs[$name]=[pscustomobject]@{result=$Extra[$name]}}
        $needs
    }
    # Independent oracle written from the contract: prerequisites succeed, each scoped job matches its flag, others never fail.
    $expectedIssues={param([hashtable]$Prerequisite,[hashtable]$Flag,[hashtable]$Result,[hashtable]$Extra=@{})
        $issues=[Collections.Generic.List[string]]::new()
        foreach($name in $prerequisites){if($Prerequisite[$name] -ceq '<absent>' -or $Prerequisite[$name] -cne 'success'){$issues.Add("CiPlanPrerequisiteRequired: $name")}}
        foreach($name in $scoped.Keys){
            $declared=if($Prerequisite['plan'] -ceq '<absent>'){$null}else{$Flag[$name]}
            $known=$declared -ceq 'true' -or $declared -ceq 'false'
            if(!$known){$issues.Add("CiPlanOutputMissing: $($scoped[$name])")}
            if($Result[$name] -ceq '<absent>'){$issues.Add("CiPlanJobMissing: $name");continue}
            if(!$known){continue}
            $expected=if($declared -ceq 'true'){'success'}else{'skipped'}
            if($Result[$name] -cne $expected){$issues.Add("CiPlanScopeResultMismatch: $name expected $expected; observed $($Result[$name])")}
        }
        foreach($name in @($Extra.Keys|Sort-Object)){if($Extra[$name] -cne 'success' -and $Extra[$name] -cne 'skipped'){$issues.Add("CiPlanJobFailed: $name")}}
        ,$issues.ToArray()
    }
    $observedIssues={param($Needs)
        try{$receipt=Assert-QuietCiPlanResults -Needs $Needs;if(!$receipt.Ready -or $receipt.SchemaVersion -ne 2 -or $receipt.QualificationMode -cne 'selected'){throw 'receipt'};return ,@()}
        catch{return ,[string[]]$_.Exception.Message.Split("`n")}
    }
}

Describe 'Assert-QuietCiPlanResults' {
    It 'accepts every consistent selective plan' -ForEach @(
        foreach($mask in 0..31){@{Mask=$mask}}
    ) {
        $prerequisite=@{plan='success';'source-checks'='success'}
        $flag=@{};$result=@{};$index=0
        foreach($name in $scoped.Keys){$on=($Mask -shr $index) -band 1;$flag[$name]=if($on){'true'}else{'false'};$result[$name]=if($on){'success'}else{'skipped'};$index++}
        $receipt=Assert-QuietCiPlanResults -Needs (& $newNeeds $prerequisite $flag $result @{images='skipped';'extra-checks'='success'})
        $receipt.Ready|Should -BeTrue
        $receipt.Jobs.Contains('images')|Should -BeTrue
    }

    It 'reports exactly the issues of <Job> with flag <FlagValue> and result <ResultValue>' -ForEach @(
        foreach($job in 'layout-tests','products','smokes','tooling-only','companion-checks','distribution','readytorun'){foreach($f in 'true','false','True','',$null,'<absent>'){foreach($r in 'success','skipped','failure','cancelled','<absent>'){@{Job=$job;FlagValue=$f;ResultValue=$r}}}}
    ) {
        $prerequisite=@{plan='success';'source-checks'='success'}
        $flag=@{};$result=@{};foreach($name in $scoped.Keys){$flag[$name]='false';$result[$name]='skipped'}
        $flag[$Job]=$FlagValue;$result[$Job]=$ResultValue
        $observed=& $observedIssues (& $newNeeds $prerequisite $flag $result)
        $expected=& $expectedIssues $prerequisite $flag $result
        ($observed -join "`n")|Should -BeExactly ($expected -join "`n")
    }

    It 'matches the oracle on random combinations of prerequisites, flags, results and extra jobs' {
        $null=Invoke-QuietProperty -Name 'plan-results' -Seed $seed -Count 400 -Generator {param($random)
            $prerequisite=@{};foreach($name in $prerequisites){$prerequisite[$name]=Get-QuietRandomItem $random @('success','success','success','failure','skipped','cancelled','<absent>')}
            $flag=@{};$result=@{};foreach($name in $scoped.Keys){$flag[$name]=Get-QuietRandomItem $random $flags;$result[$name]=Get-QuietRandomItem $random (@($results)+'<absent>')}
            $extra=@{};foreach($index in 1..$random.Next(0,4)){$extra['job-'+(New-QuietRandomString $random 'abc' 1 3)]=Get-QuietRandomItem $random $results}
            [pscustomobject]@{Prerequisite=$prerequisite;Flag=$flag;Result=$result;Extra=$extra}
        } -Property {param($case)
            $observed=& $observedIssues (& $newNeeds $case.Prerequisite $case.Flag $case.Result $case.Extra)
            $expected=& $expectedIssues $case.Prerequisite $case.Flag $case.Result $case.Extra
            if(($observed -join "`n") -cne ($expected -join "`n")){throw "observed [$($observed -join ' | ')] expected [$($expected -join ' | ')]"}
            $true
        }
    }

    It 'never crashes on malformed needs entries' -ForEach @(
        @{Name='a plan without outputs';Needs=[ordered]@{plan=[pscustomobject]@{result='success'}}}
        @{Name='a null plan';Needs=[ordered]@{plan=$null}}
        @{Name='scalar entries';Needs=[ordered]@{plan='success';products='success'}}
        @{Name='non-string outputs';Needs=[ordered]@{plan=[pscustomobject]@{result='success';outputs=@{run_products=$true;run_smokes=1}}}}
        @{Name='an empty object';Needs=[ordered]@{}}
    ) {
        $message=try{$null=Assert-QuietCiPlanResults -Needs $Needs;'<accepted>'}catch{$_.Exception.Message}
        $message|Should -Not -BeExactly '<accepted>'
        foreach($line in $message.Split("`n")){$line|Should -Match '\ACiPlan(PrerequisiteRequired|OutputMissing|JobMissing|ScopeResultMismatch|JobFailed): '}
    }
}
