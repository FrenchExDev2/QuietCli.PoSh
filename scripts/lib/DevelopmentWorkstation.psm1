#Objective: Detect, plan and provision an independently bootstrappable development workstation.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-DevelopmentHost {
    <#
    .SYNOPSIS
    Detects a native Windows/Linux target without evaluating os-release as executable code.
    .PARAMETER OperatingSystem
    Optional host fixture; defaults to the actual operating system.
    .PARAMETER Architecture
    Native architecture; an emulated PowerShell process is rejected.
    .PARAMETER OsReleaseText
    Optional UTF-8 Linux os-release fixture.
    #>
    [CmdletBinding()]
    param([string]$OperatingSystem,[string]$Architecture,[AllowEmptyString()][string]$OsReleaseText)
    if(!$OperatingSystem){$OperatingSystem=if($IsWindows){'Windows'}elseif($IsLinux){'Linux'}else{'Unsupported'}}
    if(!$Architecture){
        if([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -ne [Runtime.InteropServices.RuntimeInformation]::OSArchitecture){throw 'WorkstationRequiresNativePowerShell'}
        $Architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    }
    if($Architecture -cnotin @('x64','arm64')){throw "WorkstationArchitectureUnsupported: $Architecture"}
    if($OperatingSystem -ceq 'Windows'){
        return [pscustomobject]@{Id='windows';Version=[Environment]::OSVersion.Version.ToString();Architecture=$Architecture;Rid="win-$Architecture";Manager='winget';EditorMode='Desktop'}
    }
    if($OperatingSystem -cne 'Linux'){throw "WorkstationOperatingSystemUnsupported: $OperatingSystem"}
    if(!$PSBoundParameters.ContainsKey('OsReleaseText')){$OsReleaseText=[IO.File]::ReadAllTextAsync('/etc/os-release',[Text.Encoding]::UTF8).GetAwaiter().GetResult()}
    if($OsReleaseText.Length -gt 16384 -or $OsReleaseText.Contains([char]0)){throw 'WorkstationOsReleaseInvalid'}
    $values=@{}
    foreach($line in ($OsReleaseText -split '\r?\n')){
        if($line -match '^\s*(ID|VERSION_ID)=(.*)\s*$'){
            $key=$Matches[1];$value=$Matches[2].Trim()
            if($values.ContainsKey($key)){throw 'WorkstationOsReleaseDuplicateKey'}
            if($value -match '^"([a-zA-Z0-9._-]+)"$' -or $value -match "^'([a-zA-Z0-9._-]+)'$"){$value=$Matches[1]}
            if($value -cnotmatch '^[a-z0-9][a-z0-9._-]*$'){throw 'WorkstationOsReleaseInvalidValue'}
            $values[$key]=$value
        }
    }
    if(!$values.ID -or !$values.VERSION_ID){throw 'WorkstationOsReleaseMissingIdentity'}
    $supported=@{debian='^(12|13)(\.[0-9]+)?$';ubuntu='^(24\.04|26\.04)(\.[0-9]+)?$';fedora='^(43|44)$';alpine='^3\.(23|24)(\.[0-9]+)?$'}
    if(!$supported.ContainsKey($values.ID) -or $values.VERSION_ID -cnotmatch $supported[$values.ID]){throw "WorkstationDistributionUnsupported: $($values.ID) $($values.VERSION_ID)"}
    $musl=$values.ID -ceq 'alpine'
    [pscustomobject]@{Id=$values.ID;Version=$values.VERSION_ID;Architecture=$Architecture;Rid=$(if($musl){"linux-musl-$Architecture"}else{"linux-$Architecture"});Manager=$(if($musl){'apk'}elseif($values.ID -ceq 'fedora'){'dnf'}else{'apt-get'});EditorMode=$(if($musl){'Remote'}else{'Desktop'})}
}

function Get-DevelopmentPackages {
    <#
    .SYNOPSIS
    Returns explicit package names for the selected distribution and component.
    .PARAMETER Target
    Validated host description.
    .PARAMETER Component
    Runtime, native build/fuzz or rootless container dependencies.
    #>
    param($Target,[ValidateSet('System','Native','Containers')][string]$Component='System')
    if($Target.Id -ceq 'windows'){return @()}
    if($Target.Id -ceq 'alpine'){
        switch($Component){
            System {@('ca-certificates','curl','git','bash','tar','xz','gzip','icu-libs','icu-data-full','libstdc++','libgcc','libssl3','libatomic','krb5-libs','zlib','tzdata')}
            Native {@('build-base','clang','compiler-rt','linux-headers','openssl-dev','zlib-dev','curl-dev','expat-dev','pkgconf')}
            Containers {@('podman','shadow-uidmap','slirp4netns','fuse-overlayfs')}
        };return
    }
    if($Target.Id -ceq 'fedora'){
        switch($Component){
            System {@('ca-certificates','curl','git','bash','tar','xz','gzip','glibc','libgcc','libstdc++','libicu','openssl-libs','krb5-libs','zlib-ng-compat','libunwind','libatomic','tzdata')}
            Native {@('gcc','gcc-c++','make','clang','compiler-rt','glibc-devel','openssl-devel','zlib-ng-compat-devel','libcurl-devel','expat-devel','pkgconf-pkg-config')}
            Containers {@('podman','shadow-utils','passt','fuse-overlayfs')}
        };return
    }
    switch($Component){
        System {
            $icu=if($Target.Id -ceq 'debian'){if($Target.Version -match '^12'){'libicu72'}else{'libicu76'}}elseif($Target.Version -match '^24'){'libicu74'}else{'libicu78'}
            $ssl=if($Target.Id -ceq 'debian' -and $Target.Version -match '^12'){'libssl3'}else{'libssl3t64'}
            @('ca-certificates','curl','git','bash','tar','xz-utils','gzip','libc6','libgcc-s1','libgssapi-krb5-2',$icu,$ssl,'libstdc++6','libunwind8','libatomic1','zlib1g','tzdata')
        }
        Native {@('build-essential','clang','libclang-rt-dev','libssl-dev','zlib1g-dev','libcurl4-openssl-dev','libexpat1-dev','pkg-config')}
        Containers {@('podman','uidmap','passt','slirp4netns','fuse-overlayfs')}
    }
}

