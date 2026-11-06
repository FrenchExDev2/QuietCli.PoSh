function Get-QuietAgentDocumentDirectory {
    <# .SYNOPSIS
    Selects packaged production documents, or their canonical source when running from the repository.
    #>
    $packaged=[IO.Path]::Combine($script:QuietRoot,'resources','agents')
    if([IO.Directory]::Exists($packaged)){return $packaged}
    $repository=[IO.Path]::GetDirectoryName($script:QuietRoot)
    if([IO.File]::Exists([IO.Path]::Combine($repository,'scripts','New-WorkspacePackage.ps1'))){
        return [IO.Path]::Combine($repository,'docs','agents')
    }
    throw 'AgentInstructionResourcesMissing'
}

function Get-QuietAgentInstruction {
    <#
    .SYNOPSIS
    Reads the distributed production AGENTS.md without starting an engine or changing configuration.
    .OUTPUTS
    System.String. Missing or invalid UTF-8 instructions fail explicitly.
    #>
    [CmdletBinding()]param()
    $path=[IO.Path]::Combine((Get-QuietAgentDocumentDirectory),'AGENTS.md')
    return [IO.File]::ReadAllTextAsync($path,$script:QuietUtf8).GetAwaiter().GetResult()
}

function Assert-QuietAgentWritePath {
    <#
    .SYNOPSIS
    Rejects linked ancestors and managed document/target collisions before a write.
    .PARAMETER Path
    Absolute write destination.
    .PARAMETER ProtectedPaths
    Distributed sources and selected project instruction files that must not be overwritten.
    #>
    param([string]$Path,[string[]]$ProtectedPaths=@())
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    foreach($protected in $ProtectedPaths){if([string]::Equals($Path,$protected,$comparison)){throw 'AgentInstructionPathConflict'}}
    $current=$Path
    while($current){
        $item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'AgentInstructionLinkedPath'}
        if($item -is [IO.FileInfo] -and $current -ne $Path){throw 'AgentInstructionAncestorIsFile'}
        $parent=[IO.Path]::GetDirectoryName($current)
        if($parent -eq $current){break}
        $current=$parent
    }
    if([IO.Directory]::Exists($Path)){throw 'AgentInstructionTargetIsDirectory'}
}

function Set-QuietAgentReferenceBlock {
    <#
    .SYNOPSIS
    Replaces one well-formed managed block while preserving all surrounding text and its newline style.
    .PARAMETER Text
    Strictly decoded existing project Markdown, including any BOM.
    .PARAMETER Reference
    Project-relative document path.
    .PARAMETER Claude
    Uses a Claude import reference instead of a Markdown link.
    #>
    param([AllowEmptyString()][string]$Text,[string]$Reference,[switch]$Claude)
    $begin='<!-- quietcli:instructions:begin -->';$end='<!-- quietcli:instructions:end -->'
    $starts=[regex]::Matches($Text,[regex]::Escape($begin));$ends=[regex]::Matches($Text,[regex]::Escape($end))
    if(($starts.Count -or $ends.Count) -and ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $starts[0].Index -ge $ends[0].Index)){throw 'AgentInstructionMalformedBlock'}
    $first=[regex]::Match($Text,"\r\n|\n|\r");$newline=if($first.Success){$first.Value}else{"`n"}
    $lines=@($begin,'## QuietCli')
    if($Claude){$lines+='Before running commands, read and apply the QuietCli instructions at the following path:';$lines+='@'+$Reference.Replace(' ','\ ')}
    else{
        $link=$Reference.Replace('%','%25').Replace('<','%3C').Replace('>','%3E').Replace('#','%23').Replace('?','%3F')
        $lines+="Before running commands, read and apply the [QuietCli instructions](<$link>)."
    }
    $block=($lines+$end) -join $newline
    if($starts.Count){$after=$ends[0].Index+$end.Length;return $Text.Substring(0,$starts[0].Index)+$block+$Text.Substring($after)}
    $separator=if($Text.Length -and $Text -notmatch '[\r\n]$'){$newline}else{''}
    return $Text+$separator+$block+$newline
}

