#requires -Version 7.6
# Companion fragment: owned fixtures, real builds, properties, malformed inputs and source-checked mutants.
$dotNetModulePath=Join-Path $WorkspaceRoot 'scripts/lib/Migration.DotNet.psm1'
$dotNetModule=Import-Module $dotNetModulePath -PassThru -Force
$dotNetRoot=Join-Path $RunDirectory 'dotnet-fixture'
$dotNetPolicy=Join-Path $RunDirectory 'dotnet-policy.json'
$dotNetCandidate=Join-Path $dotNetRoot 'Net/FrenchExDev/Selected'
$policy=[pscustomobject]@{schemaVersion=1;default='Exclude';items=@([pscustomobject]@{id='Selected';path='Net/FrenchExDev/Selected';intent='Assess';approved=$false})}
Write-MigrationFixtureText $dotNetPolicy (ConvertTo-Json $policy -Depth 12)
$project='<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'Good/Good.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'Good/Subject.cs') "#if DEBUG`n#error Release configuration required`n#endif`npublic static class Subject { public static int Value => 42; }`n"
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'Broken/Broken.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'Broken/Subject.cs') 'public class Broken { deliberately invalid code; }'
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'Selected.slnx') '<Solution><Project Path="Good/Good.csproj"/><Project Path="Broken/Broken.csproj"/></Solution>'
Write-MigrationFixtureText (Join-Path $dotNetRoot 'Net/FrenchExDev/Unselected/Other.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'obj/generated.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetCandidate 'StrykerOutput/generated.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetRoot 'Net/FrenchExDev/.fake/generated.csproj') $project
Write-MigrationFixtureText (Join-Path $dotNetRoot 'Net/FrenchExDev/NuGet.Config') '<configuration><packageSources><clear/></packageSources></configuration>'
$plan=Get-DotNetMigrationBuildPlan -SourceRoot $dotNetRoot -PolicyPath $dotNetPolicy
Assert-Case 'dotnet discovers solutions and projects while excluding generated trees' ($plan.DiscoveredCount -eq 4 -and $plan.SelectedCount -eq 3 -and @($plan.Results | Where-Object State -CEQ NotSelected).Count -eq 1)
Assert-Case 'dotnet build command has an explicit Release argument and no shell command' (@($plan.Results | Where-Object { $_.Arguments -cnotcontains 'Release' -or $_.Arguments[0] -cne 'build' -or $_.Executable -cne 'dotnet' }).Count -eq 0)
$all=Get-DotNetMigrationBuildPlan $dotNetRoot $dotNetPolicy -AllDiscovered
Assert-Case 'all discovered assessment is explicit and does not approve migration' ($all.SelectedCount -eq 4 -and !$all.Passed -and $all.Scope.Contains('does not approve migration'))
$specific=Get-DotNetMigrationBuildPlan $dotNetRoot $dotNetPolicy -Target 'Selected/Good/Good.csproj' -NoRestore
Assert-Case 'exact target and no-restore are forwarded without changing project configuration' ($specific.SelectedCount -eq 1 -and ($specific.Results | Where-Object Selected).Arguments -ccontains '--no-restore')
$previewRun=Join-Path $RunDirectory 'dotnet-preview'
$previewJson=Join-Path $RunDirectory 'dotnet-preview.json'
$preview=Invoke-DotNetMigrationBuild $dotNetRoot $dotNetPolicy -RunDirectory $previewRun -JsonPath $previewJson -WorkspaceRoot $WorkspaceRoot -WhatIf
Assert-Case 'dotnet WhatIf starts no worker and creates no report or build output' ($preview.Mode -ceq 'WhatIf' -and !(Test-Path $previewRun) -and !(Test-Path $previewJson) -and !(Test-Path (Join-Path $dotNetCandidate 'Good/bin')))
$json=& (Join-Path $WorkspaceRoot 'scripts/Test-DotNetMigrationBuild.ps1') -SourceRoot $dotNetRoot -PolicyPath $dotNetPolicy -WhatIf -OutputFormat Json
$parsed=$json | ConvertFrom-Json -Depth 32
Assert-Case 'facade WhatIf JSON is parseable with no incidental pipeline output' ($json -is [string] -and $parsed.Mode -ceq 'WhatIf' -and $parsed.Configuration -ceq 'Release')
$lines=@(Format-DotNetMigrationBuildTable $preview -Width 80)
Assert-Case 'dotnet static table uses Unicode framing at the requested width' (@($lines | Where-Object {$_.StartsWith('┌')}).Count -eq 1 -and @($lines | Where-Object Length -NE 80).Count -eq 0 -and ($lines -join "`n").Contains('Duration') -and $lines[0].StartsWith('Projet :'))
Assert-Case 'human table shows selected entries while JSON retains full discovery' (!(($lines -join "`n").Contains('Unselected/Other.csproj')) -and $preview.Results.Count -eq 4)
$cell=& $dotNetModule {Format-DotNetBuildCell '中é' 6}
Assert-Case 'table preserves accents and aligns wide graphemes' ($cell -ceq "中é   ")
foreach($bad in @('../escape.csproj','C:/escape.csproj','*.csproj',"bad`n.csproj",'Missing.csproj','Unselected/Other.csproj')){
    $rejected=try{$null=Get-DotNetMigrationBuildPlan $dotNetRoot $dotNetPolicy -Target $bad;$false}catch{$true}
    Assert-Case "dotnet target refuses malformed unknown or unselected path $($cases.Count)" $rejected fuzz
}
$rejected=try{$null=Get-DotNetMigrationBuildPlan $dotNetRoot $dotNetPolicy -ItemId Unknown;$false}catch{$true}
Assert-Case 'dotnet unknown whitelist identifier refused' $rejected fuzz
$rejected=try{$null=Get-DotNetMigrationBuildPlan $dotNetRoot $dotNetPolicy -Target @();$false}catch{$true}
Assert-Case 'empty explicit dotnet selection does not expand to all targets' $rejected fuzz
$rejected=try{$null=Invoke-DotNetMigrationBuild $dotNetRoot $dotNetPolicy -Target @() -WorkspaceRoot $WorkspaceRoot -WhatIf;$false}catch{$true}
Assert-Case 'executor preserves an explicitly empty target refusal' $rejected fuzz
for($iteration=0;$iteration -lt 24;$iteration++){
    $outcome=@('Success','Failed','Timeout')[$iteration%3];$exitCode=$iteration-8
    $observed=& $dotNetModule {param($o,$e) Get-DotNetBuildOutcome ([pscustomobject]@{Outcome=$o;ExitCode=$e})} $outcome $exitCode
    Assert-Case "nonzero native build cannot pass $iteration" ($exitCode -eq 0 -or $observed -cne 'Success') property
    Assert-Case "failed or timed-out native build cannot pass $iteration" ($outcome -ceq 'Success' -or $observed -cne 'Success') property
}
$build=Invoke-DotNetMigrationBuild -SourceRoot $dotNetRoot -PolicyPath $dotNetPolicy -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory 'dotnet-real-build') -TimeoutSeconds 90 -TotalTimeoutSeconds 240 -Confirm:$false
$success=@($build.Results | Where-Object { $_.RelativePath -ceq 'Selected/Good/Good.csproj' })
$broken=@($build.Results | Where-Object { $_.RelativePath -ceq 'Selected/Broken/Broken.csproj' })
Assert-Case 'real Release build compiles a guarded C# fixture' ($success.Count -eq 1 -and $success[0].State -ceq 'Success' -and $success[0].ExitCode -eq 0 -and $success[0].SdkVersion)
Assert-Case 'real compile errors and dependent solution failures do not stop later targets' ($broken[0].State -ceq 'Failed' -and $broken[0].ExitCode -ne 0 -and $build.Complete -and !$build.Passed -and $success[0].State -ceq 'Success')
Assert-Case 'real build JSON and bounded logs are retained' ((Test-Path $build.ReportPath) -and (Get-Content $build.ReportPath -Raw -Encoding utf8 | ConvertFrom-Json).State -ceq 'Failed' -and (Test-Path $broken[0].LogPath))

