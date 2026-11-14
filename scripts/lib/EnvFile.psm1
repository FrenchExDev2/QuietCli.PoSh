function Read-QuietEnvText {
    <#
    .SYNOPSIS
    Reads at most one MiB of strict UTF-8 dotenv text without evaluating its contents.
    .PARAMETER Path
    Exact dotenv file; an absent file returns null.
    .PARAMETER Raw
    Preserves the BOM and original line endings for exact write-idempotence comparisons.
    #>
    param([Parameter(Mandatory)][string]$Path,[switch]$Raw)
    if(![IO.File]::Exists($Path)){return $null}
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $buffer=[byte[]]::new(1048577);$count=0
        while($count -lt $buffer.Length){
            $read=$stream.ReadAsync($buffer,$count,$buffer.Length-$count).GetAwaiter().GetResult()
            if(!$read){break};$count+=$read
        }
        if($count -gt 1048576){throw 'EnvFileSizeLimit'}
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($buffer,0,$count)
        if($Raw){return $text}
        if($text.Length -and $text[0] -eq [char]0xfeff){$text=$text.Substring(1)}
        return $text.Replace("`r`n","`n").Replace("`r","`n")
    }finally{$stream.Dispose()}
}
function ConvertFrom-QuietEnvLiteral {
    <#
    .SYNOPSIS
    Decodes one single-line dotenv literal with no interpolation or command evaluation.
    .PARAMETER Text
    Raw assignment value, including optional quotes and trailing comment.
    #>
    param([AllowEmptyString()][string]$Text)
    $value=$Text.Trim()
    if(!$value -or $value.StartsWith('#')){return ''}
    if($value[0] -notin @([char]34,[char]39)){return ([regex]::Replace($value,'\s+#.*\z','')).TrimEnd()}
    $quote=$value[0];$result=[Text.StringBuilder]::new()
    for($index=1;$index -lt $value.Length;$index++){
        $character=$value[$index]
        if($quote -eq [char]34 -and $character -eq [char]92 -and $index+1 -lt $value.Length -and $value[$index+1] -in @([char]34,[char]92)){
            [void]$result.Append($value[++$index]);continue
        }
        if($character -eq $quote){
            $tail=$value.Substring($index+1).Trim()
            if($tail -and !$tail.StartsWith('#')){throw 'EnvValueTrailingContent'}
            return $result.ToString()
        }
        [void]$result.Append($character)
    }
    throw 'EnvValueUnclosedQuote'
}
function Get-QuietEnvValue {
    <#
    .SYNOPSIS
    Reads only the requested case-sensitive key and rejects ambiguous duplicate assignments.
    .PARAMETER Path
    Dotenv file path.
    .PARAMETER Key
    Identifier to read; absent files or keys return null, unlike an assigned empty string.
    #>
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][ValidatePattern('\A[A-Za-z_][A-Za-z0-9_]*\z')][string]$Key)
    $text=Read-QuietEnvText $Path
    if($null -eq $text){return $null}
    $pattern='^\s*(?:export\s+)?'+[regex]::Escape($Key)+'\s*=(?<value>.*)$'
    $found=$false;$value=$null
    foreach($line in $text.Split("`n")){
        $match=[regex]::Match($line,$pattern)
        if(!$match.Success){continue}
        if($found){throw ('EnvKeyDuplicate: '+$Key)}
        $found=$true;$value=ConvertFrom-QuietEnvLiteral $match.Groups['value'].Value
    }
    return $value
}
function Set-QuietEnvValue {
    <#
    .SYNOPSIS
    Atomically sets one quoted dotenv key, preserving unrelated lines and emitting metadata without values.
    .PARAMETER Path
    File to create or update; writes use UTF-8 without a BOM and LF line endings.
    .PARAMETER Key
    Case-sensitive identifier; duplicate assignments for this key are consolidated.
    .PARAMETER Value
    Literal single-line value; variables and commands are never evaluated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][ValidatePattern('\A[A-Za-z_][A-Za-z0-9_]*\z')][string]$Key,[Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if($Value.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0){throw 'EnvValueMustBeSingleLine'}
    $pathFull=[IO.Path]::GetFullPath($Path,$PWD.Path)
    if([IO.File]::Exists($pathFull) -and ([IO.File]::GetAttributes($pathFull) -band [IO.FileAttributes]::ReparsePoint)){throw 'EnvFileWriteLinkRejected'}
    $before=Read-QuietEnvText $pathFull -Raw
    $lines=[Collections.Generic.List[string]]::new()
    if($null -ne $before -and $before.Length){
        $content=$before
        if($content[0] -eq [char]0xfeff){$content=$content.Substring(1)}
        $content=$content.Replace("`r`n","`n").Replace("`r","`n")
        if($content.EndsWith("`n")){$content=$content.Substring(0,$content.Length-1)}
        foreach($line in $content.Split("`n")){$lines.Add($line)}
    }
    $pattern='^\s*(?:export\s+)?'+[regex]::Escape($Key)+'\s*='
    $indices=@(for($index=0;$index -lt $lines.Count;$index++){if($lines[$index] -cmatch $pattern){$index}})
    $literal=$Key+'="'+$Value.Replace('\','\\').Replace('"','\"')+'"'
    if($indices.Count){
        $lines[$indices[0]]=$literal
        for($index=$indices.Count-1;$index -gt 0;$index--){$lines.RemoveAt($indices[$index])}
    }else{$lines.Add($literal)}
    $after=($lines -join "`n")+"`n"
    if([Text.UTF8Encoding]::new($false,$true).GetByteCount($after) -gt 1048576){throw 'EnvFileSizeLimit'}
    $changed=$null -eq $before -or $before -cne $after
    if(!$changed){return [pscustomobject]@{Path=$pathFull;Key=$Key;Changed=$false}}
    if(!$PSCmdlet.ShouldProcess($pathFull,('Set dotenv key '+$Key))){return}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($pathFull))
    $temporary=$pathFull+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [void][IO.File]::WriteAllTextAsync($temporary,$after,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
        if(!$IsWindows){[IO.File]::SetUnixFileMode($temporary,([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite))}
        if([IO.File]::Exists($pathFull)){[IO.File]::Replace($temporary,$pathFull,[NullString]::Value)}else{[IO.File]::Move($temporary,$pathFull)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    [pscustomobject]@{Path=$pathFull;Key=$Key;Changed=$true}
}

Export-ModuleMember -Function 'Read-QuietEnvText','ConvertFrom-QuietEnvLiteral','Get-QuietEnvValue','Set-QuietEnvValue'
