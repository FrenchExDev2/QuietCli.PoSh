function Get-QuietGitIndexOperationCases {
    <#
    .SYNOPSIS
    Builds independent index effects and generated destination-guard assertions.
    .PARAMETER RootDirectory
    Owned fixture root.
    .PARAMETER Environment
    Isolated Git environment.
    .PARAMETER WorkspaceRoot
    Product source for isolated policy mutations.
    #>
    param([string]$RootDirectory,[hashtable]$Environment,[string]$WorkspaceRoot)
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture
    $success=Get-Command Assert-QuietGitSuccess;$assert=Get-Command Assert-QuietEqual
    $cases=[ordered]@{}
    $cases['index update-index observes removal and re-add without altering worktree contents']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git update-index --force-remove file.txt
        & $success $r;& $assert $r.Data.Before.Count 1;& $assert $r.Data.After.Count 0
        if(!(Test-Path -LiteralPath (Join-Path $path 'file.txt'))){throw 'Worktree file was removed'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git update-index --add file.txt
        & $success $r;& $assert $r.Data.Before.Count 0;& $assert $r.Data.After.Count 1
        & $assert $r.Data.After[0].Path file.txt;& $assert $r.Data.After[0].Stage 0
    }.GetNewClosure()
    $cases['index read-tree empties then restores tree and checkout-index restores file bytes']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git read-tree --empty
        & $success $r;& $assert $r.Data.Before.Count 1;& $assert $r.Data.After.Count 0
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git read-tree HEAD
        & $success $r;& $assert $r.Data.After.Count 1
        $file=Join-Path $path 'file.txt';$expected=[IO.File]::ReadAllBytes($file)
        Remove-Item -LiteralPath $file
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git checkout-index file.txt
        & $success $r;& $assert $r.Data.Before.Count 1;& $assert $r.Data.After.Count 1
        & $assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file))) ([Convert]::ToBase64String($expected))
    }.GetNewClosure()
    $cases['index failed native operation retains observed state and never reports success']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git checkout-index missing-unique-file
        & $assert $r.Outcome Failed;& $assert $r.Data.Before.Count 1;& $assert $r.Data.After.Count 1
        & $assert $r.Data.Observation.AfterAvailable $true
    }.GetNewClosure()
    $cases['index generated scope properties and isolated mutants reject foreign destinations']={
        $file=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/src/IndexOperations.ps1'
        $source=[IO.File]::ReadAllText($file,[Text.UTF8Encoding]::new($false))
        $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
        $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-QuietGitIndexObservationScope'},$true)
        if(!$node){throw 'Scope function missing'}
        $definition=$node.Extent.Text
        $vectors=[Collections.Generic.List[object]]::new();$random=[Random]::new(77051)
        for($i=0;$i -lt 500;$i++){
            $command=@('update-index','read-tree','checkout-index')[$random.Next(3)]
            $flag=@('--index-output','--temp','--prefix','--dry-run','--force','--assume-unchanged','--no-prefix')[$random.Next(7)]
            $reject=($command -ceq 'read-tree' -and $flag -ceq '--index-output') -or ($command -ceq 'checkout-index' -and $flag -cin @('--temp','--prefix'))
            $vectors.Add(@{Command=$command;Flags=@($flag);Reject=$reject})
        }
        $check={param($text,$vectors)
            & {
                param($text,$vectors)
                . ([scriptblock]::Create($text))
                foreach($v in $vectors){$rejected=$false;try{Assert-QuietGitIndexObservationScope $v.Command $v.Flags}catch{$rejected=$true};if($rejected -ne $v.Reject){return $false}}
                return $true
            } $text $vectors
        }
        for($i=0;$i -lt 1000;$i++){
            $noise='--'+[guid]::new([byte[]](1..16|ForEach-Object {[byte]$random.Next(256)})).ToString('N')
            $vectors.Add(@{Command='checkout-index';Flags=@($noise);Reject=$false})
        }
        if(!(& $check $definition $vectors)){throw 'Generated scope property failed'}
        foreach($mutant in @($definition.Replace("'read-tree'","'update-index'"),$definition.Replace("'--temp','--prefix'","'--temp'"))){if(& $check $mutant $vectors){throw 'Scope mutant survived'}}
    }.GetNewClosure()
    return $cases
}
