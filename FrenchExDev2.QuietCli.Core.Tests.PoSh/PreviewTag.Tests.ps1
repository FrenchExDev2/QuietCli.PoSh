function Test-QuietPreviewTagProperties {
    <#
    .SYNOPSIS
    Checks timestamp identity, UTC equivalence, precision, culture independence and malformed versions.
    .PARAMETER Create
    Production or sandbox-mutated tag factory.
    #>
    param([scriptblock]$Create)
    $instant = [DateTimeOffset]::Parse('2026-11-08T14:30:00.1234567+01:00', [Globalization.CultureInfo]::InvariantCulture)
    if ((& $Create '0.2.0' $instant) -cne 'v0.2.0-preview20261108T1330001234567Z') { throw 'TagExactIdentity' }
    $random = [Random]::new(81126)
    for ($i = 0; $i -lt 128; $i++) {
        $version = '{0}.{1}.{2}' -f $random.Next(0, 50), $random.Next(0, 100), $random.Next(0, 100)
        $utc = $instant.AddDays($random.Next(-10000, 10000)).ToUniversalTime()
        $tag = & $Create $version $utc
        if (!$tag.StartsWith("v$version-preview", [StringComparison]::Ordinal)) { throw 'TagVersionLost' }
        if ($tag -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+-preview[0-9]{8}T[0-9]{13}Z\z') { throw 'TagFormatInvalid' }
        if ($tag -cne (& $Create $version ($utc.ToOffset([TimeSpan]::FromHours($random.Next(-12, 13)))))) { throw 'TagUtcEquivalence' }
        $next = & $Create $version ($utc.AddTicks(1))
        if ([StringComparer]::Ordinal.Compare($tag, $next) -ge 0) { throw 'TagPrecisionOrOrderingLost' }
    }
    $culture = [Globalization.CultureInfo]::CurrentCulture
    try {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('ar-SA')
        if ((& $Create '0.2.0' $instant) -cne 'v0.2.0-preview20261108T1330001234567Z') { throw 'TagCultureDependent' }
    } finally { [Globalization.CultureInfo]::CurrentCulture = $culture }
    $corpus = @('', ' ', '0.2', '0.2.0.1', '00.2.0', '-1.2.3', '0.2.0-preview', '0.2.0+build', '../0.2.0', "0.2.0`n", "0.2.0`0", 'v0.2.0', '٠.٢.٠')
    $corpus += @(for ($i = 0; $i -lt 64; $i++) { '1.2.3' + [char]$random.Next(1, 32) })
    foreach ($value in $corpus) {
        $rejected = $false
        try { $null = & $Create $value $instant } catch { $rejected = $true }
        if (!$rejected) { throw 'TagMalformedVersionAccepted' }
    }
}

function Invoke-QuietPreviewTagTests {
    <#
    .SYNOPSIS
    Exercises local annotated tags in an owned repository and targeted identity mutations.
    .PARAMETER WorkspaceRoot
    Source checkout supplying the script and built local modules.
    .PARAMETER RunDirectory
    External report root containing the owned Git fixture.
    .PARAMETER Mutation
    Runs the bounded pure-factory mutation catalogue.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory, [switch]$Mutation)
    $modulePath = Join-Path $WorkspaceRoot 'scripts/lib/PreviewTag.psm1'
    Import-Module $modulePath -Force
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1')
    Test-QuietPreviewTagProperties { param($version, $stamp) New-QuietPreviewTagName $version $stamp }
    $directory = Join-Path $RunDirectory 'preview-tag-fixture'
    [void][IO.Directory]::CreateDirectory($directory)
    $empty = Join-Path $directory 'empty-template'
    [void][IO.Directory]::CreateDirectory($empty)
    function Invoke-TagFixtureGit {
        <#
        .SYNOPSIS
        Executes a fixture command and retains only its requested small scalar output.
        .PARAMETER Arguments
        Exact native arguments for the owned disposable repository.
        #>
        param([string[]]$Arguments)
        $result = quiet -AsObject -C preview-tag-tests -WorkingDirectory $directory -RecordDelimiter "`n" `
            -Data @{ Value = '' } -Output {
                param($event, $runtime)
                if ($event.Stream -eq 'stdout') {
                    if ($runtime.Data.Value.Length + $event.Text.Length -gt 4096) { throw 'TagFixtureOutputTooLarge' }
                    $runtime.Data.Value += $event.Text
                }
            } -Complete { param($runtime) $runtime.Data } -FilePath git -ArgumentList $Arguments
        if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis) { throw "TagFixtureGitFailed: $($Arguments[0])" }
        return $result.Data.Value.TrimEnd([char[]]"`r`n")
    }
    $null = Invoke-TagFixtureGit @('init', '--quiet', "--template=$empty", '.')
    $null = Invoke-TagFixtureGit @('config', 'user.name', 'Preview tag fixture')
    $null = Invoke-TagFixtureGit @('config', 'user.email', 'preview-tag@example.invalid')
    $null = Invoke-TagFixtureGit @('config', 'core.hooksPath', $empty)
    $moduleRoot = Join-Path $directory 'FrenchExDev2.QuietCli.Core.PoSh'
    [void][IO.Directory]::CreateDirectory($moduleRoot)
    $manifest = Join-Path $moduleRoot 'FrenchExDev2.QuietCli.Core.PoSh.psd1'
    $manifestText = "@{ModuleVersion='3.4.5';PrivateData=@{PSData=@{Prerelease='preview'};QuietCli=@{Publishable=`$true}}}`n"
    [void][IO.File]::WriteAllTextAsync($manifest, $manifestText, [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $null = Invoke-TagFixtureGit @('add', '--', '.')
    $null = Invoke-TagFixtureGit @('-c', 'commit.gpgSign=false', 'commit', '--quiet', '--no-verify', '-m', 'Owned fixture')
    $script = Join-Path $WorkspaceRoot 'scripts/New-QuietPreviewTag.ps1'
    $stamp = [DateTimeOffset]::Parse('2026-11-08T14:30:00.1234567+01:00')
    $before = Invoke-TagFixtureGit @('rev-parse', 'HEAD')
    $plan = & $script -WorkspaceRoot $directory -Timestamp $stamp -WhatIf
    if ($plan.Created -or !$plan.Clean -or $plan.Tag -cne 'v3.4.5-preview20261108T1330001234567Z' -or (Invoke-TagFixtureGit @('tag', '--list'))) { throw 'TagWhatIfChangedRefs' }
    $created = & $script -WorkspaceRoot $directory -Timestamp $stamp -Confirm:$false
    if (!$created.Created -or $created.Revision -cne $before -or $created.Version -cne '3.4.5') { throw 'TagCreationFailed' }
    if ((Invoke-TagFixtureGit @('cat-file', '-t', "refs/tags/$($created.Tag)")) -cne 'tag') { throw 'TagNotAnnotated' }
    if ((Invoke-TagFixtureGit @('rev-parse', "$($created.Tag)^{commit}")) -cne $before) { throw 'TagWrongTarget' }
    $rejected = $false
    try { $null = & $script -WorkspaceRoot $directory -Timestamp $stamp -Confirm:$false } catch { $rejected = $_.Exception.Message -like 'PreviewTagAlreadyExists:*' }
    if (!$rejected) { throw 'TagCollisionNotRejected' }
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'dirty.txt'), "uncommitted`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $rejected = $false
    try { $null = & $script -WorkspaceRoot $directory -Timestamp ($stamp.AddSeconds(1)) -Confirm:$false } catch { $rejected = $_.Exception.Message -like 'PreviewTagDirtyCheckout:*' }
    if (!$rejected) { throw 'TagDirtyCheckoutAccepted' }
    $dirtyPlan = & $script -WorkspaceRoot $directory -Timestamp ($stamp.AddSeconds(1)) -WhatIf
    if ($dirtyPlan.Clean -or $dirtyPlan.Created) { throw 'TagDirtyPreviewInvalid' }
    $rejected = $false
    try { $null = & $script -WorkspaceRoot $moduleRoot -WhatIf } catch { $rejected = $_.Exception.Message -eq 'PreviewTagWorkspaceMustBeRepositoryRoot' }
    if (!$rejected) { throw 'TagNestedRootAccepted' }
    if ((Invoke-TagFixtureGit @('tag', '--list')) -cne $created.Tag -or (Invoke-TagFixtureGit @('rev-parse', 'HEAD')) -cne $before) { throw 'TagUnexpectedRefs' }
    if ([IO.File]::ReadAllTextAsync($manifest, [Text.Encoding]::UTF8).GetAwaiter().GetResult() -cne $manifestText) { throw 'TagChangedManifest' }
    $releasePreview=& $script -WorkspaceRoot $directory -Release -WhatIf
    if($releasePreview.Created -or $releasePreview.Clean -or $releasePreview.Tag -cne 'QuietCli/v3.4.5-preview' -or $releasePreview.Version -cne '3.4.5-preview'){throw 'ReleaseTagPreviewInvalid'}
    $rejected=$false
    try{$null=& $script -WorkspaceRoot $directory -Release -Confirm:$false}catch{$rejected=$_.Exception.Message -like 'PreviewTagDirtyCheckout:*'}
    if(!$rejected){throw 'ReleaseTagDirtyCheckoutAccepted'}
    Remove-Item -LiteralPath (Join-Path $directory 'dirty.txt')
    $releaseTag=& $script -WorkspaceRoot $directory -Release -Confirm:$false
    if(!$releaseTag.Created -or (Invoke-TagFixtureGit @('cat-file','-t',"refs/tags/$($releaseTag.Tag)")) -cne 'tag' -or (Invoke-TagFixtureGit @('rev-parse',"$($releaseTag.Tag)^{commit}")) -cne $before){throw 'ReleaseTagCreationInvalid'}
    $rejected=$false
    try{$null=& $script -WorkspaceRoot $directory -Release -Confirm:$false}catch{$rejected=$_.Exception.Message -like 'PreviewTagAlreadyExists:*'}
    if(!$rejected -or [IO.File]::ReadAllText($manifest,[Text.Encoding]::UTF8) -cne $manifestText){throw 'ReleaseTagCollisionOrSourceMutation'}
    $mutants = [Collections.Generic.List[object]]::new()
    if ($Mutation) {
        $source = [IO.File]::ReadAllTextAsync($modulePath, [Text.Encoding]::UTF8).GetAwaiter().GetResult()
        foreach ($mutant in @(
            @{ Name = 'version-identity'; From = 'v$Version-preview'; To = 'v0.0.1-preview' },
            @{ Name = 'utc-conversion'; From = '$Timestamp.ToUniversalTime()'; To = '$Timestamp' },
            @{ Name = 'timestamp-precision'; From = 'ssfffffff'; To = 'ssfff' },
            @{ Name = 'strict-version'; From = "if ($" + "Version -cnotmatch"; To = "if ($" + "false -and $" + "Version -cnotmatch" }
        )) {
            if ([regex]::Matches($source, [regex]::Escape($mutant.From)).Count -ne 1) { throw 'TagInvalidMutantAnchor' }
            $changed = $source.Replace($mutant.From, $mutant.To)
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseInput($changed, [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw 'TagInvalidMutantSyntax' }
            $outcome = 'Survived'
            try {
                & { param($text)
                    . ([scriptblock]::Create($text.Replace('Export-ModuleMember -Function New-QuietPreviewTagName', '')))
                    Test-QuietPreviewTagProperties { param($version, $stamp) New-QuietPreviewTagName $version $stamp }
                } $changed
            } catch { $outcome = 'Killed' }
            $mutants.Add([pscustomobject]@{ Name = $mutant.Name; Outcome = $outcome })
        }
    }
    $report = @{ Seed = 81126; GeneratedInputs = 128; MalformedInputs = 77; Lifecycle = 'Passed'; Mutations = $mutants.ToArray(); ExternalPublication = $false }
    Write-WorkspaceJson (Join-Path $RunDirectory 'preview-tags.json') $report
    if (@($mutants | Where-Object Outcome -NE Killed).Count) { throw 'TagMutationSurvived' }
}
