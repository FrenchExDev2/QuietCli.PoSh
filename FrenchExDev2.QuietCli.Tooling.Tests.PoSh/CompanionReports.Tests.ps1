function Test-QuietCompanionReportAggregation {
    <#
    .SYNOPSIS
    Verifies immutable per-case progress aggregation, duplicate rejection and targeted mutants.
    .PARAMETER WorkspaceRoot
    Checkout supplying the companion supervisor.
    .PARAMETER RunDirectory
    Owned external fixture and evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $module=Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/CiCompanionWorkers.psm1')) -DisableNameChecking -PassThru -ErrorAction Stop
    & $module {
        param($RunDirectory,$WorkspaceRoot)
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
        $subject=(Get-Command Read-QuietCiCompanionProgress).ScriptBlock
        $oracle={
            param($Subject,[string]$Name)
            $root=[IO.Path]::Combine($RunDirectory,('companion-receipts-'+$Name))
            [void][IO.Directory]::CreateDirectory($root)
            $worker=[pscustomobject]@{Name='Fixture';Directory=$root;Receipts=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);CaseStates=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)}
            # No progress JSON is available until a complete case receipt is published.
            $empty=& $Subject $worker
            if($empty.Passed -or $empty.Failed){throw 'CompanionReportInventedProgress'}
            foreach($index in 1..32){
                $path=[IO.Path]::Combine($root,('core-cases/case-'+$index+'/case-result.json'))
                Write-WorkspaceJson $path @{Name=('cas-é漢-'+$index);State=$(if($index%2){'Passed'}else{'Failed'})}
                $r=& $Subject $worker
                if($r.Passed -ne [Math]::Ceiling($index/2.0) -or $r.Failed -ne [Math]::Floor($index/2.0)){throw 'CompanionReportCountPropertyFailed'}
                $again=& $Subject $worker
                if($again.Passed -ne $r.Passed -or $again.Failed -ne $r.Failed){throw 'CompanionReportCountedTwice'}
            }
            # Receipts are cached after publication; subsequent polls do not reopen them.
            $first=[IO.Path]::Combine($root,'core-cases/case-1/case-result.json')
            $held=[IO.File]::Open($first,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
            try{$r=& $Subject $worker;if($r.Passed -ne 16 -or $r.Failed -ne 16){throw 'CompanionReportCachedCountsChanged'}}finally{$held.Dispose()}
            foreach($damage in @(@{Name='duplicate';Value=@{Name='cas-é漢-1';State='Passed'}},@{Name='unknown';Value=@{Name='fixture';State='Running'}},@{Name='missing';Value=@{State='Passed'}})){
                $path=[IO.Path]::Combine($root,('core-cases/'+$damage.Name+'/case-result.json'))
                Write-WorkspaceJson $path $damage.Value
                $rejected=$false;try{$null=& $Subject $worker}catch{$rejected=$_.Exception.Message -like 'CompanionCaseReceiptInvalid:*'}
                if(!$rejected){throw 'CompanionReportInvalidAccepted'}
                [IO.File]::Delete($path)
            }
            $bad=[IO.Path]::Combine($root,'core-cases/malformed/case-result.json')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($bad))
            [IO.File]::WriteAllText($bad,'{',[Text.UTF8Encoding]::new($false))
            $rejected=$false;try{$null=& $Subject $worker}catch{$rejected=$true}
            if(!$rejected){throw 'CompanionReportMalformedJsonAccepted'}
        }
        & $oracle $subject 'baseline'
        $source=$subject.ToString()
        $mutations=@(
            @('if($Worker.Receipts.Contains($path) -or !(Test-Path -LiteralPath $path))','if(!(Test-Path -LiteralPath $path))'),
            @("`$receipt.State -cnotin @('Passed','Failed')",'$false'),
            @("`$_ -ceq 'Passed'","`$_ -ceq 'Failed'")
        )
        $killed=0
        foreach($mutation in $mutations){
            if(!$source.Contains($mutation[0])){throw 'CompanionReportMutationAnchorMissing'}
            $rejected=$false
            try{& $oracle ([scriptblock]::Create($source.Replace($mutation[0],$mutation[1]))) ('mutant-'+$killed)}catch{if($_.Exception.Message -like 'Companion*' -or $_.Exception.GetBaseException() -is [IO.IOException]){$rejected=$true}else{throw}}
            if(!$rejected){throw 'CompanionReportMutantSurvived'}
            $killed++
        }
        [pscustomobject]@{GeneratedReceipts=32;RepeatedPolls=32;MalformedCases=4;MutantsKilled=$killed;MutableStatusRead=$false}
    } $RunDirectory $WorkspaceRoot
}
