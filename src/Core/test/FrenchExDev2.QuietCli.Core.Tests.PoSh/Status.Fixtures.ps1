function New-QuietControlledStatusFixtures {
    <#
    .SYNOPSIS
    Creates owned Git fixtures and literal state expectations without loading a business companion.
    .PARAMETER Root
    New absolute directory; existing paths are rejected and never cleaned or reset.
    .PARAMETER GitPath
    Existing Git executable used by the independent CI setup runner.
    #>
    param([string]$Root,[string]$GitPath)
    if(![IO.Path]::IsPathFullyQualified($Root) -or (Test-Path -LiteralPath $Root)){throw 'ControlledFixtureRequiresNewAbsoluteRoot'}
    [void][IO.Directory]::CreateDirectory($Root)
    $utf8=[Text.UTF8Encoding]::new($false)
    $hooks=Join-Path $Root 'empty-hooks';[void][IO.Directory]::CreateDirectory($hooks)
    $config=Join-Path $Root 'empty.gitconfig'
    [void][IO.File]::WriteAllTextAsync($config,'',$utf8).GetAwaiter().GetResult()
    foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_CONFIG_PARAMETERS','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_TEMPLATE_DIR')){
        Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue
        if([Environment]::GetEnvironmentVariables().Contains($name)){throw ('FixtureEnvironmentNotRemoved: '+$name)}
    }
    $env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=$config;$env:GIT_CONFIG_COUNT='0'
    $env:GIT_CEILING_DIRECTORIES=$Root;$env:GIT_TERMINAL_PROMPT='0';$env:GIT_OPTIONAL_LOCKS='0'
    $env:GIT_AUTHOR_NAME='Core integration';$env:GIT_COMMITTER_NAME='Core integration'
    $env:GIT_AUTHOR_EMAIL='integration@example.invalid';$env:GIT_COMMITTER_EMAIL=$env:GIT_AUTHOR_EMAIL
    $env:GIT_AUTHOR_DATE='2020-01-01T00:00:00+0000';$env:GIT_COMMITTER_DATE=$env:GIT_AUTHOR_DATE
    $env:LC_ALL='C';$env:LANG='C'

    function Invoke-FixtureGit {
        <#
        .SYNOPSIS
        Runs setup only inside this owned fixture root, with hooks and signing disabled.
        .PARAMETER Directory
        Owned working directory.
        .PARAMETER Arguments
        Exact Git setup arguments.
        .PARAMETER ExpectedExit
        Independently expected exit, including an intentional merge conflict.
        #>
        param([string]$Directory,[string[]]$Arguments,[int]$ExpectedExit=0)
        $relative=[IO.Path]::GetRelativePath($Root,[IO.Path]::GetFullPath($Directory))
        if([IO.Path]::IsPathRooted($relative) -or $relative -match '^\.\.([\\/]|$)'){throw 'FixtureCommandEscapedOwnedRoot'}
        $diagnostics=@{Lines=[Collections.Generic.Queue[string]]::new()}
        $result=Invoke-CiProcess -FilePath $GitPath -WorkingDirectory $Directory -ArgumentList (@('-c',"core.hooksPath=$hooks",'-c','commit.gpgsign=false')+$Arguments) -TimeoutSeconds 60 -State $diagnostics -OnOutput {
            param($event,$state)
            if($state.Lines.Count -ge 8){$null=$state.Lines.Dequeue()}
            $state.Lines.Enqueue($event.Text)
        }
        if($result.ExitCode -ne $ExpectedExit -or $result.Outcome -notin @('Success','Failed')){
            Write-WorkspaceJson (Join-Path $Root 'setup-error.json') @{Arguments=$Arguments;Result=$result;Diagnostics=$diagnostics.Lines.ToArray()}
            throw ('FixtureGitFailed: '+($Arguments -join ' ')+' / '+$result.Outcome+' / '+$result.ExitCode+' / '+($diagnostics.Lines.ToArray() -join ' | '))
        }
    }
    function Write-FixtureText {
        <#
        .SYNOPSIS
        Writes deterministic UTF-8/LF fixture content with asynchronous file I/O.
        .PARAMETER Repository
        Owned repository directory.
        .PARAMETER Name
        Literal relative fixture path.
        .PARAMETER Text
        File content.
        #>
        param([string]$Repository,[string]$Name,[string]$Text)
        $path=Join-Path $Repository $Name
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [void][IO.File]::WriteAllTextAsync($path,$Text,$utf8).GetAwaiter().GetResult()
    }
    function New-FixtureRepository {
        <#
        .SYNOPSIS
        Creates a repository with fixed identity, SHA-1, line handling and an optional initial commit.
        .PARAMETER Name
        Unique directory below the owned root.
        .PARAMETER Unborn
        Leaves the repository without a commit.
        #>
        param([string]$Name,[switch]$Unborn)
        $repo=Join-Path $Root $Name;[void][IO.Directory]::CreateDirectory($repo)
        Invoke-FixtureGit $repo @('init','--initial-branch=main','--object-format=sha1',('--template='+$hooks))
        foreach($entry in @(@('core.autocrlf','false'),@('core.filemode','false'),@('core.quotepath','false'),@('status.renames','true'))){Invoke-FixtureGit $repo @('config',$entry[0],$entry[1])}
        if(!$Unborn){
            foreach($file in @('modified.txt','both.txt','deleted.txt','staged-delete.txt','rename-old.txt','conflict.txt','stable.txt')){Write-FixtureText $repo $file ("baseline $file`n")}
            Write-FixtureText $repo '.gitignore' "ignored.log`n"
            Invoke-FixtureGit $repo @('add','--all');Invoke-FixtureGit $repo @('commit','-m','Controlled baseline')
        }
        return $repo
    }
    $fixtures=[Collections.Generic.List[object]]::new()
    $unborn=New-FixtureRepository unborn -Unborn
    Write-FixtureText $unborn 'new.txt' "new`n";Invoke-FixtureGit $unborn @('add','--','new.txt')
    $fixtures.Add(@{Name='unborn';Path=$unborn;Entries=@(@{Status='A ';Path='new.txt';IndexText="new`n"})})
    $clean=New-FixtureRepository clean
    $fixtures.Add(@{Name='clean';Path=$clean;Entries=@()})
    $mixed=New-FixtureRepository mixed
    Write-FixtureText $mixed 'modified.txt' "worktree edit`n"
    Write-FixtureText $mixed 'both.txt' "index edit`n";Invoke-FixtureGit $mixed @('add','--','both.txt');Write-FixtureText $mixed 'both.txt' "second worktree edit`n"
    [IO.File]::Delete((Join-Path $mixed 'deleted.txt'))
    Invoke-FixtureGit $mixed @('rm','--','staged-delete.txt')
    Invoke-FixtureGit $mixed @('mv','--','rename-old.txt','rename-new.txt')
    Write-FixtureText $mixed 'new-staged.txt' "staged`n";Invoke-FixtureGit $mixed @('add','--','new-staged.txt')
    foreach($path in @('-leading.txt','nested/é漢 space.txt','ignored.log')){Write-FixtureText $mixed $path "untracked or ignored`n"}
    $fixtures.Add(@{Name='mixed';Path=$mixed;Entries=@(
        @{Status='MM';Path='both.txt';IndexText="index edit`n"},@{Status=' D';Path='deleted.txt'},@{Status=' M';Path='modified.txt'},
        @{Status='A ';Path='new-staged.txt';IndexText="staged`n"},@{Status='R ';Path='rename-new.txt';OriginalPath='rename-old.txt'},
        @{Status='D ';Path='staged-delete.txt'},@{Status='??';Path='-leading.txt'},@{Status='??';Path='nested/é漢 space.txt'},@{Status='!!';Path='ignored.log'})})
    $conflict=New-FixtureRepository conflict
    Invoke-FixtureGit $conflict @('checkout','-b','side');Write-FixtureText $conflict 'conflict.txt' "side`n"
    Invoke-FixtureGit $conflict @('commit','-am','Side change');Invoke-FixtureGit $conflict @('checkout','main')
    Write-FixtureText $conflict 'conflict.txt' "main`n";Invoke-FixtureGit $conflict @('commit','-am','Main change')
    Invoke-FixtureGit $conflict @('merge','--no-edit','side') 1
    $fixtures.Add(@{Name='conflict';Path=$conflict;Entries=@(@{Status='UU';Path='conflict.txt'})})
    $detached=New-FixtureRepository detached;Invoke-FixtureGit $detached @('checkout','--detach','HEAD')
    $fixtures.Add(@{Name='detached';Path=$detached;Entries=@()})
    $linked=Join-Path $Root 'linked-worktree';Invoke-FixtureGit $clean @('worktree','add','--detach',$linked,'HEAD')
    Write-FixtureText $linked 'modified.txt' "linked edit`n"
    $fixtures.Add(@{Name='linked-worktree';Path=$linked;Entries=@(@{Status=' M';Path='modified.txt'})})
    $subSource=New-FixtureRepository submodule-source;$sub=New-FixtureRepository submodule
    Invoke-FixtureGit $sub @('-c','protocol.file.allow=always','submodule','add',$subSource,'component')
    Invoke-FixtureGit $sub @('commit','-am','Add local submodule')
    Write-FixtureText (Join-Path $sub 'component') 'stable.txt' "submodule edit`n"
    $fixtures.Add(@{Name='submodule';Path=$sub;Entries=@(@{Status=' M';Path='component';Submodule=$true})})
    $bulk=New-FixtureRepository bulk;$entries=[Collections.Generic.List[object]]::new();$random=[Random]::new(73594)
    foreach($index in 0..511){
        $name='untracked/tree-{0:D2}/item-{1:D4}-é漢 space.txt' -f ($index%8),$index
        Write-FixtureText $bulk $name ("seed 73594 / $($random.Next())`n")
        $entries.Add(@{Status='??';Path=$name})
    }
    $fixtures.Add(@{Name='bulk';Path=$bulk;Entries=$entries.ToArray();Seed=73594})
    return ,$fixtures.ToArray()
}

