function Test-QuietGitCommandReference {
    <#
    .SYNOPSIS
    Checks catalogue coverage, deterministic generation and write boundaries.
    .PARAMETER WorkspaceRoot
    Checkout containing the Git catalogue and tracked reference.
    .PARAMETER RunDirectory
    Owned test report directory.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory)

    $entryPoint = [IO.Path]::Combine($WorkspaceRoot, 'src/Git/scripts/Export-GitCommandReference.ps1')
    $document = [IO.Path]::Combine($WorkspaceRoot, 'docs/README-git-command-reference.md')
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    & $entryPoint -Check
    $expected = $utf8.GetString([IO.File]::ReadAllBytes($document))
    $commands = @([regex]::Matches($expected, '(?m)^\| `([^ `]+)` \| `[^`]+` \| \[`Invoke-QuietGit') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    $registered = @(Get-QuietGitCoverage | Where-Object Specialized | Select-Object -ExpandProperty Command | Sort-Object)
    Assert-QuietEqual ($commands -join ',') ($registered -join ',') 'Every specialized handler has one source entry'
    Assert-QuietEqual ($expected.Contains("`r")) $false 'Generated Markdown uses LF'

    $directory = [IO.Path]::Combine($RunDirectory, 'git-command-reference')
    $null = [IO.Directory]::CreateDirectory($directory)
    $output = [IO.Path]::Combine($directory, 'reference.md')
    & $entryPoint -OutputPath $output -WhatIf
    Assert-QuietEqual ([IO.File]::Exists($output)) $false 'Preview does not create a new document'
    foreach ($stale in @($null, '# stale', "`u{FEFF}$expected", $expected.Replace("`n", "`r`n"))) {
        if ($null -ne $stale) { [IO.File]::WriteAllText($output, $stale, $utf8) }
        $failure = $null
        try { & $entryPoint -OutputPath $output -Check } catch { $failure = $_.Exception.Message }
        if ($failure -notlike 'GitCommandReferenceStale:*') { throw 'Stale or missing reference accepted' }
        if ($null -ne $stale) {
            & $entryPoint -OutputPath $output -WhatIf
            $after = $utf8.GetString([IO.File]::ReadAllBytes($output))
            Assert-QuietEqual ($after.Equals($stale, [StringComparison]::Ordinal)) $true 'Check and preview leave existing bytes intact'
        }
    }
    & $entryPoint -OutputPath $output -Confirm:$false
    Assert-QuietEqual ([IO.File]::ReadAllText($output, $utf8)) $expected 'Generation matches the tracked reference'
    $timestamp = [datetime]::new(2020, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($output, $timestamp)
    & $entryPoint -OutputPath $output -Confirm:$false
    Assert-QuietEqual ([IO.File]::GetLastWriteTimeUtc($output)) $timestamp 'An identical reference is left untouched'
    Assert-QuietEqual (@([IO.Directory]::GetFiles($directory)).Count) 1 'No sibling temporary files remain'
}

function Test-QuietGitCommandReferenceGuidance {
    <#
    .SYNOPSIS
    Permutes guidance and checks catalogue and Markdown mutations against the renderer.
    .PARAMETER WorkspaceRoot
    Checkout containing the real Git source and guidance.
    .PARAMETER RunDirectory
    Owned test report directory.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory)

    $group = [IO.Path]::Combine($WorkspaceRoot, 'src/Git')
    $module = [IO.Path]::Combine($group, 'src/FrenchExDev2.QuietCli.Git.PoSh')
    Import-Module ([IO.Path]::Combine($group, 'scripts/lib/GitCommandReference.psm1')) -DisableNameChecking -ErrorAction Stop
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $guidancePath = [IO.Path]::Combine($group, 'scripts/GitCommandReference.json')
    $source = [IO.File]::ReadAllText($guidancePath, $utf8)
    $fixture = [IO.Path]::Combine($RunDirectory, 'git-reference-guidance.json')
    $expected = Get-QuietGitCommandReference -ModuleDirectory $module -GuidancePath $guidancePath
    $random = [Random]::new(10579)
    $guidance = $source | ConvertFrom-Json -AsHashtable
    foreach ($sample in 1..8) {
        $permuted = [ordered]@{}
        foreach ($name in ($guidance.Keys | Sort-Object { $random.Next() })) { $permuted[$name] = $guidance[$name] }
        [IO.File]::WriteAllText($fixture, ($permuted | ConvertTo-Json -Depth 6), $utf8)
        $actual = Get-QuietGitCommandReference -ModuleDirectory $module -GuidancePath $fixture
        Assert-QuietEqual $actual $expected "Ordering property sample $sample"
    }

    $mutations = @(
        @{ Change = { param($data) $data.Remove('status') }; Error = 'GitCommandReferenceCoverageMismatch:*' }
        @{ Change = { param($data) $data['unsupported'] = $data['status'] }; Error = 'GitCommandReferenceCoverageMismatch:*' }
        @{ Change = { param($data) $data['status'] = @() }; Error = 'GitCommandReferenceFormsMissing:*' }
        @{ Change = { param($data) $data['status'][0]['Form'] = 'log -1' }; Error = 'GitCommandReferenceFormInvalid:*' }
        @{ Change = { param($data) $data['status'] += $data['status'][0] }; Error = 'GitCommandReferenceFormInvalid:*' }
        @{ Change = { param($data) $data['status'][0]['Data'] = 42 }; Error = 'GitCommandReferenceFormInvalid:*' }
        @{ Change = { param($data) $data['status'][0]['Limits'] = 'example | broken table' }; Error = 'GitCommandReferenceFormInvalid:*' }
        @{ Change = { param($data) $data['status'][0]['Limits'] = "broken`nrow" }; Error = 'GitCommandReferenceFormInvalid:*' }
    )
    foreach ($mutation in $mutations) {
        $changed = $source | ConvertFrom-Json -AsHashtable
        $null = & $mutation.Change $changed
        [IO.File]::WriteAllText($fixture, ($changed | ConvertTo-Json -Depth 6), $utf8)
        $failure = $null
        try { $null = Get-QuietGitCommandReference -ModuleDirectory $module -GuidancePath $fixture }
        catch { $failure = $_.Exception.Message }
        if ($failure -notlike $mutation.Error) { throw "Guidance mutation escaped validation: $($mutation.Error)" }
    }
}

