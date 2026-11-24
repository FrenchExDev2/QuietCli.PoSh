#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceSolutions.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Resources.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop

function Resolve-NewCompanionBranch {
    <#
    .SYNOPSIS
    Resolves a branch override or derives the companion branch from the module group.
    #>
    param([string]$Name, [string]$GitBranch)
    if (!$GitBranch) { $GitBranch = $Name.ToLowerInvariant() }
    if ($GitBranch.Contains('/')) {
        $target = Resolve-QuietWorkBranchName -Branch $GitBranch
        if ($target.Kind -cne 'companion') { throw 'CompanionBranchKindRequired' }
        return $target.Branch
    }
    (Resolve-QuietWorkBranchName -Kind companion -Name $GitBranch).Branch
}

function Resolve-NewCompanionPath {
    <#
    .SYNOPSIS
    Resolves a workspace path and rejects linked components before reading or writing.
    #>
    param([string]$Root, [string]$RelativePath)
    $path = $Root
    foreach ($component in $RelativePath.Split('/')) {
        $path = [IO.Path]::Combine($path, $component)
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "CompanionPathLinkRejected: $path"
        }
    }
    $path
}

function Assert-NewCompanionAvailable {
    <#
    .SYNOPSIS
    Rejects group and package path collisions.
    #>
    param([string]$Root, [string]$Name)
    foreach ($relative in @("src/$Name")) {
        $path = Resolve-NewCompanionPath $Root $relative
        $parent = [IO.Path]::GetDirectoryName($path)
        if (Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop | Where-Object Name -IEQ ([IO.Path]::GetFileName($path))) {
            throw "CompanionDestinationExists: $relative"
        }
    }
    $product = "FrenchExDev2.QuietCli.$Name.PoSh"
    $tests = "FrenchExDev2.QuietCli.$Name.Tests.PoSh"
    if (Get-QuietWorkspaceProjects $Root | Where-Object { $_.SolutionGroup -ieq $Name -or $_.Name -in @($product, $tests) }) {
        throw "CompanionNameAlreadyUsed: $Name"
    }
}

function Write-NewCompanionText {
    <#
    .SYNOPSIS
    Writes a UTF-8 staged file with LF endings and exactly one final newline.
    #>
    param([string]$Path, [string]$Text)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [void][IO.File]::WriteAllTextAsync($Path, $Text.Replace("`r`n", "`n").TrimEnd("`n") + "`n", [Text.UTF8Encoding]::new($false, $true)).GetAwaiter().GetResult()
}

function Copy-NewCompanionInput {
    <#
    .SYNOPSIS
    Copies one checked workspace input into the staging workspace.
    #>
    param([string]$Root, [string]$Stage, [string]$RelativePath)
    $source = Resolve-NewCompanionPath $Root $RelativePath
    $target = [IO.Path]::Combine($Stage, $RelativePath)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy($source, $target)
}

