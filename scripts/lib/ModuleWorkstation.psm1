#Objective: Returns the per-user module tool/cache directory without creating it.
#requires -Version 7.6
Import-Module (Join-Path $PSScriptRoot 'DevelopmentWorkstation.psm1') -ErrorAction Stop
$script:ModuleWorkspaceRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Get-ModuleWorkstationCacheRoot {
    <# .SYNOPSIS
    Returns the per-user module tool/cache directory without creating it.
    #>
    if($IsWindows){return (Join-Path $env:LOCALAPPDATA 'QuietCli2/modules')}
    Join-Path $HOME '.local/share/QuietCli2/modules'
}

function Get-ModuleWorkstationStatus {
    <#
    .SYNOPSIS
    Probes a module tool and its usable container client without changing the host.
    .PARAMETER Name
    Git or Vagrant.
    .PARAMETER Target
    Validated development host.
    #>
    param([ValidateSet('Git','Vagrant')][string]$Name,$Target)
    $cache=Join-Path (Get-ModuleWorkstationCacheRoot) $Name
    $preferred=if($Name -eq 'Git'){
        Join-Path $cache $(if($Target.Id -eq 'windows'){'git/cmd/git.exe'}else{'git/bin/git'})
    }elseif($Target.Id -eq 'windows'){'C:/HashiCorp/Vagrant/bin/vagrant.exe'}else{$null}
    $application=Find-DevelopmentApplication $Name.ToLowerInvariant() $preferred
    $version=$null;$toolReady=$false
    if($application){
        $probe=Invoke-DevelopmentCommand $application @('--version') -Capture -AllowFailure -TimeoutSeconds 30
        $version=($probe.Lines -join "`n").Trim()
        $toolReady=$probe.Outcome -eq 'Success' -and $(if($Name -eq 'Git'){Test-DevelopmentGitVersion $version}else{Test-DevelopmentVagrantVersion $version})
    }
    $provider=$null;$providerReady=$true
    if($Name -eq 'Vagrant'){
        # Vagrant's built-in Docker provider requires a working docker client, including with a Podman socket.
        $provider=if($env:DOCKER_HOST -match 'podman'){'docker via podman'}else{'docker'}
        $docker=Find-DevelopmentApplication docker
        $providerReady=[bool]($docker -and (Invoke-DevelopmentCommand $docker @('info') -Capture -AllowFailure -TimeoutSeconds 30).Outcome -eq 'Success')
    }
    [pscustomobject]@{Module=$Name;State=if($toolReady -and $providerReady){'Ready'}else{'NeedsInstallation'};Version=$version;Path=$application;ToolReady=[bool]$toolReady;Provider=$provider;ProviderReady=$providerReady;Action='None';CachePath=$null;RestartRequired=$false}
}

function Get-ModuleWorkstationArtifact {
    <#
    .SYNOPSIS
    Selects a checksum-pinned artifact, keeping unsupported platforms explicit.
    .PARAMETER Name
    Selected module.
    .PARAMETER Target
    Validated development host.
    #>
    param([ValidateSet('Git','Vagrant')][string]$Name,$Target)
    if($Name -eq 'Git'){
        $spec=Get-DevelopmentSpecification $script:ModuleWorkspaceRoot $Target
        $entry=if($Target.Id -eq 'windows'){$spec.WindowsGit}else{$spec.GitSource}
        $file=if($Target.Id -eq 'windows'){"git-$($spec.GitVersion)-$($Target.Architecture).zip"}else{"git-$($spec.GitVersion).tar.gz"}
        return [pscustomobject]@{Url=$entry.Url;SHA256=$entry.SHA256;File=$file;Specification=$spec}
    }
    $lock=Get-Content -LiteralPath (Join-Path $script:ModuleWorkspaceRoot 'build/vagrant-installers.lock.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $platform=switch($Target.Id){'windows'{'windows'} 'debian'{'deb'} 'ubuntu'{'deb'} 'fedora'{'rpm'} default{throw 'UnsupportedVagrantInstallerTarget'}}
    $entries=@($lock.Artifacts | Where-Object {$_.Platform -ceq $platform -and $_.Architecture -ceq $Target.Architecture})
    if($lock.SchemaVersion -ne 1 -or $lock.Version -cnotmatch '^2\.[34]\.\d+$' -or $entries.Count -ne 1){throw 'UnsupportedVagrantInstallerTarget'}
    $entry=$entries[0]
    if([IO.Path]::GetFileName($entry.File) -cne $entry.File){throw 'VagrantInstallerPathInvalid'}
    [pscustomobject]@{Url="https://releases.hashicorp.com/vagrant/$($lock.Version)/$($entry.File)";SHA256=$entry.SHA256;File=$entry.File;Specification=$null}
}

function Save-ModuleWorkstationDownload {
    <#
    .SYNOPSIS
    Downloads and verifies a selected tool artifact, without extracting or installing it.
    .PARAMETER Name
    Selected module.
    .PARAMETER Target
    Validated development host.
    #>
    param([ValidateSet('Git','Vagrant')][string]$Name,$Target)
    $artifact=Get-ModuleWorkstationArtifact $Name $Target
    $destination=Join-Path (Get-ModuleWorkstationCacheRoot) "$Name/downloads/$($artifact.File)"
    $development=Get-Module DevelopmentWorkstation
    & $development {param($artifact,$destination) Get-DevelopmentArchive $artifact.Url $artifact.SHA256 $destination} $artifact $destination
}

function Install-ModuleWorkstationTool {
    <#
    .SYNOPSIS
    Installs an explicitly selected pinned tool after the caller's ShouldProcess gate.
    .PARAMETER Name
    Selected module.
    .PARAMETER Target
    Validated development host.
    #>
    param([ValidateSet('Git','Vagrant')][string]$Name,$Target)
    if($Name -eq 'Git'){
        $artifact=Get-ModuleWorkstationArtifact $Name $Target
        $plan=[pscustomobject]@{Target=$Target;InstallRoot=(Join-Path (Get-ModuleWorkstationCacheRoot) $Name);Specification=$artifact.Specification}
        & (Get-Module DevelopmentWorkstation) {param($plan) Install-DevelopmentGit $plan} $plan
        return $false
    }
    $archive=Save-ModuleWorkstationDownload $Name $Target
    if($Target.Id -eq 'windows'){
        $result=Invoke-DevelopmentCommand msiexec.exe @('/i',$archive,'/qn','/norestart') -AllowFailure
        if($result.ExitCode -notin @(0,3010)){throw "VagrantInstallerFailed: $($result.ExitCode)"}
        return ($result.ExitCode -eq 3010)
    }
    $tool=$Target.Manager
    $arguments=if($tool -eq 'apt-get'){@('install','-y','--no-install-recommends',$archive)}else{@('install','-y',$archive)}
    if([Environment]::UserName -cne 'root'){$arguments=@('-n',$tool)+$arguments;$tool='sudo'}
    $null=Invoke-DevelopmentCommand $tool $arguments
    $false
}

Export-ModuleMember -Function Get-ModuleWorkstationCacheRoot,Get-ModuleWorkstationStatus,Get-ModuleWorkstationArtifact,Save-ModuleWorkstationDownload,Install-ModuleWorkstationTool
