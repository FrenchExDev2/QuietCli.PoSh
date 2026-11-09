function Test-QuietWorkstationResources {
    <#
    .SYNOPSIS
    Checks ownership, PID reuse, deletion boundaries, hostile metadata and resource policy mutations.
    .PARAMETER WorkspaceRoot
    Repository containing the resource lifecycle module.
    .PARAMETER RunDirectory
    Owned external fixture/report directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $path=Join-Path $WorkspaceRoot 'scripts/lib/WorkstationResources.psm1'
    $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace(". (Join-Path `$PSScriptRoot '../Ci.Process.ps1')",'# Independent native boundary fixture.')
    $verify={param($candidate,$output)
        $module=New-Module -Name ('ResourceFixture'+[guid]::NewGuid().ToString('N')) -ScriptBlock ([scriptblock]::Create($candidate))
        try{& $module {
            param($output)
            [void][IO.Directory]::CreateDirectory($output)
            $run=Join-Path $output 'owned-run';[void][IO.Directory]::CreateDirectory($run)
            $receipt=Register-WorkstationRun $run $output
            if((Get-WorkstationCleanupDecision $run $output).State -cne 'Active'){throw 'Live worker is not protected'}
            $reuse=@{Host=[Environment]::MachineName;ProcessId=$PID;ProcessStartedUtc=[DateTimeOffset]::UtcNow.AddDays(-5).ToString('o')}
            if(Test-WorkstationOwnerActive $reuse){throw 'Reused PID treated as original worker'}
            if(!(Test-WorkstationOwnerActive @{Host='unknown-host';ProcessId=123;ProcessStartedUtc='invalid'})){throw 'Foreign ownership unprotected'}
            $receipt.Owner.ProcessId=[int]::MaxValue;$receipt.State='Success';Write-WorkstationOwnership $run $receipt
            if((Get-WorkstationCleanupDecision $run $output).State -cne 'Inactive'){throw 'Terminated owner was not recognized'}
            if((Get-WorkstationCleanupDecision $run ($output+'-other')).State -cne 'Protected'){throw 'Foreign workspace accepted'}
            if(!(Test-WorkstationDirectoryBoundary $output $run)){throw 'Owned run boundary rejected'}
            $existingSibling=$output+'-escape';[void][IO.Directory]::CreateDirectory($existingSibling)
            if(Test-WorkstationDirectoryBoundary $output $existingSibling){throw 'Existing sibling deletion boundary accepted'}
            $random=[Random]::new(604331)
            for($i=0;$i -lt 256;$i++){
                $sibling=$output+'-escape-'+$random.Next()
                if(Test-WorkstationDirectoryBoundary $output $sibling){throw 'Sibling deletion boundary accepted'}
            }
            foreach($bad in @('',"{`"SchemaVersion`":1}",'{','[]','null',('x'*4096))){
                [void][IO.File]::WriteAllTextAsync((Join-Path $run 'ownership.json'),$bad,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $decision=Get-WorkstationCleanupDecision $run $output
                if($decision.State -notin @('Protected','Unmanaged')){throw 'Malformed ownership accepted'}
            }
            $script:Removed=0;$script:ActualLabel='foreign';$script:Running=$false;$script:Consumer=''
            function script:Invoke-WorkstationResourceCommand {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>

                param($Arguments)
                if($Arguments -contains '--force'){throw 'Forced cleanup is forbidden'}
                if($Arguments[0] -ceq 'ps'){return [pscustomobject]@{Outcome='Success';ExitCode=0;Text=$script:Consumer}}
                if($Arguments[1] -ceq 'rm'){$script:Removed++;return [pscustomobject]@{Outcome='Success';ExitCode=0;Text='removed'}}
                $text=@{Labels=@{'io.frenchexdev.quietcli.workstation.run'=$script:ActualLabel};Config=@{Labels=@{'io.frenchexdev.quietcli.workstation.run'=$script:ActualLabel}};State=@{Running=$script:Running}}|ConvertTo-Json -Depth 6 -Compress
                [pscustomobject]@{Outcome='Success';ExitCode=0;Text=$text}
            }
            $resource=@{Kind='Container';Name='quietcli-workstation-fixture';Label='owned-run'}
            if((Remove-WorkstationOwnedResource $resource) -cne 'Foreign' -or $script:Removed){throw 'Foreign resource removed'}
            $script:ActualLabel='owned-run';$script:Running=$true
            if((Remove-WorkstationOwnedResource $resource) -cne 'InUse' -or $script:Removed){throw 'Active container removed'}
            $script:Running=$false
            if((Remove-WorkstationOwnedResource $resource -Preview) -cne 'Eligible' -or $script:Removed){throw 'Preview removed a resource'}
            if((Remove-WorkstationOwnedResource $resource) -cne 'Removed' -or $script:Removed -ne 1){throw 'Owned inactive resource not released'}
            $resource.Kind='Image';$script:Consumer='retained-consumer'
            if((Remove-WorkstationOwnedResource $resource) -cne 'InUse' -or $script:Removed -ne 1 -or $resource.Consumers[0] -cne 'retained-consumer'){throw 'Image consumer not protected or identified'}
            $script:Consumer=''
            if((Remove-WorkstationOwnedResource $resource -Preview) -cne 'Eligible' -or $script:Removed -ne 1){throw 'Image preview changed a resource'}
            if((Remove-WorkstationOwnedResource $resource) -cne 'Removed' -or $script:Removed -ne 2){throw 'Unused owned image not released'}
        } $output}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
    }
    & $verify $source (Join-Path $RunDirectory 'resource-baseline')
    $mutations=@(
        @{Id='delete-sibling-path';Find='if(!$pathFull.StartsWith(';Replace='if($false -and !$pathFull.StartsWith('},
        @{Id='trust-foreign-label';Find="if(`$labels.'io.frenchexdev.quietcli.workstation.run' -cne `$Resource.Label)";Replace='if($false)'},
        @{Id='remove-running-container';Find="if(`$kind -ceq 'container' -and `$record.State.Running)";Replace='if($false)'},
        @{Id='mutate-in-preview';Find='if($Preview){return ''Eligible''}';Replace='if($false){return ''Eligible''}'},
        @{Id='ignore-live-owner';Find='if(Test-WorkstationOwnerActive $receipt.Owner)';Replace='if($false)'},
        @{Id='force-resource-removal';Find='@($kind,''rm'',$Resource.Name)';Replace='@($kind,''rm'',''--force'',$Resource.Name)'},
        @{Id='ignore-image-consumer';Find='if($references.Text.Trim())';Replace='if($false)'}
    )
    foreach($mutation in $mutations){$candidate=$source.Replace($mutation.Find,$mutation.Replace);if($candidate -ceq $source){throw ('InvalidResourceMutant: '+$mutation.Id)};$killed=$false;try{& $verify $candidate (Join-Path $RunDirectory ('resource-'+$mutation.Id))}catch{$killed=$true};if(!$killed){throw ('ResourceMutantSurvived: '+$mutation.Id)}}
    # Real filesystem cleanup stays inside an independently named disposable workspace/report root.
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/WorkstationResources.psm1')
    . (Join-Path $WorkspaceRoot 'scripts/ReportPaths.ps1')
    $fixtureWorkspace=Join-Path $RunDirectory ('cleanup-workspace-'+[guid]::NewGuid().ToString('N'))
    $fixtureRoot=Get-QuietReportRoot $fixtureWorkspace workstation -ContinuousIntegration $false
    $fixtureRun=Join-Path $fixtureRoot 'owned-cleanup-fixture'
    [void][IO.Directory]::CreateDirectory($fixtureRun)
    $receipt=Register-WorkstationRun $fixtureRun $fixtureWorkspace
    $receipt.Owner.ProcessId=[int]::MaxValue;$receipt.State='Success';$receipt.FinishedUtc=[DateTimeOffset]::UtcNow.AddDays(-30).ToString('o')
    [void][IO.File]::WriteAllTextAsync((Join-Path $fixtureRun 'ownership.json'),($receipt|ConvertTo-Json -Depth 10)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $leasePath=Join-Path $fixtureRun 'run.lease'
    $lease=[IO.FileStream]::new($leasePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    $cleanup=Join-Path $WorkspaceRoot 'scripts/Remove-DevelopmentWorkstationRun.ps1'
    try{$locked=@(& $cleanup -WorkspaceRoot $fixtureWorkspace -RetentionDays 0 -KeepLatest 0 -ActiveGraceMinutes 0 -Confirm:$false);if($locked[0].State -cne 'Protected' -or !(Test-Path -LiteralPath $fixtureRun)){throw 'Cleanup ignored a live lease'}}finally{$lease.Dispose()}
    $preview=@(& $cleanup -WorkspaceRoot $fixtureWorkspace -RetentionDays 0 -KeepLatest 0 -ActiveGraceMinutes 0 -WhatIf)
    if($preview[0].State -cne 'Eligible' -or !(Test-Path -LiteralPath $fixtureRun)){throw 'Cleanup WhatIf changed the filesystem'}
    $removed=@(& $cleanup -WorkspaceRoot $fixtureWorkspace -RetentionDays 0 -KeepLatest 0 -ActiveGraceMinutes 0 -Confirm:$false)
    if($removed[0].State -cne 'Removed' -or (Test-Path -LiteralPath $fixtureRun)){throw 'Inactive owned fixture cleanup failed'}
    $enclosingCleanup=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot '../../../../scripts/Invoke-ArtifactsCleanup.ps1'))
    $enclosingChecked=$false
    if(Test-Path -LiteralPath $enclosingCleanup){
        $scripts=Join-Path $fixtureWorkspace 'scripts';[void][IO.Directory]::CreateDirectory($scripts)
        $copiedCleanup=Join-Path $scripts 'Invoke-ArtifactsCleanup.ps1';Copy-Item -LiteralPath $enclosingCleanup -Destination $copiedCleanup
        $old=[DateTime]::UtcNow.AddDays(-30)
        foreach($name in @('active','expired')){
            $directory=Join-Path $fixtureWorkspace ('.artifacts/tests/'+$name);[void][IO.Directory]::CreateDirectory($directory)
            $status=Join-Path $directory 'status.json'
            [void][IO.File]::WriteAllTextAsync($status,(@{State=$(if($name -ceq 'active'){'Running'}else{'Success'});ProcessId=$(if($name -ceq 'active'){$PID}else{[int]::MaxValue})}|ConvertTo-Json),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            [IO.File]::SetLastWriteTimeUtc($status,$old)
        }
        $null=& $copiedCleanup -RetentionDays 0 -KeepLatest 0 -ActiveGraceMinutes 0 -SkipQuietCliWorkstation -WhatIf
        if(!(Test-Path -LiteralPath (Join-Path $fixtureWorkspace '.artifacts/tests/expired'))){throw 'Enclosing cleanup WhatIf removed evidence'}
        $null=& $copiedCleanup -RetentionDays 0 -KeepLatest 0 -ActiveGraceMinutes 0 -SkipQuietCliWorkstation -Confirm:$false
        if(!(Test-Path -LiteralPath (Join-Path $fixtureWorkspace '.artifacts/tests/active')) -or (Test-Path -LiteralPath (Join-Path $fixtureWorkspace '.artifacts/tests/expired'))){throw 'Enclosing cleanup did not distinguish live and expired workers'}
        $enclosingChecked=$true
    }
    $report=@{State='Success';Seed=604331;PropertyExecutions=256;MalformedInputs=6;MutantsKilled=$mutations.Count;FilesystemCleanup='Passed';EnclosingWorkspaceCleanup=$enclosingChecked;Scope='Ownership/native-boundary fixtures and owned disposable directory deletion; no user artifact or real Podman resource deletion'}
    [void][IO.File]::WriteAllTextAsync((Join-Path $RunDirectory 'workstation-resources.json'),($report|ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [pscustomobject]$report
}
