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
    $tooling=$false;$conservative=$false;$distribution=$false
    foreach($project in $graph|Where-Object EvaluationFailure){
        $conservative=$true
        foreach($group in $configuration.Companions.Keys){[void]$selected.Add($group)}
        $reasons.Add([pscustomobject]@{Input='MSBuildEvaluation';Package=$null;Project=$project.Path;Companion='*';Action='full';Reason=('EvaluationUnavailable: '+$project.EvaluationFailure)})
    }
    $toolingOnly=@('scripts/New-RunProfile.ps1','scripts/Invoke-RunProfile.ps1','scripts/lib/RunProfileStore.psm1')
    foreach($path in $ChangedPaths){
        if(!$path -or $path.Contains([char]0) -or $path.Contains('\') -or $path.StartsWith('/') -or $path.Split('/') -contains '..'){throw 'CiImpactPathInvalid'}
        if($path -match '^docs/|\.md$|^icons/'){continue}
        if($path -cin $toolingOnly -or $path -cmatch '\Ascripts/RunProfiles/[a-z0-9][a-z0-9-]{0,63}\.profile\.psd1\z'){$tooling=$true;continue}
        $affected=@();$reason='SourceChanged';$packages=@()
        if($path -match '(?:^|/)Directory\.Packages\.props$'){
            $absolute=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $path)
            $after=if(Test-Path -LiteralPath $absolute){[IO.File]::ReadAllText($absolute,[Text.Encoding]::UTF8)}else{''}
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
                continue
            }else{
                $tooling=$true;$conservative=$true
                foreach($suite in $configuration.Companions.Keys){[void]$selected.Add($suite)}
                $reasons.Add([pscustomobject]@{Input=$path;Package=$null;Project=$null;Companion='*';Action='full';Reason='SharedOrUnknownInput'})
            }
        }
        foreach($project in $affected){
            [void]$builds.Add($project.Path)
            if($configuration.Companions.Contains($project.Group)){[void]$selected.Add($project.Group)}
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
    foreach($suite in $configuration.Companions.Keys){
        if($selected.Contains($suite)){continue}
        $closure=Resolve-QuietCiCompanions $configuration -Suite $suite
        if(@($closure.Dependencies|Where-Object {$selected.Contains($_)}).Count){[void]$smokes.Add($suite)}
    }
    # A build also needs the forward project-reference closure.
    $progress=$true
    while($progress){$progress=$false;foreach($project in $graph|Where-Object {$builds.Contains($_.Path)}){
        foreach($reference in $project.References){if($builds.Add($reference)){$progress=$true}}
    }}
    $names=@($configuration.Companions.Keys|Where-Object {$selected.Contains($_)})
    foreach($name in $smokes){$reasons.Add([pscustomobject]@{Input='DependencyGraph';Package=$null;Project=$null;Companion=$name;Action='smoke';Reason='ChangedRuntimeDependency'})}
    [pscustomobject]@{SchemaVersion=2;Suite=$(if($names.Count -eq 1){$names[0]}elseif($names.Count){'Selected'}else{'None'});RunProducts=($names.Count -gt 0);RunTooling=$tooling;RunDistribution=$distribution;ChangedPaths=@($ChangedPaths);SelectedSuites=$names;FullSuites=$names;SmokeSuites=@($smokes|Sort-Object);BuildProjects=@($builds|Sort-Object);Reasons=$reasons.ToArray();ConservativeFull=$conservative}
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
Export-ModuleMember -Function Get-QuietCiImpact,Test-QuietDevelopReceipt
