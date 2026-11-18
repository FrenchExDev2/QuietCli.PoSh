#requires -Version 7.6
function Get-QuietWorkflowYamlParser {
    <#
    .SYNOPSIS
    Returns the verified YAML parser used by the workflow documentation generators.
    .PARAMETER Preview
    Resolves the pinned parser without restoring a missing resource.
    .PARAMETER ConfirmRestore
    Forwards an explicitly supplied confirmation preference to resource preparation.
    #>
    [CmdletBinding()]
    param([switch]$Preview,[Nullable[bool]]$ConfirmRestore)

    Import-Module ([IO.Path]::Combine($PSScriptRoot,'Resources.psm1')) -DisableNameChecking -ErrorAction Stop
    $restore = @{ WhatIf = [bool]$Preview }
    if ($PSBoundParameters.ContainsKey('ConfirmRestore')) { $restore.Confirm = [bool]$ConfirmRestore }
    $resource = Ensure-QuietResource -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder @restore
    if ($resource.State -cne 'Ready') { throw 'WorkflowYamlResourceNotReady: preview cannot prepare the missing parser.' }
    [YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
}

function Get-QuietWorkflowScriptPaths {
    <#
    .SYNOPSIS
    Finds literal repository PowerShell script paths in GitHub Actions run blocks.
    .PARAMETER Text
    One or more run blocks as text. Expressions and shell code are never evaluated.
    #>
    param([AllowEmptyString()][string]$Text)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches($Text, '(?<![\w.-])scripts[/\\](?:[\w.-]+[/\\])*[\w.-]+\.psm?1(?![\w./\\-])')) {
        $path = $match.Value.Replace('\','/')
        if ($path -notmatch '(^|/)\.{1,2}(/|$)' -and $seen.Add($path)) { $path }
    }
}

function Get-QuietWorkflowDocumentation {
    <#
    .SYNOPSIS
    Reads workflow structure and renders its deterministic documentation contract without executing YAML.
    .PARAMETER WorkspaceRoot
    Repository whose workflows and corresponding documentation are inspected.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $directory=[IO.Path]::Combine($WorkspaceRoot,'.github/workflows')
    $files=@(Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue|Where-Object Extension|Sort-Object Name)
    if(!$files.Count){return}
    $preview=@{Preview=[bool]$WhatIfPreference}
    if($PSBoundParameters.ContainsKey('Confirm')){$preview.ConfirmRestore=$PSBoundParameters['Confirm']}
    $parser=Get-QuietWorkflowYamlParser @preview
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($file in $files){
        if(!$file.Extension){continue}
        if(!$names.Add($file.BaseName)){throw 'WorkflowDocBasenameCollision'}
        $text=[IO.File]::ReadAllTextAsync($file.FullName,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
        $reader=[IO.StringReader]::new($text)
        try{$workflow=$parser.Deserialize($reader,[object])}finally{$reader.Dispose()}
        if($workflow -isnot [Collections.IDictionary] -or $workflow['jobs'] -isnot [Collections.IDictionary]){throw ('WorkflowStructureInvalid: '+$file.Name)}
        $jobs=$workflow['jobs']
        $triggers=$workflow['on']
        $events=if($triggers -is [Collections.IDictionary]){@($triggers.Keys|Sort-Object)}else{@($triggers)}
        $lines=[Collections.Generic.List[string]]::new()
        $lines.Add('<!-- workflow-generated:begin -->')
        $lines.Add('')
        $lines.Add('[Workflow source](../../../.github/workflows/'+[uri]::EscapeDataString($file.Name)+')')
        $lines.Add('')
        $lines.Add('## Jobs and dependencies')
        $lines.Add('')
        $lines.Add('Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.')
        $lines.Add('')
        $lines.Add('~~~mermaid')
        $lines.Add('flowchart TD')
        $eventLabel=[Net.WebUtility]::HtmlEncode(('Triggers: '+($events -join ', '))).Replace('"','&quot;')
        $lines.Add('    event["'+$eventLabel+'"]')
        $ids=@{};$usedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($name in @($jobs.Keys|Sort-Object)){
            $id='job_'+([regex]::Replace($name,'[^a-zA-Z0-9_]','_'))
            if(!$usedIds.Add($id)){throw 'WorkflowDiagramIdCollision'}
            $ids[$name]=$id
            $label=[Net.WebUtility]::HtmlEncode([string]$name).Replace('"','&quot;')
            $lines.Add('    '+$id+'["'+$label+'"]')
        }
        foreach($name in @($jobs.Keys|Sort-Object)){
            $needs=@($jobs[$name]['needs']|Where-Object {$_})
            if(!$needs.Count){$lines.Add('    event --> '+$ids[$name])}
            foreach($dependency in $needs){
                if(!$ids.ContainsKey($dependency)){throw ('WorkflowDependencyMissing: '+$name+'/'+$dependency)}
                $lines.Add('    '+$ids[$dependency]+' --> '+$ids[$name])
            }
        }
        $lines.Add('~~~')
        $lines.Add('')
        $lines.Add('| Job | Execution | Needs | Condition | Script entry points |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach($name in @($jobs.Keys|Sort-Object)){
            $job=$jobs[$name]
            $execution=if($job['uses']){'reuses '+$job['uses']}else{'runner '+(@($job['runs-on']) -join ', ')}
            if($job['container']){
                $container=if($job['container'] -is [Collections.IDictionary]){$job['container']['image']}else{$job['container']}
                $execution+='; container '+$container
            }
            $runText=@($job['steps']|Where-Object {$_}|ForEach-Object {$_['run']}) -join "`n"
            $scripts=@(foreach($scriptPath in Get-QuietWorkflowScriptPaths -Text $runText){
                $docPath=[IO.Path]::ChangeExtension(('docs/'+$scriptPath),'.md')
                if([IO.File]::Exists([IO.Path]::Combine($WorkspaceRoot,$docPath))){
                    '[`./'+$scriptPath+'`](../../'+(($docPath.Substring(5).Split('/') | ForEach-Object {[uri]::EscapeDataString($_)}) -join '/')+')'
                }else{'`./'+$scriptPath+'`'}
            })
            $cells=@($name,$execution,(@($job['needs']) -join ', '),$(if($job['if']){$job['if']}else{'default success condition'}),($scripts -join ', '))
            $cells=@($cells|ForEach-Object {([string]$_).Replace('|','&#124;').Replace("`r",'').Replace("`n",'<br>')})
            $lines.Add('| '+($cells -join ' | ')+' |')
        }
        $lines.Add('')
        $lines.Add('<!-- workflow-generated:end -->')
        [pscustomobject]@{
            Name=$file.Name;RelativePath='.github/workflows/'+$file.Name
            DocRelativePath='docs/ci/github/script-'+$file.BaseName+'.md'
            SourceSHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            Generated=($lines -join "`n");Workflow=$workflow
        }
    }
}
function Get-QuietWorkflowReadme {
    <#
    .SYNOPSIS
    Renders the navigable workflow documentation index from the inspected catalogue.
    .PARAMETER Entries
    Current workflow contracts.
    #>
    param([AllowEmptyCollection()][object[]]$Entries)
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in @('# GitHub workflow documentation','','Generated by [Sync-GitHubWorkflowsReadme.ps1](../../../scripts/Sync-GitHubWorkflowsReadme.ps1).','','Use [Export-GitHubWorkflowMap.ps1](../../scripts/Export-GitHubWorkflowMap.md) for a navigable map of triggers, reusable workflows and composite actions.','','Run ./scripts/Sync-GitHubWorkflowsReadme.ps1 -Apply to regenerate graphs and this index after reviewing the matching document and updating its source receipt.','','| Workflow | Contract |','| --- | --- |')){$lines.Add($line)}
    foreach($entry in $Entries){$lines.Add('| ['+$entry.Name+'](../../../'+$entry.RelativePath+') | [documentation]('+[IO.Path]::GetFileName($entry.DocRelativePath)+') |')}
    $lines.Add('')
    $lines.Add('[Execution model](../execution-model.md) and [automation requirements](../../README-automation-contracts.md).')
    return (($lines -join "`n")+"`n")
}

Export-ModuleMember -Function 'Get-QuietWorkflowDocumentation','Get-QuietWorkflowReadme','Get-QuietWorkflowYamlParser','Get-QuietWorkflowScriptPaths'
