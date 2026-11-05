function ConvertTo-QuietGitTestCanonical {
    <#
    .SYNOPSIS
    Normalizes fixture maps and DTOs for migration comparisons, never a QuietCli result envelope.
    .PARAMETER Value
    Explicit fixture binding or parser-owned business graph.
    #>
    param([AllowNull()]$Value)
    if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $map=[ordered]@{};foreach($key in @($Value.Keys|Sort-Object -CaseSensitive)){$map[$key]=ConvertTo-QuietGitTestCanonical $Value[$key]};return $map
    }
    if($Value -is [Collections.IEnumerable]){$items=[Collections.Generic.List[object]]::new();foreach($item in $Value){$items.Add((ConvertTo-QuietGitTestCanonical $item))};return ,$items.ToArray()}
    $map=[ordered]@{};foreach($property in @($Value.PSObject.Properties|Sort-Object Name -CaseSensitive)){$map[$property.Name]=ConvertTo-QuietGitTestCanonical $property.Value};return $map
}
function Measure-QuietGitMigration {
    <#
    .SYNOPSIS
    Compares existing PowerShell bindings/parsers with the local C# companion using authored fixture vectors.
    #>
    $canonical=Get-Command ConvertTo-QuietGitTestCanonical
    & (Get-Module FrenchExDev2.QuietCli.Git.PoSh) {
        param($baseline,$canonical)
        . $baseline
        Import-QuietGitParser
        foreach($entry in @(@{Major=10;Framework='net10.0'},@{Major=11;Framework='net11.0'},@{Major=12;Framework='net11.0'})){
            if((Resolve-QuietGitParserTarget -RuntimeMajor $entry.Major) -cne $entry.Framework){throw 'GitParserTargetSelectionChanged'}
        }
        $rejected=$false;try{$null=Resolve-QuietGitParserTarget -RuntimeMajor 9}catch{$rejected=$true};if(!$rejected){throw 'GitParserAcceptedIncompatibleClr'}
        $framework=[FrenchExDev2.QuietCli.Git.GitArguments].Assembly.GetCustomAttributes([System.Runtime.Versioning.TargetFrameworkAttribute],$false)[0].FrameworkName
        $expectedFramework=if([Environment]::Version.Major -ge 11){'.NETCoreApp,Version=v11.0'}else{'.NETCoreApp,Version=v10.0'}
        if($framework -cne $expectedFramework){throw 'GitParserLoadedWrongFramework'}
        $schema=Get-GitArgumentSchema
        $vectors=@(
            @{Command='status';Argv=@('-sb','--untracked-files','--','-path')},
            @{Command='log';Argv=@('--author','--all','-n2','--grep=','--','é file')},
            @{Command='commit';Argv=@('-am','--looks-like-flag')},
            @{Command='diff';Argv=@('--unknown','--','-p')},
            @{Command='stash';Argv=@('push','-m','--all','--','file')},
            @{Command='worktree';Argv=@('list','--porcelain','-z')},
            @{Command='update-index';Argv=@('--cacheinfo','100644',('a'*40),'path')},
            @{Command='log';Argv=@('--format=','--','')},
            @{Command='no-curated-command';Argv=@('x','--all')}
        )
        foreach($vector in $vectors){
            $expected=Get-GitArgumentTokenBaseline -Command $vector.Command -ArgumentList $vector.Argv -Version '2.56.0' -Schema $schema
            $actual=Get-GitArgumentToken -Command $vector.Command -ArgumentList $vector.Argv -Version '2.56.0' -Schema $schema
            $left=ConvertTo-Json -InputObject (& $canonical $expected) -Depth 40 -Compress
            $right=ConvertTo-Json -InputObject (& $canonical $actual) -Depth 40 -Compress
            if($left -cne $right){
                $position=0;while($position -lt [Math]::Min($left.Length,$right.Length) -and $left[$position] -ceq $right[$position]){$position++}
                $start=[Math]::Max(0,$position-50)
                throw ('GitBindingMigrationChanged: '+$vector.Command+' index='+$position+' expected='+$left.Substring($start,[Math]::Min(180,$left.Length-$start))+' actual='+$right.Substring($start,[Math]::Min(180,$right.Length-$start)))
            }
        }
        $id='a'*40;$record=[Text.Encoding]::UTF8.GetBytes("1 M. N... 100644 100644 100644 $id $id é file")
        $line=[Text.Encoding]::UTF8.GetBytes('+é content')
        foreach($operation in @('Status','Patch','Binding')){
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('PowerShell','CSharp')}else{@('CSharp','PowerShell')})){
                    if($operation -eq 'Status'){$data=@{Pending=$null;Counts=@{Changed=0L;Staged=0L;Unstaged=0L;Untracked=0L;Conflicted=0L;Renamed=0L;Ignored=0L};Entries=[Collections.Generic.List[object]]::new()};$calls=2000}
                    elseif($operation -eq 'Patch'){
                        $data=New-QuietGitPatch diff '2.56.0';$calls=2000
                        foreach($text in @('diff --git a/f b/f','--- a/f','+++ b/f','@@ -1 +1 @@')){[FrenchExDev2.QuietCli.Git.GitRecords]::Patch([Text.Encoding]::UTF8.GetBytes($text),$data)}
                    }else{$calls=100}
                    $watch=[Diagnostics.Stopwatch]::StartNew()
                    foreach($call in 1..$calls){
                        switch($operation){
                            Status {if($implementation -eq 'PowerShell'){Receive-QuietGitStatusRecordBaseline $record $data}else{[FrenchExDev2.QuietCli.Git.GitRecords]::Status($record,$data)}}
                            Patch {if($implementation -eq 'PowerShell'){Receive-QuietGitPatchRecordBaseline $line $data}else{[FrenchExDev2.QuietCli.Git.GitRecords]::Patch($line,$data)}}
                            Binding {$binding=if($implementation -eq 'PowerShell'){Get-GitArgumentTokenBaseline -Command log -ArgumentList @('--author','--all','-n2','--','path') -Version '2.56.0' -Schema $schema}else{Get-GitArgumentToken -Command log -ArgumentList @('--author','--all','-n2','--','path') -Version '2.56.0' -Schema $schema}}
                        }
                    }
                    $watch.Stop()
                    if($operation -eq 'Status' -and ($data.Counts.Changed -ne $calls -or $data.Counts.Staged -ne $calls -or $data.Entries.Count -ne $calls)){throw 'GitStatusBenchmarkCounterMismatch'}
                    if($operation -eq 'Patch' -and ($data.Files.Count -ne 1 -or $data.Files[0].Hunks[0].Lines.Count -ne $calls)){throw 'GitPatchBenchmarkCounterMismatch'}
                    if($operation -eq 'Binding' -and (!$binding.Complete -or $binding.Options.Count -ne 2 -or $binding.Operands[0] -cne 'path')){throw 'GitBindingBenchmarkCounterMismatch'}
                    @{Kind='GitLocalParser';Operation=$operation;Implementation=$implementation;Iteration=$iteration;Calls=$calls;ElapsedMs=$watch.Elapsed.TotalMilliseconds;ProtocolBytes=0L;Scope='Same authored Git records or argv; local parsing/policy construction only, no Git process, engine IPC or native startup.'}
                }
            }
        }
    } (Join-Path $PSScriptRoot 'Migration.Baseline.ps1') $canonical
}
