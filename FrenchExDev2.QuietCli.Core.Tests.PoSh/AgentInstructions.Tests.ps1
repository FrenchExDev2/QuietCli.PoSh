function Test-QuietAgentReferenceProperties {
    <#
    .SYNOPSIS
    Verifies independent preservation/idempotence properties and malformed marker corpora.
    .PARAMETER Builder
    Production reference builder or one isolated source mutant.
    #>
    param([scriptblock]$Builder)
    $random=[Random]::new(73607)
    foreach($index in 1..48){
        $newline=if($index%2){"`n"}else{"`r`n"}
        $prefix="# Project é漢 $($random.Next())$newline";$suffix="$newline## Existing footer $index$newline"
        $original=$prefix+'<!-- quietcli:instructions:begin -->'+$newline+'old'+$newline+'<!-- quietcli:instructions:end -->'+$suffix
        $reference='./instructions é漢/#percent%/AGENTS.md'
        $updated=& $Builder -Text $original -Reference $reference
        if(!$updated.StartsWith($prefix) -or !$updated.EndsWith($suffix) -or !$updated.Contains('./instructions é漢/%23percent%25/AGENTS.md')){throw 'AgentReferencePreservation: seed 73607'}
        if((& $Builder -Text $updated -Reference $reference) -cne $updated){throw 'AgentReferenceNotIdempotent'}
        if([regex]::Matches($updated,'<!-- quietcli:instructions:begin -->').Count -ne 1){throw 'AgentReferenceDuplicated'}
        $fresh=& $Builder -Text '' -Reference $reference
        if($fresh.Contains("`r")){throw 'AgentReferenceNewFileNotLf'}
        foreach($bad in @(
            '<!-- quietcli:instructions:begin -->', '<!-- quietcli:instructions:end -->',
            '<!-- quietcli:instructions:end --><!-- quietcli:instructions:begin -->',
            '<!-- quietcli:instructions:begin --><!-- quietcli:instructions:begin --><!-- quietcli:instructions:end -->',
            '<!-- quietcli:instructions:begin --><!-- quietcli:instructions:end --><!-- quietcli:instructions:end -->'
        )){
            $rejected=$false;try{$null=& $Builder -Text ($prefix+$bad+$suffix) -Reference $reference}catch{$rejected=$true}
            if(!$rejected){throw 'AgentMalformedMarkersAccepted'}
        }
    }
}

function Test-QuietAgentDocumentSet {
    <#
    .SYNOPSIS
    Verifies the distributed documents from independent properties: concise, self-contained, complete and consistent.
    .DESCRIPTION
    Checks AGENTS.md (LF only, at most 150 lines, no relative link, Get-Help and repository pointers, every
    exported command named in backticks) and that SKILL.md equals the generated skill text for that AGENTS.md.
    Throws a stable error code on the first violation.
    .PARAMETER AgentsText
    Full AGENTS.md text.
    .PARAMETER SkillText
    Full SKILL.md text.
    .PARAMETER ExportedCommands
    Public Core commands that AGENTS.md must name.
    #>
    param([string]$AgentsText,[string]$SkillText,[string[]]$ExportedCommands)
    if($AgentsText.Contains("`r") -or $SkillText.Contains("`r")){throw 'AgentDocumentNotLf'}
    if(($AgentsText -split "`n").Count -gt 150){throw 'AgentDocumentNotConcise'}
    if([regex]::IsMatch($AgentsText,'\]\((?!https?://|#)')){throw 'AgentDocumentHasRelativeLink'}
    foreach($pointer in @('Get-Help','https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh')){
        if(!$AgentsText.Contains($pointer)){throw ('AgentDocumentMissingPointer: '+$pointer)}
    }
    foreach($command in $ExportedCommands){
        if(!$AgentsText.Contains('`'+$command+'`')){throw ('AgentDocumentMissingCommand: '+$command)}
    }
    if($SkillText -cne (New-QuietSkillDocumentText -AgentsText $AgentsText)){throw 'AgentSkillDiffersFromAgents'}
}

