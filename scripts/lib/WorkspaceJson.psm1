#requires -Version 7.6
function Write-WorkspaceJson {
    <#
.SYNOPSIS
Publishes UTF-8 JSON atomically, creating missing destination directories for reports and monitors.
    .PARAMETER Path
    Destination JSON path.
    .PARAMETER Value
    State metadata.
    #>
    param([string]$Path,$Value)
    $Path=[IO.Path]::GetFullPath($Path,$PWD.Path)
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $json=(ConvertTo-Json -InputObject $Value -Depth 32).Replace("`r`n","`n").Replace("`r","`n")
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    try{
        [void][IO.File]::WriteAllTextAsync($temporary,$json,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        for($attempt=0;$attempt -le 5;$attempt++){
            try{[IO.File]::Move($temporary,$Path,$true);break}catch{
                $code=$_.Exception.GetBaseException().HResult -band 65535
                if(!$IsWindows -or $attempt -eq 5 -or $code -notin @(5,32,33) -or ![IO.File]::Exists($Path)){throw}
                [void][Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult()
            }
        }
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
Export-ModuleMember -Function 'Write-WorkspaceJson'