function Get-QuietFixtureObjectId {
    <#
    .SYNOPSIS
    Computes a SHA-1 Git object identifier from its documented header and literal payload.
    .PARAMETER Kind
    Git object type; this is an object-format checksum, not author authentication.
    .PARAMETER Payload
    Exact object payload bytes.
    #>
    param([string]$Kind,[byte[]]$Payload)
    $header=[Text.Encoding]::ASCII.GetBytes($Kind+' '+$Payload.Length+[char]0)
    [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]($header+$Payload))).ToLowerInvariant()
}

function Get-QuietFixtureBaselineCommit {
    <#
    .SYNOPSIS
    Independently constructs the fixed baseline tree and commit used by the local submodule.
    #>
    $tree=[IO.MemoryStream]::new()
    try{
        $names=@('.gitignore','both.txt','conflict.txt','deleted.txt','modified.txt','rename-old.txt','stable.txt','staged-delete.txt')
        foreach($name in $names){
            $content=if($name -eq '.gitignore'){"ignored.log`n"}else{"baseline $name`n"}
            $hash=Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes($content))
            $entry=[byte[]]([Text.Encoding]::UTF8.GetBytes('100644 '+$name+[char]0)+[Convert]::FromHexString($hash))
            [void]$tree.WriteAsync($entry,0,$entry.Length).GetAwaiter().GetResult()
        }
        $treeId=Get-QuietFixtureObjectId tree $tree.ToArray()
        $commit="tree $treeId`nauthor Core integration <integration@example.invalid> 1577836800 +0000`ncommitter Core integration <integration@example.invalid> 1577836800 +0000`n`nControlled baseline`n"
        Get-QuietFixtureObjectId commit ([Text.Encoding]::UTF8.GetBytes($commit))
    }finally{$tree.Dispose()}
}

