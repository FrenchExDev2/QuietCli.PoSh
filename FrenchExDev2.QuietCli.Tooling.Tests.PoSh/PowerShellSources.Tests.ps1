function Test-QuietPowerShellSourcePolicy {
    <#
    .SYNOPSIS
    Exercises inert source checking, nested help regressions, invalid syntax and prepared-index commit rejection.
    .PARAMETER WorkspaceRoot
    Checkout supplying the shared checker and commit implementation.
    .PARAMETER RunDirectory
    Owned temporary fixtures and evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PowerShellSources.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/ScriptReview.psm1')) -DisableNameChecking -ErrorAction Stop
    $review=@(Get-QuietScriptReview $WorkspaceRoot|Where-Object Path -ceq 'scripts/Test-PowerShellSources.ps1')
    if($review.Count -ne 1 -or $review[0].Mode -cne 'ReadOnly' -or $review[0].NeedsGuard){throw 'PowerShellSourcePreviewClassificationChanged'}
    $fixture=[IO.Path]::Combine($RunDirectory,'source-check-fixture')
    $project=[IO.Path]::Combine($fixture,'FrenchExDev2.QuietCli.Fixture.PoSh')
    [void][IO.Directory]::CreateDirectory($project)
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($fixture,'scripts'))
    $utf8=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText([IO.Path]::Combine($project,'FrenchExDev2.QuietCli.Fixture.PoSh.psd1'),"@{ModuleVersion='1.0.0'}`n",$utf8)
    $path=[IO.Path]::Combine($project,'Fixture.ps1')
    $valid=@'
