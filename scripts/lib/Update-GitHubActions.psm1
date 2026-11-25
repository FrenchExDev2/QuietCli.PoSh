#requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionReferences.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionReleases.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionUpdates.psm1')) -DisableNameChecking -ErrorAction Stop

function Read-QuietGitHubActionSource {
    <#
    .SYNOPSIS
    Reads one text file as strict UTF-8 and returns {FullPath, Text, Bom, Sha256}, Sha256 being that of its bytes.
    .PARAMETER FullPath
    File to read.
    #>
    param([Parameter(Mandatory)][string]$FullPath)
    $bytes=[IO.File]::ReadAllBytes($FullPath)
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset=if($bom){3}else{0}
    try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)}catch{throw ('GitHubActionFileNotUtf8: '+$FullPath)}
    [pscustomobject]@{FullPath=$FullPath;Text=$text;Bom=$bom;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}

function ConvertTo-QuietGitHubActionBytes {
    <#
    .SYNOPSIS
    Encodes a text as UTF-8, with the BOM only when the source had one.
    .PARAMETER Text
    Text to encode.
    .PARAMETER Bom
    Whether to prefix the UTF-8 BOM.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[bool]$Bom)
    $encoding=[Text.UTF8Encoding]::new($Bom,$true)
    [byte[]]($encoding.GetPreamble()+$encoding.GetBytes($Text))
}

function Assert-QuietGitHubActionSourceCurrent {
    <#
    .SYNOPSIS
    Rejects changes to a planned source since its original read.
    .PARAMETER Source
    Object returned by Read-QuietGitHubActionSource.
    #>
    param([Parameter(Mandatory)][object]$Source)
    $current=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Source.FullPath)))
    if($current -cne $Source.Sha256){throw ('GitHubActionSourceChanged: '+$Source.FullPath+' changed since it was read')}
}