function Get-QuietStatusOracle {
    <#
    .SYNOPSIS
    Encodes complete porcelain v2 -z records from literal fixture states and independently computed object IDs.
    .PARAMETER Entries
    Independently constructed XY/path/optional-rename-source records.
    #>
    param([AllowEmptyCollection()][object[]]$Entries)
    $normal=@($Entries|Where-Object Status -NotIn @('??','!!')|Sort-Object Path -CaseSensitive)
    $untracked=@($Entries|Where-Object Status -EQ '??'|Sort-Object Path -CaseSensitive)
    $ignored=@($Entries|Where-Object Status -EQ '!!'|Sort-Object Path -CaseSensitive)
    $text=[Text.StringBuilder]::new();$records=0;$zero='0'*40
    foreach($entry in @($normal)+@($untracked)+@($ignored)){
        $xy=$entry.Status.Replace(' ','.');$path=$entry.Path
        if($entry.Status -eq '??'){$record='? '+$path}
        elseif($entry.Status -eq '!!'){$record='! '+$path}
        elseif($entry.Status -eq 'UU'){
            $base=Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes("baseline conflict.txt`n"))
            $ours=Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes("main`n"))
            $theirs=Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes("side`n"))
            $record="u UU N... 100644 100644 100644 100644 $base $ours $theirs $path"
        }else{
            $oldPath=if($entry.ContainsKey('OriginalPath')){$entry.OriginalPath}else{$path}
            $head=if($xy[0] -eq 'A'){$zero}else{Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes("baseline $oldPath`n"))}
            $index=if($xy[0] -eq 'D'){$zero}elseif($entry.ContainsKey('IndexText')){Get-QuietFixtureObjectId blob ([Text.Encoding]::UTF8.GetBytes($entry.IndexText))}else{$head}
            $headMode=if($xy[0] -eq 'A'){'000000'}else{'100644'}
            $indexMode=if($xy[0] -eq 'D'){'000000'}else{'100644'}
            $workMode=if($xy[0] -eq 'D' -or $xy[1] -eq 'D'){'000000'}else{'100644'}
            $sub='N...'
            if($entry.ContainsKey('Submodule')){$head=Get-QuietFixtureBaselineCommit;$index=$head;$headMode='160000';$indexMode='160000';$workMode='160000';$sub='S.M.'}
            if($entry.ContainsKey('OriginalPath')){$record="2 $xy $sub $headMode $indexMode $workMode $head $index R100 $path"}
            else{$record="1 $xy $sub $headMode $indexMode $workMode $head $index $path"}
        }
        [void]$text.Append($record+[char]0);$records++
        if($entry.ContainsKey('OriginalPath')){[void]$text.Append($entry.OriginalPath+[char]0);$records++}
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes($text.ToString())
    [pscustomobject]@{Format='porcelain-v2-z';Bytes=$bytes.Length;Records=$records;SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}