function New-QuietCompanionFiles {
    <#
    .SYNOPSIS
    Renders the product, test project and optional compiled parser into staging.
    #>
    param([string]$Root, [string]$Stage, [string]$Name, [string]$Executable, [string]$LicenseText, [switch]$WithCSharp)
    $manifest = [ordered]@{
        Product = "FrenchExDev2.QuietCli.$Name.PoSh"
        Tests = "FrenchExDev2.QuietCli.$Name.Tests.PoSh"
        Runner = "Invoke-Quiet$($Name)Tests"
        Core = 'FrenchExDev2.QuietCli.Core.PoSh'
    }
    $core = Get-QuietWorkspaceProjects $Root | Where-Object Name -CEQ $manifest.Core
    if (!$core) { throw 'CompanionCoreManifestMissing' }
    $productPath = "src/$Name/src/$($manifest.Product)"
    $testsPath = "src/$Name/test/$($manifest.Tests)"
    $parserProject = "engine/QuietCli.$Name.Parser.csproj"
    $buildDeclaration = ''
    if ($WithCSharp) {
        $buildDeclaration = @"
            BuildProjects = @(
                @{ Project='$parserProject'; Outputs=@{'net10.0'='lib/parser/net10.0'; 'net11.0'='lib/parser/net11.0'} }
            )
"@
        Write-NewCompanionText ([IO.Path]::Combine($Stage, $productPath, $parserProject)) @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net10.0;net11.0</TargetFrameworks>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>QuietCli.$Name.Parser</AssemblyName>
  </PropertyGroup>
</Project>
"@
        Write-NewCompanionText ([IO.Path]::Combine($Stage, $productPath, 'engine/Parser.cs')) @"
namespace QuietCli.$Name;

internal static class Parser
{
}
"@
    }
    $productManifest = @"
@{
    RootModule = '$($manifest.Product).psm1'
    ModuleVersion = '0.1.0'
    GUID = '$([guid]::NewGuid())'
    Author = 'Stéphane Erard'
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ModuleName='$($manifest.Core)'; ModuleVersion='$($core.Manifest.ModuleVersion)'})
    Description = 'QuietCli companion module for $Executable.'
    FunctionsToExport = @()
    AliasesToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{Prerelease='preview'; Tags=@('QuietCli','$Name'); LicenseUri='https://opensource.org/license/mit'; ProjectUri='https://github.com/FrenchExDev2/QuietCli.PoSh'}
        QuietCli = @{
            SolutionGroup = '$Name'
            Binary = '$Executable'
            TestsModule = '$($manifest.Tests)'
            Publishable = `$false
$buildDeclaration
        }
    }
}
"@
    $testManifest = @"
@{
    RootModule = '$($manifest.Tests).psm1'
    ModuleVersion = '0.1.0'
    GUID = '$([guid]::NewGuid())'
    Author = 'Stéphane Erard'
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ModuleName='$($manifest.Product)'; ModuleVersion='0.1.0'})
    FunctionsToExport = @('$($manifest.Runner)')
    AliasesToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{QuietCli=@{
        SolutionGroup = '$Name'
        TestCatalogue = @{Runner='$($manifest.Runner)'; Sources=@()}
        TestExecution = @{
            SchemaVersion = 1
            DefaultMode = 'Ordered'
            DefaultReason = 'Inspect the local modules loaded in the test worker.'
            MaxParallelCases = 1
            Cases = @{}
        }
    }}
}
"@
    $runner = @'
#requires -Version 7.6
function __RUNNER__ {
    <#
    .SYNOPSIS
    Checks that the selected checkout loaded the companion and its Core dependency.
    .PARAMETER WorkspaceRoot
    QuietCli checkout providing the imported modules.
    .PARAMETER OnProgress
    Optional progress callback receiving the case, state, passed and failed counts.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot, [scriptblock]$OnProgress)

    $cases = [ordered]@{}
    $cases['loads the companion and Core from the selected checkout'] = {
        foreach ($entry in @{
            '__PRODUCT__' = '__PRODUCT_PATH__'
            'FrenchExDev2.QuietCli.Core.PoSh' = 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'
        }.GetEnumerator()) {
            $expected = [IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot, $entry.Value, $entry.Key + '.psm1'))
            # Inspect all modules so a separately installed module cannot satisfy the assertion.
            $loaded = @(Get-Module -Name $entry.Key -All)
            if (!$loaded.Count -or @($loaded | Where-Object Path -CNE $expected).Count) {
                throw "CompanionModulePathMismatch: $($entry.Key)"
            }
        }
    }
    $caseMetadata = @{
        'loads the companion and Core from the selected checkout' = @{TestKind='Integration'; Dependencies=@('FileSystem', 'EngineState')}
    }
    $passed = 0
    $failed = 0
    $results = foreach ($caseName in $cases.Keys) {
        if ($env:QUIETCLI_TEST_CASE -and $caseName -notlike $env:QUIETCLI_TEST_CASE) { continue }
        $label = "[Integration] $caseName"
        if ($OnProgress) { $null = & $OnProgress $label 'Running' $passed $failed }
        $errorText = $null
        try {
            & $cases[$caseName]
            $state = 'Passed'
            $passed++
        } catch {
            $state = 'Failed'
            $errorText = $_.ToString()
            $failed++
        }
        if ($OnProgress) { $null = & $OnProgress $label $state $passed $failed }
        [pscustomobject]@{Name=$caseName; State=$state; Error=$errorText; TestKind=$caseMetadata[$caseName].TestKind; Dependencies=$caseMetadata[$caseName].Dependencies}
    }
    if (!$passed -and !$failed) { throw 'CompanionTestCaseNotFound' }
    [pscustomobject]@{
        Project='__TESTS__'; Passed=$passed; Failed=$failed; Skipped=0
        Partial=[bool]$env:QUIETCLI_TEST_CASE; Incomplete=$false; StoppedAt=$null; Cases=@($results)
    }
}

Export-ModuleMember -Function '__RUNNER__'
'@
    $runner = $runner.Replace('__RUNNER__', $manifest.Runner).Replace('__PRODUCT__', $manifest.Product).Replace('__PRODUCT_PATH__', $productPath).Replace('__TESTS__', $manifest.Tests)
    $files = [ordered]@{
        "$productPath/$($manifest.Product).psd1" = $productManifest
        "$productPath/$($manifest.Product).psm1" = "#requires -Version 7.6`nExport-ModuleMember -Function @() -Alias @() -Cmdlet @() -Variable @()"
        "$productPath/README.md" = "# $Name companion`n`nThis package is a starting point for QuietCli handlers for $Executable. The test suite verifies local module loading. Add the supported commands and version coverage alongside the first handler."
        "$productPath/LICENSE_CREDITS.md" = $LicenseText
        "$testsPath/$($manifest.Tests).psd1" = $testManifest
        "$testsPath/$($manifest.Tests).psm1" = $runner
        "$testsPath/README.md" = "# $Name tests`n`nRun this companion's module-loading test from the QuietCli checkout with ``./scripts/Invoke-WorkspaceCi.ps1 -Suite $Name``. The suite requires the local Core build and uses no native $Executable installation."
    }
    foreach ($entry in $files.GetEnumerator()) {
        Write-NewCompanionText ([IO.Path]::Combine($Stage, $entry.Key)) $entry.Value
    }
    foreach ($directory in @($productPath, $testsPath)) {
        [IO.File]::Copy([IO.Path]::Combine($Root, 'LICENSE'), [IO.Path]::Combine($Stage, $directory, 'LICENSE'))
    }
}