function Invoke-QuietAgentInstructionTests {
    <#
    .SYNOPSIS
    Qualifies production instruction copying, installed resources, malformed inputs and targeted mutations.
    .PARAMETER WorkspaceRoot
    QuietCli source root.
    .PARAMETER RunDirectory
    Owned report directory.
    .PARAMETER OnProgress
    Existing monitored launcher progress callback.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[scriptblock]$OnProgress)
    . (Join-Path $WorkspaceRoot 'scripts/AgentDocuments.ps1')
    $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    $root=Join-Path $RunDirectory 'agent-instructions';[void][IO.Directory]::CreateDirectory($root)
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    $cases=[ordered]@{};$results=[Collections.Generic.List[object]]::new();$mutations=[Collections.Generic.List[object]]::new()
    $campaign=@{Seed=73607;PropertyCases=48;MalformedMarkerCases=240;FilesystemProperties=24;MalformedFilesystemCases=0;MutantsKilled=0;MutantsTotal=9}
    $builder=& $core {(Get-Command Set-QuietAgentReferenceBlock).ScriptBlock}
    $cases['generated references preserve text, escaping, LF and idempotence; malformed markers fail']={Test-QuietAgentReferenceProperties $builder}
    $cases['project installation preserves BOM and existing rules across generated Unicode paths and targets']={
        foreach($index in 1..24){
            $project=Join-Path $root "project-$index-é漢 # space";[void][IO.Directory]::CreateDirectory($project)
            $newline=if($index%2){"`n"}else{"`r`n"};$original=[char]0xfeff+"# Existing rules $index$newline"
            [void][IO.File]::WriteAllTextAsync((Join-Path $project 'AGENTS.md'),$original,$utf8).GetAwaiter().GetResult()
            $installed=Add-QuietAgentInstruction -Path $project -Agents -Claude -Skill -DocumentDirectory 'instructions é漢 #percent%'
            if(@($installed.Files).Count -ne 3 -or @($installed.Documents).Count -ne 2){throw 'AgentInstallationMissingTargets'}
            $claudeText=[IO.File]::ReadAllTextAsync((Join-Path $project 'CLAUDE.md'),$utf8).GetAwaiter().GetResult()
            $skillTargetText=[IO.File]::ReadAllTextAsync((Join-Path $project 'SKILL.md'),$utf8).GetAwaiter().GetResult()
            if(!$claudeText.Contains('@./instructions\ é漢\ #percent%/AGENTS.md')){throw 'AgentClaudeImportMissing'}
            if(!$skillTargetText.Contains('instructions é漢 %23percent%25/SKILL.md') -or (Test-Path (Join-Path $project 'SKILLS.md'))){throw 'AgentSkillTargetWrong'}
            $path=Join-Path $project 'AGENTS.md';$text=[IO.File]::ReadAllTextAsync($path,$utf8).GetAwaiter().GetResult()
            if(!$text.StartsWith($original.TrimStart([char]0xfeff))){throw 'AgentExistingRulesLost'}
            $bytes=[IO.File]::ReadAllBytesAsync($path).GetAwaiter().GetResult()
            if($bytes[0] -ne 0xef -or $bytes[1] -ne 0xbb -or $bytes[2] -ne 0xbf){throw 'AgentBomLost'}
            $before=(Get-Item $path).LastWriteTimeUtc
            $again=Add-QuietAgentInstruction -Path $project -Agents -Claude -Skill -DocumentDirectory 'instructions é漢 #percent%'
            if(@($again.Files+$again.Documents|Where-Object Status -NE Unchanged).Count -or (Get-Item $path).LastWriteTimeUtc -ne $before){throw 'AgentRepeatedInstallRewroteFiles'}
            foreach($name in @('AGENTS.md','SKILL.md')){
                $expected=[IO.File]::ReadAllBytesAsync((Join-Path $WorkspaceRoot "docs/agents/$name")).GetAwaiter().GetResult()
                $actual=[IO.File]::ReadAllBytesAsync((Join-Path $project "instructions é漢 #percent%/$name")).GetAwaiter().GetResult()
                if([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($expected)){throw 'AgentCopyChangedProductionBytes'}
            }
        }
    }
    $cases['WhatIf and malformed targets preflight without partial writes']={
        $project=Join-Path $root 'preflight';[void][IO.Directory]::CreateDirectory($project)
        $preview=Add-QuietAgentInstruction -Path $project -Agents -WhatIf
        if((Test-Path (Join-Path $project '.skills')) -or (Test-Path (Join-Path $project 'AGENTS.md')) -or $preview.Files[0].Status -ne 'Simulated'){throw 'AgentWhatIfWroteFiles'}
        foreach($bad in @('<!-- quietcli:instructions:begin -->','<!-- quietcli:instructions:end -->')){
            [void][IO.File]::WriteAllTextAsync((Join-Path $project 'AGENTS.md'),$bad,$utf8).GetAwaiter().GetResult()
            $rejected=$false;try{$null=Add-QuietAgentInstruction -Path $project -Agents}catch{$rejected=$true}
            if(!$rejected -or (Test-Path (Join-Path $project '.skills'))){throw 'AgentMalformedPreflightWroteFiles'};$campaign.MalformedFilesystemCases++
        }
        [void][IO.File]::WriteAllBytesAsync((Join-Path $project 'AGENTS.md'),[byte[]]@(0xff,0xfe)).GetAwaiter().GetResult()
        $rejected=$false;try{$null=Add-QuietAgentInstruction -Path $project -Agents}catch{$rejected=$true}
        if(!$rejected -or (Test-Path (Join-Path $project '.skills'))){throw 'AgentInvalidUtf8Accepted'};$campaign.MalformedFilesystemCases++
        foreach($directory in @('.',"bad`nname")){
            $rejected=$false;try{$null=Add-QuietAgentInstruction -Path $project -Agents -DocumentDirectory $directory}catch{$rejected=$true}
            if(!$rejected){throw 'AgentConflictingDirectoryAccepted'};$campaign.MalformedFilesystemCases++
        }
        $rejected=$false;try{$null=Add-QuietAgentInstruction -Path $project}catch{$rejected=$true}
        if(!$rejected){throw 'AgentMissingSelectionAccepted'};$campaign.MalformedFilesystemCases++
    }
    $cases['linked instruction directory cannot redirect writes outside the project']={
        $project=Join-Path $root 'linked-project';$outside=Join-Path $root 'outside';[void][IO.Directory]::CreateDirectory($project);[void][IO.Directory]::CreateDirectory($outside)
        $kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
        $null=New-Item -ItemType $kind -Path (Join-Path $project '.skills') -Target $outside
        $rejected=$false;try{$null=Add-QuietAgentInstruction -Path $project -Agents}catch{$rejected=$_.Exception.Message -eq 'AgentInstructionLinkedPath'}
        if(!$rejected -or @(Get-ChildItem $outside -Force).Count){throw 'AgentLinkRedirectedWrite'}
    }
    $cases['production resources stage byte-for-byte and run after installation outside sources']={
        $stage=Join-Path $root 'installed/FrenchExDev2.QuietCli.Core.PoSh';[void][IO.Directory]::CreateDirectory($stage)
        $module=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
        foreach($name in @('FrenchExDev2.QuietCli.Core.PoSh.psd1','FrenchExDev2.QuietCli.Core.PoSh.psm1','protocol.json','runtime-targets.json','src','lib','resources')){Copy-Item -LiteralPath (Join-Path $module $name) -Destination $stage -Recurse}
        Copy-QuietProductionAgentDocuments $WorkspaceRoot $stage
        $expected=(Get-FileHash (Join-Path $WorkspaceRoot 'docs/agents/AGENTS.md') -Algorithm SHA256).Hash
        if((Get-FileHash (Join-Path $stage 'resources/agents/AGENTS.md') -Algorithm SHA256).Hash -cne $expected){throw 'AgentPackageResourceMismatch'}
        $project=Join-Path $root 'installed-project';[void][IO.Directory]::CreateDirectory($project)
        $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
        $result=quiet -AsObject -Role Infrastructure -RecordDelimiter "`n" -Data @{Success=$false} -Output {
            param($event,$runtime)
            if($event.Stream -eq 'stdout' -and $event.Text.StartsWith('@@AGENT@@')){$reply=$event.Text.Substring(9)|ConvertFrom-Json;$runtime.Data.Success=$reply.Success -and !$reply.EngineStarted}
        } -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-File',(Join-Path $PSScriptRoot 'AgentInstructions.Probe.ps1'),'-Manifest',(Join-Path $stage 'FrenchExDev2.QuietCli.Core.PoSh.psd1'),'-Project',$project,'-ExpectedHash',$expected)
        if($result.Outcome -ne 'Success' -or !$result.Data.Success -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('AgentInstalledProbeFailed: '+($result.Error|ConvertTo-Json -Compress))}
        $empty=Join-Path $root 'missing-resources/resources/agents';[void][IO.Directory]::CreateDirectory($empty)
        $rejected=& $core {param($temporary)$previous=$script:QuietRoot;try{$script:QuietRoot=$temporary;try{$null=Get-QuietAgentInstruction;$false}catch{$true}}finally{$script:QuietRoot=$previous}} (Split-Path (Split-Path $empty -Parent) -Parent)
        if(!$rejected){throw 'AgentMissingResourceUsedFallback'}
    }
    $cases['published skill examples produce verified business objects and offline Recall analyses']={
        . (Join-Path $PSScriptRoot 'PersistentShell.Support.ps1')
        $fixtureRoot=Join-Path $root 'skill-examples';[void][IO.Directory]::CreateDirectory($fixtureRoot)
        $config=Join-Path $fixtureRoot 'fixture.gitconfig';$hooks=Join-Path $fixtureRoot 'hooks';[void][IO.Directory]::CreateDirectory($hooks)
        [void][IO.File]::WriteAllTextAsync($config,"[core]`n hooksPath = $($hooks.Replace('\','/'))`n[commit]`n gpgsign = false`n",$utf8).GetAwaiter().GetResult()
        $environment=@{GIT_CONFIG_GLOBAL=$config;GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_COUNT='0';GIT_CEILING_DIRECTORIES=$fixtureRoot;GIT_TERMINAL_PROMPT='0';GIT_AUTHOR_NAME='Skill example';GIT_COMMITTER_NAME='Skill example';GIT_AUTHOR_EMAIL='skill@example.invalid';GIT_COMMITTER_EMAIL='skill@example.invalid';GIT_AUTHOR_DATE='2020-01-01T00:00:00+0000';GIT_COMMITTER_DATE='2020-01-01T00:00:00+0000'}
        $saved=@{};foreach($name in $environment.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,$environment[$name])}
        $controls=@('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_CONFIG_PARAMETERS','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_TEMPLATE_DIR')
        foreach($name in $controls){$saved[$name]=[Environment]::GetEnvironmentVariable($name);Remove-Item -LiteralPath ('Env:'+$name) -ErrorAction SilentlyContinue}
        try{
            $repository=New-QuietGitRepositoryFixture $fixtureRoot $environment
            $pattern='(?ms)<!-- quiet-example: (?<name>[^ ]+) -->\n```powershell\n(?<code>.*?)^```'
            $agentsExamples=[regex]::Matches([IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'docs/agents/AGENTS.md'),$utf8).GetAwaiter().GetResult(),$pattern)
            $extendedExamples=[regex]::Matches([IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'docs/agents/examples.md'),$utf8).GetAwaiter().GetResult(),$pattern)
            if($agentsExamples.Count -ne 4 -or $extendedExamples.Count -ne 7){throw ('SkillExampleSetChanged: '+$agentsExamples.Count+'+'+$extendedExamples.Count)}
            $examples=@($agentsExamples)+@($extendedExamples)
            foreach($example in $examples){
                try{. ([scriptblock]::Create($example.Groups['code'].Value))}
                catch{
                    $diagnostic=if(Get-Variable recent -ErrorAction SilentlyContinue){$recent.Error|ConvertTo-Json -Compress -Depth 6}else{''}
                    throw ('SkillExampleFailed: '+$example.Groups['name'].Value+' / '+$_.Exception.Message+' / '+$diagnostic)
                }
            }
            if($count.Data.ReachableCommits -ne 1 -or $recent.Data.ReturnedCommits -ne 1 -or $recent.Data.Commits[0].Subject -ne 'baseline'){throw 'SkillBusinessObjectsMismatch'}
            if($review.Data.ReviewedCommits -ne 1 -or $review.Data.RequiresReview -or $restored.Data.ReturnedCommits -ne 1 -or $restored.Data.Commits[0].Subject -ne 'baseline'){throw 'SkillRecallBusinessMismatch'}
            $jsonDocument=$json|ConvertFrom-Json
            if($jsonDocument.Data.Changes[0].Subject -ne 'baseline' -or !$yaml.Contains('baseline') -or $gain.GetType().Name -ne 'PSCustomObject' -or !($gainCompactJson|ConvertFrom-Json)){throw 'SkillDeliveryFormatsMismatch'}
            if($imported.RecallId -ne $recorded.Recall.RecallId -or !(Test-Path $archive)){throw 'SkillEvidenceTransferMismatch'}
        }finally{
            foreach($name in $saved.Keys){if($null -eq $saved[$name]){Remove-Item -LiteralPath ('Env:'+$name) -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($name,$saved[$name])}}
        }
    }
    $cases['distributed documents are concise, self-contained, name every command and SKILL.md is generated from AGENTS.md']={
        $manifest=Import-PowerShellDataFile (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
        # Public commands are split between script functions and compiled cmdlets.
        $exports=[string[]]@($manifest.FunctionsToExport)+[string[]]@($manifest.CmdletsToExport)
        if($exports.Count -lt 20){throw 'AgentExportListUnexpectedlySmall'}
        $agentsText=[IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'docs/agents/AGENTS.md'),$utf8).GetAwaiter().GetResult()
        $skillText=[IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'docs/agents/SKILL.md'),$utf8).GetAwaiter().GetResult()
        Test-QuietAgentDocumentSet -AgentsText $agentsText -SkillText $skillText -ExportedCommands $exports
        $mutants=@(
            @{Name='command removed from AGENTS.md';Agents=$agentsText.Replace('`Import-QuietRecall`','Import-QuietRecall');Skill=$null},
            @{Name='relative link added to AGENTS.md';Agents=$agentsText+"`nSee [other](other.md).`n";Skill=$null},
            @{Name='AGENTS.md grows beyond the concise limit';Agents=$agentsText+("`nfiller"*40);Skill=$null},
            @{Name='SKILL.md body edited by hand';Agents=$agentsText;Skill=$skillText.Replace('Rules','Rule')}
        )
        foreach($mutant in $mutants){
            $skillForMutant=if($null -eq $mutant.Skill){New-QuietSkillDocumentText -AgentsText $mutant.Agents}else{$mutant.Skill}
            $detected=$false;try{Test-QuietAgentDocumentSet -AgentsText $mutant.Agents -SkillText $skillForMutant -ExportedCommands $exports}catch{$detected=$true}
            if(!$detected){throw ('AgentDocumentMutantSurvived: '+$mutant.Name)}
            $mutations.Add(@{Original='distributed documents';Replacement=$mutant.Name;State='Killed'});$campaign.MutantsKilled++
        }
    }
    $cases['targeted source mutations are killed by independent reference properties']={
        $definition=$builder.ToString()
        foreach($mutation in @(
            @('$starts.Count -ne 1','$false'),@('$ends.Count -ne 1','$false'),
            @('$Text.Substring($after)',"''"),@(".Replace('%','%25')",''),
            @('if($starts.Count){$after','if($false){$after')
        )){
            if(!$definition.Contains($mutation[0])){throw 'AgentMutantInvalid'}
            $mutant=[scriptblock]::Create($definition.Replace($mutation[0],$mutation[1]))
            $detected=$false;try{Test-QuietAgentReferenceProperties $mutant}catch{$detected=$true}
            if(!$detected){throw 'AgentMutantSurvived'}
            $mutations.Add(@{Original=$mutation[0];Replacement=$mutation[1];State='Killed'});$campaign.MutantsKilled++
        }
    }
    $passed=0;$failed=0
    foreach($entry in $cases.GetEnumerator()){
        if($OnProgress){& $OnProgress $entry.Key Running $passed $failed}
        try{& $entry.Value;$passed++;$results.Add(@{Name=$entry.Key;State='Passed';Error=$null})}catch{$failed++;$results.Add(@{Name=$entry.Key;State='Failed';Error=$_.Exception.ToString()})}
        if($OnProgress){& $OnProgress $entry.Key $(if($results[-1].State -eq 'Passed'){'Passed'}else{'Failed'}) $passed $failed}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Campaign=$campaign;Mutations=$mutations.ToArray();Limits='Focused PowerShell/reference and installed-layout resource qualification; no publication or full release matrix. Staged import exercises the packaged resource layout, not a Gallery download.'}
}
