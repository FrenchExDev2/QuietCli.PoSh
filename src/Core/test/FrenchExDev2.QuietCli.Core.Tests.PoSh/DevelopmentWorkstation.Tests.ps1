function Test-QuietDevelopmentWorkstation {
    <#
    .SYNOPSIS
    Exercises independent host/version properties, hostile inputs and targeted installer policy mutations.
    .PARAMETER WorkspaceRoot
    Repository containing the independently loaded provisioning module.
    .PARAMETER RunDirectory
    Owned test output directory; no installation touches the developer's host.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $path=Join-Path $WorkspaceRoot 'scripts/lib/DevelopmentWorkstation.psm1'
    $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    # Isolated test modules never load a native executor. Every reachable side effect is trapped.
    $source=$source.Replace("Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop",'# Process boundary replaced by independent test fixtures.')
    $counts=@{Examples=0;Properties=0;FuzzInputs=0;MutantsKilled=0;Seed=914227}
    $verify={
        param($candidate,$output,$counts)
        $module=New-Module -Name ('WorkstationFixture'+[guid]::NewGuid().ToString('N')) -ScriptBlock ([scriptblock]::Create($candidate))
        try{
            & $module {
                param($output,$counts)
                $random=[Random]::new($counts.Seed)
                foreach($banner in @('Vagrant 2.3.0','Vagrant 2.4.9')){if(!(Test-DevelopmentVagrantVersion $banner)){throw 'Compatible Vagrant rejected'}}
                foreach($banner in @('Vagrant 2.2.99','Vagrant 2.5.0','Vagrant 3.0.0','Vagrant 2.4.9-rc1')){if(Test-DevelopmentVagrantVersion $banner){throw 'Unsupported Vagrant accepted'}}
                $versions=@{debian=@('12','13');ubuntu=@('24.04','26.04');alpine=@('3.23','3.24');fedora=@('43','44')}
                foreach($id in $versions.Keys){foreach($version in $versions[$id]){foreach($architecture in @('x64','arm64')){
                    $target=Get-DevelopmentHost Linux $architecture "ID=`"$id`"`nVERSION_ID='$version'`n"
                    $expected=if($id -ceq 'alpine'){"linux-musl-$architecture"}else{"linux-$architecture"}
                    if($target.Rid -cne $expected){throw 'Wrong native architecture/libc'}
                    if(($target.EditorMode -ceq 'Remote') -ne ($id -ceq 'alpine')){throw 'Wrong Alpine editor boundary'}
                    $counts.Examples++
                }}}
                foreach($bad in @('ID=debian','ID=debian' + "`nVERSION_ID=12`nID=ubuntu",'ID=unknown' + "`nVERSION_ID=12",'ID=ubuntu' + "`nVERSION_ID=22.04",'ID=alpine' + "`nVERSION_ID=3.24`0")){
                    $rejected=$false;try{$null=Get-DevelopmentHost Linux x64 $bad}catch{$rejected=$true};if(!$rejected){throw 'Invalid host description accepted'};$counts.Examples++
                }
                foreach($arch in @('x86','ARM64','amd64','aarch64','../../x64')){
                    $rejected=$false;try{$null=Get-DevelopmentHost Windows $arch}catch{$rejected=$true};if(!$rejected){throw 'Unknown architecture accepted'}
                }
                for($i=0;$i -lt 400;$i++){
                    $minor=$random.Next(0,90);$patch=$random.Next(0,999);$banner="git version 2.$minor.$patch"
                    $expected=$minor -ge 40 -and $minor -le 56
                    foreach($text in @($banner,($banner+'.windows.3'))){if((Test-DevelopmentGitVersion $text) -ne $expected){throw 'Stable Git range property failed'};$counts.Properties++}
                    foreach($text in @(($banner+'-rc1'),($banner+'; touch injected'),($banner+"`ninvalid"))){if(Test-DevelopmentGitVersion $text){throw 'Malformed Git version accepted'};$counts.FuzzInputs++}
                }
                for($i=0;$i -lt 400;$i++){
                    $payload='$(throw "must not evaluate")'+[char]$random.Next(33,127)
                    $rejected=$false;try{$null=Get-DevelopmentHost Linux x64 ("ID=debian`nVERSION_ID=`""+$payload+'"')}catch{$rejected=$true}
                    if(!$rejected){throw 'Host payload accepted'};$counts.FuzzInputs++
                }
                $target=Get-DevelopmentHost Windows x64
                $workflowLock=[pscustomobject]@{
                    Version='0.8.0';Source='https://api.github.com/repos/bahdotsh/wrkflw/releases/tags/v0.8.0'
                    Artifacts=@(
                        [pscustomobject]@{Rid='win-x64';Url='https://github.com/bahdotsh/wrkflw/releases/download/v0.8.0/wrkflw-x86_64-pc-windows-msvc.zip';SHA256=('a'*64)}
                        [pscustomobject]@{Rid='linux-x64';Url='https://github.com/bahdotsh/wrkflw/releases/download/v0.8.0/wrkflw-x86_64-unknown-linux-gnu.tar.gz';SHA256=('b'*64)}
                        [pscustomobject]@{Rid='linux-arm64';Url='https://github.com/bahdotsh/wrkflw/releases/download/v0.8.0/wrkflw-aarch64-unknown-linux-gnu.tar.gz';SHA256=('c'*64)}
                        [pscustomobject]@{Rid='linux-musl-x64';Url='https://github.com/bahdotsh/wrkflw/releases/download/v0.8.0/wrkflw-x86_64-unknown-linux-musl.tar.gz';SHA256=('d'*64)}
                    )
                }
                foreach($rid in @('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
                    $selected=Get-DevelopmentWrkflwSpecification $workflowLock ([pscustomobject]@{Rid=$rid})
                    $supported=$rid -notin @('win-arm64','linux-musl-arm64')
                    if(($null -ne $selected.Artifact) -ne $supported -or ($supported -and $selected.Artifact.Rid -cne $rid)){throw 'Wrkflw native artifact selection failed'}
                    $counts.Properties++
                }
                foreach($change in @('version','source','host','duplicate','missing','url','digest','digest-newline')){
                    $bad=$workflowLock|ConvertTo-Json -Depth 5|ConvertFrom-Json
                    switch($change){
                        version {$bad.Version='0.8.0-dev'}
                        source {$bad.Source='https://example.invalid/wrkflw'}
                        host {$bad.Artifacts[0].Rid='win-arm64'}
                        duplicate {$bad.Artifacts+=,$bad.Artifacts[0]}
                        missing {$bad.Artifacts=@($bad.Artifacts|Select-Object -Skip 1)}
                        url {$bad.Artifacts[0].Url+='?unreviewed=true'}
                        digest {$bad.Artifacts[0].SHA256='bad-digest'}
                        digest-newline {$bad.Artifacts[0].SHA256+="`n"}
                    }
                    $rejected=$false;try{$null=Get-DevelopmentWrkflwSpecification $bad $target}catch{$rejected=$true}
                    if(!$rejected){throw "Malformed wrkflw lock accepted: $change"};$counts.FuzzInputs++
                }
                if(!(Test-DevelopmentWrkflwVersion 'wrkflw 0.8.0' '0.8.0')){throw 'Pinned wrkflw rejected'}
                for($index=0;$index -lt 200;$index++){
                    $text='wrkflw 0.'+$random.Next(0,30)+'.'+$random.Next(0,30)
                    $expected=$text -ceq 'wrkflw 0.8.0'
                    if((Test-DevelopmentWrkflwVersion $text '0.8.0') -ne $expected){throw 'Wrkflw exact version property failed'};$counts.Properties++
                    foreach($suffix in @('-dev',';echo injected',"`nextra",[string][char]0)){
                        if(Test-DevelopmentWrkflwVersion ('wrkflw 0.8.0'+$suffix) '0.8.0'){throw 'Malformed wrkflw banner accepted'};$counts.FuzzInputs++
                    }
                }
                $spec=[pscustomobject]@{SdkVersion='11.0.100-rc.3.26522.148';ZigVersion='0.15.2';PowerShellFramework=$null;Wrkflw=(Get-DevelopmentWrkflwSpecification $workflowLock $target)}
                $plan=New-DevelopmentPlan $target $output (Join-Path $output 'owned-install') $spec -Insiders $true -Skipped @('Editor','Native','Profilers','Containers','Workflows')
                if(!$plan.Insiders -or $plan.Extensions -notcontains 'ms-vscode-remote.remote-wsl'){throw 'Editor channel/Windows extension selection failed'}
                $alpine=Get-DevelopmentHost Linux arm64 "ID=alpine`nVERSION_ID=3.24"
                $alpinePlan=New-DevelopmentPlan $alpine $output (Join-Path $output 'owned-alpine') $spec
                if($alpinePlan.Extensions -contains 'ms-vscode-remote.remote-wsl'){throw 'Windows extension leaked into Linux'}
                $packages=@(Get-DevelopmentPackages $alpine Native)
                if($packages -notcontains 'compiler-rt' -or $packages -notcontains 'musl-dev' -and $packages -notcontains 'build-base'){throw 'Native sanitizer/header prerequisites missing'}
                $machines=@([pscustomobject]@{Name='keep';Default=$true},[pscustomobject]@{Name='other';Default=$false})
                if((Select-DevelopmentPodmanMachine $machines) -cne 'keep' -or (Select-DevelopmentPodmanMachine @()) -cne 'quietcli2-development'){throw 'Machine preservation/default failed'}
                if((Select-DevelopmentPodmanMachine $machines 'explicit') -cne 'explicit'){throw 'Explicit machine ignored'}
                $rejected=$false;try{$null=Select-DevelopmentPodmanMachine @([pscustomobject]@{Name='one';Default=$false},[pscustomobject]@{Name='two';Default=$false})}catch{$rejected=$true};if(!$rejected){throw 'Ambiguous machines accepted'}
                foreach($name in @('--default','a b','a;remove','../escape')){$rejected=$false;try{$null=New-DevelopmentPlan $target $output $plan.InstallRoot $spec -PodmanMachineName $name}catch{$rejected=$true};if(!$rejected){throw 'Invalid machine argument accepted'}}
                $counts.Examples+=12

                $script:ObservedSdk=$spec.SdkVersion;$script:ObservedRuntimes=@();$script:ObservedWrkflw=$null
                function script:Find-DevelopmentApplication {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Name,$Preferred) if($Name -in @('dotnet','git') -or ($Name -ceq 'wrkflw' -and $script:ObservedWrkflw)){return (Join-Path $output $Name)};return $null}
                function script:Invoke-DevelopmentCommand {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>

                    param($FilePath,$Arguments,$WorkingDirectory,[switch]$Capture,[switch]$AllowFailure,$TimeoutSeconds)
                    $text=if($Arguments[0] -ceq '--list-runtimes'){$script:ObservedRuntimes}elseif([IO.Path]::GetFileName($FilePath) -ceq 'git'){'git version 2.56.0.windows.3'}elseif([IO.Path]::GetFileName($FilePath) -ceq 'wrkflw'){$script:ObservedWrkflw}else{$script:ObservedSdk}
                    [pscustomobject]@{Outcome='Success';ExitCode=0;Lines=@($text|Where-Object {$null -ne $_});Diagnostics=@()}
                }
                $good=Get-DevelopmentInventory $plan
                if($good.Sdk.State -ne 'Ready' -or $good.Git.State -ne 'Ready'){throw 'Compatible installations not retained'}
                $workflowPlan=New-DevelopmentPlan $target $output (Join-Path $output "workflow tools ' Unicode-é") $spec -Skipped @('Editor','Native','Profilers','Containers')
                if((Get-DevelopmentInventory $workflowPlan).Workflows.State -cne 'Missing'){throw 'Missing wrkflw reported ready'}
                foreach($banner in @('wrkflw 0.8.1','wrkflw 0.8.0-dev','WRKFLW 0.8.0','wrkflw 0.8.0 extra')){
                    $script:ObservedWrkflw=$banner
                    if((Get-DevelopmentInventory $workflowPlan).Workflows.State -ceq 'Ready'){throw 'Unpinned wrkflw inventory accepted'};$counts.Examples++
                }
                $script:ObservedWrkflw='wrkflw 0.8.0'
                $workflowReady=Get-DevelopmentInventory $workflowPlan
                if($workflowReady.Workflows.State -cne 'Ready'){throw 'Pinned wrkflw inventory not ready'}
                $unsupportedPlan=New-DevelopmentPlan (Get-DevelopmentHost Windows arm64) $output (Join-Path $output 'unsupported-must-not-exist') ([pscustomobject]@{SdkVersion=$spec.SdkVersion;ZigVersion=$spec.ZigVersion;PowerShellFramework=$null;Wrkflw=(Get-DevelopmentWrkflwSpecification $workflowLock ([pscustomobject]@{Rid='win-arm64'}))}) -Skipped @('Editor','Native','Profilers','Containers')
                $unsupported=Get-DevelopmentInventory $unsupportedPlan
                if($unsupported.Workflows.State -cne 'Unsupported'){throw 'Unpublished wrkflw architecture reported ready'}
                $unsupportedReport=Invoke-DevelopmentProvisioning $unsupportedPlan $unsupported -ShouldApply {$true}
                if($unsupportedReport.State -cne 'Failed' -or $unsupportedReport.Error -notlike 'WorkstationWrkflwArtifactUnavailable:*' -or (Test-Path -LiteralPath $unsupportedPlan.InstallRoot)){throw 'Unsupported wrkflw was installed or performed preceding effects'}
                $unsupportedPlan.Skipped+=,'Workflows'
                if((Get-DevelopmentInventory $unsupportedPlan).Workflows.State -cne 'Excluded'){throw 'Wrkflw exclusion was not honored'}
                [void][IO.Directory]::CreateDirectory($workflowPlan.InstallRoot)
                $activationInventory=[ordered]@{Sdk=[pscustomobject]@{State='Excluded';Path=$null};Git=[pscustomobject]@{Path=$null};Native=[pscustomobject]@{State='Excluded';Path=$null};Editor=[pscustomobject]@{Path=$null};Workflows=[pscustomobject]@{Path=(Join-Path $workflowPlan.InstallRoot 'wrkflw/wrkflw.exe')}}
                $activation=Write-DevelopmentActivation $workflowPlan $activationInventory
                $savedPath=$env:PATH
                try{
                    . $activation
                    . $activation
                    $workflowDirectory=Join-Path $workflowPlan.InstallRoot 'wrkflw'
                    $activated=@($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator))
                    if($activated[0] -cne $workflowDirectory -or @($activated|Where-Object {$_ -ceq $workflowDirectory}).Count -ne 1){throw 'Wrkflw activation missing, escaped incorrectly or duplicated'}
                }finally{$env:PATH=$savedPath}
                $counts.Examples+=6
                $archivePath=Join-Path $output 'wrkflw-cache.zip'
                [void][IO.File]::WriteAllTextAsync($archivePath,'independent archive fixture',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $archiveHash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
                if((Get-DevelopmentArchive $workflowLock.Artifacts[0].Url $archiveHash $archivePath) -cne $archivePath){throw 'Verified wrkflw cache was not reused'}
                $rejected=$false;try{$null=Get-DevelopmentArchive $workflowLock.Artifacts[0].Url ('0'*64) $archivePath}catch{$rejected=$_.Exception.Message -ceq 'WorkstationCacheDigestMismatch'}
                if(!$rejected){throw 'Corrupt wrkflw cache accepted'}
                foreach($url in @('https://github.com.evil.invalid/bahdotsh/wrkflw/releases/download/v0.8.0/wrkflw-x86_64-pc-windows-msvc.zip',($workflowLock.Artifacts[0].Url+'?alternate'),($workflowLock.Artifacts[0].Url+"`n"))){
                    $rejected=$false;try{$null=Get-DevelopmentArchive $url $archiveHash $archivePath}catch{$rejected=$_.Exception.Message -ceq 'WorkstationArtifactIdentityInvalid'}
                    if(!$rejected){throw 'Unreviewed wrkflw archive URL accepted'};$counts.FuzzInputs++
                }
                $script:ArchiveRequest=$null;$script:ExtractionRequest=$null
                function script:Get-DevelopmentArchive {
                    <#
                    .SYNOPSIS
                    Records an artifact request without opening the network.
                    #>
                    param($Url,$Digest,$Destination,$Algorithm)
                    $script:ArchiveRequest=@($Url,$Digest,$Destination)
                    'verified-wrkflw-fixture.zip'
                }
                function script:Expand-DevelopmentArchive {
                    <#
                    .SYNOPSIS
                    Records extraction into the owned tool directory without starting a process.
                    #>
                    param($Archive,$Destination,$StripComponents)
                    $script:ExtractionRequest=@($Archive,$Destination)
                }
                Install-DevelopmentWrkflw $workflowPlan
                $expectedArtifact=$workflowLock.Artifacts[0]
                $expectedCache=Join-Path $workflowPlan.InstallRoot 'downloads/wrkflw-0.8.0-wrkflw-x86_64-pc-windows-msvc.zip'
                if($script:ArchiveRequest[0] -cne $expectedArtifact.Url -or $script:ArchiveRequest[1] -cne $expectedArtifact.SHA256 -or $script:ArchiveRequest[2] -cne $expectedCache -or
                    $script:ExtractionRequest[0] -cne 'verified-wrkflw-fixture.zip' -or $script:ExtractionRequest[1] -cne (Join-Path $workflowPlan.InstallRoot 'wrkflw')){throw 'Wrkflw installation lost artifact identity or isolation'}
                $counts.Examples+=3
                $extensionFixture=[ordered]@{Editor=[pscustomobject]@{State='Ready';Detail='Missing extensions: ms-vscode.PowerShell'}}
                if((@(Get-DevelopmentActions $extensionFixture) -join ',') -cne 'Extensions'){throw 'Missing editor extensions were reported ready'}
                foreach($version in @('11.0.100','11.0.101','11.0.100-rc.3.26522.148-extra','12.0.100')){
                    $script:ObservedSdk=$version
                    if((Get-DevelopmentInventory $plan).Sdk.State -ceq 'Ready'){throw 'SDK exact pin bypassed'};$counts.Examples++
                }
                $script:ObservedSdk=$spec.SdkVersion
                $spec.PowerShellFramework=[pscustomobject]@{Name='Microsoft.NETCore.App';Version='10.0.14'}
                if((Get-DevelopmentInventory $plan).Sdk.State -ceq 'Ready'){throw 'Framework-dependent PowerShell runtime was hidden'}
                $script:ObservedRuntimes=@('Microsoft.NETCore.App 10.0.14 [fixture]')
                if((Get-DevelopmentInventory $plan).Sdk.State -cne 'Ready'){throw 'Existing PowerShell runtime was not preserved'}
                $spec.PowerShellFramework=$null;$script:ObservedRuntimes=@();$counts.Examples+=2
                for($i=0;$i -lt 200;$i++){
                    $inventory=[ordered]@{}
                    $expected=[Collections.Generic.List[string]]::new()
                    foreach($name in @('System','Sdk','Git','Editor','Native','Profilers','Containers','Workflows')){
                        $state=@('Ready','Missing','Excluded','RemoteRequired')[$random.Next(0,4)]
                        $inventory[$name]=[pscustomobject]@{Name=$name;State=$state;Version=$null;Path=$null;Detail=$null}
                        if($state -ceq 'Missing'){[void]$expected.Add($name)}
                    }
                    if((@(Get-DevelopmentActions $inventory) -join ',') -cne ($expected -join ',')){throw 'Missing-component action property failed'};$counts.Properties++
                }
                $missing=Get-DevelopmentInventory $plan;$missing.Sdk.State='Missing'
                $script:Effects=0
                function script:Install-DevelopmentSdk {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)$script:Effects++;throw 'Unexpected installation in control mode'}
                foreach($check in @($true,$false)){
                    $report=Invoke-DevelopmentProvisioning $plan $missing -CheckOnly:$check -ShouldApply {param($p,$a)$false}
                    if($report.State -cne 'NeedsInstallation' -or $script:Effects -ne 0 -or (Test-Path -LiteralPath $plan.InstallRoot)){throw 'Control mode performed a mutation'};$counts.Examples++
                }
                # End-to-end state transitions use fake effects in this run's owned temporary directory.
                $script:FakeInventory=$good;$script:SdkInstalls=0
                function script:Get-DevelopmentInventory {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)$script:FakeInventory}
                function script:Install-DevelopmentSdk {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)$script:SdkInstalls++}
                function script:Write-DevelopmentActivation {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan,$Inventory)'activation-fixture.ps1'}
                $first=Invoke-DevelopmentProvisioning $plan $missing -ShouldApply {$true}
                if($first.State -cne 'Ready' -or $script:SdkInstalls -ne 1){throw 'First install did not verify independently'}
                $again=Invoke-DevelopmentProvisioning $plan $good -ShouldApply {$true}
                if($again.State -cne 'Ready' -or $script:SdkInstalls -ne 1){throw 'Compatible tool was reinstalled'}
                $script:WorkflowInstalls=0
                function script:Install-DevelopmentWrkflw {
                    <#
                    .SYNOPSIS
                    Counts workflow installations without downloading or changing the host.
                    #>
                    param($Plan) $script:WorkflowInstalls++
                }
                $script:FakeInventory=$workflowReady
                $workflowMissing=[ordered]@{}
                foreach($key in $workflowReady.Keys){$workflowMissing[$key]=$workflowReady[$key].PSObject.Copy()}
                $workflowMissing.Workflows.State='Missing'
                foreach($check in @($true,$false)){
                    $null=Invoke-DevelopmentProvisioning $workflowPlan $workflowMissing -CheckOnly:$check -ShouldApply {$false}
                    if($script:WorkflowInstalls){throw 'Wrkflw installed in a control mode'}
                }
                $installedWorkflow=Invoke-DevelopmentProvisioning $workflowPlan $workflowMissing -ShouldApply {$true}
                $null=Invoke-DevelopmentProvisioning $workflowPlan $workflowReady -ShouldApply {$true}
                if($installedWorkflow.State -cne 'Ready' -or $script:WorkflowInstalls -ne 1){throw 'Wrkflw installation missing or not idempotent'}
                $script:FakeInventory=$workflowMissing
                $unverifiedWorkflow=Invoke-DevelopmentProvisioning $workflowPlan $workflowMissing -ShouldApply {$true}
                if($unverifiedWorkflow.State -cne 'Failed' -or $unverifiedWorkflow.Error -notlike '*Workflows*'){throw 'Unverified wrkflw install reported success'}
                $script:FakeInventory=$good;$counts.Examples+=5
                function script:Install-DevelopmentSdk {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)throw 'FixtureDownloadFailed'}
                $failure=Invoke-DevelopmentProvisioning $plan $missing -ShouldApply {$true}
                if($failure.State -cne 'Failed' -or $failure.Error -cne 'FixtureDownloadFailed' -or $failure.ActivationScript){throw 'Installation failure became success'}
                $plan.Skipped=@('Editor','Native','Profilers');$missing.Sdk.State='Ready';$missing.Containers.State='Missing'
                function script:Initialize-DevelopmentPodman {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)$true}
                $restart=Invoke-DevelopmentProvisioning $plan $missing -ShouldApply {$true}
                if($restart.State -cne 'RestartRequired' -or !$restart.RestartRequired){throw 'Reboot was not reported'}
                function script:Initialize-DevelopmentPodman {
                    <#
                    .SYNOPSIS
                    Supplies an isolated native or installation boundary for independent assertions.
                    #>
param($Plan)$false}
                $resumed=Invoke-DevelopmentProvisioning $plan $missing -ShouldApply {$true}
                if($resumed.State -cne 'Ready'){throw 'Reboot resume failed'}
                $counts.Examples+=5
            } $output $counts
        }finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
    }
    $baseline=Join-Path $RunDirectory 'workstation-baseline'
    [void][IO.Directory]::CreateDirectory($baseline)
    & $verify $source $baseline $counts
    $mutations=@(
        @{Id='accept-newer-sdk';Find='$inventory.Sdk.Version -ceq $spec.SdkVersion';Replace='$true'},
        @{Id='allow-git-next-major-range';Find="[version]'2.57.0'";Replace="[version]'2.99.0'"},
        @{Id='allow-vagrant-next-minor-range';Find="[version]'2.5.0'";Replace="[version]'2.6.0'"},
        @{Id='replace-compatible-tools';Find="@('Ready','Excluded','RemoteRequired')";Replace="@('Excluded','RemoteRequired')"},
        @{Id='ignore-check-only-and-whatif';Find='if($CheckOnly -or !(& $ShouldApply';Replace='if($false -and !(& $ShouldApply'},
        @{Id='lose-musl-selection';Find='$musl=$values.ID -ceq ''alpine''';Replace='$musl=$false'},
        @{Id='ignore-podman-selection';Find='if($Name){return $Name}';Replace='if($false){return $Name}'},
        @{Id='hide-install-failures';Find="catch{`$report.State='Failed';";Replace="catch{`$report.State='Ready';"},
        @{Id='hide-reboot';Find="`$report.State='RestartRequired'";Replace="`$report.State='Ready'"},
        @{Id='hide-powershell-framework';Find='if($spec.PSObject.Properties[''PowerShellFramework''] -and $spec.PowerShellFramework)';Replace='if($false)'},
        @{Id='accept-any-wrkflw-version';Find="[string]::Equals(`$Text,('wrkflw '+`$ExpectedVersion),[StringComparison]::Ordinal)";Replace='$true'},
        @{Id='ignore-wrkflw-digest';Find="`$artifact.SHA256 -cnotmatch '\A[a-f0-9]{64}\z'";Replace='$false'},
        @{Id='ignore-wrkflw-url';Find='$artifact.Url -cne $expected';Replace='$false'},
        @{Id='fallback-wrkflw-architecture';Find='$Configuration.Artifacts|Where-Object Rid -CEQ $Target.Rid';Replace='$Configuration.Artifacts|Where-Object Rid -CEQ ''win-x64'''},
        @{Id='omit-wrkflw-install';Find="if(`$actions -contains 'Workflows'){Install-DevelopmentWrkflw `$Plan}";Replace=''},
        @{Id='omit-wrkflw-activation';Find="@('Sdk','Git','Native','Editor','Workflows')";Replace="@('Sdk','Git','Native','Editor')"},
        @{Id='ignore-wrkflw-cache-checksum';Find="if((Get-FileHash -LiteralPath `$Destination -Algorithm `$Algorithm).Hash -ine `$Digest)";Replace='if($false)'},
        @{Id='wrong-wrkflw-download-checksum';Find='$archive=Get-DevelopmentArchive $tool.Url $tool.SHA256';Replace='$archive=Get-DevelopmentArchive $tool.Url (''0''*64)'}
    )
    $results=[Collections.Generic.List[object]]::new()
    foreach($mutation in $mutations){
        $candidate=$source.Replace($mutation.Find,$mutation.Replace)
        if($candidate -ceq $source){throw ('WorkstationMutantInvalid: '+$mutation.Id)}
        $directory=Join-Path $RunDirectory ('workstation-mutant-'+$mutation.Id)
        [void][IO.Directory]::CreateDirectory($directory)
        $detected=$false;$message=$null
        try{& $verify $candidate $directory @{Examples=0;Properties=0;FuzzInputs=0;Seed=$counts.Seed}}catch{$detected=$true;$message=$_.Exception.Message}
        if(!$detected){throw ('WorkstationMutantSurvived: '+$mutation.Id)}
        $counts.MutantsKilled++;[void]$results.Add(@{Id=$mutation.Id;State='Killed';Reason=$message})
    }
    $report=[ordered]@{State='Success';SourceSHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;Examples=$counts.Examples;PropertyExecutions=$counts.Properties;FuzzInputs=$counts.FuzzInputs;Seed=$counts.Seed;Mutation=@{Killed=$counts.MutantsKilled;Survived=0;Invalid=0;Cases=@($results)};Scope='Isolated PowerShell host/version/policy fixtures; no real package installation or ARM64 execution'}
    $report.ModuleWorkstation=Test-QuietModuleWorkstation -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    [void][IO.File]::WriteAllTextAsync((Join-Path $RunDirectory 'development-workstation.json'),($report|ConvertTo-Json -Depth 10)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [pscustomobject]$report
}