function Add-QuietCompanionRegistration {
    <#
    .SYNOPSIS
    Adds one companion and suite while preserving the catalogue's existing text.
    #>
    param([string]$Text, [string]$Name)
    $text = $Text.Replace("`r`n", "`n")
    $sections = [regex]::Matches($text, '(?m)^suites:[ \t]*(?:#[^\n]*)?$')
    if ($sections.Count -ne 1) { throw 'CompanionCatalogueSuitesSectionInvalid' }
    $companion = "  $($Name):`n    src: src/$Name/src/FrenchExDev2.QuietCli.$Name.PoSh`n    test: src/$Name/test/FrenchExDev2.QuietCli.$Name.Tests.PoSh`n    requires: [Core]`n    image: none`n"
    $suite = "  $($Name):`n    test_project: FrenchExDev2.QuietCli.$Name.Tests.PoSh`n    command: Invoke-Quiet$($Name)Tests`n    requires: [$Name]`n    core_evidence: false`n"
    $text.Insert($sections[0].Index, $companion).TrimEnd("`n") + "`n" + $suite
}

function New-QuietCompanionStage {
    <#
    .SYNOPSIS
    Builds and validates the companion and its generated repository files in isolation.
    #>
    param([string]$Root, [string]$Stage, [string]$ScriptRoot, [string]$Name, [string]$Executable, [string]$LicenseText, [switch]$WithCSharp)
    $cataloguePath = [IO.Path]::GetRelativePath($Root,(Get-QuietCiCompanionCataloguePath $Root)).Replace('\','/')
    $resource = 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    foreach ($file in Get-QuietSourceFiles ([IO.Path]::Combine($Root, 'src'))) {
        # The solution generator observes these sources, and the catalogue reads the Core resource lock.
        if ($file.Path -match '\.(csproj|ps1|psm1|psd1|md)$' -or $file.Path.EndsWith('/resources/dependencies.lock.json')) {
            Copy-NewCompanionInput $Root $Stage ('src/' + $file.Path)
        }
    }
    Copy-NewCompanionInput $Root $Stage $resource
    $stagedYaml = Ensure-QuietResource -WorkspaceRoot $Stage -RelativePath 'resources/yaml/YamlDotNet.dll' -WhatIf
    if ($stagedYaml.State -cne 'Ready') { throw 'CompanionYamlResourceChanged' }
    New-QuietCompanionFiles $Root $Stage $Name  $Executable $LicenseText -WithCSharp:$WithCSharp
    $catalogue = [IO.File]::ReadAllText((Resolve-NewCompanionPath $Root $cataloguePath), [Text.UTF8Encoding]::new($false, $true))
    Write-NewCompanionText ([IO.Path]::Combine($Stage, $cataloguePath)) (Add-QuietCompanionRegistration $catalogue $Name)
    if($cataloguePath -ceq 'build/companions.yaml'){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'PullRequestChecklist.psm1')) -DisableNameChecking -ErrorAction Stop
        $templatePath='.github/pull_request_template.md'
        $template=[IO.File]::ReadAllText((Resolve-NewCompanionPath $Root $templatePath),[Text.Encoding]::UTF8)
        Write-NewCompanionText ([IO.Path]::Combine($Stage,$templatePath)) (Expand-QuietPullRequestTemplate -Template $template -Configuration (Read-QuietCiCompanions $Stage))
    }

    $null = Get-QuietWorkspaceSuiteSelection -WorkspaceRoot $Stage -Suite $Name
    $null = Get-QuietWorkspaceBuildProjects -WorkspaceRoot $Stage
    $null = & ([IO.Path]::Combine($ScriptRoot, 'Test-TestCaseMetadata.ps1')) -WorkspaceRoot $Stage -Suite $Name
    foreach ($definition in Get-QuietWorkspaceSolutions $Stage | Where-Object Path -CIn @('Quietly.slnx', "src/$Name/$Name.slnx")) {
        Write-NewCompanionText ([IO.Path]::Combine($Stage, $definition.Path)) $definition.Content
    }
    Assert-QuietCompanionProfile -WorkspaceRoot $Stage -Suite $Name -SolutionPath "src/$Name/$Name.slnx" -SourcePath "src/$Name/src" -TestPath "src/$Name/test"
    $null = & ([IO.Path]::Combine($ScriptRoot, 'Sync-Credits.ps1')) -WorkspaceRoot $Stage -CreditsPath ([IO.Path]::Combine($Stage, 'CREDITS.md')) -Apply -Confirm:$false
}