throw 'InspectedSourceWasExecuted'
function Get-Fixture {
    <#
    .SYNOPSIS
    Reads an inert Unicode fixture: é漢.
    #>
    param()
    function script:Invoke-WorkspaceNative {
        <#
        .SYNOPSIS
        Simulates the native boundary without running a command.
        #>
        param($FilePath,$Arguments,$WorkingDirectory)
    }
}
'@
    $badHelp=$valid.Replace("        <#`n        .SYNOPSIS`n        Simulates the native boundary without running a command.`n        #>`n",'')
    if($badHelp -ceq $valid){throw 'PowerShellSourceHelpAnchorMissing'}
    $oracle={
        param($subject)
        foreach($index in 1..32){
            [IO.File]::WriteAllText($path,($valid.Replace('é漢',('é漢'+$index))+"`n"),$utf8)
            $r=& $subject -WorkspaceRoot $fixture
            if($r.Files -ne 1 -or $r.Functions -ne 2){throw 'PowerShellSourceInventoryMismatch'}
        }
        foreach($bad in @(@{Text=$badHelp;Error='Unreadable function help:*script:Invoke-WorkspaceNative'},@{Text='function Get-Broken {';Error='PowerShell syntax:*'},@{Text='filter Get-Undocumented { $_ }';Error='Unreadable function help:*'})){
            [IO.File]::WriteAllText($path,($bad.Text+"`n"),$utf8)
            $rejected=$false
            try{$null=& $subject -WorkspaceRoot $fixture}catch{if($_.Exception.Message -like $bad.Error){$rejected=$true}elseif($_.Exception.Message -like 'Unreadable function help:*' -or $_.Exception.Message -like 'PowerShell syntax:*'){throw 'PowerShellSourceWrongDiagnostic'}else{throw}}
            if(!$rejected){throw 'PowerShellSourceInvalidAccepted'}
        }
    }
    $null=& $oracle (Get-Command Test-QuietPowerShellSources)
    [IO.File]::WriteAllBytes($path,[byte[]]@(195,40))
    $rejected=$false;try{$null=Test-QuietPowerShellSources -WorkspaceRoot $fixture}catch{$rejected=$true}
    if(!$rejected){throw 'PowerShellSourceInvalidEncodingAccepted'}
    $source=(Get-Command Test-QuietPowerShellSources).Definition
    $mutants=@(
        @('if($errors.Count)','if($false)'),
        @('if(!$help -or [string]::IsNullOrWhiteSpace($help.Synopsis))','if($false)'),
        @('FunctionDefinitionAst]},$true)','FunctionDefinitionAst]},$false)')
    )
    $killed=0
    foreach($mutation in $mutants){
        if(!$source.Contains($mutation[0])){throw 'PowerShellSourceMutationAnchorMissing'}
        $rejected=$false
        try{$null=& $oracle ([scriptblock]::Create($source.Replace($mutation[0],$mutation[1])))}catch{if($_.Exception.Message -like 'PowerShellSource*'){$rejected=$true}else{throw}}
        if(!$rejected){throw 'PowerShellSourceMutantSurvived'}
        $killed++
    }
    [IO.File]::WriteAllText($path,($valid+"`n"),$utf8)
    $registry=[IO.Path]::Combine($WorkspaceRoot,'scripts/Invoke-WorkspaceChecks.ps1')
    $null=& $registry -WorkspaceRoot $fixture -Check PowerShellSources
    [IO.File]::WriteAllText($path,($badHelp+"`n"),$utf8)
    $rejected=$false;try{$null=& $registry -WorkspaceRoot $fixture -Check PowerShellSources}catch{$rejected=$_.Exception.Message -like 'Unreadable function help:*'}
    if(!$rejected){throw 'PowerShellSourceRegistryAcceptedRegression'}
    $realScripts=[IO.Path]::Combine($WorkspaceRoot,'scripts')
    $commitFixture=New-QuietCommitWorkspaceFixture -Root $RunDirectory -RealScriptsPath $realScripts
    $defect=[IO.Path]::Combine($commitFixture,'FrenchExDev2.QuietCli.Core.PoSh/Undocumented.ps1')
    [IO.File]::WriteAllText($defect,($badHelp+"`n"),$utf8)
    $null=& ([IO.Path]::Combine($realScripts,'Update-WorkspaceLock.ps1')) -WorkspaceRoot $commitFixture
    $null=Invoke-WorkspaceNative git @('-C',$commitFixture,'add','--all','--') $commitFixture
    $index=[IO.Path]::Combine($commitFixture,'.git/index')
    $before=(Get-FileHash -LiteralPath $index).Hash
    # An unstaged repair must not hide the defect in the prepared index.
    [IO.File]::WriteAllText($defect,($valid+"`n"),$utf8)
    $rejected=$false
    try{$null=& ([IO.Path]::Combine($realScripts,'Commit-Workspace.ps1')) -WorkspaceRoot $commitFixture -Message 'Reject undocumented staged function' -NoAll -WhatIf -SkipCheck @('ScriptLayout','TestCaseMetadata','ScriptsReadme','GitHubWorkflowDocs','ScriptShouldProcess','Resources','ScriptContracts','DocsCredits','Credits')}catch{$rejected=$_.Exception.Message -like 'Unreadable function help:*'}
    if(!$rejected -or (Get-FileHash -LiteralPath $index).Hash -cne $before){throw 'PowerShellSourcePreparedIndexRegression'}
    $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $workflow=$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($WorkspaceRoot,'.github/workflows/companions-ci.yml'),[Text.Encoding]::UTF8))
    $job=$workflow['jobs']['source-checks']
    if(!$job -or $job.ContainsKey('needs') -or $job.ContainsKey('if') -or @($workflow['jobs']['ci-status']['needs']) -cnotcontains 'source-checks'){throw 'PowerShellSourceEarlyJobMissing'}
    if((@($job['steps']|ForEach-Object {[string]$_['run']}) -join "`n") -notmatch 'Invoke-WorkspaceChecks.ps1 -Check PowerShellSources'){throw 'PowerShellSourceEarlyCheckChanged'}
    if((@($workflow['jobs']['ci-status']['steps']|ForEach-Object {[string]$_['run']}) -join "`n").IndexOf("if(`$jobs['source-checks'].result -cne 'success')",[StringComparison]::Ordinal) -lt 0){throw 'PowerShellSourceSkippedJobAccepted'}
    [pscustomobject]@{GeneratedSources=32;MalformedSources=3;MutantsKilled=$killed;PreparedIndexRejected=$true;PreviewPreservedIndex=$true;InspectedSourcesExecuted=$false}
}
