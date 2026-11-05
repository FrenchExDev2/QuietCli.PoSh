function Invoke-QuietGitHistory {
    <#
.SYNOPSIS
Distinguishes between default history and explicitly requested formatting.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git request.
    .PARAMETER Binding
    Git-owned token binding.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $explicit=@('--format','--pretty','--oneline','--graph','--raw','--numstat','--name-only','--name-status','--stat','--shortstat','--dirstat','--summary','--check','--word-diff','--color-words','--binary','--output','--color','-z','--null')
    if(@($flags|Where-Object{$_ -cin $explicit}).Count){$delimiter=if('-z' -cin $flags -or '--null' -cin $flags){[byte]0}else{[byte]10};return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $Request.Name -Delimiter $delimiter}
    if($Request.Name -eq 'show' -or @($flags|Where-Object{$_ -cin @('-p','-u','--patch','--patch-with-stat','--patch-with-raw','-U','--unified','-W','--function-context','-s','--no-patch')}).Count){return Invoke-QuietGitDiff $Runtime $Request $Binding $Prefix}
    $data=@{Command='log';GitVersion=$Runtime.State.DetectedVersion;OutputMode='Commits';Commits=[Collections.Generic.List[object]]::new();Scope=@{Walk='Requested native history walk';ImplicitLimit=$false;Format='NUL-delimited full object IDs, parents, author, committer, subject and body'}}
    $parser={
        param($f,$data)
            if($f[0] -isnot [string] -or $f[0] -notmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$'){throw 'MalformedLogObjectId'}
            $data.Commits.Add(@{ObjectId=$f[0];Parents=@(([string]$f[1]).Split(' ',[StringSplitOptions]::RemoveEmptyEntries));Author=@{Name=$f[2];Email=$f[3];Date=$f[4]};Committer=@{Name=$f[5];Email=$f[6];Date=$f[7]};Subject=$f[8];Body=$f[9]})
    }.GetNewClosure()
    $format='--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s%x00%b%x00%x00'
    $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('log',$format)+@($Request.Arguments)) $data -FieldCount 10 -Commit $parser
    return $r.Data
}
function Invoke-QuietGitShow {
    <#
.SYNOPSIS
Uses Git object type as authority, using authoritative blob-classification checks.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git show request.
    .PARAMETER Binding
    Bound options; option values are never guessed to be revisions.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $objects=[Collections.Generic.List[string]]::new();$literal=$false
    foreach($token in $Binding.Tokens){if($token.Kind -eq 'Separator'){$literal=$true;continue};if(!$literal -and $token.Kind -eq 'Operand'){$objects.Add([string]$token.Raw)}}
    $object=if($objects.Count -eq 0){'HEAD'}elseif($objects.Count -eq 1){$objects[0]}else{$null}
    if($object){
        $type=Read-QuietGitScalar $Runtime ($Prefix+@('cat-file','-t','--',$object)) @(0,128)
        if($type.Execution.Native.ExitCode -eq 0 -and $type.Data -ceq 'blob'){
            return Invoke-QuietGitBlobOutput $Runtime ($Prefix+@('show')+@($Request.Arguments)) $object
        }
    }
    return Invoke-QuietGitHistory $Runtime $Request $Binding $Prefix
}
function Invoke-QuietGitBlobOutput {
    <#
.SYNOPSIS
Writes explicitly requested blob output as an owned business artifact, not an engine capture.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Arguments
    Exact requested show arguments, including transformations if requested.
    .PARAMETER Object
    Requested object expression.
    #>
    param($Runtime,[string[]]$Arguments,[string]$Object)
    $owner=[guid]::NewGuid().ToString('N');$directory=Join-Path ([IO.Path]::GetTempPath()) ('quietcli2-git-artifact-'+$owner)
    if($IsWindows){[void][IO.Directory]::CreateDirectory($directory)}
    else{[void][IO.Directory]::CreateDirectory($directory,([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute))}
    $path=Join-Path $directory 'content.bin'
    $file=$null;$hash=$null;$retained=$false
    try{
    $fileOptions=[IO.FileStreamOptions]::new()
    $fileOptions.Mode=[IO.FileMode]::CreateNew;$fileOptions.Access=[IO.FileAccess]::Write;$fileOptions.Share=[IO.FileShare]::Read
    $fileOptions.BufferSize=16384;$fileOptions.Options=[IO.FileOptions]::Asynchronous
    if(!$IsWindows){$fileOptions.UnixCreateMode=[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite}
    $file=[IO.FileStream]::new($path,$fileOptions)
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    $sink=@{File=$file;Hash=$hash;Bytes=0L;Path=$path;OwnerId=$owner;Object=$Object}
    $r=Invoke-QuietGitNative $Runtime $Arguments -StdoutMode Bytes -StderrMode Bytes -Data $sink -Output {
        param($e,$r)
        if($e.Stream -eq 'stdout'){[void]$r.Data.File.WriteAsync($e.Bytes,0,$e.Bytes.Length).GetAwaiter().GetResult();$r.Data.Hash.AppendData($e.Bytes);$r.Data.Bytes+=$e.Bytes.Length}
    } -Complete {
        param($r)
        [void]$r.Data.File.FlushAsync().GetAwaiter().GetResult()
        @{Command='show';ObjectType='blob';Expression=$r.Data.Object;OutputMode='Artifact';Artifact=@{Kind='Git.RequestedShowOutput';Path=$r.Data.Path;OwnerId=$r.Data.OwnerId;Bytes=$r.Data.Bytes;SHA256=[Convert]::ToHexString($r.Data.Hash.GetHashAndReset());Complete=($r.Execution.SourceComplete -and $r.AnalysisComplete);Representation='Exact requested git show output; transformations, if requested, are preserved.'}}
    }
    if([object]::ReferenceEquals($r.Data,$sink)){
        return @{Command='show';ObjectType='blob';Expression=$Object;OutputMode='Artifact';Artifact=$null;Complete=$false;Outcome=$r.Outcome}
    }
    $script:GitArtifacts[$path]=@{OwnerId=$owner;Directory=$directory}
    $retained=$true
    return $r.Data
    }finally{
        if($file){$file.Dispose()};if($hash){$hash.Dispose()}
        if(!$retained){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop};if(@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0){Remove-Item -LiteralPath $directory -ErrorAction Stop}}
    }
}
function Remove-QuietGitArtifact {
    <#
.SYNOPSIS
Removes only an explicitly supplied business artifact owned by this module session.
    .PARAMETER Artifact
    Artifact descriptor returned by a blob show handler.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$Artifact)
    $path=[IO.Path]::GetFullPath($Artifact.Path)
    if(!$script:GitArtifacts.ContainsKey($path) -or $script:GitArtifacts[$path].OwnerId -cne $Artifact.OwnerId){throw 'UnknownOwnedGitArtifact'}
    $directory=$script:GitArtifacts[$path].Directory
    Remove-Item -LiteralPath $path -ErrorAction Stop
    if(@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0){Remove-Item -LiteralPath $directory -ErrorAction Stop}
    $script:GitArtifacts.Remove($path)
}