function Install-NewCompanionFile {
    <#
    .SYNOPSIS
    Replaces a file from a temporary sibling so an interrupted write cannot truncate the destination.
    #>
    param([string]$Path, [byte[]]$Bytes, [bool]$Replace)
    $temporary = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Path), ".quiet-companion-$([guid]::NewGuid()).tmp")
    try {
        [void][IO.File]::WriteAllBytesAsync($temporary, $Bytes).GetAwaiter().GetResult()
        [IO.File]::Move($temporary, $Path, $Replace)
    } finally {
        [IO.File]::Delete($temporary)
    }
}

function Publish-NewQuietCompanion {
    <#
    .SYNOPSIS
    Installs the staged files and restores modified files on failure.
    #>
    param([string]$Root, [string]$Stage, [string]$GroupPath, [string[]]$Files, [hashtable]$Original)
    $updated = [Collections.Generic.List[string]]::new()
    $newDirectories = [Collections.Generic.List[string]]::new()
    try {
        foreach ($relative in $Files) {
            $path = Resolve-NewCompanionPath $Root $relative
            $previous = $Original[$relative]
            if ($null -eq $previous) {
                if (Test-Path -LiteralPath $path) { throw "CompanionDestinationExists: $relative" }
            } elseif (!(Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path).Hash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($previous))) {
                throw "CompanionWorkspaceChanged: $relative"
            }
        }
        foreach ($relative in $Files) {
            $path = Resolve-NewCompanionPath $Root $relative
            $bytes = [IO.File]::ReadAllBytes([IO.Path]::Combine($Stage, $relative))
            $directory = [IO.Path]::GetDirectoryName($path)
            if ($relative.StartsWith($GroupPath + '/', [StringComparison]::Ordinal)) {
                $missing = $directory
                while (![IO.Directory]::Exists($missing)) {
                    $newDirectories.Add($missing)
                    $missing = [IO.Path]::GetDirectoryName($missing)
                }
                $null = [IO.Directory]::CreateDirectory($directory)
            }
            Install-NewCompanionFile $path $bytes ($null -ne $Original[$relative])
            $updated.Add($relative)
        }
    } catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        for ($index = $updated.Count - 1; $index -ge 0; $index--) {
            $relative = $updated[$index]
            try {
                $path = Resolve-NewCompanionPath $Root $relative
                if ($null -eq $Original[$relative]) { [IO.File]::Delete($path) }
                else { Install-NewCompanionFile $path $Original[$relative] $true }
            } catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        foreach ($directory in $newDirectories | Sort-Object Length -Descending) {
            try {
                if ([IO.Directory]::Exists($directory)) { [IO.Directory]::Delete($directory, $false) }
            } catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($rollbackErrors.Count) { throw "CompanionRollbackIncomplete: $failure | $($rollbackErrors -join ' | ')" }
        throw $failure
    }
}

