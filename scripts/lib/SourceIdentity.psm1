Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'BinaryHeaders.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RuntimeTargets.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
function Get-QuietSourceFiles {
    <#
    .SYNOPSIS
    Enumerates source files while pruning generated directories and rejecting filesystem links.
    .PARAMETER Root
    Repository or project directory.
    .PARAMETER ExcludeChildren
    Top-level child repositories excluded from orchestration sources.
    #>
    param([string]$Root,[string[]]$ExcludeChildren=@())
    $rootPath=[IO.Path]::GetFullPath($Root)
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($rootPath)
    $files=[Collections.Generic.List[string]]::new()
    while($pending.Count){
        $directory=$pending.Pop()
        foreach($item in Get-ChildItem -LiteralPath $directory -Force){
            if($item.Name -in @('.git','.dotnet','.cache','bin','obj','artifacts','.vs','.profilers')){continue}
            if(!$item.PSIsContainer -and $item.Name -match '\.(json|csproj|props)\.bak-'){continue}
            if($item.Name -eq 'lib' -and $item.FullName -ne [IO.Path]::GetFullPath([IO.Path]::Combine($rootPath,'scripts/lib'))){continue}
            if($directory -eq $rootPath -and $item.Name -in $ExcludeChildren){continue}
            if($directory -eq $rootPath -and $item.Name -eq 'repositories.lock.json'){continue}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('SourceLinkNotAllowed: '+$item.FullName)}
            if($item.PSIsContainer){$pending.Push($item.FullName)}else{$files.Add($item.FullName)}
        }
    }
    $sorted=$files.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    foreach($path in $sorted){[pscustomobject]@{Path=[IO.Path]::GetRelativePath($rootPath,$path).Replace('\','/');Bytes=(Get-Item -LiteralPath $path -Force).Length;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}
}

function Get-QuietManifestDigest {
    <#
    .SYNOPSIS
    Hashes ordered portable paths and content hashes, independent from timestamps.
    .PARAMETER Files
    Source-file manifest records.
    #>
    param([object[]]$Files)
    [string[]]$lines=@($Files|ForEach-Object{([string]$_.Path)+' '+([string]$_.SHA256)})
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))
}
function Get-QuietBinaryInputs {
    <#
    .SYNOPSIS
    Lists the actual source inputs for one compiled project and its engine reference.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace.
    .PARAMETER Project
    Relative project path.
    #>
    param([string]$WorkspaceRoot,[string]$Project)
    $workspace=[IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push(([IO.Path]::Combine($WorkspaceRoot,$Project)))
    $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $roots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while($pending.Count){
        $path=[IO.Path]::GetFullPath($pending.Pop())
        if(!$path.StartsWith($workspace,[StringComparison]::OrdinalIgnoreCase)){throw 'BinaryInputOutsideWorkspace'}
        if(!$visited.Add($path)){continue}
        $directory=Split-Path $path -Parent;[void]$roots.Add($directory)
        $text=Get-Content -LiteralPath $path -Raw -Encoding utf8
        if($text -match '<!DOCTYPE'){throw 'BinaryInputDtdRejected'}
        $document=[xml]::new();$document.XmlResolver=$null;$document.LoadXml($text)
        foreach($reference in $document.SelectNodes('//ProjectReference[@Include]|//Compile[@Include]')){
            $include=$reference.GetAttribute('Include')
            if($include -match '[$*?;]'){throw ('BinaryInputExpressionUnsupported: '+$include)}
            $dependency=[IO.Path]::GetFullPath(([IO.Path]::Combine($directory,$include)))
            if(!$dependency.StartsWith($workspace,[StringComparison]::OrdinalIgnoreCase)){throw 'BinaryInputOutsideWorkspace'}
            if($reference.Name -ceq 'ProjectReference'){$pending.Push($dependency)}else{[void]$roots.Add((Split-Path $dependency -Parent))}
        }
    }
    $files=foreach($root in $roots){foreach($file in Get-QuietSourceFiles $root){$file.Path=[IO.Path]::GetRelativePath($WorkspaceRoot,([IO.Path]::Combine($root,$file.Path))).Replace('\','/');$file}}
    $sdk=[IO.Path]::Combine($WorkspaceRoot,'global.json')
    $spec=[IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh/protocol.json')
    $packages=[IO.Path]::Combine($WorkspaceRoot,'Directory.Packages.props')
    @($files)+@([pscustomobject]@{Path='global.json';Bytes=(Get-Item $sdk).Length;SHA256=(Get-FileHash $sdk -Algorithm SHA256).Hash},[pscustomobject]@{Path='FrenchExDev2.QuietCli.Core.PoSh/protocol.json';Bytes=(Get-Item $spec).Length;SHA256=(Get-FileHash $spec -Algorithm SHA256).Hash},[pscustomobject]@{Path='Directory.Packages.props';Bytes=(Get-Item $packages).Length;SHA256=(Get-FileHash $packages -Algorithm SHA256).Hash})
    $policy=[IO.Path]::Combine($WorkspaceRoot,'Directory.Build.props')
    if(Test-Path -LiteralPath $policy){[pscustomobject]@{Path='Directory.Build.props';Bytes=(Get-Item $policy).Length;SHA256=(Get-FileHash $policy -Algorithm SHA256).Hash}}
}
function Write-QuietBuildManifest {
    <#
    .SYNOPSIS
    Binds built files to their exact C# and SDK inputs; never includes business output.
    .PARAMETER WorkspaceRoot
    Source workspace.
    .PARAMETER Project
    Relative project path.
    .PARAMETER Output
    Relative compiled output directory.
    .PARAMETER Inputs
    Source snapshot captured before compilation.
    .PARAMETER Configuration
    Actual build configuration.
    .PARAMETER RuntimeIdentifier
    Published target RID or portable for the test/reference build.
    .PARAMETER PlatformTarget
    Actual compiler architecture, independently checked from PE headers for Windows publications.
    .PARAMETER ReadyToRun
    Requires a verified ReadyToRun native header before recording the publication.
    .PARAMETER ReadyToRunTargets
    RID slots selected by this build; portable manifests use this to exclude stale slots.
    #>
    param([string]$WorkspaceRoot,[string]$Project,[string]$Output,[Parameter(Mandatory)][object[]]$Inputs,[string]$Configuration='Release',[string]$RuntimeIdentifier='portable',[string]$PlatformTarget='AnyCPU',[switch]$ReadyToRun,[string[]]$ReadyToRunTargets=@())
    $after=@(Get-QuietBinaryInputs $WorkspaceRoot $Project)
    if((Get-QuietManifestDigest $Inputs) -cne (Get-QuietManifestDigest $after)){throw ('SourcesChangedDuringBuild: '+$Project)}
    $directory=[IO.Path]::Combine($WorkspaceRoot,$Output)
    if($ReadyToRun -and !(Test-QuietReadyToRunImage ([IO.Path]::Combine($directory,'QuietCli.Engine.dll')))){throw ('ReadyToRunImageMissing: '+$Output)}
    $binaries=@(Get-ChildItem -LiteralPath $directory -File|Where-Object Name -NE 'build-manifest.json'|Sort-Object Name|ForEach-Object{@{Path=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    Write-WorkspaceJson ([IO.Path]::Combine($directory,'build-manifest.json')) @{SchemaVersion=1;Project=$Project;Configuration=$Configuration;RuntimeIdentifier=$RuntimeIdentifier;PlatformTarget=$PlatformTarget;ReadyToRun=[bool]$ReadyToRun;ReadyToRunTargets=$ReadyToRunTargets;SourceSHA256=(Get-QuietManifestDigest $Inputs);Inputs=$Inputs;Binaries=$binaries}
}
function Test-QuietBuildManifest {
    <#
    .SYNOPSIS
    Rejects stale or modified compiled output before tests, including runs using SkipBuild.
    .PARAMETER WorkspaceRoot
    Current source checkout.
    .PARAMETER Output
    Relative compiled output directory.
    #>
    param([string]$WorkspaceRoot,[string]$Output)
    $directory=[IO.Path]::Combine($WorkspaceRoot,$Output)
    $path=[IO.Path]::Combine($directory,'build-manifest.json')
    if(!(Test-Path -LiteralPath $path)){throw ('BuildManifestMissing: '+$Output)}
    $manifest=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $manifest.Project)
    if((Get-QuietManifestDigest $inputs) -cne $manifest.SourceSHA256){throw ('StaleBuild: '+$manifest.Project)}
    foreach($file in $manifest.Binaries){
        if([IO.Path]::GetFileName($file.Path) -cne $file.Path){throw 'BuildManifestUnsafePath'}
        $binary=[IO.Path]::Combine($directory,$file.Path)
        if(!(Test-Path -LiteralPath $binary) -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -cne $file.SHA256){throw ('BuildBinaryMismatch: '+$binary)}
    }
    if($manifest.PSObject.Properties['ReadyToRun'] -and $manifest.ReadyToRun -and !(Test-QuietReadyToRunImage ([IO.Path]::Combine($directory,'QuietCli.Engine.dll')))){throw ('ReadyToRunImageMissing: '+$Output)}
    if($manifest.PSObject.Properties['RuntimeIdentifier'] -and $manifest.RuntimeIdentifier -ne 'portable'){
        $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $manifest.RuntimeIdentifier
        if(!$target -or $manifest.PlatformTarget -cne $target.PlatformTarget){throw 'EnginePublicationTargetInvalid'}
        Assert-QuietRuntimePublication $directory $target
    }
    return $manifest
}
function Read-QuietRepositoryValue {
    <#
    .SYNOPSIS
    Reads one Git scalar without treating an unborn revision as a fabricated value.
    .PARAMETER Path
    Monorepo root.
    .PARAMETER Arguments
    Read-only Git argument vector.
    #>
    param([string]$Path,[string[]]$Arguments)
    $state=@{Value=[Text.StringBuilder]::new()}
    $result=Invoke-CiProcess -FilePath git -ArgumentList (@('-c',('safe.directory='+[IO.Path]::GetFullPath($Path)))+$Arguments) -WorkingDirectory $Path -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Value.Append($e.Text)}}
    if($result.Outcome -eq 'Success'){return $state.Value.ToString().Trim()};return $null
}
function Get-QuietWorkspaceIdentity {
    <#
    .SYNOPSIS
    Captures one repository, discovered project identities and the binaries actually tested.
    .PARAMETER WorkspaceRoot
    QuietCli2 root.
    .PARAMETER IncludeBinaries
    Verifies build/source associations and records binary digests.
    .PARAMETER Suite
    Restricts binary verification to the selected dependency closure; source drift still covers the checkout.
    #>
    param([string]$WorkspaceRoot,[switch]$IncludeBinaries,[string]$Suite='All')
    $children=@((Get-QuietWorkspaceProjects $WorkspaceRoot).Name)
    $revision=$null;$remote=$null;$dirty=$false
    $allowedFiles=$null
    if(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'.git'))){
        $revision=Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD')
        $remote=Read-QuietRepositoryValue $WorkspaceRoot @('remote','get-url','origin')
        $dirty=![string]::IsNullOrWhiteSpace((Read-QuietRepositoryValue $WorkspaceRoot @('status','--porcelain=v1')))
        $selection=@{Files=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)}
        $listed=Invoke-CiProcess -FilePath git -ArgumentList @('-c',('safe.directory='+[IO.Path]::GetFullPath($WorkspaceRoot)),'-c','core.quotepath=false','ls-files','--cached','--others','--exclude-standard') -WorkingDirectory $WorkspaceRoot -State $selection -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Files.Add($e.Text)}}
        if($listed.Outcome -ne 'Success'){throw 'MonorepoSourceListUnavailable'}
        $allowedFiles=$selection.Files
    }
    $projects=@(foreach($name in $children){$files=@(Get-QuietSourceFiles ([IO.Path]::Combine($WorkspaceRoot,$name))|Where-Object {$null -eq $allowedFiles -or $allowedFiles.Contains($name+'/'+$_.Path)});@{Name=$name;Path=$name;SourceSHA256=(Get-QuietManifestDigest $files);Files=$files}})
    $rootFiles=@(Get-QuietSourceFiles $WorkspaceRoot|Where-Object {$null -eq $allowedFiles -or $allowedFiles.Contains($_.Path)})
    $repository=@{Name='FrenchExDev2.QuietCli.PoSh';Revision=$revision;Remote=$remote;Dirty=$dirty;SourceSHA256=(Get-QuietManifestDigest $rootFiles);Files=$rootFiles}
    $binaries=@()
    if($IncludeBinaries){
        $selectedModules=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot -Suite $Suite)
        foreach($distribution in Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $selectedModules){$binaries+=Test-QuietBuildManifest $WorkspaceRoot $distribution.Output}
    }
    if($IncludeBinaries){foreach($rid in (Get-QuietRuntimeTargets $WorkspaceRoot).Rid){
        $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
        if(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$output))){$binaries+=Test-QuietBuildManifest $WorkspaceRoot $output}
    }}
    if($IncludeBinaries){
        $portable=Test-QuietBuildManifest $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
        foreach($rid in @($(if($portable.PSObject.Properties['ReadyToRunTargets']){$portable.ReadyToRunTargets}))) {
            if($rid -notin (Get-QuietRuntimeTargets $WorkspaceRoot).Rid){throw 'ReadyToRunTargetInvalid'}
            $binaries+=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid)
        }
    }
    $originPath=[IO.Path]::Combine($WorkspaceRoot,'transport-origin.json')
    $origin=if(Test-Path -LiteralPath $originPath){Get-Content -LiteralPath $originPath -Encoding utf8 -Raw|ConvertFrom-Json}else{$null}
    return @{SchemaVersion=3;Repository=$repository;Projects=$projects;Builds=$binaries;TransportOrigin=$origin}
}

Export-ModuleMember -Function 'Get-QuietBinaryInputs','Get-QuietManifestDigest','Get-QuietPeMachine','Get-QuietSourceFiles','Get-QuietWorkspaceBuildProjects','Get-QuietWorkspaceBuildSelection','Get-QuietWorkspaceDotNetHost','Get-QuietWorkspaceIdentity','Get-QuietWorkspacePackages','Get-QuietWorkspaceProjects','Get-QuietWorkspaceSuiteNames','Get-QuietWorkspaceSuiteSelection','Get-QuietWorkspaceTestSuites','New-QuietWorkspaceSuiteParameter','Read-QuietRepositoryValue','Test-QuietBuildManifest','Write-QuietBuildManifest'
