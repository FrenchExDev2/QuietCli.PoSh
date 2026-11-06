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

function New-QuietSkillDocumentText {
    <#
    .SYNOPSIS
    Builds the distributed SKILL.md: the skill front matter followed by the AGENTS.md body, unchanged.
    .DESCRIPTION
    AGENTS.md is the single source of the production instructions. SKILL.md must never be edited by
    hand; regenerate it with scripts/Sync-SkillDocument.ps1.
    .PARAMETER AgentsText
    Full UTF-8 text of AGENTS.md, LF line endings.
    #>
    param([Parameter(Mandatory)][string]$AgentsText)
    $description='Use when running a native command (git, dotnet, or any executable) from PowerShell through the `quiet` alias to get a typed business object instead of raw output; covers bounded JSON/YAML delivery, measured gains and Recall evidence for reanalysis.'
    return "---`nname: quiet-cli`ndescription: $description`n---`n$AgentsText"
}