function Get-QuietCompanionScaffoldPlan {
    <#
    .SYNOPSIS
    Validates inputs and lists the planned branch and destination files without effects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Executable,
        [Parameter(Mandatory)][Alias('LicenseCreditsPath')][string]$NativeLicensePath,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [switch]$WithCSharp,
        [string]$GitBranch,
        [switch]$NoGitBranch
    )
    $ErrorActionPreference = 'Stop'
    if ($Name -cnotmatch '\A[A-Z][A-Za-z0-9]*\z' -or $Name -match '\A(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])\z' -or
        $Name -in @('All', 'SmokeBatch')) { throw "CompanionNameInvalid: $Name" }
    if (!$Executable) { $Executable = $Name.ToLowerInvariant() }
    if ($Executable -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._+-]*\z') { throw "CompanionExecutableInvalid: $Executable" }
    if ($NoGitBranch -and $GitBranch) { throw 'CompanionBranchOptionsConflict' }
    $branch = if (!$NoGitBranch) { Resolve-NewCompanionBranch $Name $GitBranch }
    $root = (Get-Item -LiteralPath ([IO.Path]::GetFullPath($WorkspaceRoot, $PWD.Path))).FullName
    $licenseText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($NativeLicensePath, $PWD.Path), [Text.UTF8Encoding]::new($false, $true))
    if ($licenseText -notmatch '(?m)^##[ \t]+\S[^\r\n]*' -or $licenseText -notmatch 'https?://\S+' -or $licenseText -match '<!--\s*module-credits:') {
        throw 'CompanionLicenseCreditsInvalid'
    }
    $groupPath = "src/$Name"
    Assert-NewCompanionAvailable $root $Name

    $product = "FrenchExDev2.QuietCli.$Name.PoSh"
    $tests = "FrenchExDev2.QuietCli.$Name.Tests.PoSh"
    $productPath = "$groupPath/src/$product"
    $testsPath = "$groupPath/test/$tests"
    $paths = @(
        "$productPath/$product.psd1"
        "$productPath/$product.psm1"
        "$productPath/README.md"
        "$productPath/LICENSE"
        "$productPath/LICENSE_CREDITS.md"
        "$testsPath/$tests.psd1"
        "$testsPath/$tests.psm1"
        "$testsPath/README.md"
        "$testsPath/LICENSE"
        "$groupPath/$Name.slnx"
    )
    if ($WithCSharp) { $paths += @("$productPath/engine/QuietCli.$Name.Parser.csproj", "$productPath/engine/Parser.cs") }
    $catalogue = Get-QuietCiCompanionCataloguePath $root
    $cataloguePath = if($catalogue){[IO.Path]::GetRelativePath($root,$catalogue).Replace('\','/')}else{'build/companions.yaml'}
    $sharedPaths = @($cataloguePath, 'Quietly.slnx', 'CREDITS.md')
    if($cataloguePath -ceq 'build/companions.yaml'){$sharedPaths+='.github/pull_request_template.md'}
    $action = if ($branch) { "Create $branch from origin/develop and generate the companion" } else { 'Generate the companion on the active companion branch' }
    [pscustomobject]@{
        Root=$root; Branch=$branch; Executable=$Executable; LicenseText=$licenseText
        GroupPath=$groupPath
        Action=$action; Paths=$paths + $sharedPaths; SharedPaths=$sharedPaths
    }
}

function Invoke-QuietScriptNewQuietCompanion {
    <#
    .SYNOPSIS
    Creates a work branch and installs a checked companion scaffold.
    .PARAMETER NoGitBranch
    Uses the selected checkout's current companion branch.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Create')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Executable,
        [Parameter(Mandatory)][Alias('LicenseCreditsPath')][string]$NativeLicensePath,
        [string]$WorkspaceRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($PSScriptRoot)),
        [switch]$WithCSharp,
        [Parameter(ParameterSetName='Create')][ValidateNotNullOrEmpty()][string]$GitBranch,
        [Parameter(Mandatory, ParameterSetName='Current')][switch]$NoGitBranch
    )
    $ErrorActionPreference = 'Stop'
    if ($PSCmdlet.ParameterSetName -eq 'Current' -and !$NoGitBranch) { throw 'CompanionNoGitBranchRequiresTrue' }
    $plan = Get-QuietCompanionScaffoldPlan -Name $Name -Executable $Executable -NativeLicensePath $NativeLicensePath -WorkspaceRoot $WorkspaceRoot -WithCSharp:$WithCSharp -GitBranch $GitBranch -NoGitBranch:$NoGitBranch
    if (!$PSCmdlet.ShouldProcess(($plan.Paths -join ', '), $plan.Action)) { return }

    $root = $plan.Root
    $branch = $plan.Branch
    $scriptRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
    $lockKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($root.ToUpperInvariant())))
    $lockPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "quiet-companion-$lockKey.lock")
    $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    $stage = $null
    try {
        # The generator is offline apart from the explicit branch operation. The normal resource script owns restoration.
        $yaml = Ensure-QuietResource -WorkspaceRoot $root -RelativePath 'resources/yaml/YamlDotNet.dll' -WhatIf
        if ($yaml.State -cne 'Ready') { throw 'CompanionYamlResourceNotReady: run Restore-CoreResources.ps1 first.' }
        if ($Name -iin @(Get-QuietWorkspaceSuiteNames -WorkspaceRoot $root) -or $Name -iin @(Get-QuietWorkspaceSuiteNames -WorkspaceRoot $root -Scope Container)) {
            throw "CompanionNameAlreadyUsed: $Name"
        }
        if ($branch) {
            $null = & ([IO.Path]::Combine($scriptRoot, 'Start-QuietWorkBranch.ps1')) -Branch $branch -WorkspaceRoot $root -BaseBranch develop -Confirm:$false
        } else {
            $branch = & ([IO.Path]::Combine($scriptRoot, 'Invoke-Quiet.ps1')) -Companion Git -Runtime $root -Code {
                param($checkout)
                $status = quiet -AsObject -C companion-branch -WorkingDirectory $checkout git status
                if ($status.Outcome -ne 'Success' -or !$status.Completeness.Source -or !$status.Completeness.Analysis -or $status.Error.Count -or
                    $status.Data.Detached -or $status.Data.Unborn -or $status.Data.Branch -cnotlike 'companion/*') {
                    throw 'CompanionActiveBranchRequired'
                }
                $status.Data.Branch
            }
        }
        Assert-NewCompanionAvailable $root $Name
        $original = @{}
        foreach ($relative in $plan.SharedPaths) {
            $original[$relative] = [IO.File]::ReadAllBytes((Resolve-NewCompanionPath $root $relative))
        }
        $stage = [IO.Directory]::CreateTempSubdirectory('quiet-companion-').FullName
        New-QuietCompanionStage $root $stage $scriptRoot $Name $plan.Executable $plan.LicenseText -WithCSharp:$WithCSharp
        Publish-NewQuietCompanion $root $stage $plan.GroupPath $plan.Paths $original
        [pscustomobject]@{Name=$Name; Branch=$branch; Executable=$plan.Executable; WithCSharp=[bool]$WithCSharp; Paths=$plan.Paths}
    } finally {
        try {
            if ($stage) { [IO.Directory]::Delete($stage, $true) }
        } finally {
            $lock.Dispose()
        }
    }
}

Export-ModuleMember -Function 'Get-QuietCompanionScaffoldPlan','Invoke-QuietScriptNewQuietCompanion'