function Invoke-QuietGitDocumentationExample {
    <#
    .SYNOPSIS
    Runs a marked PowerShell example from the tracked documentation.
    .PARAMETER Path
    Document containing the example.
    .PARAMETER Name
    Name in the git-example marker immediately before the fence.
    #>
    param([string]$Path, [string]$Name)
    $markdown = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $pattern = '(?ms)^<!-- git-example:' + [regex]::Escape($Name) + ' -->\r?\n```powershell\r?\n(.*?)^```$'
    $match = [regex]::Match($markdown, $pattern)
    if (!$match.Success) { throw "Git documentation example missing: $Name" }
    & ([scriptblock]::Create($match.Groups[1].Value))
}

function Test-QuietGitDocumentationExamples {
    <#
    .SYNOPSIS
    Executes the Git examples against independent native and byte expectations.
    .PARAMETER WorkspaceRoot
    Checkout containing the examples.
    .PARAMETER RunDirectory
    Owned test report directory for the disposable Git repository.
    .PARAMETER Environment
    Isolated Git environment for the fixture preparer.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory, [hashtable]$Environment)

    $tutorial = [IO.Path]::Combine($WorkspaceRoot, 'docs/README-create-git-handler.md')
    $version = Invoke-QuietGitDocumentationExample -Path $tutorial -Name version
    Assert-QuietEqual $version.Command 'version'
    if (!$version.Version) { throw 'The documentation handler returned no version' }
    Assert-QuietEqual (@(Get-QuietHandler -Binary git | Where-Object Id -CEQ 'Example.Git.Version').Count) 0 'The example unregisters its handler'

    $repository = [IO.Path]::Combine($RunDirectory, 'git-reference-fixture')
    $null = [IO.Directory]::CreateDirectory($repository)
    Invoke-GitFixture $repository @('init', '--initial-branch=main') $Environment
    $payload = [byte[]]@(65, 0, 195, 169, 13, 10, 255)
    [IO.File]::WriteAllBytes([IO.Path]::Combine($repository, 'README.md'), $payload)
    Invoke-GitFixture $repository @('-c', 'core.autocrlf=false', 'add', '--', 'README.md') $Environment
    Invoke-GitFixture $repository @('-c', 'commit.gpgsign=false', 'commit', '-m', 'Blob reference fixture') $Environment
    $guide = [IO.Path]::Combine($WorkspaceRoot, 'src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/README.md')
    Push-Location -LiteralPath $repository
    try { $artifact = Invoke-QuietGitDocumentationExample -Path $guide -Name blob }
    finally { Pop-Location }
    Assert-QuietEqual $artifact.Bytes $payload.Length 'The reference projects the exact fixture byte count'
    Assert-QuietEqual $artifact.SHA256 ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload))) 'The artifact hash is independently calculated'
}
