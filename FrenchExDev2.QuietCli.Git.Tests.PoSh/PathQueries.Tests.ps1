function Test-QuietGitGrepMode {
    <#
    .SYNOPSIS
    Checks generated grep mode selection without executing a native process.
    .PARAMETER Source
    Production mode-selector function or one isolated source-checked mutant.
    #>
    param([string]$Source)
    . ([scriptblock]::Create($Source))
    $random=[Random]::new(75055)
    $names=@('-l','-L','-q','--quiet','--files-with-matches','--files-without-match','-e')
    foreach($iteration in 1..500){
        $selected=@(foreach($i in 1..$random.Next(1,9)){$names[$random.Next($names.Count)]})
        $options=@(foreach($name in $selected){@{Name=$name;Value=$names[$random.Next($names.Count)]}})
        $expected='NativeRecords'
        $quiet=@($selected|Where-Object {$_ -cin @('-q','--quiet')}).Count
        $fileNames=@($selected|Where-Object {$_ -cin @('-l','-L','--files-with-matches','--files-without-match')})
        if($quiet){$expected='Quiet'}elseif($fileNames.Count){$expected=if($fileNames[-1] -cin @('-L','--files-without-match')){'FilesWithoutMatches'}else{'FilesWithMatches'}}
        if((Get-QuietGitGrepMode @{Options=$options}) -cne $expected){throw ('GrepModePropertyFailed: seed 75055 iteration '+$iteration)}
    }
    if((Get-QuietGitGrepMode @{Options=@(@{Name='-e';Value='-q'})}) -cne 'NativeRecords'){throw 'GrepModeMisreadOptionValue'}
}
function Get-QuietGitPathQueryCases {
    <#
    .SYNOPSIS
    Creates search/path-check and raw plumbing-diff workflows with explicit mode properties.
    .PARAMETER RootDirectory
    Owned disposable fixture root.
    .PARAMETER Environment
    Isolated Git environment.
    .PARAMETER WorkspaceRoot
    Source root for pure mode/guard regression evidence.
    #>
    param([string]$RootDirectory,[hashtable]$Environment,[string]$WorkspaceRoot)
    $Environment=$Environment.Clone();$Environment.GIT_DEFAULT_HASH='sha1'
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture
    $success=Get-Command Assert-QuietGitSuccess;$assert=Get-Command Assert-QuietEqual
    $cases=[ordered]@{}
    $cases['pathquery grep quiet file lists native records and invalid expressions remain distinct']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'é match.txt'),"needle`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('add','--','é match.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git grep -l needle
        & $success $r;& $assert $r.Data.Mode FilesWithMatches;& $assert $r.Data.Files[0].Path 'é match.txt'
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git grep -L needle -- file.txt
        & $success $r;& $assert $r.Data.Mode FilesWithoutMatches;& $assert $r.Data.Files[0].Path file.txt
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git grep -q no-such-match
        & $success $r;& $assert $r.Data.Matched $false;& $assert $r.Data.ExitCode 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git grep -n needle
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat
        if($r.Data.Records.Count -ne 1){throw 'Requested grep line missing'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git grep '['
        & $assert $r.Outcome Failed
    }.GetNewClosure()
    $cases['pathquery attribute NUL fields preserve requested values and path names']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path '.gitattributes'),"*.txt custom=value -diff`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git check-attr custom diff -- 'é path.txt'
        & $success $r;& $assert $r.Data.Entries.Count 2
        & $assert $r.Data.Entries[0].Path 'é path.txt';& $assert $r.Data.Entries[0].Value value;& $assert $r.Data.Entries[1].Value unset
        $bytes=[Text.Encoding]::UTF8.GetBytes("file.txt`0")
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -InputBytes $bytes git check-attr -z --stdin custom
        & $success $r;& $assert $r.Data.Entries[0].Path file.txt
    }.GetNewClosure()
    $cases['pathquery ignore rules preserve negation nonmatching groups and caller stdin framing']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path '.gitignore'),"*.log`n!keep.log`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git check-ignore -- 'é skip.log' keep.log
        & $success $r;& $assert $r.Data.Entries.Count 2
        & $assert $r.Data.Entries[0].Ignored $true;& $assert $r.Data.Entries[1].Ignored $false;& $assert $r.Data.Entries[1].Negated $true
        $bytes=[Text.Encoding]::UTF8.GetBytes("unmatched.txt`0")
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -InputBytes $bytes git check-ignore --stdin -z -v --non-matching
        & $success $r;& $assert $r.Data.Entries.Count 1;& $assert $r.Data.Entries[0].Ignored $false;& $assert $r.Data.Entries[0].Line $null
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git check-ignore --quiet ignored.log
        & $success $r;& $assert $r.Data.AnyIgnored $true
    }.GetNewClosure()
    $cases['pathquery mailmap returns native canonical contacts in one business execution']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path '.mailmap'),"Canonical Name <canonical@example.invalid> Alias Name <alias@example.invalid>`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git check-mailmap 'Alias Name <alias@example.invalid>'
        & $success $r;& $assert $r.Data.Contacts.Count 1;& $assert $r.Data.Contacts[0].Name 'Canonical Name';& $assert $r.Data.Contacts[0].Email canonical@example.invalid
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['pathquery raw diff files index tree and patch display preserve native comparison scope']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"changed`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-files
        & $success $r;& $assert $r.Data.OutputMode RawDiff;& $assert $r.Data.Files[0].Status M;& $assert $r.Data.Files[0].Path file.txt
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-index --exit-code HEAD
        & $success $r;& $assert $r.Data.ExitCode 1;& $assert $r.Data.Files.Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-files -p
        & $success $r;& $assert $r.Data.OutputMode Patch;& $assert $r.Data.Files.Count 1
        & $prepare $path @('commit','-am','changed') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-tree 'HEAD~1' HEAD
        & $success $r;& $assert $r.Data.Files.Count 1;& $assert $r.Data.Files[0].Path file.txt
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-tree HEAD
        & $success $r;& $assert $r.Data.Commits.Count 1
    }.GetNewClosure()
    $cases['pathquery raw rename paths preserve distinct source and destination']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('mv','file.txt','renamed é.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -- git diff-index --cached --find-renames=100% HEAD
        & $success $r;& $assert $r.Data.Files.Count 1;& $assert $r.Data.Files[0].Status R;& $assert $r.Data.Files[0].Score 100
        & $assert $r.Data.Files[0].OldPath file.txt;& $assert $r.Data.Files[0].Path 'renamed é.txt'
    }.GetNewClosure()
    $modeTest=Get-Command Test-QuietGitGrepMode
    $cases['pathquery PowerShell mode properties and display flags have isolated mutation evidence']={
        $path=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/src/PathQueries.ps1'
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-QuietGitGrepMode'},$true)
        $source=$function.Extent.Text;& $modeTest $source
        $mutants=@(@{Name='quiet-mode';From="return 'Quiet'";To="return 'NativeRecords'"},@{Name='file-mode';From="'FilesWithoutMatches'}else{'FilesWithMatches'";To="'FilesWithMatches'}else{'FilesWithoutMatches'"})
        foreach($mutant in $mutants){
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw 'GrepModeMutationSourceMismatch'}
            $killed=$false;try{& $modeTest $source.Replace($mutant.From,$mutant.To)}catch{$killed=$true};if(!$killed){throw ('GrepModeMutationSurvived: '+$mutant.Name)}
        }
        $module=Get-Module FrenchExDev2.QuietCli.Git.PoSh
        & $module {
            foreach($name in @('diff','diff-files','diff-index','diff-tree','log','blame','annotate')){Assert-QuietGitInteraction @{Request=@{}} @{Name=$name} @{Options=@(@{Name='-p'});Subcommand=$null}}
        }
        $report=Join-Path $RootDirectory 'grep-mode-mutation.json'
        [void][IO.File]::WriteAllTextAsync($report,(@{Seed=75055;GeneratedCases=500;Selected=2;Killed=2;SourceSHA256=(Get-FileHash -LiteralPath $path).Hash}|ConvertTo-Json).Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }.GetNewClosure()
    return $cases
}
