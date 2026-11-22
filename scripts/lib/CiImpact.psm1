#requires -Version 7.6

Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'CiProjectGraph.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietCiImpact {
    <#
    .SYNOPSIS
    Separates affected builds, full qualification and dependent smokes from complete old/new changed paths.
    .PARAMETER WorkspaceRoot
    Checkout owning the inert suite and module catalogues.
    .PARAMETER ChangedPaths
    Complete old/new changed paths without rename collapsing.
    .PARAMETER PreviousFiles
    Baseline XML contents indexed by changed path, including deleted files.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot,[AllowEmptyCollection()][string[]]$ChangedPaths,[hashtable]$PreviousFiles=@{})
    $ErrorActionPreference='Stop'
    foreach($path in $ChangedPaths){if(!$path -or $path.Contains([char]0) -or $path.Contains('\') -or $path.StartsWith('/') -or $path.Split('/') -contains '..'){throw 'CiImpactPathInvalid'}}
    $configuration=Read-QuietCiCompanions $WorkspaceRoot
    $modules=@(Get-QuietWorkspaceProjects $WorkspaceRoot)
    $graph=@(Get-QuietCiProjectGraph $WorkspaceRoot -Evaluate:([bool]($ChangedPaths -match '\.(cs|csproj|props|targets)$').Count))
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $smokes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $builds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $reasons=[Collections.Generic.List[object]]::new()
    $scripts=[Collections.Generic.List[string]]::new()
    $tooling=$false;$conservative=$false;$distribution=$false
    foreach($project in $graph|Where-Object EvaluationFailure){
        $conservative=$true
        foreach($group in $configuration.Companions.Keys){[void]$selected.Add($group)}
        $reasons.Add([pscustomobject]@{Input='MSBuildEvaluation';Package=$null;Project=$project.Path;Companion='*';Action='full';Reason=('EvaluationUnavailable: '+$project.EvaluationFailure)})
    }
    foreach($path in $ChangedPaths){
        if($path -match '^docs/|\.md$|^icons/' -or [IO.Path]::GetFileName($path) -ceq '.gitignore'){continue}
        # Repository scripts and their tests never ship in a companion product: only the script tests and mutation
        # targets they reach qualify them (ScriptPaths). Products and the full tooling are a manual dispatch.
        if($path.StartsWith('scripts/',[StringComparison]::Ordinal) -or $path.StartsWith('test/scripts/',[StringComparison]::Ordinal)){$scripts.Add($path);continue}
        $affected=@();$reason='SourceChanged';$packages=@()
        if($path -match '(?:^|/)Directory\.Packages\.props$'){
            $absolute=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $path)
            $after=if(Test-Path -LiteralPath $absolute){[IO.File]::ReadAllText($absolute,[Text.Encoding]::UTF8)}  # a deleted file reads as the empty project
            if($PreviousFiles.ContainsKey($path)){
                $before=[string]$PreviousFiles[$path];$packages=@(Get-QuietChangedPackages $before $after)
                $left=Read-QuietBuildXml $before;$right=Read-QuietBuildXml $after
                foreach($xml in @($left,$right)){foreach($node in @($xml.SelectNodes('//PackageVersion'))){[void]$node.ParentNode.RemoveChild($node)}}
                if($left.OuterXml -ceq $right.OuterXml){
                    $affected=@($graph|Where-Object {$_.Imports -ccontains $path -and @($_.Packages|Where-Object {$_.Name.ToLowerInvariant() -cin $packages -and !$_.Version -and !$_.VersionOverride}).Count})
                    $reason='CentralPackageConsumer'
                    if($packages.Count -and @($right.SelectNodes('//CentralPackageTransitivePinningEnabled')|Where-Object {$_.InnerText.Trim() -ine 'false'}).Count){
                        $affected=@($graph|Where-Object {$_.Imports -ccontains $path})
                        $reason='TransitivePinningRequiresResolvedConsumerGraph';$conservative=$true
                    }
                }else{$affected=@($graph|Where-Object {$_.Imports -ccontains $path});$reason='CentralRestorePolicyChanged'}
            }else{$affected=@($graph|Where-Object {$_.Imports -ccontains $path});$reason='BaselineUnavailable';$conservative=$true}
        }elseif($path -match '\.(props|targets)$|(?:^|/)(global\.json|[Nn]u[Gg]et\.[Cc]onfig)$'){
            $affected=@($graph|Where-Object {$path -ceq 'global.json' -or $_.Imports -ccontains $path});$reason='InheritedBuildInput'
        }else{
            $owners=@($modules|Where-Object {$path.StartsWith($_.Path+'/',[StringComparison]::Ordinal) -or $path.StartsWith($_.Name+'/',[StringComparison]::Ordinal)})
            if($owners.Count){
                foreach($owner in $owners){
                    if($owner.SolutionGroup -ceq 'Tooling'){$tooling=$true;continue}
                    if($owner.SolutionGroup -ceq 'Distribution'){$distribution=$true;continue}
                    foreach($suite in $configuration.Suites.Keys){
                        if($configuration.Suites[$suite].TestsModule -ceq $owner.Name -or $configuration.Suites[$suite].Group -ceq $owner.SolutionGroup){[void]$selected.Add($configuration.Suites[$suite].Group)}
                    }
                    $reasons.Add([pscustomobject]@{Input=$path;Package=$null;Project=$owner.Path;Companion=$owner.SolutionGroup;Action='full';Reason=$reason})
                    if($path -match '\.(cs|csproj)$'){$affected+=@($graph|Where-Object {$_.Module -ceq $owner.Name -and $path.StartsWith(([IO.Path]::GetDirectoryName($_.Path).Replace('\','/')+'/'),[StringComparison]::Ordinal)})}
                }
            }elseif($path -ceq '.github/workflows/distribution-ci.yml'){
                $distribution=$true
            }elseif($path -ceq '.github/workflows/tooling-component-ci.yml'){
                $tooling=$true
            }elseif($path -match '^\.github/workflows/(?<name>[a-z0-9]+)-ci\.yml$'){
                $workflow=$Matches.name
                $names=@($configuration.Companions.Keys|Where-Object {$_ -ieq $workflow})
                if($names.Count){[void]$selected.Add($names[0])}elseif($workflow -ceq 'tooling'){$tooling=$true}else{$tooling=$true;$conservative=$true;foreach($name in $configuration.Companions.Keys){[void]$selected.Add($name)}}
            }elseif($path -match '^src/[^/]+/[^/]+\.slnx$|^Quietly\.slnx$'){
                # Solution files only list projects: their builds follow from the project changes themselves.
            }else{
                $tooling=$true;$conservative=$true
                foreach($suite in $configuration.Companions.Keys){[void]$selected.Add($suite)}
                $reasons.Add([pscustomobject]@{Input=$path;Package=$null;Project=$null;Companion='*';Action='full';Reason='SharedOrUnknownInput'})
            }
        }
        foreach($project in $affected){
            [void]$builds.Add($project.Path)
            # Selection is only ever read through companion names, so a Tooling or Distribution group is inert here.
            [void]$selected.Add($project.Group)
            $reasons.Add([pscustomobject]@{Input=$path;Package=($packages -join ',');Project=$project.Path;Companion=$project.Group;Action='build';Reason=$reason})
        }
    }
    # Reverse C# dependencies require compilation and their owning suite, not every runtime consumer.
    $progress=$true
    while($progress){$progress=$false;foreach($project in $graph){
        if(!$builds.Contains($project.Path) -and @($project.References|Where-Object {$builds.Contains($_)}).Count){
            [void]$builds.Add($project.Path);$progress=$true
        }
    }}
    foreach($suite in @(Get-QuietCiDependentSmokes $configuration $selected)){[void]$smokes.Add($suite)}
    # A build also needs the forward project-reference closure.
    $progress=$true
    while($progress){$progress=$false;foreach($project in $graph|Where-Object {$builds.Contains($_.Path)}){
        foreach($reference in $project.References){if($builds.Add($reference)){$progress=$true}}
    }}
    $names=@($configuration.Companions.Keys|Where-Object {$selected.Contains($_)})
    foreach($name in $smokes){$reasons.Add([pscustomobject]@{Input='DependencyGraph';Package=$null;Project=$null;Companion=$name;Action='smoke';Reason='ChangedRuntimeDependency'})}
    [pscustomobject]@{SchemaVersion=2;Suite=$(if($names.Count -eq 1){$names[0]}elseif($names.Count){'Selected'}else{'None'});RunProducts=($names.Count -gt 0);RunTooling=$tooling;RunDistribution=$distribution;ChangedPaths=@($ChangedPaths);SelectedSuites=$names;FullSuites=$names;SmokeSuites=@($smokes|Sort-Object);BuildProjects=@($builds|Sort-Object);Reasons=$reasons.ToArray();ConservativeFull=$conservative;ScriptPaths=[string[]]$scripts.ToArray()}
}

function Get-QuietCiDependentSmokes {
    <#
    .SYNOPSIS
    Returns, in catalogue order, the unselected companions whose dependency closure contains a selected one.
    .PARAMETER Configuration
    Companion catalogue.
    .PARAMETER Selected
    Fully qualified companion names.
    #>
    param($Configuration,[Collections.Generic.HashSet[string]]$Selected)
    foreach($suite in $Configuration.Companions.Keys){
        if($Selected.Contains($suite)){continue}
        $closure=Resolve-QuietCiCompanions $Configuration -Suite $suite
        if(@($closure.Dependencies|Where-Object {$Selected.Contains($_)}).Count){$suite}
    }
}

function Get-QuietCiDispatchImpact {
    <#
    .SYNOPSIS
    Selects companion suites and the full tooling for qualification on an explicit manual dispatch, without reading a diff.
    .PARAMETER WorkspaceRoot
    Checkout owning the inert companion catalogue.
    .PARAMETER Suite
    Companion names or Tooling, as items or comma-separated, matched without case; all selects every companion and
    the tooling.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot,[AllowEmptyCollection()][AllowNull()][string[]]$Suite)
    $ErrorActionPreference='Stop'
    $configuration=Read-QuietCiCompanions $WorkspaceRoot
    $all=@($configuration.Companions.Keys)
    $requested=@(foreach($item in @($Suite)){foreach($part in ([string]$item).Split(',')){if($part.Trim()){$part.Trim()}}})
    if(!$requested.Count){throw 'CiDispatchSuiteRequired'}
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $tooling=$false
    foreach($name in $requested){
        # Tooling is the full repository tooling workflow (Core without Git, run profiles, every script test and target).
        if($name -ieq 'Tooling'){$tooling=$true;continue}
        if($name -ieq 'all'){$tooling=$true}
        $match=@(if($name -ieq 'all'){$all}else{$all|Where-Object {$_ -ieq $name}})
        if(!$match.Count){throw ('CiDispatchSuiteUnknown: '+$name)}
        foreach($companion in $match){[void]$selected.Add($companion)}
    }
    $names=@($all|Where-Object {$selected.Contains($_)})
    $smokes=@(Get-QuietCiDependentSmokes $configuration $selected)
    $reasons=@(
        foreach($name in $names){[pscustomobject]@{Input='workflow_dispatch';Package=$null;Project=$null;Companion=$name;Action='full';Reason='ManualDispatch'}}
        if($tooling){[pscustomobject]@{Input='workflow_dispatch';Package=$null;Project=$null;Companion='Tooling';Action='full';Reason='ManualDispatch'}}
        foreach($name in $smokes){[pscustomobject]@{Input='DependencyGraph';Package=$null;Project=$null;Companion=$name;Action='smoke';Reason='ChangedRuntimeDependency'}}
    )
    [pscustomobject]@{SchemaVersion=2;Suite=$(if($names.Count -eq 1){$names[0]}elseif($names.Count){'Selected'}else{'None'});RunProducts=($names.Count -gt 0);RunTooling=$tooling;RunDistribution=$false;ChangedPaths=@();SelectedSuites=$names;FullSuites=$names;SmokeSuites=@($smokes|Sort-Object);BuildProjects=@();Reasons=$reasons;ConservativeFull=$false;ScriptPaths=[string[]]@()}
}

function Test-QuietDevelopReceipt {
    <#
    .SYNOPSIS
    Accepts successful PR evidence only for the exact merged source tree and originating workflow attempt.
    .PARAMETER Receipt
    Parsed bounded artifact document.
    .PARAMETER Tree
    Actual merged commit tree.
    .PARAMETER RunId
    Authoritative successful PR workflow run.
    .PARAMETER RunAttempt
    Authoritative workflow attempt.
    #>
    param($Receipt,[string]$Tree,[string]$RunId,[string]$RunAttempt)
    if($Tree -cnotmatch '\A[a-f0-9]{40}\z' -or $Receipt.Tree -cne $Tree -or
        $Receipt.Ready -isnot [bool] -or !$Receipt.Ready -or [string]$Receipt.RunId -cne $RunId -or [string]$Receipt.RunAttempt -cne $RunAttempt -or
        $Receipt.Windows -cne 'success' -or $Receipt.Linux -cne 'success' -or
        $Receipt.PerformanceRequired -isnot [bool] -or $Receipt.Performance -cne $(if($Receipt.PerformanceRequired){'success'}else{'skipped'}) -or
        $Receipt.ToolingRequired -isnot [bool] -or $Receipt.Tooling -cne $(if($Receipt.ToolingRequired){'success'}else{'skipped'}) -or
        $Receipt.ToolingMutation -cne $(if($Receipt.ToolingRequired){'success'}else{'skipped'}) -or
        $Receipt.MutationRequired -isnot [bool] -or $Receipt.Mutation -cne $(if($Receipt.MutationRequired){'success'}else{'skipped'})){return $false}
    return $true
}
Export-ModuleMember -Function Get-QuietCiImpact,Get-QuietCiDispatchImpact,Test-QuietDevelopReceipt
