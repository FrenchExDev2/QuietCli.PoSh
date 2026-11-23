#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
function Get-QuietWorkspaceProjects {
    <#
    .SYNOPSIS
    Discovers inert module manifests and orders local projects by their declared dependencies.
    .PARAMETER WorkspaceRoot
    Monorepo containing group/src and group/test module directories.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
    $projects=[Collections.Generic.List[object]]::new()
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $homes=@($root);if(Test-Path -LiteralPath ([IO.Path]::Combine($root,'src')) -PathType Container){
        if((Get-Item -LiteralPath ([IO.Path]::Combine($root,'src'))).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WorkspaceProjectLinkRejected'}
        $homes+=([IO.Path]::Combine($root,'src'))
    }
    $directories=@(foreach($group in $homes | ForEach-Object {Get-ChildItem -LiteralPath $_ -Directory}){
        if($group.Name -like 'FrenchExDev2.QuietCli.*.PoSh'){$group;continue}
        if($group.Name -cnotmatch '\A[A-Z][A-Za-z0-9]*\z'){continue}
        foreach($category in @('src','test')){
            $container=[IO.Path]::Combine($group.FullName,$category)
            if(!(Test-Path -LiteralPath $container -PathType Container)){continue}
            foreach($item in @($group,(Get-Item -LiteralPath $container))){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WorkspaceProjectLinkRejected'}}
            Get-ChildItem -LiteralPath $container -Directory
        }
    })
    foreach($directory in $directories | Sort-Object FullName){
        if($directory.Name -notlike 'FrenchExDev2.QuietCli.*.PoSh'){continue}
        if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WorkspaceProjectLinkRejected'}
        if(!$names.Add($directory.Name)){throw 'WorkspaceProjectNameCollision'}
        $manifestPath=[IO.Path]::Combine($directory.FullName,($directory.Name+'.psd1'))
        if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw ('ProjectManifestMissing: '+$directory.Name)}
        if((Get-Item -LiteralPath $manifestPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WorkspaceProjectLinkRejected'}
        # Validate the text encoding before the inert data-file reader parses it; no module code is imported.
        $null=[IO.File]::ReadAllTextAsync($manifestPath,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
        $manifest=Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
        $required=@(foreach($entry in $manifest['RequiredModules']){if($entry -is [string]){$entry}else{[string]$entry['ModuleName']}})
        $metadata=if($manifest['PrivateData'] -and $manifest['PrivateData']['QuietCli']){$manifest['PrivateData']['QuietCli']}else{@{}}
        $isTest=$directory.Name.EndsWith('.Tests.PoSh',[StringComparison]::OrdinalIgnoreCase)
        $relative=[IO.Path]::GetRelativePath($root,$directory.FullName).Replace('\','/')
        $segments=$relative.Split('/')
        $offset=if($segments[0] -ceq 'src'){1}else{0}
        $group=if($metadata['SolutionGroup']){[string]$metadata['SolutionGroup']}elseif($segments.Count -ge 3){$segments[$offset]}else{($directory.Name -replace '^FrenchExDev2\.QuietCli\.','' -replace '(\.Tests)?\.PoSh$','')}
        if($group -cnotmatch '\A[A-Z][A-Za-z0-9]*\z'){throw 'WorkspaceSolutionGroupInvalid'}
        if($segments.Count -ge 3 -and ($segments[$offset] -cne $group -or $segments[$offset+1] -cne $(if($isTest){'test'}else{'src'}))){throw ('WorkspaceProjectCategoryMismatch: '+$relative)}
        $suite=if(!$isTest){$directory.Name.Substring('FrenchExDev2.QuietCli.'.Length,$directory.Name.Length-'FrenchExDev2.QuietCli.'.Length-'.PoSh'.Length)}else{$null}
        $tests=if($metadata['TestsModule']){[string]$metadata['TestsModule']}else{$null}
        $projects.Add([pscustomobject]@{
            Name=$directory.Name;Path=$relative;Directory=$directory.FullName;ManifestPath=$manifestPath;SolutionGroup=$group
            IsTest=$isTest;Suite=$suite;TestsModule=$tests;TestCommand=if($suite){'Invoke-Quiet'+$suite+'Tests'}else{$null}
            RequiredModules=$required;Dependencies=@();Manifest=$manifest
        })
    }
    if(!$projects.Count){throw 'WorkspaceProjectsNotFound'}
    foreach($project in $projects){$project.Dependencies=@($project.RequiredModules | Where-Object {$names.Contains($_)})}
    $ordered=[Collections.Generic.List[object]]::new()
    $emitted=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while($ordered.Count -lt $projects.Count){
        $progress=$false
        foreach($project in $projects){
            if($emitted.Contains($project.Name)){continue}
            if(@($project.Dependencies | Where-Object {!$emitted.Contains($_)}).Count){continue}
            $ordered.Add($project);[void]$emitted.Add($project.Name);$progress=$true
        }
        if(!$progress){throw 'WorkspaceProjectDependencyCycle'}
    }
    $ordered.ToArray()
}

function Get-QuietWorkspaceBuildProjects {
    <#
    .SYNOPSIS
    Resolves declared portable C# distributions without importing modules or executing tools.
    .PARAMETER WorkspaceRoot
    Selected workspace whose PrivateData.QuietCli.BuildProjects declarations define the outputs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $outputs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pairs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($package in Get-QuietWorkspaceProjects $WorkspaceRoot){
        $private=$package.Manifest['PrivateData']
        $metadata=if($private -and $private['QuietCli']){$private['QuietCli']}else{@{}}
        foreach($entry in $metadata['BuildProjects']){
            if($entry -isnot [System.Collections.IDictionary] -or $entry.Keys.Count -ne 2 -or !$entry.Contains('Project') -or !$entry.Contains('Outputs') -or $entry['Outputs'] -isnot [System.Collections.IDictionary] -or !$entry['Outputs'].Count){throw ('WorkspaceBuildDeclarationInvalid: '+$package.Name)}
            $project=[string]$entry['Project']
            if($project -cnotmatch '\A(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\.csproj\z' -or $project.Split('/') -contains '..'){throw ('WorkspaceBuildProjectPathInvalid: '+$package.Name)}
            $path=[IO.Path]::Combine($package.Directory,$project)
            if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw ('WorkspaceBuildProjectMissing: '+$project)}
            $cursor=Get-Item -LiteralPath $path
            while($cursor.FullName -ne $package.Directory){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WorkspaceBuildLinkRejected'};$cursor=if($cursor -is [IO.FileInfo]){$cursor.Directory}else{$cursor.Parent};if(!$cursor){throw 'WorkspaceBuildPathEscapedPackage'}}
            $text=Get-Content -LiteralPath $path -Raw -Encoding utf8
            if($text -match '<!DOCTYPE'){throw 'WorkspaceBuildDtdRejected'}
            $document=[xml]::new();$document.XmlResolver=$null;$document.LoadXml($text)
            $declared=@($document.SelectNodes('//TargetFramework|//TargetFrameworks') | ForEach-Object {$_.InnerText.Split(';')})
            foreach($framework in @($entry['Outputs'].Keys | Sort-Object)){
                $output=[string]$entry['Outputs'][$framework]
                if($framework -cnotmatch '\Anet[0-9]+\.[0-9]+\z'){throw ('WorkspaceBuildFrameworkInvalid: '+$package.Name)}
                if($framework -cnotin $declared){throw ('WorkspaceBuildFrameworkNotDeclared: '+$package.Name)}
                if($output -cnotmatch '\Alib/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\z' -or $output.Split('/') -contains '..'){throw ('WorkspaceBuildOutputPathInvalid: '+$package.Name)}
                if(!$pairs.Add($package.Name+'/'+$project+'|'+$framework) -or !$outputs.Add($package.Name+'/'+$output)){throw ('WorkspaceBuildOutputCollision: '+$package.Name)}
                foreach($other in $outputs){if($other -cne $package.Name+'/'+$output -and ($other.StartsWith($package.Name+'/'+$output+'/',[StringComparison]::OrdinalIgnoreCase) -or ($package.Name+'/'+$output).StartsWith($other+'/',[StringComparison]::OrdinalIgnoreCase))){throw ('WorkspaceBuildOutputCollision: '+$package.Name)}}
                [pscustomobject]@{Package=$package.Name;Project=$package.Path+'/'+$project;TargetFramework=[string]$framework;Output=$package.Path+'/'+$output}
            }
        }
    }
}

function Get-QuietWorkspaceDotNetHost {
    <#
    .SYNOPSIS
    Finds an already-installed checkout-pinned SDK host with the stable runtime required by native test fixtures.
    .PARAMETER WorkspaceRoot
    Checkout containing global.json and optional private SDK installation receipt; nothing is installed or executed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $pin=[IO.Path]::Combine($WorkspaceRoot,'global.json')
    if(!(Test-Path -LiteralPath $pin)){return}
    $sdk=(Get-Content -LiteralPath $pin -Raw -Encoding utf8|ConvertFrom-Json).sdk.version
    if($sdk -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?\z'){throw 'WorkspaceSdkVersionInvalid'}
    $directory=[IO.Path]::Combine($WorkspaceRoot,('.dotnet/'+$sdk))
    $hostPath=[IO.Path]::Combine($directory,$(if($IsWindows){'dotnet.exe'}else{'dotnet'}))
    $receiptPath=[IO.Path]::Combine($directory,'frenchexdev-install.json')
    if(!(Test-Path -LiteralPath $hostPath) -or !(Test-Path -LiteralPath $receiptPath)){return}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding utf8|ConvertFrom-Json
    if($receipt.SdkVersion -cne $sdk -or $receipt.Rid -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier){return}
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
    $manifestPath=Resolve-QuietWorkspacePath $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1'
    $manifest=Import-PowerShellDataFile -LiteralPath $manifestPath
    $fixture=@($manifest.PrivateData.QuietCli.BuildProjects|Where-Object Project -CEQ 'fixture/QuietCli.Fixture.csproj')
    if($fixture.Count -ne 1 -or $fixture[0].Outputs.Count -ne 1){throw 'WorkspaceFixtureFrameworkAmbiguous'}
    $framework=@($fixture[0].Outputs.Keys)[0]
    if($framework -cnotmatch '\Anet([0-9]+)\.([0-9]+)\z'){throw 'WorkspaceFixtureFrameworkInvalid'}
    $prefix=$Matches[1]+'.'+$Matches[2]+'.'
    $runtimes=[IO.Path]::Combine($directory,'shared/Microsoft.NETCore.App')
    $stable=@(Get-ChildItem -LiteralPath $runtimes -Directory -ErrorAction SilentlyContinue|Where-Object {$_.Name.StartsWith($prefix,[StringComparison]::Ordinal) -and $_.Name -cmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z'})
    if(!$stable.Count){return}
    [pscustomobject]@{Path=$hostPath;Directory=$directory;SdkVersion=$sdk;FixtureFramework=$framework}
}

function Get-QuietWorkspaceBuildSelection {
    <#
    .SYNOPSIS
    Resolves suite test modules and their transitive manifest dependencies without importing the engine.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER Suite
    Product suite or focused orchestration mode. All and Tooling retain the complete build.
    .PARAMETER Module
    Exact project roots for packaging validation; includes their transitive manifest dependencies.
    #>
    [CmdletBinding(DefaultParameterSetName='Suite')]
    param([Parameter(Mandatory,Position=0)][string]$WorkspaceRoot,
        [Parameter(ParameterSetName='Suite',Position=1)][string]$Suite='All',
        [Parameter(Mandatory,ParameterSetName='Module',Position=1)][ValidateNotNullOrEmpty()][string[]]$Module)
    $projects=@(Get-QuietWorkspaceProjects $WorkspaceRoot)
    if($PSCmdlet.ParameterSetName -ceq 'Suite' -and $Suite -in @('All','Tooling','GalleryPreview','DotNet')){return $projects.Name}
    $roots=if($PSCmdlet.ParameterSetName -ceq 'Module'){@($Module)}elseif($Suite -in @('Import','Integration','RealStatus','Recall','RecallMutation','RecallLarge','ConfigurationDelivery','AgentInstructions','Script','Mutation','RunProfiles','RunProfilesMutation')){@('FrenchExDev2.QuietCli.Core.Tests.PoSh')}else{@('FrenchExDev2.QuietCli.'+$Suite+'.Tests.PoSh')}
    if($PSCmdlet.ParameterSetName -ceq 'Suite' -and (Get-QuietCiCompanionCataloguePath $WorkspaceRoot)){
        $configuration=Read-QuietCiCompanions $WorkspaceRoot
        if($configuration.Companions.Contains($Suite) -or $configuration.Suites.Contains($Suite)){
            $selection=Resolve-QuietCiCompanions $configuration -Suite $Suite
            $roots=@(foreach($name in $selection.Selected){$configuration.Suites[$name].TestsModule})
        }
    }
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pending=[Collections.Generic.Queue[string]]::new()
    foreach($name in $roots){$pending.Enqueue($name)}
    while($pending.Count){
        $name=$pending.Dequeue()
        if(!$selected.Add($name)){continue}
        $project=@($projects|Where-Object Name -CEQ $name)
        if($project.Count -ne 1){throw ('WorkspaceBuildModuleMissing: '+$name)}
        foreach($dependency in $project[0].RequiredModules){
            if($dependency -clike 'FrenchExDev2.QuietCli.*.PoSh'){$pending.Enqueue($dependency)}
        }
    }
    @($projects|Where-Object {$selected.Contains($_.Name)}|ForEach-Object {$_.Name})
}

function Get-QuietWorkspaceTestSuites {
    <#
    .SYNOPSIS
    Resolves business modules to declared test companions and exported runner commands.
    .PARAMETER WorkspaceRoot
    Selected source workspace.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $projects=@(Get-QuietWorkspaceProjects $WorkspaceRoot)
    foreach($project in $projects){
        if($project.IsTest){continue}
        if(!$project.TestsModule){throw ('WorkspaceTestModuleUndeclared: '+$project.Name)}
        $tests=@($projects | Where-Object Name -CEQ $project.TestsModule)
        if($tests.Count -ne 1 -or !$tests[0].IsTest -or $tests[0].Dependencies -cnotcontains $project.Name){throw ('WorkspaceTestModuleInvalid: '+$project.Name)}
        $private=$tests[0].Manifest['PrivateData']
        $metadata=if($private -and $private['QuietCli']){$private['QuietCli']}else{@{}}
        $command=if($metadata['TestCatalogue'] -and $metadata['TestCatalogue']['Runner']){[string]$metadata['TestCatalogue']['Runner']}else{$project.TestCommand}
        if($tests[0].Manifest.FunctionsToExport -cnotcontains $command){throw ('WorkspaceTestRunnerNotExported: '+$command)}
        [pscustomobject]@{Name=$project.Suite;Group=$project.SolutionGroup;Project=$project.Name;ProjectDirectory=$project.Directory;TestsModule=$tests[0].Name;TestsManifest=$tests[0].ManifestPath;Command=$command}
    }
}

function Get-QuietWorkspacePackages {
    <#
    .SYNOPSIS
    Lists publishable and non-publishable source packages with their explicit eligibility reason.
    .DESCRIPTION
    Test companions are never publishable. Other modules require a boolean Publishable declaration
    in PrivateData.QuietCli; missing declarations deny publication. Suite modes such as All are
    not projects and never enter this catalogue. Eligibility never authorizes publication.
    .PARAMETER WorkspaceRoot
    Selected monorepo, defaulting to this script's workspace.
    .PARAMETER Publishable
    Returns only explicitly publishable business packages.
    .PARAMETER NonPublishable
    Returns only excluded packages, including every test companion.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot=(Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),[switch]$Publishable,[switch]$NonPublishable)
    if($Publishable -and $NonPublishable){throw 'WorkspacePackageFiltersAreExclusive'}
    foreach($project in Get-QuietWorkspaceProjects $WorkspaceRoot){
        $private=$project.Manifest['PrivateData']
        $metadata=if($private -and $private['QuietCli']){$private['QuietCli']}else{@{}}
        if($metadata.ContainsKey('Publishable') -and $metadata['Publishable'] -isnot [bool]){throw ('WorkspacePublishableMustBeBoolean: '+$project.Name)}
        $eligible=!$project.IsTest -and $metadata.ContainsKey('Publishable') -and $metadata['Publishable']
        $reason=if($project.IsTest){'TestProject'}elseif(!$metadata.ContainsKey('Publishable')){'PublicationNotDeclared'}elseif(!$eligible){'PublicationDisabled'}else{'ExplicitlyPublishable'}
        $packageName=if($metadata['PackageName']){[string]$metadata['PackageName']}else{$project.Name}
        if($packageName -cnotmatch '^[A-Za-z][A-Za-z0-9_.-]{0,127}$'){throw ('WorkspacePackageNameInvalid: '+$project.Name)}
        if(($Publishable -and !$eligible) -or ($NonPublishable -and $eligible)){continue}
        [pscustomobject]@{Name=$project.Name;PackageName=$packageName;Publishable=[bool]$eligible;Reason=$reason;IsTest=$project.IsTest;Path=$project.Path;ManifestPath=$project.ManifestPath}
    }
}

function Get-QuietWorkspaceSuiteNames {
    <#
    .SYNOPSIS
    Combines discovered companion suites with the supported orchestration modes for one launcher.
    .PARAMETER WorkspaceRoot
    Selected source workspace.
    .PARAMETER Scope
    Host supports all focused local modes; Container supports its existing portable modes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[ValidateSet('Host','Container')][string]$Scope='Host')
    $special=if($Scope -eq 'Container'){@('All','Import','Integration','Mutation','Tooling')}else{@('All','Import','Integration','RealStatus','Recall','RecallMutation','RecallLarge','ConfigurationDelivery','AgentInstructions','Script','RunProfiles','RunProfilesMutation','GalleryPreview','DotNet','Tooling','Distribution','WorkspaceLayout','CompanionSmoke')}
    $configuration=$null
    $suites=@(if(Get-QuietCiCompanionCataloguePath $WorkspaceRoot){
        $configuration=Read-QuietCiCompanions $WorkspaceRoot
        $configuration.Suites.Values
    }else{Get-QuietWorkspaceTestSuites $WorkspaceRoot})
    foreach($suite in $suites){if($special -contains $suite.Name){throw ('WorkspaceSuiteNameConflict: '+$suite.Name)}}
    $names=@($suites.Name)
    if($configuration){$names+=@(Get-QuietCompanions -Configuration $configuration|Where-Object {$_ -cnotin $names})}
    $names+$special
}

function New-QuietWorkspaceSuiteParameter {
    <#
    .SYNOPSIS
    Creates the dynamic Suite parameter with native ValidateSet validation and tab completion.
    .PARAMETER WorkspaceRoot
    Workspace whose inert manifests define the available companions.
    .PARAMETER Scope
    Supported launcher modes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[ValidateSet('Host','Container')][string]$Scope='Host')
    $attributes=[Collections.ObjectModel.Collection[Attribute]]::new()
    $attributes.Add([Management.Automation.ParameterAttribute]::new())
    $attributes.Add([Management.Automation.ValidateSetAttribute]::new([string[]]@(Get-QuietWorkspaceSuiteNames $WorkspaceRoot -Scope $Scope)))
    $parameter=[Management.Automation.RuntimeDefinedParameter]::new('Suite',[string],$attributes)
    $parameters=[Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $parameters.Add('Suite',$parameter)
    return $parameters
}

function Get-QuietWorkspaceSuiteSelection {
    <#
    .SYNOPSIS
    Expands All to the dependency-ordered discovered companion runners.
    .PARAMETER WorkspaceRoot
    Selected source workspace.
    .PARAMETER Suite
    All or one companion suite name; focused orchestration modes are dispatched by their launcher.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string]$Suite='All')
    if(Get-QuietCiCompanionCataloguePath $WorkspaceRoot){
        $configuration=Read-QuietCiCompanions $WorkspaceRoot
        foreach($owned in @(Get-QuietWorkspaceTestSuites $WorkspaceRoot)){
            $registered=@($configuration.Suites.Values|Where-Object {$_.TestsModule -ceq $owned.TestsModule -and $_.Command -ceq $owned.Command -and $_.Group -ceq $owned.Group})
            if(!$configuration.Companions.Contains($owned.Group) -or $registered.Count -ne 1){
                throw ('WorkspaceCompanionQualificationUndeclared: '+$owned.Name)
            }
        }
        $selection=Resolve-QuietCiCompanions $configuration -Suite $Suite
        foreach($name in $selection.Selected){
            $entry=$configuration.Suites[$name]
            $project=if($configuration.Companions.Contains($name)){'FrenchExDev2.QuietCli.'+$name+'.PoSh'}else{$entry.TestsModule}
            $owner=@(Get-QuietWorkspaceProjects $WorkspaceRoot | Where-Object Name -CEQ $project)
            if(!$owner.Count){
                $owner=@(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object {$_.SolutionGroup -ceq $entry.Group -and !$_.IsTest}|Select-Object -First 1)
            }
            if($owner.Count -ne 1){throw ('WorkspaceSuiteProjectMissing: '+$project)}
            [pscustomobject]@{Name=$name;Project=$project;ProjectDirectory=$owner[0].Directory;TestsModule=$entry.TestsModule;TestsManifest=$entry.TestsManifest;Command=$entry.Command}
        }
        return
    }
    $suites=@(Get-QuietWorkspaceTestSuites $WorkspaceRoot)
    if($Suite -eq 'All'){return $suites}
    $selected=@($suites | Where-Object Name -IEQ $Suite)
    if($selected.Count -ne 1){throw ('WorkspaceCompanionSuiteUnknown: '+$Suite)}
    $selected
}

Export-ModuleMember -Function 'Get-QuietWorkspaceProjects','Get-QuietWorkspaceBuildProjects','Get-QuietWorkspaceDotNetHost','Get-QuietWorkspaceBuildSelection','Get-QuietWorkspaceTestSuites','Get-QuietWorkspacePackages','Get-QuietWorkspaceSuiteNames','New-QuietWorkspaceSuiteParameter','Get-QuietWorkspaceSuiteSelection'