# A real build is a mandatory additional gate for .NET entries, without erasing the static/evaluated-graph blockers.
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Migration.Dependencies.psm1') -Force
$dependency=Get-MigrationDependencyReport $dotNetRoot $dotNetPolicy
$dependencyPath=Join-Path $RunDirectory 'dotnet-static-dependencies.json'
Export-MigrationDependencyReport $dependency $dependencyPath -Confirm:$false
$gateWithoutBuild=Test-MigrationQualification $dependencyPath $gateSummary
Assert-Case 'migration gate requires real Release evidence for .NET entries' ('MissingDotNetReleaseBuildEvidence' -cin $gateWithoutBuild.Errors)
$gateWithFailedBuild=Test-MigrationQualification $dependencyPath $gateSummary -DotNetBuildReportPath $build.ReportPath
Assert-Case 'failed Release assessment cannot satisfy migration gate' ('DotNetReleaseBuildNotQualified' -cin $gateWithFailedBuild.Errors)

$source=Get-Content $dotNetModulePath -Raw -Encoding utf8
$mutants=@(
    @{Name='Release configuration';From="'--configuration','Release'";To="'--configuration','Debug'";Witness='release'},
    @{Name='whitelist entry selection';From='$selected=($AllDiscovered -or $null -ne $owner) -and $matchTarget';To='$selected=$matchTarget';Witness='selection'},
    @{Name='native outcome';From="`$Native.Outcome -ceq 'Success' -and `$Native.ExitCode -eq 0";To='$Native.ExitCode -eq 0';Witness='outcome'}
)
foreach($mutation in $mutants){
    if(([regex]::Matches($source,[regex]::Escape($mutation.From))).Count -ne 1){throw "DotNetMutationTargetInvalid:$($mutation.Name)"}
    $mutantPath=Join-Path $RunDirectory ('DotNetMutant'+$mutation.Witness+'.psm1')
    Write-MigrationFixtureText $mutantPath ($source.Replace($mutation.From,$mutation.To))
    $mutant=Import-Module $mutantPath -PassThru -Force
    $killed=switch($mutation.Witness){
        release {$p=& $mutant {param($r,$p) Get-DotNetMigrationBuildPlan $r $p} $dotNetRoot $dotNetPolicy;($p.Results | Where-Object Selected | Select-Object -First 1).Arguments -ccontains 'Debug'}
        selection {(& $mutant {param($r,$p) Get-DotNetMigrationBuildPlan $r $p} $dotNetRoot $dotNetPolicy).SelectedCount -eq 4}
        outcome {(& $mutant {Get-DotNetBuildOutcome ([pscustomobject]@{Outcome='Failed';ExitCode=0})}) -ceq 'Success'}
    }
    $mutationResults.Add([pscustomobject]@{Name=$mutation.Name;Outcome=if($killed){'Killed'}else{'Survived'};SourceSha256=(Get-FileHash $mutantPath).Hash;Witness=$mutation.Witness})
    Assert-Case "dotnet mutant $($mutation.Name)" $killed mutation
    Remove-Module $mutant
}
Write-WorkspaceJson (Join-Path $RunDirectory 'mutations.json') $mutationResults.ToArray()
