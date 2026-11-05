function Invoke-QuietGitPushMutation {
    <#
    .SYNOPSIS
    Builds source-checked push mutants in owned artifact directories and requires assertion failures.
    .PARAMETER WorkspaceRoot
    Monorepo root containing the production parser and its independent tests.
    .PARAMETER Catalogue
    Source-checked push or repository command mutation catalogue.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[ValidateSet('Push','Repository')][string]$Catalogue='Push')
    $ErrorActionPreference='Stop'
    . (Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1')
    $run=Join-Path $WorkspaceRoot ('artifacts/git-'+$Catalogue.ToLowerInvariant()+'-mutation/'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run)
    $staging=Join-Path ([IO.Path]::GetTempPath()) ('qgpm-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($staging)
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'global.json') -Destination $staging
    $production=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/engine'
    $tests=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests'

    $mutants=@(
        @{Name='remote-case';From='StringComparison.OrdinalIgnoreCase';To='StringComparison.Ordinal'},
        @{Name='remote-value';From='line[3..]';To='line[4..]'},
        @{Name='cr-preservation';From="text.TrimEnd('\r')";To='text'},
        @{Name='flag-rejection';From='" =*+!-"';To='" =*+-"'},
        @{Name='acceptance';From="line[0] != '!'";To="line[0] == '!'"},
        @{Name='source-boundary';From='line[2..colon]';To='line[1..colon]'},
        @{Name='target-boundary';From='line[(colon + 1)..tab]';To='line[colon..tab]'},
        @{Name='summary-boundary';From='line[(tab + 1)..]';To='line[tab..]'}
    )
    foreach($mutation in $mutants){$mutation.File='GitPush.cs'}
    if($Catalogue -eq 'Repository'){
        $mutants=@(
            @{Name='config-null';File='GitConfigRecords.cs';From='split >= 0';To='split < 0'},
            @{Name='config-value';File='GitConfigRecords.cs';From='record[(split + 1)..]';To='record[split..]'},
            @{Name='config-key';File='GitConfigRecords.cs';From='if (key.Length == 0)';To='if (false)'},
            @{Name='remote-name';File='GitRemoteRecords.cs';From='record[..tab]';To='record[..(tab + 1)]'},
            @{Name='remote-push';File='GitRemoteRecords.cs';From='direction = "push"';To='direction = "fetch"'},
            @{Name='remote-url';File='GitRemoteRecords.cs';From='suffix = 7';To='suffix = 8'},
            @{Name='operation-success';File='GitOperationOutcome.cs';From='exitCode == 0';To='exitCode != 0'},
            @{Name='operation-conflict';File='GitOperationOutcome.cs';From='conflicts > 0';To='conflicts < 0'}
        )
    }
    $results=[Collections.Generic.List[object]]::new()
    try {
        foreach($mutation in @(@{Name='baseline';From=$null;To=$null})+$mutants){
            $directory=Join-Path $run $mutation.Name
            [void][IO.Directory]::CreateDirectory($directory)
            $stage=Join-Path $staging $mutation.Name
            $engine=Join-Path $stage 'FrenchExDev2.QuietCli.Git.PoSh/engine'
            $testDirectory=Join-Path $stage 'FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests'
            [void][IO.Directory]::CreateDirectory($engine)
            [void][IO.Directory]::CreateDirectory($testDirectory)
            foreach($file in Get-ChildItem -LiteralPath $production -File | Where-Object Extension -In @('.cs','.csproj')){Copy-Item -LiteralPath $file.FullName -Destination $engine}
            foreach($file in Get-ChildItem -LiteralPath $tests -File | Where-Object Extension -In @('.cs','.csproj')){Copy-Item -LiteralPath $file.FullName -Destination $testDirectory}
            if($mutation.From){
                $source=[IO.File]::ReadAllTextAsync((Join-Path $production $mutation.File),[Text.Encoding]::UTF8).GetAwaiter().GetResult()
                if(([regex]::Matches($source,[regex]::Escape($mutation.From))).Count -ne 1){throw ('MutationSourceMismatch: '+$mutation.Name)}
                [void][IO.File]::WriteAllTextAsync((Join-Path $engine $mutation.File),$source.Replace($mutation.From,$mutation.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            }
            $log=[Collections.Generic.List[string]]::new()
            $observer={param($record,$state)$state.Add($record.Text)}
            $build=Invoke-CiProcess dotnet @('build',(Join-Path $testDirectory 'QuietCli.Git.Parser.Tests.csproj'),'-c','Release','-o',(Join-Path $stage 'out'),'--nologo') -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 120 -OnOutput $observer -State $log
            [void][IO.File]::WriteAllLinesAsync((Join-Path $directory 'build.log'),$log,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if($build.ExitCode -ne 0){throw ('InvalidMutationBuild: '+$mutation.Name)}
            $log.Clear()
            $execution=Invoke-CiProcess dotnet @((Join-Path $stage 'out/QuietCli.Git.Parser.Tests.dll'),(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/Git.ArgumentSchema.json')) -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 60 -OnOutput $observer -State $log
            [void][IO.File]::WriteAllLinesAsync((Join-Path $directory 'tests.log'),$log,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if($execution.Outcome -eq 'Timeout'){throw ('MutationTimeout: '+$mutation.Name)}
            $report=($log -join "`n") | ConvertFrom-Json -ErrorAction Stop
            $pushFailures=@($report.Cases | Where-Object {$_.State -eq 'Failed' -and $_.Name.StartsWith($(if($Catalogue -eq 'Push'){'push '}else{'repository '}))})
            if($mutation.Name -eq 'baseline'){
                if($execution.ExitCode -ne 0 -or $report.Failed -ne 0 -or $report.Passed -ne 22){throw 'MutationBaselineFailed'}
                $state='BaselinePassed'
            }else{
                if($execution.ExitCode -ne 1 -or $pushFailures.Count -eq 0){throw ('MutationSurvivedOrCrashed: '+$mutation.Name)}
                $state='Killed'
            }
            $results.Add([pscustomobject]@{Name=$mutation.Name;State=$state;FailedCases=$pushFailures.Name;ExitCode=$execution.ExitCode})
        }
    }catch{
        $message=$_.Exception.Message
        $failureState=if($message.StartsWith('InvalidMutationBuild:')){'Invalid'}elseif($message.StartsWith('MutationTimeout:')){'Timeout'}elseif($message.StartsWith('MutationSurvivedOrCrashed:') -and $execution.ExitCode -eq 0){'Survived'}else{'InfrastructureError'}
        $results.Add([pscustomobject]@{Name=$mutation.Name;State=$failureState;Error=$message})
        throw
    }finally{
        $summary=[ordered]@{Catalogue=$Catalogue;StagingDirectory=$staging;Sources=@(foreach($file in @($mutants.File|Sort-Object -Unique)){@{File=$file;SHA256=(Get-FileHash -LiteralPath (Join-Path $production $file)).Hash}});Selected=$mutants.Count;Killed=@($results|Where-Object State -EQ Killed).Count;Completed=$results.Count;Survived=@($results|Where-Object State -EQ Survived).Count;Invalid=@($results|Where-Object State -EQ Invalid).Count;Timeout=@($results|Where-Object State -EQ Timeout).Count;InfrastructureError=@($results|Where-Object State -EQ InfrastructureError).Count;Results=$results.ToArray()}
        [void][IO.File]::WriteAllTextAsync((Join-Path $run 'summary.json'),($summary|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    return $run
}