function Test-QuietModuleWorkstation {
    <#
    .SYNOPSIS
    Verifies selector order, module control modes and version properties with trapped effects.
    .PARAMETER WorkspaceRoot
    Source of the real scripts and independently loaded helpers.
    .PARAMETER RunDirectory
    Owned fixtures and mutation evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $root=Join-Path $RunDirectory 'module-workstation'
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'scripts'))
    $selector=Join-Path $WorkspaceRoot 'scripts/Install-ModuleWorkstation.ps1'
    $selectorSource=[IO.File]::ReadAllTextAsync($selector,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $verifySelector={
        param($source)
        $selectedPath=Join-Path $root 'scripts/Install-ModuleWorkstation.ps1'
        [void][IO.File]::WriteAllTextAsync($selectedPath,$source,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        foreach($selection in @(@('Git'),@('Vagrant'),@('Git','Vagrant'),@('Vagrant','Git'))){
            $observed=@(& $selectedPath -Modules $selection -CheckOnly)
            if(($observed.Module -join ',') -cne ($selection -join ',') -or @($observed | Where-Object {!$_.CheckOnly -or $_.Download}).Count){throw 'ModuleSelectorOrderOrScopeLost'}
            $download=@(& $selectedPath -Modules $selection -Download -WhatIf)
            if(@($download | Where-Object {!$_.Download -or !$_.WhatIf}).Count){throw 'ModuleSelectorWhatIfOrDownloadLost'}
        }
        foreach($options in @(@{Modules=@('Core')},@{Modules=@('Git','Vagrant');CheckOnly=$true;Download=$true})){
            $rejected=$false;try{$null=& $selectedPath @options}catch{$rejected=$true}
            if(!$rejected){throw 'InvalidModuleSelectorAccepted'}
        }
    }
    foreach($name in @('Git','Vagrant','Core')){
        $directory=Join-Path $root "FrenchExDev2.QuietCli.$name.PoSh/scripts"
        [void][IO.Directory]::CreateDirectory($directory)
        $stub='[CmdletBinding(SupportsShouldProcess)]param([switch]$CheckOnly,[switch]$Download) [pscustomobject]@{Module='''+$name+''';CheckOnly=[bool]$CheckOnly;Download=[bool]$Download;WhatIf=[bool]$WhatIfPreference}'
        [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'Install-Workstation.ps1'),$stub,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    & $verifySelector $selectorSource
    $mutations=@(
        @{Name='selector-reverses-order';From='foreach ($module in $Modules)';To='foreach ($module in @($Modules | Sort-Object -Descending))'},
        @{Name='selector-download-lost';From='-Download:$Download';To='-Download:$false'},
        @{Name='selector-whatif-lost';From='-WhatIf:$WhatIfPreference';To='-WhatIf:$false'},
        @{Name='selector-conflict-accepted';From="if (`$CheckOnly -and `$Download) { throw 'CheckOnlyAndDownloadAreMutuallyExclusive' }";To=''},
        @{Name='selector-validation-removed';From="[ValidateSet('Git', 'Vagrant')]";To=''}
    )
    $killed=[Collections.Generic.List[string]]::new()
    foreach($mutation in $mutations){
        if(([regex]::Matches($selectorSource,[regex]::Escape($mutation.From))).Count -ne 1){throw "ModuleWorkstationMutationAnchorInvalid: $($mutation.Name)"}
        $detected=$false;try{& $verifySelector $selectorSource.Replace($mutation.From,$mutation.To)}catch{$detected=$true}
        if(!$detected){throw "ModuleWorkstationMutantSurvived: $($mutation.Name)"};$killed.Add($mutation.Name)
    }
    $development=Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/DevelopmentWorkstation.psm1') -PassThru
    $random=[Random]::new(20261108);$propertyCount=0;$fuzzCount=0
    foreach($banner in @('Vagrant 2.3.0','Vagrant 2.4.9')){if(!(Test-DevelopmentVagrantVersion $banner)){throw 'SupportedVagrantVersionRejected'}}
    foreach($banner in @('Vagrant 2.2.99','Vagrant 2.5.0','Vagrant 3.0.0','vagrant 2.4.9','Vagrant 2.4.9-rc1','Vagrant 2.4.9 extra','Vagrant 2.4.999999999999999999999')){if(Test-DevelopmentVagrantVersion $banner){throw 'UnsupportedVagrantVersionAccepted'}}
    for($index=0;$index -lt 200;$index++){
        $minor=$random.Next(0,10);$patch=$random.Next(0,1000);$banner="Vagrant 2.$minor.$patch"
        if((Test-DevelopmentVagrantVersion $banner) -ne ($minor -in @(3,4))){throw 'VagrantVersionPropertyFailed'};$propertyCount++
        foreach($suffix in @(';echo bad',"`nother",'-dev','_extra')){if(Test-DevelopmentVagrantVersion ($banner+$suffix)){throw 'MalformedVagrantVersionAccepted'};$fuzzCount++}
    }
    $module=Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/ModuleWorkstation.psm1') -Force -PassThru
    try{
        & $module {
            $script:Effects=[Collections.Generic.List[string]]::new();$script:FakeReady=$false
            function script:Get-ModuleWorkstationStatus {
                <#
                .SYNOPSIS
                Returns a simulated readiness state without native probes.
                #>
                param($Name,$Target)
                [pscustomobject]@{Module=$Name;State=if($script:FakeReady){'Ready'}else{'NeedsInstallation'};ToolReady=$script:FakeReady;Action='None';CachePath=$null;RestartRequired=$false}
            }
            function script:Save-ModuleWorkstationDownload {
                <#
                .SYNOPSIS
                Records an isolated download boundary without network access.
                #>
                param($Name,$Target) $script:Effects.Add('Download:'+ $Name);'fixture-cache'
            }
            function script:Install-ModuleWorkstationTool {
                <#
                .SYNOPSIS
                Records an isolated install boundary without changing the host.
                #>
                param($Name,$Target) $script:Effects.Add('Install:'+ $Name);$script:FakeReady=$true;$false
            }
        }
        foreach($name in @('Git','Vagrant')){
            $scriptPath=Join-Path $WorkspaceRoot "FrenchExDev2.QuietCli.$name.PoSh/scripts/Install-Workstation.ps1"
            foreach($ready in @($false,$true)){
                & $module {param($value)$script:FakeReady=$value;$script:Effects.Clear()} $ready
                $null=& $scriptPath -CheckOnly
                $null=& $scriptPath -WhatIf
                $null=& $scriptPath -Download -WhatIf
                $effects=@(& $module {$script:Effects.ToArray()})
                if($effects.Count){throw 'ModuleControlModePerformedEffects'}
                $download=& $scriptPath -Download
                $effects=@(& $module {$script:Effects.ToArray()})
                if(($effects -join ',') -cne ('Download:'+$name) -or $download.Action -cne 'Downloaded'){throw 'ModuleDownloadDependsOnReadinessOrInstalls'}
            }
            & $module {$script:FakeReady=$false;$script:Effects.Clear()}
            $installed=& $scriptPath
            $null=& $scriptPath
            $effects=@(& $module {$script:Effects.ToArray()})
            if(($effects -join ',') -cne ('Install:'+$name) -or $installed.State -cne 'Ready'){throw 'ModuleInstallIsNotVerifiedAndIdempotent'}
            $rejected=$false;try{$null=& $scriptPath -CheckOnly -Download}catch{$rejected=$_.Exception.Message -eq 'CheckOnlyAndDownloadAreMutuallyExclusive'}
            if(!$rejected){throw 'ModuleConflictingModesAccepted'}
        }
    }finally{Remove-Module $module -Force}
    [pscustomobject]@{Seed=20261108;PropertyExecutions=$propertyCount;FuzzInputs=$fuzzCount;SelectorMutantsKilled=@($killed);Scope='Real selector and module scripts; simulated status/download/install effects; no native installation'}
}
