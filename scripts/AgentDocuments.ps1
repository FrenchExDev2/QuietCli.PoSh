function Copy-QuietProductionAgentDocuments {
    <#
    .SYNOPSIS
    Stages canonical production agent resources into Core without repository development rules.
    .PARAMETER WorkspaceRoot
    QuietCli monorepo containing docs/agents.
    .PARAMETER ModuleDirectory
    Owned Core package staging directory.
    #>
    param([string]$WorkspaceRoot,[string]$ModuleDirectory)
    $source=Join-Path $WorkspaceRoot 'docs/agents'
    $target=Join-Path $ModuleDirectory 'resources/agents'
    $documents=@(foreach($name in @('AGENTS.md','SKILL.md','openai.yaml')){
        $bytes=[IO.File]::ReadAllBytesAsync((Join-Path $source $name)).GetAwaiter().GetResult()
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        if(!$text.Length -or $text.Contains("`r")){throw 'AgentDocumentMustBeNonemptyUtf8Lf'}
        @{Name=$name;Bytes=$bytes}
    })
    [void][IO.Directory]::CreateDirectory($target)
    foreach($document in $documents){[void][IO.File]::WriteAllBytesAsync((Join-Path $target $document.Name),$document.Bytes).GetAwaiter().GetResult()}
}
