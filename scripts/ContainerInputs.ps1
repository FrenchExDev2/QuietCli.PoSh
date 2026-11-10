function Copy-QuietContainerInputs {
    <#
    .SYNOPSIS
    Stages source, documentation, built modules and restored packages for networkless companion execution.
    .PARAMETER WorkspaceRoot
    Selected source checkout, already built and restored on the host.
    .PARAMETER Destination
    Owned staging directory, outside source inputs.
    .PARAMETER NativeOnly
    Copies only the independent native campaign sources and transport resources.
    .PARAMETER ContainerRuntime
    Effective transport selection; only this public key is forwarded into the staged dotenv file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$Destination,[switch]$NativeOnly,[ValidateSet('','podman','docker')][string]$ContainerRuntime)
    if(!$PSCmdlet.ShouldProcess($Destination,'Copy explicit container inputs and restored NuGet packages')){return}
    . (Join-Path $PSScriptRoot 'Common.ps1')
    $projects=if($NativeOnly){@()}else{@(Get-QuietWorkspaceProjects $WorkspaceRoot)}
    $directories=if($NativeOnly){@('FrenchExDev2.QuietCli.Core.PoSh/native','FrenchExDev2.QuietCli.Core.PoSh/resources/transport','FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests')}else{@('scripts','build','docs','.github')+@($projects.Path)}
    foreach($directory in $directories){
        $source=Join-Path $WorkspaceRoot $directory
        foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File -Force){
            $relative=[IO.Path]::GetRelativePath($source,$file.FullName)
            if($relative -match '(^|[\\/])(\.git|bin|obj|artifacts)[\\/]'){continue}
            if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ContainerInputLinkRejected'}
            $target=Join-Path (Join-Path $Destination $directory) $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    if($NativeOnly){return}
    foreach($file in Get-ChildItem -LiteralPath $WorkspaceRoot -File -Force){
        if($file.Extension -cne '.md' -and $file.Name -cnotin @('global.json','Directory.Build.props','Directory.Packages.props','Quietly.slnx','repositories.lock.json','.gitattributes','.editorconfig','.gitignore','LICENSE')){continue}
        Copy-Item -LiteralPath $file.FullName -Destination $Destination
    }
    $runtime=if($ContainerRuntime){$ContainerRuntime}else{Get-QuietEnvValue -Path (Join-Path $WorkspaceRoot '.env') -Key QUIET_CONTAINER_RUNTIME}
    if($null -ne $runtime){
        if($runtime -cnotin @('podman','docker')){throw 'ContainerRuntimeConfigurationInvalid'}
        $null=Set-QuietEnvValue -Path (Join-Path $Destination '.env') -Key QUIET_CONTAINER_RUNTIME -Value $runtime -Confirm:$false
    }
    $packages=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($project in $projects){foreach($directory in Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot $project.Path) -Directory){
        $assetsPath=Join-Path $directory.FullName 'obj/project.assets.json'
        if(!(Test-Path -LiteralPath $assetsPath)){continue}
        $assets=Get-Content -LiteralPath $assetsPath -Raw -Encoding utf8|ConvertFrom-Json
        foreach($library in $assets.libraries.PSObject.Properties){
            if($library.Value.type -cne 'package'){continue}
            $relative=[string]$library.Value.path
            if($relative -cnotmatch '\A[a-z0-9_.-]+/[a-z0-9_.+-]+\z' -or $relative.Split('/') -ccontains '..' -or $relative.Split('/') -ccontains '.'){throw 'ContainerNuGetPackagePathInvalid'}
            if($packages.ContainsKey($relative)){continue}
            $cached=@(foreach($folder in $assets.packageFolders.PSObject.Properties.Name){$candidate=Join-Path $folder $relative;if(Test-Path -LiteralPath $candidate -PathType Container){$candidate}})
            if(!$cached.Count){throw ('ContainerRestoredPackageMissing: '+$relative)}
            $packages.Add($relative,$cached[0])
        }
    }}
    foreach($package in $packages.GetEnumerator()){
        $target=Join-Path $Destination ('artifacts/nuget-cache/'+$package.Key)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath $package.Value -Destination $target -Recurse
    }
}
