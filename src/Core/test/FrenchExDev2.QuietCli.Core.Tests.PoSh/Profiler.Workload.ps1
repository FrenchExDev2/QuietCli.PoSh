<#
.SYNOPSIS
Exercises user callbacks, the PowerShell facade and compiled framing in an explicitly instrumented pass.
.PARAMETER RepositoryPath
Owned bulk fixture from the completed integration run.
#>
param([string]$RepositoryPath)
$git=(Get-Command git -CommandType Application|Select-Object -First 1).Source
foreach($iteration in 1..8){
    $result=quiet -AsObject -WorkingDirectory $RepositoryPath -StdoutMode Bytes -Data @{Bytes=0L} -Output {
        param($event,$runtime)
        $runtime.Data.Bytes+=$event.ByteCount
    } -Complete {param($runtime)$runtime.Data.Bytes} -FilePath $git -ArgumentList @('status','--porcelain=v2','-z','--untracked-files=all')
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Data -ne $result.Execution.Native.StdoutBytesRead){throw 'ProfiledBusinessResultMismatch'}
    $framer=New-QuietByteRecordFramer -Delimiter 0
    try{
        $block=[byte[]]::new(16384);$block[-1]=0
        foreach($chunk in 1..128){$null=@($framer.Push($block))}
    }finally{$framer.Dispose()}
    foreach($query in 1..16){$null=Get-QuietEngine}
}
