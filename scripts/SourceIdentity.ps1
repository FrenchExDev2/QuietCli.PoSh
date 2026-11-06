# Objectif : Partager une identité déterministe des sources et des binaires entre verrouillage, build et tests.
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
            if($item.Name -in @('.git','bin','obj','lib','artifacts','.vs')){continue}
            if($directory -eq $rootPath -and $item.Name -in $ExcludeChildren){continue}
            if($directory -eq $rootPath -and $item.Name -eq 'repositories.lock.json'){continue}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('SourceLinkNotAllowed: '+$item.FullName)}
            if($item.PSIsContainer){$pending.Push($item.FullName)}else{$files.Add($item.FullName)}
        }
    }
    $sorted=$files.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    foreach($path in $sorted){[pscustomobject]@{Path=[IO.Path]::GetRelativePath($rootPath,$path).Replace('\','/');Bytes=(Get-Item -LiteralPath $path -Force).Length;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}
}
function Get-QuietPeMachine {
    <#
    .SYNOPSIS
    Reads the actual PE machine field without loading or executing a managed assembly or native apphost.
    .PARAMETER Path
    Compiled Windows executable or assembly.
    #>
    param([string]$Path)
    $stream=[IO.File]::OpenRead($Path);$reader=[IO.BinaryReader]::new($stream)
    try{
        if($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d){throw 'InvalidPeHeader'}
        $stream.Position=0x3c;$offset=$reader.ReadUInt32()
        if($offset -gt $stream.Length-6){throw 'InvalidPeOffset'}
        $stream.Position=$offset
        if($reader.ReadUInt32() -ne 0x4550){throw 'InvalidPeSignature'}
        return $reader.ReadUInt16()
    }finally{$reader.Dispose();$stream.Dispose()}
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
    $roots=@((Split-Path (Join-Path $WorkspaceRoot $Project) -Parent))
    if($Project -match 'engine-tests'){$roots+=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/engine'}
    if($Project -match 'engine-tests'){$roots+=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools'}
    if($Project -match 'recall-tools'){$roots+=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/engine'}
    if($Project -like 'FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests/*'){$roots+=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/engine'}
    $files=foreach($root in $roots){foreach($file in Get-QuietSourceFiles $root){$file.Path=[IO.Path]::GetRelativePath($WorkspaceRoot,(Join-Path $root $file.Path)).Replace('\','/');$file}}
    $sdk=Join-Path $WorkspaceRoot 'global.json'
    $spec=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/protocol.json'
    @($files)+@([pscustomobject]@{Path='global.json';Bytes=(Get-Item $sdk).Length;SHA256=(Get-FileHash $sdk -Algorithm SHA256).Hash},[pscustomobject]@{Path='FrenchExDev2.QuietCli.Core.PoSh/protocol.json';Bytes=(Get-Item $spec).Length;SHA256=(Get-FileHash $spec -Algorithm SHA256).Hash})
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
    #>
    param([string]$WorkspaceRoot,[string]$Project,[string]$Output,[Parameter(Mandatory)][object[]]$Inputs,[string]$Configuration='Release',[string]$RuntimeIdentifier='portable',[string]$PlatformTarget='AnyCPU')
    $after=@(Get-QuietBinaryInputs $WorkspaceRoot $Project)
    if((Get-QuietManifestDigest $Inputs) -cne (Get-QuietManifestDigest $after)){throw ('SourcesChangedDuringBuild: '+$Project)}
    $directory=Join-Path $WorkspaceRoot $Output
    $binaries=@(Get-ChildItem -LiteralPath $directory -File|Where-Object Name -NE 'build-manifest.json'|Sort-Object Name|ForEach-Object{@{Path=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    Write-WorkspaceJson (Join-Path $directory 'build-manifest.json') @{SchemaVersion=1;Project=$Project;Configuration=$Configuration;RuntimeIdentifier=$RuntimeIdentifier;PlatformTarget=$PlatformTarget;SourceSHA256=(Get-QuietManifestDigest $Inputs);Inputs=$Inputs;Binaries=$binaries}
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
    $directory=Join-Path $WorkspaceRoot $Output
    $path=Join-Path $directory 'build-manifest.json'
    if(!(Test-Path -LiteralPath $path)){throw ('BuildManifestMissing: '+$Output)}
    $manifest=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $manifest.Project)
    if((Get-QuietManifestDigest $inputs) -cne $manifest.SourceSHA256){throw ('StaleBuild: '+$manifest.Project)}
    foreach($file in $manifest.Binaries){
        if([IO.Path]::GetFileName($file.Path) -cne $file.Path){throw 'BuildManifestUnsafePath'}
        $binary=Join-Path $directory $file.Path
        if(!(Test-Path -LiteralPath $binary) -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -cne $file.SHA256){throw ('BuildBinaryMismatch: '+$binary)}
    }
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
    $result=Invoke-CiProcess -FilePath git -ArgumentList $Arguments -WorkingDirectory $Path -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Value.Append($e.Text)}}
    if($result.Outcome -eq 'Success'){return $state.Value.ToString().Trim()};return $null
}
function Get-QuietWorkspaceIdentity {
    <#
    .SYNOPSIS
    Captures one repository, four project identities and the binaries actually tested.
    .PARAMETER WorkspaceRoot
    QuietCli2 root.
    .PARAMETER IncludeBinaries
    Verifies build/source associations and records binary digests.
    #>
    param([string]$WorkspaceRoot,[switch]$IncludeBinaries)
    $children=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh')
    $revision=$null;$remote=$null;$dirty=$false
    $allowedFiles=$null
    if(Test-Path -LiteralPath (Join-Path $WorkspaceRoot '.git')){
        $revision=Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD')
        $remote=Read-QuietRepositoryValue $WorkspaceRoot @('remote','get-url','origin')
        $dirty=![string]::IsNullOrWhiteSpace((Read-QuietRepositoryValue $WorkspaceRoot @('status','--porcelain=v1')))
        $selection=@{Files=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)}
        $listed=Invoke-CiProcess -FilePath git -ArgumentList @('-c','core.quotepath=false','ls-files','--cached','--others','--exclude-standard') -WorkingDirectory $WorkspaceRoot -State $selection -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Files.Add($e.Text)}}
        if($listed.Outcome -ne 'Success'){throw 'MonorepoSourceListUnavailable'}
        $allowedFiles=$selection.Files
    }
    $projects=@(foreach($name in $children){$files=@(Get-QuietSourceFiles (Join-Path $WorkspaceRoot $name)|Where-Object {$null -eq $allowedFiles -or $allowedFiles.Contains($name+'/'+$_.Path)});@{Name=$name;Path=$name;SourceSHA256=(Get-QuietManifestDigest $files);Files=$files}})
    $rootFiles=@(Get-QuietSourceFiles $WorkspaceRoot|Where-Object {$null -eq $allowedFiles -or $allowedFiles.Contains($_.Path)})
    $repository=@{Name='FrenchExDev2.QuietCli.PoSh';Revision=$revision;Remote=$remote;Dirty=$dirty;SourceSHA256=(Get-QuietManifestDigest $rootFiles);Files=$rootFiles}
    $binaries=@()
    if($IncludeBinaries){foreach($output in @('FrenchExDev2.QuietCli.Core.PoSh/lib/engine','FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess','FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture','FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests','FrenchExDev2.QuietCli.Git.PoSh/lib/parser/net10.0','FrenchExDev2.QuietCli.Git.PoSh/lib/parser/net11.0','FrenchExDev2.QuietCli.Git.Tests.PoSh/lib/parser-tests')){$binaries+=Test-QuietBuildManifest $WorkspaceRoot $output}}
    if($IncludeBinaries){foreach($rid in (Get-QuietRuntimeTargets $WorkspaceRoot).Rid){
        $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
        if(Test-Path -LiteralPath (Join-Path $WorkspaceRoot $output)){$binaries+=Test-QuietBuildManifest $WorkspaceRoot $output}
    }}
    $originPath=Join-Path $WorkspaceRoot 'transport-origin.json'
    $origin=if(Test-Path -LiteralPath $originPath){Get-Content -LiteralPath $originPath -Encoding utf8 -Raw|ConvertFrom-Json}else{$null}
    return @{SchemaVersion=3;Repository=$repository;Projects=$projects;Builds=$binaries;TransportOrigin=$origin}
}
