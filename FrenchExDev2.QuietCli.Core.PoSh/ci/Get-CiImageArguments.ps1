# Objectif : Definir les entrees verifiees et les stages de l'image CI de Core elle-meme.
<#
.SYNOPSIS
Resolves Core's own CI image build arguments and Containerfile stages for one Linux RID.
.DESCRIPTION
Core declares its own needs through the exact same Stages shape a Core-consumer module declares through
its own ci/Get-CiImageArguments.ps1 (see FrenchExDev2.QuietCli.Git.PoSh/ci/Get-CiImageArguments.ps1) --
including the explicit, visible decision to install a plain distro `git` package in its own final stage.
That decision belongs to Core alone: it exists only because Core's own test suite
(FrenchExDev2.QuietCli.Core.Tests.PoSh/Status.ControlledProbe.ps1) resolves `git` from PATH independent
of the Git module, never because the Git module needs it -- the Git module makes its own independent
decision in its own declaration, and Core never reads it to make this one. Invoked directly as a script
by scripts/CiImages.ps1's Get-QuietCiImagePlan, at this exact relative path: this file IS Core's own
declared contract, symmetric with every module's.
.PARAMETER WorkspaceRoot
Monorepo containing the reviewed image and upstream source locks.
.PARAMETER RuntimeIdentifier
Exact guest architecture and libc to test.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier)
$ErrorActionPreference='Stop'
$lock=Get-Content (Join-Path $WorkspaceRoot 'build/ci-images.lock.json') -Encoding utf8 -Raw|ConvertFrom-Json
$sdk=(Get-Content (Join-Path $WorkspaceRoot global.json) -Encoding utf8 -Raw|ConvertFrom-Json).sdk.version
if($lock.SchemaVersion -ne 2 -or $lock.SDK -cne $sdk){throw 'CiImageSdkLockMismatch'}
$entries=@($lock.Platforms|Where-Object Rid -CEQ $RuntimeIdentifier)
if($entries.Count -ne 1){throw 'CiImageTargetNotUnique'}
$target=$entries[0]
$architecture=if($RuntimeIdentifier.EndsWith('arm64')){'arm64'}else{'x64'}
$platform=if($RuntimeIdentifier.StartsWith('linux-musl-')){'alpine'}else{'debian'}
if($target.Architecture -cne $architecture -or $target.Platform -cne $platform){throw 'CiImageTargetMismatch'}
if($target.Base -cnotmatch '^docker\.io/library/(alpine|debian):[a-z0-9.-]+@sha256:[a-f0-9]{64}$' -or $target.SDK_SHA512 -cnotmatch '^[a-f0-9]{128}$'){throw 'CiImageDigestInvalid'}
$arguments=[ordered]@{
    SDK_URL="https://builds.dotnet.microsoft.com/dotnet/Sdk/$sdk/dotnet-sdk-$sdk-$RuntimeIdentifier.tar.gz"
    SDK_SHA512=$target.SDK_SHA512
}
$toolsArgs=@('SDK_URL','SDK_SHA512')
if($platform -ceq 'debian'){
    if($target.PowerShell -cnotmatch '^7\.[6-9]\.\d+$' -or $target.PowerShell_SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'CiImagePowerShellLockInvalid'}
    $arguments.POWERSHELL_URL="https://github.com/PowerShell/PowerShell/releases/download/v$($target.PowerShell)/powershell-$($target.PowerShell)-linux-$architecture.tar.gz"
    $arguments.POWERSHELL_SHA256=$target.PowerShell_SHA256
    $toolsArgs+=@('POWERSHELL_URL','POWERSHELL_SHA256')
}else{
    if($lock.AlpinePowerShellPackage -cnotmatch '\A7\.[6-9]\.\d+-r\d+\z'){throw 'CiImagePowerShellLockInvalid'}
    $arguments.POWERSHELL_PACKAGE=$lock.AlpinePowerShellPackage
    if($lock.AlpineRuntime -cnotmatch '\A10\.0\.\d+\z' -or $target.Runtime_SHA512 -cnotmatch '\A[a-f0-9]{128}\z'){throw 'CiImageRuntimeLockInvalid'}
    $arguments.RUNTIME_URL="https://builds.dotnet.microsoft.com/dotnet/Runtime/$($lock.AlpineRuntime)/dotnet-runtime-$($lock.AlpineRuntime)-$RuntimeIdentifier.tar.gz"
    $arguments.RUNTIME_SHA512=$target.Runtime_SHA512
    $toolsArgs+=@('RUNTIME_URL','RUNTIME_SHA512')
    # The distro PowerShell package does not provide the Gallery packaging cmdlets.
    # Reuse the already pinned Microsoft archive for managed PSResourceGet only.
    $donors=@($lock.Platforms|Where-Object Rid -CEQ ('linux-'+$architecture))
    if($donors.Count -ne 1 -or $donors[0].PowerShell -cnotmatch '\A7\.[6-9]\.\d+\z' -or $donors[0].PowerShell_SHA256 -cnotmatch '\A[a-f0-9]{64}\z'){throw 'CiImagePSResourceGetDonorInvalid'}
    $donor=$donors[0]
    $arguments.POWERSHELL_URL="https://github.com/PowerShell/PowerShell/releases/download/v$($donor.PowerShell)/powershell-$($donor.PowerShell)-linux-$architecture.tar.gz"
    $arguments.POWERSHELL_SHA256=$donor.PowerShell_SHA256
    $toolsArgs+=@('POWERSHELL_URL','POWERSHELL_SHA256')
}
# gcc/clang/etc. only serve a separate, local-only native mutation/ASan/UBSan campaign (docs/ci/linux-images.md);
# the ordinary CI matrix never uses them, so they are excluded by default and only added when that campaign
# explicitly opts in, by setting MUTATION_TESTING in the environment that resolves this plan.
$mutationTesting=[bool]$env:MUTATION_TESTING
$ciPackages=if($platform -ceq 'debian'){'ca-certificates libicu72 libunwind8 libatomic1 libssl3 zlib1g libsqlite3-0 git tzdata tar zstd'}else{'ca-certificates icu-data-full icu-libs libatomic libstdc++ libgcc libssl3 sqlite-libs git tzdata tar zstd'}
if($platform -ceq 'alpine'){$ciPackages+=' powershell=$POWERSHELL_PACKAGE'}
if($mutationTesting){$ciPackages+=if($platform -ceq 'debian'){' gcc libc6-dev g++ clang libclang-rt-dev'}else{' gcc musl-dev g++ clang compiler-rt'}}
$envMap=if($platform -ceq 'debian'){
    [ordered]@{DOTNET_ROOT='/usr/share/dotnet';PATH='/usr/share/dotnet:/usr/local/bin:/usr/bin:/bin';LANG='C.UTF-8';DOTNET_CLI_TELEMETRY_OPTOUT='1';POWERSHELL_TELEMETRY_OPTOUT='1';DOTNET_NOLOGO='1'}
}else{
    # Microsoft builds report the portable musl RID; the distro runtime reports an Alpine-version RID.
    [ordered]@{DOTNET_ROOT='/opt/pwsh-runtime';PATH='/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';LANG='C.UTF-8';DOTNET_SYSTEM_GLOBALIZATION_INVARIANT='false';DOTNET_CLI_TELEMETRY_OPTOUT='1';POWERSHELL_TELEMETRY_OPTOUT='1';DOTNET_NOLOGO='1'}
}
$ciStage=[pscustomobject]@{Name='ci';From=$target.Base;Args=$null;Packages=$ciPackages;Copy=@([pscustomobject]@{Stage='tools';Spec='/opt/dotnet /usr/share/dotnet'});Run=$null;Env=$envMap;PathPrefix=$null;WorkDir='/workspace';Entrypoint=@('pwsh')}
if($platform -ceq 'debian'){
    $ciStage.Copy+=[pscustomobject]@{Stage='tools';Spec='/opt/powershell /opt/powershell'}
    $ciStage.Run=@('ln -s /opt/powershell/pwsh /usr/local/bin/pwsh')
}else{
    $ciStage.Args=@('POWERSHELL_PACKAGE='+$lock.AlpinePowerShellPackage)
    $ciStage.Copy+=[pscustomobject]@{Stage='tools';Spec='/opt/pwsh-runtime /opt/pwsh-runtime'}
    $ciStage.Copy+=[pscustomobject]@{Stage='tools';Spec='/opt/powershell/Modules/Microsoft.PowerShell.PSResourceGet /usr/local/share/powershell/Modules/Microsoft.PowerShell.PSResourceGet'}
    $ciStage.Run=@('pwsh -NoProfile -Command "Get-Command Compress-PSResource -ErrorAction Stop | Out-Null"')
}
$containerfile=[pscustomobject]@{
    Platform=$platform
    Objective="Construire nativement le banc $platform ; seuls les outils livres passent dans l'etape finale."
    Stages=@(
        [pscustomobject]@{Name='tools';From=$target.Base;Args=$toolsArgs;Packages='ca-certificates curl';FetchScript='fetch-ci-tools.sh'}
        $ciStage
    )
}
$paths=@('build/ci-images.lock.json','global.json','scripts/CiImages.ps1','scripts/New-CiImage.ps1')
$paths+=@(Get-ChildItem (Join-Path $WorkspaceRoot '.github/containers') -File -Force|ForEach-Object {'.github/containers/'+$_.Name})
[pscustomobject]@{Arguments=$arguments;InputPaths=$paths;Containerfile=$containerfile;Base=$target.Base;Architecture=$architecture;Platform=$platform}