function Write-QuietGitHubActionSource {
    <#
    .SYNOPSIS
    Replaces a file atomically with new bytes, after checking that it still has the bytes that were read.
    .DESCRIPTION
    A concurrent edit since the read throws GitHubActionSourceChanged and leaves the file untouched. The bytes go
    to a temporary sibling file first, which then replaces the target, so a failure never leaves a partial file.
    .PARAMETER Source
    Object returned by Read-QuietGitHubActionSource.
    .PARAMETER Bytes
    New content.
    #>
    param([Parameter(Mandatory)][object]$Source,[Parameter(Mandatory)][byte[]]$Bytes)
    Assert-QuietGitHubActionSourceCurrent -Source $Source
    $temporary=$Source.FullPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{[IO.File]::WriteAllBytes($temporary,$Bytes);[IO.File]::Move($temporary,$Source.FullPath,$true)}
    finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Format-QuietGitHubActionRef {
    <#
    .SYNOPSIS
    Shortens a ref for the report: a commit id to 12 digits, followed by its comment in parentheses.
    .PARAMETER Ref
    Ref after '@'.
    .PARAMETER Comment
    Comment without '#', or null.
    #>
    param([string]$Ref,[AllowNull()][string]$Comment)
    $shown=if($Ref -cmatch '\A[0-9a-f]{40}\z'){$Ref.Substring(0,12)}else{$Ref}
    if(![string]::IsNullOrWhiteSpace($Comment)){$shown+=' ('+$Comment.Trim()+')'}
    $shown
}

function Test-QuietGitHubActionSelected {
    <#
    .SYNOPSIS
    Returns whether an owner/repository action matches one Include wildcard and no Exclude wildcard.
    .PARAMETER Action
    owner/repository.
    .PARAMETER Include
    Wildcards selecting actions.
    .PARAMETER Exclude
    Wildcards removing actions after Include.
    #>
    param([Parameter(Mandatory)][string]$Action,[string[]]$Include=@(),[string[]]$Exclude=@())
    foreach($pattern in $Exclude){if($Action -like $pattern){return $false}}
    foreach($pattern in $Include){if($Action -like $pattern){return $true}}
    $false
}

function Invoke-QuietScriptUpdateGitHubActions {
    <#
    .SYNOPSIS
    Reports, and with -Apply writes, the latest release of every action referenced by the GitHub workflows and composite actions.
    .DESCRIPTION
    Reads .github/workflows/*.yml|yaml and .github/actions/**/action.yml|yaml, finds every remote uses:
    reference, resolves the latest release of each distinct action (GitHub API, or -ReleaseCatalogPath) and
    decides each line with Get-QuietGitHubActionUpdate: a commit pin stays a commit pin, with its '# vX.Y.Z'
    comment following the tag; a version tag moves to the new tag; branches, prereleases above the latest
    release and repositories without releases are reported and left alone. Local (./) and docker:// references
    are ignored.
    Every release is resolved and every change validated before the first write: an unknown release, an invalid
    reference or a stale receipt stops the run with nothing written. Without -Apply nothing is written. With
    -Apply each changed workflow or action and its optional receipt share one ShouldProcess decision, so
    -WhatIf shows all planned paths and -Confirm asks once per update. Each file is replaced atomically
    after checking it did not change since it was read.
    With -RefreshWorkflowReceipts, the documentation receipt of each written workflow
    (docs/ci/github/script-<name>.md, RAC-WF-001) moves to the new file hash, only if it matched the old one:
    a pin-only edit does not change documented behavior, so the existing review still applies.
    .PARAMETER WorkspaceRoot
    Checkout whose .github directory is read and updated.
    .PARAMETER Apply
    Writes the updates; without it the run only reports.
    .PARAMETER Include
    Wildcards over owner/repository selecting the actions to update (default every action).
    .PARAMETER Exclude
    Wildcards over owner/repository excluded after Include.
    .PARAMETER ReleaseCatalogPath
    JSON catalog {"owner/repository": {"Tag", "Sha"}} used instead of the GitHub API.
    .PARAMETER RefreshWorkflowReceipts
    Also moves the current receipts of the written workflows' documents to their new hash.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))),
        [switch]$Apply,
        [string[]]$Include=@('*'),
        [string[]]$Exclude=@(),
        [string]$ReleaseCatalogPath,
        [switch]$RefreshWorkflowReceipts
    )
    $ErrorActionPreference='Stop'
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $catalog=if($ReleaseCatalogPath){Read-QuietGitHubActionReleaseCatalog -Path ([IO.Path]::GetFullPath($ReleaseCatalogPath))}else{$null}

    $sources=@(foreach($file in Get-QuietGitHubActionFiles -WorkspaceRoot $root){
        $source=Read-QuietGitHubActionSource -FullPath $file.FullPath
        $source|Add-Member -NotePropertyName RelativePath -NotePropertyValue $file.RelativePath
        $source|Add-Member -NotePropertyName References -NotePropertyValue @(ConvertFrom-QuietGitHubActionUses -Text $source.Text -Path $file.RelativePath)
        $source
    })
    $remote=@(foreach($source in $sources){foreach($reference in $source.References){
        if($reference.Kind -ceq 'Remote' -and (Test-QuietGitHubActionSelected -Action $reference.Action -Include $Include -Exclude $Exclude)){$reference}
    }})
    # ForEach-Object -MemberName honors $WhatIfPreference and returns nothing under -WhatIf: keep a plain loop.
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $actions=[string[]]@(foreach($reference in $remote){if($seen.Add($reference.Action)){$reference.Action}})
    $releases=Resolve-QuietGitHubActionReleases -Actions $actions -Catalog $catalog
    $decisions=@(foreach($reference in $remote){Get-QuietGitHubActionUpdate -Reference $reference -Release $releases[$reference.Action]})

    # Every new text, hash and receipt is computed before the first write.
    $plans=@(foreach($source in $sources){
        $changes=@($decisions|Where-Object {$_.Status -ceq 'Update' -and $_.Reference.Path -ceq $source.RelativePath}|ForEach-Object {[pscustomobject]@{LineNumber=$_.Reference.LineNumber;Line=$_.Reference.Line;NewLine=$_.NewLine}})
        if(!$changes.Count){continue}
        $text=Get-QuietGitHubActionRewrittenText -Text $source.Text -Changes $changes
        $bytes=ConvertTo-QuietGitHubActionBytes -Text $text -Bom $source.Bom
        $receipt=$null
        $document=Get-QuietGitHubActionWorkflowDocumentPath -RelativePath $source.RelativePath
        if($RefreshWorkflowReceipts -and $document){
            $documentPath=[IO.Path]::Combine($root,$document)
            if([IO.File]::Exists($documentPath)){
                $documentSource=Read-QuietGitHubActionSource -FullPath $documentPath
                $newSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
                try{$documentText=Get-QuietGitHubActionReceiptText -Text $documentSource.Text -PreviousSha256 $source.Sha256 -NewSha256 $newSha}
                catch{throw ('GitHubActionReceiptNotCurrent: '+$document+' does not record the current '+$source.RelativePath+'; review it first')}
                $receipt=[pscustomobject]@{RelativePath=$document;Source=$documentSource;Bytes=(ConvertTo-QuietGitHubActionBytes -Text $documentText -Bom $documentSource.Bom)}
            }
        }
        [pscustomobject]@{Source=$source;Changes=$changes;Bytes=$bytes;Receipt=$receipt}
    })

    $rows=@($decisions|Group-Object {$_.Reference.Value+'|'+$_.Reference.Comment+'|'+$_.Status}|ForEach-Object {
        $first=$_.Group[0]
        [pscustomobject]@{
            Action=$first.Reference.Action+$(if($first.Reference.SubPath){'/'+$first.Reference.SubPath}else{''})
            From=Format-QuietGitHubActionRef -Ref $first.Reference.Ref -Comment $first.Reference.Comment
            To=if($first.Status -ceq 'Update'){Format-QuietGitHubActionRef -Ref $first.Ref -Comment $first.Comment}else{''}
            Status=$first.Status
            Reason=$first.Reason
            Count=$_.Count
        }
    }|Sort-Object Action,From)
    if($rows.Count){Write-Host ($rows|Format-Table Action,From,To,Status,Reason,Count -AutoSize|Out-String -Width 240).TrimEnd()}
    $updates=@($decisions|Where-Object Status -ceq 'Update').Count
    Write-Host ('Summary: {0} reference(s) in {1} file(s); {2} to update in {3} file(s), {4} up to date, {5} skipped.' -f $remote.Count,$sources.Count,$updates,$plans.Count,@($decisions|Where-Object Status -ceq 'UpToDate').Count,@($decisions|Where-Object Status -ceq 'Skipped').Count)
    if(!$Apply -and $plans.Count){Write-Host 'Nothing written: run with -Apply to write these updates (-WhatIf previews them).'}

    $written=[Collections.Generic.List[string]]::new()
    $receipts=[Collections.Generic.List[string]]::new()
    if($Apply){
        foreach($plan in $plans){
            $target=$plan.Source.RelativePath
            if($plan.Receipt){$target+=' and '+$plan.Receipt.RelativePath}
            if(!$PSCmdlet.ShouldProcess($target,('Update '+$plan.Changes.Count+' GitHub action reference(s) to their latest release'))){continue}
            if($plan.Receipt){Assert-QuietGitHubActionSourceCurrent -Source $plan.Receipt.Source}
            Write-QuietGitHubActionSource -Source $plan.Source -Bytes $plan.Bytes
            $written.Add($plan.Source.RelativePath)
            if($plan.Receipt){
                Write-QuietGitHubActionSource -Source $plan.Receipt.Source -Bytes $plan.Receipt.Bytes
                $receipts.Add($plan.Receipt.RelativePath)
            }
        }
    }
    [pscustomobject]@{
        Check='GitHubActions'
        Files=$sources.Count
        References=$remote.Count
        Updates=$updates
        UpToDate=@($decisions|Where-Object Status -ceq 'UpToDate').Count
        Skipped=@($decisions|Where-Object Status -ceq 'Skipped').Count
        PlannedFiles=[string[]]@($plans|ForEach-Object {$_.Source.RelativePath})
        WrittenFiles=[string[]]$written.ToArray()
        RefreshedReceipts=[string[]]$receipts.ToArray()
        Applied=$written.Count -gt 0
        Rows=$rows
    }
}

Export-ModuleMember -Function 'Invoke-QuietScriptUpdateGitHubActions'