function Add-QuietAgentInstruction {
    <#
    .SYNOPSIS
    Copies production instructions and adds portable references to selected project Markdown files.
    .DESCRIPTION
    Preflights all UTF-8 sources, paths and managed blocks before writing. Copies AGENTS.md and
    SKILL.md together, preserving their bytes and mutual links. Only the delimited reference
    block is replaced in existing project files. Repeated identical calls do not rewrite files.
    No engine, native process, telemetry, profile edit or native skill registration is involved.
    .PARAMETER Path
    Existing project directory; defaults to the current directory.
    .PARAMETER Agents
    Creates or updates the project's AGENTS.md.
    .PARAMETER Claude
    Creates or updates CLAUDE.md with a relative import.
    .PARAMETER Skills
    Creates or updates SKILLS.md; does not register a native agent skill.
    .PARAMETER DocumentDirectory
    Managed copy directory, relative to Path or an explicit absolute path on the same filesystem root.
    .PARAMETER Document
    Auto selects AGENTS.md for Agents/Claude and SKILL.md for Skills. Agents or Skill overrides all targets.
    .OUTPUTS
    System.Management.Automation.PSCustomObject with Files and Documents metadata. This is not a native execution envelope.
    .EXAMPLE
    $installation = Add-QuietAgentInstruction -Path ./project -Agents
    $installation.Files
    #>
    [CmdletBinding(SupportsShouldProcess)]param(
        [ValidateNotNullOrEmpty()][string]$Path=(Get-Location).Path,
        [switch]$Agents,[switch]$Claude,[switch]$Skills,
        [ValidateNotNullOrEmpty()][string]$DocumentDirectory='.skills',
        [ValidateSet('Auto','Agents','Skill')][string]$Document='Auto'
    )
    if(!$Agents -and !$Claude -and !$Skills){throw 'AgentInstructionTargetRequired'}
    $project=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($project -isnot [IO.DirectoryInfo]){throw 'AgentInstructionProjectMustBeDirectory'}
    $copyRoot=[IO.Path]::GetFullPath($DocumentDirectory.Replace('\',[IO.Path]::DirectorySeparatorChar),$project.FullName)
    $relative=[IO.Path]::GetRelativePath($project.FullName,$copyRoot)
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '[\r\n]'){throw 'AgentInstructionNonportableDirectory'}
    $sourceRoot=Get-QuietAgentDocumentDirectory
    $sourcePaths=@(foreach($name in @('AGENTS.md','SKILL.md')){[IO.Path]::Combine($sourceRoot,$name)})
    $selected=@(@{Enabled=$Agents;Name='AGENTS.md';Choice='Agents'},@{Enabled=$Claude;Name='CLAUDE.md';Choice='Agents'},@{Enabled=$Skills;Name='SKILLS.md';Choice='Skill'})
    $targets=@(foreach($target in $selected){if($target.Enabled){[IO.Path]::Combine($project.FullName,$target.Name)}})
    $copies=@(foreach($source in $sourcePaths){
        $bytes=[IO.File]::ReadAllBytesAsync($source).GetAwaiter().GetResult();$null=$script:QuietUtf8.GetString($bytes)
        $destination=[IO.Path]::Combine($copyRoot,[IO.Path]::GetFileName($source))
        Assert-QuietAgentWritePath $destination ($sourcePaths+$targets)
        $exists=[IO.File]::Exists($destination)
        $same=$exists -and [Convert]::ToBase64String([IO.File]::ReadAllBytesAsync($destination).GetAwaiter().GetResult()) -ceq [Convert]::ToBase64String($bytes)
        [pscustomobject]@{Path=$destination;Bytes=$bytes;Exists=$exists;Same=$same}
    })
    $pending=@(foreach($target in $selected){if(!$target.Enabled){continue}
        $destination=[IO.Path]::Combine($project.FullName,$target.Name)
        Assert-QuietAgentWritePath $destination ($sourcePaths+@($copies.Path))
        $choice=if($Document -eq 'Auto'){$target.Choice}else{$Document}
        $name=if($choice -eq 'Agents'){'AGENTS.md'}else{'SKILL.md'}
        $reference='./'+[IO.Path]::GetRelativePath($project.FullName,[IO.Path]::Combine($copyRoot,$name)).Replace('\','/')
        $exists=[IO.File]::Exists($destination)
        $text=if($exists){$script:QuietUtf8.GetString([IO.File]::ReadAllBytesAsync($destination).GetAwaiter().GetResult())}else{''}
        $content=Set-QuietAgentReferenceBlock -Text $text -Reference $reference -Claude:($target.Name -eq 'CLAUDE.md')
        [pscustomobject]@{Path=$destination;SourcePath=[IO.Path]::Combine($copyRoot,$name);ReferencePath=$reference;Document=$choice;Exists=$exists;Same=($exists -and $content -ceq $text);Content=$content}
    })
    $documents=@(foreach($item in $copies){
        $status=if($item.Same){'Unchanged'}elseif($PSCmdlet.ShouldProcess($item.Path,'Copy production QuietCli instructions')){
            [void][IO.Directory]::CreateDirectory($copyRoot)
            [void][IO.File]::WriteAllBytesAsync($item.Path,$item.Bytes).GetAwaiter().GetResult()
            if($item.Exists){'Updated'}else{'Created'}
        }elseif($WhatIfPreference){'Simulated'}else{'Skipped'}
        [pscustomobject]@{Path=$item.Path;Status=$status}
    })
    $declined=@($documents|Where-Object Status -EQ Skipped).Count -gt 0
    $files=@(foreach($item in $pending){
        $status=if($item.Same){'Unchanged'}elseif($declined){'Skipped'}elseif($PSCmdlet.ShouldProcess($item.Path,'Add production QuietCli instruction reference')){
            [void][IO.File]::WriteAllTextAsync($item.Path,$item.Content,$script:QuietUtf8).GetAwaiter().GetResult()
            if($item.Exists){'Updated'}else{'Created'}
        }elseif($WhatIfPreference){'Simulated'}else{'Skipped'}
        [pscustomobject]@{Path=$item.Path;Document=$item.Document;SourcePath=$item.SourcePath;ReferencePath=$item.ReferencePath;Status=$status}
    })
    [pscustomobject]@{Files=$files;Documents=$documents}
}