function Test-DevelopmentGitVersion {
    <#
    .SYNOPSIS
    Checks the stable Git range supported by the companion, including Windows suffixes.
    .PARAMETER Text
    Git's version banner.
    #>
    param([string]$Text)
    if($Text -cnotmatch '^git version (2\.[0-9]+\.[0-9]+)(\.windows\.[0-9]+)?$'){return $false}
    $version=[version]$Matches[1]
    $version -ge [version]'2.40.0' -and $version -lt [version]'2.57.0'
}

function Test-DevelopmentVagrantVersion {
    <#
    .SYNOPSIS
    Checks the stable Vagrant range supported by the companion module (same range as the handlers' own TestVersion).
    .PARAMETER Text
    Vagrant's version banner (`vagrant --version` output).
    #>
    param([string]$Text)
    if($Text -cnotmatch '^Vagrant (\d+\.\d+\.\d+)$'){return $false}
    $version=$null
    if(![version]::TryParse($Matches[1],[ref]$version)){return $false}
    $version -ge [version]'2.3.0' -and $version -lt [version]'2.5.0'
}

function Get-DevelopmentWrkflwSpecification {
    <#
    .SYNOPSIS
    Validates reviewed wrkflw release identities and selects only a native host artifact.
    .PARAMETER Configuration
    Version, provenance URL and checksum-pinned artifacts from the workstation lock.
    .PARAMETER Target
    Validated native host description; missing upstream artifacts remain unsupported.
    #>
    param($Configuration,$Target)
    $version=$null
    if(!$Configuration -or $Configuration.Version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z' -or
        ![version]::TryParse($Configuration.Version,[ref]$version) -or
        $Configuration.Source -cne ('https://api.github.com/repos/bahdotsh/wrkflw/releases/tags/v'+$Configuration.Version)){
        throw 'WorkstationWrkflwLockInvalid'
    }
    $triples=@{
        'win-x64'='x86_64-pc-windows-msvc'
        'linux-x64'='x86_64-unknown-linux-gnu'
        'linux-arm64'='aarch64-unknown-linux-gnu'
        'linux-musl-x64'='x86_64-unknown-linux-musl'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($artifact in $Configuration.Artifacts){
        if(!$triples.ContainsKey([string]$artifact.Rid) -or !$seen.Add([string]$artifact.Rid)){
            throw 'WorkstationWrkflwArtifactNotUniqueOrUnsupported'
        }
        $suffix=if($artifact.Rid -ceq 'win-x64'){'zip'}else{'tar.gz'}
        $expected='https://github.com/bahdotsh/wrkflw/releases/download/v'+$Configuration.Version+'/wrkflw-'+$triples[$artifact.Rid]+'.'+$suffix
        if($artifact.Url -cne $expected -or $artifact.SHA256 -cnotmatch '\A[a-f0-9]{64}\z'){
            throw 'WorkstationWrkflwArtifactIdentityInvalid'
        }
    }
    if($seen.Count -ne $triples.Count){throw 'WorkstationWrkflwArtifactsMissing'}
    $selected=@($Configuration.Artifacts|Where-Object Rid -CEQ $Target.Rid)
    [pscustomobject]@{Version=[string]$Configuration.Version;Source=[string]$Configuration.Source;Artifact=$(if($selected.Count){$selected[0]}else{$null})}
}

function Test-DevelopmentWrkflwVersion {
    <#
    .SYNOPSIS
    Accepts only the exact stable wrkflw banner selected by the reviewed lock.
    .PARAMETER Text
    Observed version banner, without its terminal newline.
    .PARAMETER ExpectedVersion
    Stable version from the validated workstation specification.
    #>
    param([string]$Text,[string]$ExpectedVersion)
    [string]::Equals($Text,('wrkflw '+$ExpectedVersion),[StringComparison]::Ordinal)
}

function Get-DevelopmentSpecification {
    <#
    .SYNOPSIS
    Resolves locked SDK, compiler and Git artifacts using the existing source locks.
    .PARAMETER WorkspaceRoot
    Monorepo root containing global.json and reviewed locks.
    .PARAMETER Target
    Validated host description.
    #>
    param([string]$WorkspaceRoot,$Target)
    $global=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'global.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $lock=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'build/development-workstation.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $ci=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'build/ci-images.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $zig=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'build/zig.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $git=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/ci-image.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $sources=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/UpstreamSources.json')) -Raw -Encoding utf8|ConvertFrom-Json
    $sdk=[string]$global.sdk.version
    if($lock.SchemaVersion -ne 1 -or $sdk -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$' -or $lock.SdkVersion -cne $sdk -or $ci.SDK -cne $sdk){throw 'WorkstationSdkLockMismatch'}
    if($lock.ZigVersion -cne $zig.Version -or $lock.GitVersion -cne $git.GitVersion){throw 'WorkstationToolLockMismatch'}
    $windows=$Target.Id -ceq 'windows'
    $entry=@(if($windows){$lock.WindowsSdks|Where-Object Rid -CEQ $Target.Rid}else{$ci.Platforms|Where-Object Rid -CEQ $Target.Rid})
    if($entry.Count -ne 1){throw 'WorkstationSdkArtifactNotUnique'}
    $hash=if($windows){$entry[0].SHA512}else{$entry[0].SDK_SHA512}
    if($hash -cnotmatch '^[a-fA-F0-9]{128}$'){throw 'WorkstationSdkDigestInvalid'}
    $zigHost=$(if($Target.Architecture -ceq 'arm64'){'aarch64'}else{'x86_64'})+'-'+$(if($windows){'windows'}else{'linux'})
    $compiler=@(if($windows){$zig.Hosts|Where-Object Host -CEQ $zigHost}else{$lock.LinuxZig|Where-Object Host -CEQ $zigHost})
    $gitSource=@($sources.Sources|Where-Object Version -CEQ $git.GitVersion)
    if($compiler.Count -ne 1 -or $gitSource.Count -ne 1){throw 'WorkstationToolArtifactNotUnique'}
    $powerShellFramework=$null
    $hostConfiguration=[IO.Path]::Combine($PSHOME,'pwsh.runtimeconfig.json')
    if(Test-Path -LiteralPath $hostConfiguration){
        $runtimeOptions=(Get-Content -LiteralPath $hostConfiguration -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable).runtimeOptions
        if($runtimeOptions.ContainsKey('framework')){
            $powerShellFramework=[pscustomobject]@{Name=$runtimeOptions.framework.name;Version=[Environment]::Version.ToString();Directory=[Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()}
        }
    }
    [pscustomobject]@{
        SdkVersion=$sdk;SdkUrl="https://builds.dotnet.microsoft.com/dotnet/Sdk/$sdk/dotnet-sdk-$sdk-$($Target.Rid)."+$(if($windows){'zip'}else{'tar.gz'});SdkHash=$hash
        ZigVersion=$zig.Version;Zig=$compiler[0];GitVersion=$git.GitVersion;GitSource=$gitSource[0]
        WindowsGit=$(if($windows){@($lock.WindowsGit|Where-Object Architecture -CEQ $Target.Architecture)[0]}else{$null})
        PowerShellFramework=$powerShellFramework
        Wrkflw=Get-DevelopmentWrkflwSpecification $lock.Wrkflw $Target
    }
}

function Invoke-DevelopmentCommand {
    <#
    .SYNOPSIS
    Runs an argument vector through the engine-independent process helper, without a shell.
    .PARAMETER FilePath
    Explicit application.
    .PARAMETER Arguments
    Native arguments, preserved individually.
    .PARAMETER WorkingDirectory
    Explicit working directory, including for global.json resolution.
    .PARAMETER Capture
    Retains bounded query lines; installation output otherwise streams to the terminal.
    .PARAMETER AllowFailure
    Returns an unsuccessful query or reboot code for the caller to classify.
    .PARAMETER TimeoutSeconds
    Owned-process deadline.
    #>
    param([string]$FilePath,[string[]]$Arguments=@(),[string]$WorkingDirectory=$PWD.Path,[switch]$Capture,[switch]$AllowFailure,[int]$TimeoutSeconds=1800)
    $state=@{Lines=[Collections.Generic.List[string]]::new();Tail=[Collections.Generic.Queue[string]]::new();Chars=0;Capture=[bool]$Capture}
    $result=Invoke-CiProcess -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds -State $state -OnOutput {
        param($e,$s)
        if($s.Tail.Count -ge 8){[void]$s.Tail.Dequeue()};$s.Tail.Enqueue($e.Text)
        if($s.Capture){if($e.Stream -eq 'stdout'){if($s.Lines.Count -ge 2048 -or $s.Chars+$e.Text.Length -gt 1048576){throw 'WorkstationQueryTooLarge'};$s.Chars+=$e.Text.Length;[void]$s.Lines.Add($e.Text)}}
        elseif($e.Stream -eq 'stderr'){[void][Console]::Error.WriteLineAsync($e.Text).GetAwaiter().GetResult()}
        else{[void][Console]::Out.WriteLineAsync($e.Text).GetAwaiter().GetResult()}
    }
    if(!$AllowFailure -and $result.Outcome -ne 'Success'){throw "WorkstationCommandFailed: $FilePath ($($result.ExitCode), $($result.Outcome)): $($state.Tail -join ' | ')"}
    [pscustomobject]@{Outcome=$result.Outcome;ExitCode=$result.ExitCode;Lines=@($state.Lines);Diagnostics=@($state.Tail)}
}

function Find-DevelopmentApplication {
    <#
    .SYNOPSIS
    Resolves an owned installation first, then existing applications and well-known Windows locations.
    .PARAMETER Name
    Application name.
    .PARAMETER Preferred
    Preferred explicit paths.
    #>
    param([string]$Name,[string[]]$Preferred=@())
    foreach($path in $Preferred){if($path -and [IO.File]::Exists($path)){return [IO.Path]::GetFullPath($path)}}
    $command=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if($command){return $command.Source}
    return $null
}

function Get-DevelopmentInventory {
    <#
    .SYNOPSIS
    Probes selected components read-only, without downloads, directory creation or profile changes.
    .PARAMETER Plan
    Immutable target, component and artifact choices.
    #>
    param($Plan)
    $target=$Plan.Target;$root=$Plan.InstallRoot;$spec=$Plan.Specification
    $inventory=[ordered]@{}
    foreach($name in @('System','Sdk','Git','Editor','Native','Profilers','Containers','Workflows')){
        $inventory[$name]=[pscustomobject]@{Name=$name;State='Missing';Version=$null;Path=$null;Detail=$null}
        if($Plan.Skipped -contains $name){$inventory[$name].State='Excluded'}
    }
    if($target.Id -ceq 'windows'){$inventory.System.State='Ready';$inventory.System.Detail='PowerShell 7.6+; Windows package prerequisites are supplied by installers.'}
    else{
        $packages=@(Get-DevelopmentPackages $target System)
        if($Plan.Skipped -notcontains 'Native'){$packages+=@(Get-DevelopmentPackages $target Native)}
        if($Plan.Skipped -notcontains 'Containers'){$packages+=@(Get-DevelopmentPackages $target Containers)}
        $missing=[Collections.Generic.List[string]]::new()
        foreach($package in $packages|Select-Object -Unique){
            $query=switch($target.Manager){
                'apt-get' {Invoke-DevelopmentCommand dpkg-query @('-W','-f=${db:Status-Status}',$package) -Capture -AllowFailure}
                'dnf' {Invoke-DevelopmentCommand rpm @('-q',$package) -Capture -AllowFailure}
                'apk' {Invoke-DevelopmentCommand apk @('info','-e',$package) -Capture -AllowFailure}
            }
            if($query.Outcome -ne 'Success' -or ($target.Manager -ceq 'apt-get' -and ($query.Lines -join '') -cne 'installed')){[void]$missing.Add($package)}
        }
        $inventory.System.State=if(!$missing.Count){'Ready'}else{'Missing'};$inventory.System.Detail=$missing -join ', '
    }
    $exe=if($target.Id -ceq 'windows'){'dotnet.exe'}else{'dotnet'}
    $dotnet=Find-DevelopmentApplication dotnet @(([IO.Path]::Combine($root,"dotnet/$exe")))
    if($dotnet){
        $query=Invoke-DevelopmentCommand $dotnet @('--version') $Plan.WorkspaceRoot -Capture -AllowFailure
        $inventory.Sdk.Path=$dotnet;$inventory.Sdk.Version=($query.Lines -join '').Trim()
        if($query.Outcome -eq 'Success' -and $inventory.Sdk.Version -ceq $spec.SdkVersion){
            $inventory.Sdk.State='Ready'
            if($spec.PSObject.Properties['PowerShellFramework'] -and $spec.PowerShellFramework){
                $runtimes=Invoke-DevelopmentCommand $dotnet @('--list-runtimes') -Capture -AllowFailure
                $expected=$spec.PowerShellFramework.Name+' '+$spec.PowerShellFramework.Version+' '
                if($runtimes.Outcome -ne 'Success' -or !@($runtimes.Lines|Where-Object {$_.StartsWith($expected,[StringComparison]::Ordinal)}).Count){$inventory.Sdk.State='Missing';$inventory.Sdk.Detail='The SDK root must also retain the framework-dependent PowerShell runtime.'}
            }
        }
    }
    $git=Find-DevelopmentApplication git @(([IO.Path]::Combine($root,$(if($target.Id -ceq 'windows'){'git/cmd/git.exe'}else{'git/bin/git'}))))
    if($git){$query=Invoke-DevelopmentCommand $git @('--version') -Capture -AllowFailure;$inventory.Git.Path=$git;$inventory.Git.Version=($query.Lines -join '').Trim();if($query.Outcome -eq 'Success' -and (Test-DevelopmentGitVersion $inventory.Git.Version)){$inventory.Git.State='Ready'}}
    if($inventory.Workflows.State -ne 'Excluded'){
        if(!$spec.Wrkflw.Artifact){
            $inventory.Workflows.State='Unsupported'
            $inventory.Workflows.Detail="No reviewed native wrkflw $($spec.Wrkflw.Version) artifact for $($target.Rid). Use -SkipWorkflows; no emulation or source build is implicit."
        }else{
            $binary=if($target.Id -ceq 'windows'){'wrkflw.exe'}else{'wrkflw'}
            $workflowTool=Find-DevelopmentApplication wrkflw @(([IO.Path]::Combine($root,"wrkflw/$binary")))
            if($workflowTool){
                $query=Invoke-DevelopmentCommand $workflowTool @('--version') -Capture -AllowFailure -TimeoutSeconds 30
                $inventory.Workflows.Path=$workflowTool
                $inventory.Workflows.Version=($query.Lines -join "`n").TrimEnd("`r","`n")
                if($query.Outcome -eq 'Success' -and (Test-DevelopmentWrkflwVersion $inventory.Workflows.Version $spec.Wrkflw.Version)){$inventory.Workflows.State='Ready'}
            }
        }
    }
    if($inventory.Editor.State -ne 'Excluded'){
        if($target.EditorMode -ceq 'Remote'){$inventory.Editor.State='RemoteRequired';$inventory.Editor.Detail='Use VS Code on a glibc/Windows desktop with WSL or Dev Containers; native extension support varies.'}
        elseif($target.Id -ceq 'windows'){
            $folder=if($Plan.Insiders){'Microsoft VS Code Insiders'}else{'Microsoft VS Code'};$binary=if($Plan.Insiders){'Code - Insiders.exe'}else{'Code.exe'}
            $editor=Find-DevelopmentApplication $binary @(([IO.Path]::Combine($env:LOCALAPPDATA,"Programs/$folder/$binary")),([IO.Path]::Combine($env:ProgramFiles,"$folder/$binary")))
            if($editor){$inventory.Editor.State='Ready';$inventory.Editor.Path=$editor;$inventory.Editor.Version=(Get-Item -LiteralPath $editor).VersionInfo.ProductVersion}
        }else{
            $editor=Find-DevelopmentApplication $(if($Plan.Insiders){'code-insiders'}else{'code'})
            if($editor){$inventory.Editor.State='Ready';$inventory.Editor.Path=$editor;$query=Invoke-DevelopmentCommand $editor @('--version','--no-sandbox') -Capture -AllowFailure;if($query.Outcome -ne 'Success'){$inventory.Editor.State='Missing'}else{$inventory.Editor.Version=$query.Lines|Select-Object -First 1}}
        }
        if($inventory.Editor.State -eq 'Ready'){
            $extensionDirectory=[IO.Path]::Combine($HOME,$(if($Plan.Insiders){'.vscode-insiders/extensions/extensions.json'}else{'.vscode/extensions/extensions.json'}))
            $installed=@()
            if(Test-Path -LiteralPath $extensionDirectory){try{$installed=@(Get-Content -LiteralPath $extensionDirectory -Raw -Encoding utf8|ConvertFrom-Json|ForEach-Object {$_.identifier.id})}catch{}}
            $missingExtensions=@($Plan.Extensions|Where-Object {$installed -inotcontains $_})
            if($missingExtensions.Count){$inventory.Editor.Detail='Missing extensions: '+($missingExtensions -join ', ')}
        }
    }
    if($inventory.Native.State -ne 'Excluded'){
        $zig=Find-DevelopmentApplication zig @(([IO.Path]::Combine($root,$(if($target.Id -ceq 'windows'){'zig/zig.exe'}else{'zig/zig'}))))
        if($zig){$query=Invoke-DevelopmentCommand $zig @('version') -Capture -AllowFailure;$inventory.Native.Path=$zig;$inventory.Native.Version=($query.Lines -join '').Trim();if($query.Outcome -eq 'Success' -and $inventory.Native.Version -ceq $spec.ZigVersion -and ($target.Id -ceq 'windows' -or ((Find-DevelopmentApplication gcc) -and (Find-DevelopmentApplication clang)))){$inventory.Native.State='Ready'}}
    }
    if($inventory.Profilers.State -ne 'Excluded'){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking
        $valid=$true
        foreach($package in Get-RunProfilerPackages){
            $directory=[IO.Path]::Combine($root,('profilers/'+$package.Name))
            $archive=[IO.Path]::Combine($directory,($package.Name+'.'+$package.Version+'.nupkg'))
            if(!(Test-Path -LiteralPath $archive) -or !(Test-Path -LiteralPath ([IO.Path]::Combine($directory,$package.Entrypoint)))){$valid=$false;continue}
            if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $package.SHA256){$valid=$false}
        }
        if($valid){$inventory.Profilers.State='Ready';$inventory.Profilers.Path=[IO.Path]::Combine($root,'profilers');$inventory.Profilers.Version='Profiler 4.3.0; dotnet-trace 10.0.750501'}
    }
    if($inventory.Containers.State -ne 'Excluded'){
        $podman=Find-DevelopmentApplication podman @($(if($target.Id -ceq 'windows'){[IO.Path]::Combine($env:LOCALAPPDATA,'Programs/Podman/podman.exe')}),$(if($target.Id -ceq 'windows'){[IO.Path]::Combine($env:ProgramFiles,'RedHat/Podman/podman.exe')}))
        if($podman){
            $inventory.Containers.Path=$podman
            $connection=if($Plan.PSObject.Properties['PodmanConnection']){$Plan.PodmanConnection}else{$Plan.PodmanMachineName}
            $arguments=$(if($connection){@('--connection',$connection)}else{@()})+@('info','--format','json')
            $query=Invoke-DevelopmentCommand $podman $arguments -Capture -AllowFailure -TimeoutSeconds 30
            if($query.Outcome -eq 'Success'){$info=($query.Lines -join "`n")|ConvertFrom-Json;$inventory.Containers.State='Ready';$inventory.Containers.Version=$info.version.Version}else{$inventory.Containers.Detail=$query.Diagnostics -join ' | '}
        }
    }
    $inventory
}

function New-DevelopmentPlan {
    <#
    .SYNOPSIS
    Creates a deterministic installation selection without probing or changing the host.
    .PARAMETER Target
    Validated host.
    .PARAMETER WorkspaceRoot
    Repository source root.
    .PARAMETER InstallRoot
    Isolated user toolchain directory.
    .PARAMETER Specification
    Reviewed artifact identities.
    .PARAMETER Insiders
    Selects VS Code Insiders instead of Stable.
    .PARAMETER Skipped
    Explicitly excluded optional components.
    .PARAMETER PodmanMachineName
    Optional existing or new Windows machine name.
    .PARAMETER Extensions
    Identifiers read from the saved editor inventory, alongside the minimum workstation set.
    .PARAMETER ExtensionManifest
    Saved identifiers, observed versions and prerelease preferences used by editor setup.
    #>
    param($Target,[string]$WorkspaceRoot,[string]$InstallRoot,$Specification,[bool]$Insiders=$false,[string[]]$Skipped=@(),[string]$PodmanMachineName,[string[]]$Extensions=@(),[string]$ExtensionManifest)
    if(!$InstallRoot -or ![IO.Path]::IsPathFullyQualified($InstallRoot)){throw 'WorkstationInstallRootMustBeAbsolute'}
    if($PodmanMachineName -and $PodmanMachineName -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$'){throw 'WorkstationMachineNameInvalid'}
    foreach($skip in $Skipped){if($skip -cnotin @('Editor','Containers','Native','Profilers','Workflows')){throw 'WorkstationSkipInvalid'}}
    $required=@('ms-vscode.PowerShell','ms-dotnettools.csharp','ms-vscode-remote.remote-containers')+$(if($Target.Id -ceq 'windows'){@('ms-vscode-remote.remote-wsl')}else{@()})
    [pscustomobject]@{Target=$Target;WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot);InstallRoot=[IO.Path]::GetFullPath($InstallRoot);Specification=$Specification;Insiders=$Insiders;Skipped=@($Skipped);PodmanMachineName=$PodmanMachineName;Extensions=@(($required+$Extensions)|Sort-Object -Unique);ExtensionManifest=$ExtensionManifest}
}

function Get-DevelopmentActions {
    <#
    .SYNOPSIS
    Selects missing components; compatible installations never request replacement.
    .PARAMETER Inventory
    Independently observed component states.
    #>
    param($Inventory)
    foreach($name in $Inventory.Keys){
        if($Inventory[$name].State -notin @('Ready','Excluded','RemoteRequired')){$name}
        elseif($name -ceq 'Editor' -and $Inventory[$name].State -eq 'Ready' -and $Inventory[$name].Detail -like 'Missing extensions:*'){'Extensions'}
    }
}

function Get-DevelopmentArchive {
    <#
    .SYNOPSIS
    Downloads or verifies one checksum-locked archive before it can be extracted or executed.
    .PARAMETER Url
    Official HTTPS artifact URL.
    .PARAMETER Digest
    Expected SHA-256 or SHA-512.
    .PARAMETER Destination
    Dedicated cache filename.
    .PARAMETER Algorithm
    Hash algorithm.
    #>
    param([string]$Url,[string]$Digest,[string]$Destination,[ValidateSet('SHA256','SHA512')][string]$Algorithm='SHA256')
    $length=if($Algorithm -ceq 'SHA512'){128}else{64}
    if($Digest -cnotmatch ('^[a-fA-F0-9]{'+$length+'}$') -or $Url -cnotmatch '^https://(builds\.dotnet\.microsoft\.com/dotnet/|ziglang\.org/download/|github\.com/git-for-windows/git/releases/download/|github\.com/bahdotsh/wrkflw/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/wrkflw-[a-z0-9_-]+\.(zip|tar\.gz)\z|codeload\.github\.com/git/git/tar\.gz/refs/tags/|releases\.hashicorp\.com/vagrant/)'){throw 'WorkstationArtifactIdentityInvalid'}
    if(!(Test-Path -LiteralPath $Destination)){
        [void][IO.Directory]::CreateDirectory((Split-Path $Destination -Parent))
        $partial=$Destination+'.partial-'+[guid]::NewGuid().ToString('N')
        try{Invoke-WebRequest -Uri $Url -OutFile $partial -TimeoutSec 600;if((Get-FileHash -LiteralPath $partial -Algorithm $Algorithm).Hash -ine $Digest){throw 'WorkstationDownloadDigestMismatch'};Move-Item -LiteralPath $partial -Destination $Destination}
        finally{if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}}
    }
    if((Get-FileHash -LiteralPath $Destination -Algorithm $Algorithm).Hash -ine $Digest){throw 'WorkstationCacheDigestMismatch'}
    $Destination
}

function Install-DevelopmentPackages {
    <#
    .SYNOPSIS
    Installs explicitly selected packages, elevating individual Linux commands through cached sudo.
    .PARAMETER Target
    Validated Linux host.
    .PARAMETER Packages
    Fixed package names from the selected distribution recipe.
    #>
    param($Target,[string[]]$Packages)
    $prefix=@();$tool=$Target.Manager
    if([Environment]::UserName -cne 'root'){
        if(!(Find-DevelopmentApplication sudo)){throw 'WorkstationNeedsRootOrSudo: install system packages as root, or install sudo first.'}
        $prefix=@('-n',$tool);$tool='sudo'
    }
    if($Target.Manager -ceq 'apt-get'){$null=Invoke-DevelopmentCommand $tool ($prefix+@('update'))}
    $arguments=switch($Target.Manager){'apt-get'{@('install','-y','--no-install-recommends')};'dnf'{@('install','-y','--setopt=install_weak_deps=False')};'apk'{@('add','--no-cache')}}
    $null=Invoke-DevelopmentCommand $tool ($prefix+$arguments+@($Packages|Select-Object -Unique))
}

function Expand-DevelopmentArchive {
    <#
    .SYNOPSIS
    Extracts a verified official archive into an owned tool directory.
    .PARAMETER Archive
    Verified ZIP or tar archive.
    .PARAMETER Destination
    Isolated destination.
    .PARAMETER StripComponents
    Removes an official tarball's enclosing directory.
    #>
    param([string]$Archive,[string]$Destination,[int]$StripComponents=0)
    [void][IO.Directory]::CreateDirectory($Destination)
    if($Archive.EndsWith('.zip')){[void][IO.Compression.ZipFile]::ExtractToDirectoryAsync($Archive,$Destination,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()}
    else{$null=Invoke-DevelopmentCommand tar (@('-xf',$Archive,'-C',$Destination)+$(if($StripComponents){@("--strip-components=$StripComponents")}else{@()}))}
}

function Install-DevelopmentSdk {
    <#
    .SYNOPSIS
    Installs the exact SDK from global.json without changing a system dotnet installation.
    .PARAMETER Plan
    Validated plan and checksum-pinned SDK artifact.
    #>
    param($Plan)
    $spec=$Plan.Specification;$suffix=if($Plan.Target.Id -ceq 'windows'){'zip'}else{'tar.gz'}
    $archive=Get-DevelopmentArchive $spec.SdkUrl $spec.SdkHash ([IO.Path]::Combine($Plan.InstallRoot,"downloads/sdk-$($spec.SdkVersion)-$($Plan.Target.Rid).$suffix")) SHA512
    Expand-DevelopmentArchive $archive ([IO.Path]::Combine($Plan.InstallRoot,'dotnet'))
    if($spec.PowerShellFramework){
        # Alpine's distribution PowerShell is framework-dependent. Selecting an SDK-only DOTNET_ROOT
        # would otherwise hide its existing .NET 10 runtime when starting the next pwsh process.
        $framework=$spec.PowerShellFramework
        $destination=[IO.Path]::Combine($Plan.InstallRoot,('dotnet/shared/'+$framework.Name+'/'+$framework.Version))
        [void][IO.Directory]::CreateDirectory($destination)
        Get-ChildItem -LiteralPath $framework.Directory -Force|Copy-Item -Destination $destination -Recurse -Force
    }
}

function Install-DevelopmentGit {
    <#
    .SYNOPSIS
    Prepares a compatible Git beside the system installation when its version is outside the companion range.
    .PARAMETER Plan
    Validated source lock and host recipe.
    #>
    param($Plan)
    $spec=$Plan.Specification;$root=$Plan.InstallRoot
    if($Plan.Target.Id -ceq 'windows'){
        $archive=Get-DevelopmentArchive $spec.WindowsGit.Url $spec.WindowsGit.SHA256 ([IO.Path]::Combine($root,"downloads/git-$($spec.GitVersion)-$($Plan.Target.Architecture).zip"))
        Expand-DevelopmentArchive $archive ([IO.Path]::Combine($root,'git'))
        return
    }
    Install-DevelopmentPackages $Plan.Target @(Get-DevelopmentPackages $Plan.Target Native)
    $archive=Get-DevelopmentArchive $spec.GitSource.URL $spec.GitSource.SHA256 ([IO.Path]::Combine($root,"downloads/git-$($spec.GitVersion).tar.gz"))
    $source=[IO.Path]::Combine($root,('sources/git-'+$spec.GitVersion))
    Expand-DevelopmentArchive $archive $source 1
    $null=Invoke-DevelopmentCommand make @('-C',$source,'-j2',('prefix='+([IO.Path]::Combine($root,'git'))),'NO_RUST=YesPlease','NO_TCLTK=YesPlease','NO_GETTEXT=YesPlease','NO_INSTALL_HARDLINKS=YesPlease','NO_REGEX=NeedsStartEnd','CFLAGS=-std=gnu11 -O2','all','install') -TimeoutSeconds 3600
}

function Install-DevelopmentNativeTools {
    <#
    .SYNOPSIS
    Installs the pinned portable Zig compiler; Linux GCC/Clang packages belong to the system recipe.
    .PARAMETER Plan
    Selected compiler and archive digest.
    #>
    param($Plan)
    $tool=$Plan.Specification.Zig
    $archive=Get-DevelopmentArchive $tool.Url $tool.SHA256 ([IO.Path]::Combine($Plan.InstallRoot,('downloads/'+[IO.Path]::GetFileName(([uri]$tool.Url).AbsolutePath))))
    $destination=[IO.Path]::Combine($Plan.InstallRoot,'zig')
    if($Plan.Target.Id -ceq 'windows'){
        $staging=[IO.Path]::Combine($Plan.InstallRoot,('extract/zig-'+[guid]::NewGuid().ToString('N')))
        Expand-DevelopmentArchive $archive $staging
        $directories=@(Get-ChildItem -LiteralPath $staging -Directory)
        if($directories.Count -ne 1 -or !(Test-Path -LiteralPath ([IO.Path]::Combine($directories[0].FullName,'zig.exe')))){throw 'WorkstationZigArchiveLayoutInvalid'}
        [void][IO.Directory]::CreateDirectory($destination)
        Get-ChildItem -LiteralPath $directories[0].FullName -Force|Copy-Item -Destination $destination -Recurse -Force
    }else{Expand-DevelopmentArchive $archive $destination 1}
}

function Install-DevelopmentWrkflw {
    <#
    .SYNOPSIS
    Installs the verified native wrkflw archive beside existing system tools, without Cargo.
    .PARAMETER Plan
    Reviewed release artifact and isolated installation root.
    #>
    param($Plan)
    $tool=$Plan.Specification.Wrkflw.Artifact
    if(!$tool){throw "WorkstationWrkflwArtifactUnavailable: $($Plan.Target.Rid)"}
    $fileName='wrkflw-'+$Plan.Specification.Wrkflw.Version+'-'+[IO.Path]::GetFileName(([uri]$tool.Url).AbsolutePath)
    $archive=Get-DevelopmentArchive $tool.Url $tool.SHA256 ([IO.Path]::Combine($Plan.InstallRoot,('downloads/'+$fileName)))
    Expand-DevelopmentArchive $archive ([IO.Path]::Combine($Plan.InstallRoot,'wrkflw'))
}

function Install-DevelopmentEditor {
    <#
    .SYNOPSIS
    Installs the selected official VS Code package without replacing the other channel.
    .PARAMETER Plan
    Host and Stable/Insiders selection.
    #>
    param($Plan)
    $channel=if($Plan.Insiders){'insider'}else{'stable'}
    if($Plan.Target.Id -ceq 'windows'){
        $id=if($Plan.Insiders){'Microsoft.VisualStudioCode.Insiders'}else{'Microsoft.VisualStudioCode'}
        $null=Invoke-DevelopmentCommand winget @('install','--exact','--id',$id,'--source','winget','--scope','user','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity');return
    }
    $kind=if($Plan.Target.Manager -ceq 'dnf'){'rpm'}else{'deb'}
    $architecture=if($kind -ceq 'deb' -and $Plan.Target.Architecture -ceq 'x64'){'x64'}else{$Plan.Target.Architecture}
    $file=[IO.Path]::Combine($Plan.InstallRoot,"downloads/vscode-$channel-$architecture.$kind")
    [void][IO.Directory]::CreateDirectory((Split-Path $file -Parent))
    # VS Code publishes a moving channel URL. Distro package resolution verifies dependencies;
    # unlike SDK/Git/Zig, this latest editor channel is deliberately not a reproducible toolchain pin.
    Invoke-WebRequest -Uri "https://update.code.visualstudio.com/latest/linux-$kind-$architecture/$channel" -OutFile $file -TimeoutSec 300
    Install-DevelopmentPackages $Plan.Target @($file)
}

function Install-DevelopmentExtensions {
    <#
    .SYNOPSIS
    Installs and updates the saved extension inventory through the shared standalone synchronizer.
    .PARAMETER Plan
    Editor channel and extension IDs.
    .PARAMETER EditorPath
    Resolved native editor executable or Linux CLI.
    #>
    param($Plan,[string]$EditorPath)
    $null=& ([IO.Path]::Combine($Plan.WorkspaceRoot,'scripts/Sync-DevelopmentEditorExtensions.ps1')) -Insiders:$Plan.Insiders -EditorPath $EditorPath -Path $Plan.ExtensionManifest -AdditionalExtension $Plan.Extensions -Update
}

function Select-DevelopmentPodmanMachine {
    <#
    .SYNOPSIS
    Selects an explicit, default or unique machine; ambiguous configurations require an explicit name.
    .PARAMETER Machines
    Read-only podman machine list records.
    .PARAMETER Name
    User-selected machine name.
    #>
    param([AllowEmptyCollection()][object[]]$Machines=@(),[string]$Name)
    if($Name){return $Name}
    if(!$Machines.Count){return 'quietcli2-development'}
    $defaults=@($Machines|Where-Object Default)
    if($defaults.Count -eq 1){return $defaults[0].Name}
    if($Machines.Count -eq 1){return $Machines[0].Name}
    throw 'WorkstationPodmanMachineAmbiguous: supply -PodmanMachineName; existing connections are preserved.'
}

function Initialize-DevelopmentPodman {
    <#
    .SYNOPSIS
    Installs Podman and prepares Windows WSL/machine prerequisites without resetting existing resources.
    .PARAMETER Plan
    Host and optional explicit machine selection.
    #>
    param($Plan)
    if($Plan.Target.Id -cne 'windows'){return $false}
    if([Environment]::OSVersion.Version.Build -lt 22000){throw 'WorkstationPodmanRequiresWindows11'}
    $podman=Find-DevelopmentApplication podman @(([IO.Path]::Combine($env:LOCALAPPDATA,'Programs/Podman/podman.exe')),([IO.Path]::Combine($env:ProgramFiles,'RedHat/Podman/podman.exe')))
    if(!$podman){$null=Invoke-DevelopmentCommand winget @('install','--exact','--id','RedHat.Podman','--source','winget','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity');$podman=Find-DevelopmentApplication podman @(([IO.Path]::Combine($env:ProgramFiles,'RedHat/Podman/podman.exe')),([IO.Path]::Combine($env:LOCALAPPDATA,'Programs/Podman/podman.exe')))}
    if(!$podman){throw 'WorkstationPodmanExecutableMissing: reopen PowerShell and rerun.'}
    $wsl=Find-DevelopmentApplication wsl.exe
    $status=if($wsl){Invoke-DevelopmentCommand $wsl @('--status') -Capture -AllowFailure}else{$null}
    if(!$status -or $status.Outcome -ne 'Success'){
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
        if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'WorkstationWslNeedsAdministrator: rerun the installer in an elevated PowerShell session for the same user.'}
        $result=Invoke-DevelopmentCommand wsl.exe @('--install','--no-distribution','--no-launch') -AllowFailure
        if($result.ExitCode -notin @(0,3010)){throw 'WorkstationWslInstallationFailed'}
        return $true
    }
    $query=Invoke-DevelopmentCommand $podman @('machine','list','--format','json') -Capture
    $machines=@(($query.Lines -join "`n")|ConvertFrom-Json|ForEach-Object {$_})
    $name=Select-DevelopmentPodmanMachine $machines $Plan.PodmanMachineName
    $machine=@($machines|Where-Object Name -CEQ $name)
    if(!$machine.Count){$null=Invoke-DevelopmentCommand $podman @('machine','init','--memory','6144',$name)}
    $inspection=Invoke-DevelopmentCommand $podman @('machine','inspect',$name,'--format','json') -Capture
    $state=@(($inspection.Lines -join "`n")|ConvertFrom-Json)[0]
    if($state.State -cne 'running'){$null=Invoke-DevelopmentCommand $podman @('machine','start',$name,'--update-connection=false')}
    $connection=Invoke-DevelopmentCommand $podman @('system','connection','list','--format','json') -Capture
    $connections=@(($connection.Lines -join "`n")|ConvertFrom-Json|ForEach-Object {$_})
    $selected=@($connections|Where-Object Name -CEQ $name)
    if($selected.Count -ne 1){throw "WorkstationPodmanConnectionMissing: $name"}
    $null=Invoke-DevelopmentCommand $podman @('--connection',$name,'info','--format','json') -Capture
    # Explicit connection selection is saved only in the generated activation script.
    $Plan|Add-Member -NotePropertyName PodmanConnection -NotePropertyValue $name -Force
    return $false
}

function Write-DevelopmentActivation {
    <#
    .SYNOPSIS
    Writes an explicit activation script without modifying a PowerShell or shell profile.
    .PARAMETER Plan
    Owned installation root and component selection.
    .PARAMETER Inventory
    Verified application paths.
    #>
    param($Plan,$Inventory)
    $quote={param($s) "'"+$s.Replace("'","''")+"'"}
    $paths=[Collections.Generic.List[string]]::new()
    foreach($component in @('Sdk','Git','Native','Editor','Workflows')){
        if($Inventory[$component].Path){
            $directory=Split-Path $Inventory[$component].Path -Parent
            if($component -ceq 'Editor' -and $Plan.Target.Id -ceq 'windows'){$directory=[IO.Path]::Combine($directory,'bin')}
            [void]$paths.Add($directory)
        }
    }
    $lines=[Collections.Generic.List[string]]::new();[void]$lines.Add('# Activate the verified QuietCli development tools in this PowerShell session.')
    if($Inventory.Sdk.State -eq 'Ready'){
        [void]$lines.Add('$env:DOTNET_ROOT = '+(& $quote (Split-Path $Inventory.Sdk.Path -Parent)))
        [void]$lines.Add('$env:DOTNET_ROOT_'+$Plan.Target.Architecture.ToUpperInvariant()+' = $env:DOTNET_ROOT')
    }
    $uniquePaths=@($paths|Select-Object -Unique);[array]::Reverse($uniquePaths)
    foreach($path in $uniquePaths){[void]$lines.Add('$env:PATH = '+(& $quote $path)+' + [IO.Path]::PathSeparator + (($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator) | Where-Object { $_ -ne '+(& $quote $path)+' }) -join [IO.Path]::PathSeparator)')}
    if($Plan.PSObject.Properties['PodmanConnection']){[void]$lines.Add('$env:CONTAINER_CONNECTION = '+(& $quote $Plan.PodmanConnection))}
    if($Inventory.Native.State -eq 'Ready'){[void]$lines.Add('$env:QUIETCLI_DEVELOPMENT_ZIG = '+(& $quote $Inventory.Native.Path))}
    $path=[IO.Path]::Combine($Plan.InstallRoot,'Activate-DevelopmentEnvironment.ps1')
    [void][IO.File]::WriteAllTextAsync($path,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $path
}

function Invoke-DevelopmentProvisioning {
    <#
    .SYNOPSIS
    Applies approved component actions, verifies results and returns a detached installation report.
    .PARAMETER Plan
    Selected host, artifacts and optional exclusions.
    .PARAMETER Inventory
    Initial read-only probes.
    .PARAMETER ShouldApply
    ShouldProcess callback; every mutation is reachable only through this gate.
    .PARAMETER CheckOnly
    Returns the initial report before any mutation or download.
    #>
    param($Plan,$Inventory,[scriptblock]$ShouldApply,[switch]$CheckOnly)
    $actions=@(Get-DevelopmentActions $Inventory)
    $report=[pscustomobject]@{Target=$Plan.Target;InstallRoot=$Plan.InstallRoot;State='NeedsInstallation';Components=@($Inventory.Values);Actions=$actions;RestartRequired=$false;ActivationScript=$null;Error=$null}
    if($CheckOnly -or !(& $ShouldApply $Plan.InstallRoot ('Prepare development workstation: '+($actions -join ', ')))){
        if(!$actions.Count){$report.State='Ready'}
        return $report
    }
    try{
        if($actions -contains 'Workflows' -and !$Plan.Specification.Wrkflw.Artifact){throw "WorkstationWrkflwArtifactUnavailable: $($Plan.Target.Rid). Use -SkipWorkflows."}
        [void][IO.Directory]::CreateDirectory($Plan.InstallRoot)
        if($Plan.Target.Id -cne 'windows' -and $actions -contains 'System'){
            $packages=@(Get-DevelopmentPackages $Plan.Target System)
            if($Plan.Skipped -notcontains 'Native'){$packages+=@(Get-DevelopmentPackages $Plan.Target Native)}
            if($Plan.Skipped -notcontains 'Containers'){$packages+=@(Get-DevelopmentPackages $Plan.Target Containers)}
            Install-DevelopmentPackages $Plan.Target $packages
        }
        if($actions -contains 'Sdk'){Install-DevelopmentSdk $Plan}
        # A system package operation may already have supplied a compatible Git.
        $current=Get-DevelopmentInventory $Plan
        if($current.Git.State -ne 'Ready'){Install-DevelopmentGit $Plan}
        if($actions -contains 'Native'){Install-DevelopmentNativeTools $Plan}
        if($actions -contains 'Workflows'){Install-DevelopmentWrkflw $Plan}
        if($actions -contains 'Editor'){Install-DevelopmentEditor $Plan}
        if($actions -contains 'Profilers'){$null=& ([IO.Path]::Combine($Plan.WorkspaceRoot,'scripts/Initialize-Profilers.ps1')) -OutputDirectory ([IO.Path]::Combine($Plan.InstallRoot,'profilers'))}
        if($Plan.Skipped -notcontains 'Containers' -and ($actions -contains 'Containers' -or $Plan.PodmanMachineName)){$report.RestartRequired=Initialize-DevelopmentPodman $Plan}
        $current=Get-DevelopmentInventory $Plan
        if($current.Editor.State -eq 'Ready'){Install-DevelopmentExtensions $Plan $current.Editor.Path}
        $report.ActivationScript=Write-DevelopmentActivation $Plan $current
        $report.Components=@($current.Values);$report.Actions=@(Get-DevelopmentActions $current)
        if($report.RestartRequired){$report.State='RestartRequired'}elseif(!$report.Actions.Count){$report.State='Ready'}else{$report.State='Failed';$report.Error='WorkstationVerificationFailed: '+($report.Actions -join ', ')}
    }catch{$report.State='Failed';$report.Error=$_.Exception.Message}
    $report
}

Export-ModuleMember -Function Get-DevelopmentHost,Get-DevelopmentPackages,Test-DevelopmentGitVersion,Test-DevelopmentVagrantVersion,Get-DevelopmentSpecification,New-DevelopmentPlan,Get-DevelopmentInventory,Get-DevelopmentActions,Select-DevelopmentPodmanMachine,Invoke-DevelopmentProvisioning,Find-DevelopmentApplication,Invoke-DevelopmentCommand
