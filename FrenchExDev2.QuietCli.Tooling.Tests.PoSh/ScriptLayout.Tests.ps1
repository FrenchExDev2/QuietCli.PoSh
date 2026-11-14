#requires -Version 7.6
function Test-QuietScriptLayoutContract {
    <#
    .SYNOPSIS
    Checks structural policy with generated valid names, hostile syntax and independently failing mutants.
    .PARAMETER WorkspaceRoot
    Checkout supplying the static policy implementation.
    .PARAMETER RunDirectory
    Owned external fixture and evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/ScriptLayout.psm1')) -DisableNameChecking -ErrorAction Stop
    $fixture=[IO.Path]::Combine($RunDirectory,'script-layout')
    $scripts=[IO.Path]::Combine($fixture,'scripts')
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($scripts,'lib'))
    $utf8=[Text.UTF8Encoding]::new($false)
    $valid=[ordered]@{}
    foreach($index in 1..32){$valid['Test-Fixture'+$index+'.ps1']="# accents é漢 and function Fake-Comment {} are inert`n'function Fake-Literal {}'`n"}
    $valid['Commit-Workspace.ps1']='param()'
    $valid['Test-Import.ps1']="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Fixture.psm1')) -DisableNameChecking"
    $valid['lib/Fixture.psm1']="function Get-Fixture { 'value' }; Export-ModuleMember -Function Get-Fixture"
    foreach($item in $valid.GetEnumerator()){[IO.File]::WriteAllText([IO.Path]::Combine($scripts,$item.Key),$item.Value,$utf8)}
    $result=Test-QuietScriptLayout $fixture
    if($result.Files -ne $valid.Count){throw 'ScriptLayoutInventoryMismatch'}
    $invalid=@(
        @{Name='BadName.ps1';Text='param()'},
        @{Name='test-Wrong.ps1';Text='param()'},
        @{Name='Test-Bad.Name.ps1';Text='param()'},
        @{Name='Test-Function.ps1';Text='function Get-Hidden {}'},
        @{Name='Test-Nested.ps1';Text='& { if($false){function Get-Hidden {}} }'},
        @{Name='Test-Filter.ps1';Text='filter Get-Hidden {$_}'},
        @{Name='Misplaced.psm1';Text='function Get-Hidden {}'},
        @{Name='Test-Path.ps1';Text="Microsoft.PowerShell.Management\Join-Path 'a' 'b'"},
        @{Name='Test-Import.ps1';Text="Import-Module './lib/Fixture.psm1'"},
        @{Name='Test-Import.ps1';Text="Import-Module './lib/Fixture.psm1' -DisableNameChecking:`$false"},
        @{Name='Test-Import.ps1';Text="Microsoft.PowerShell.Core\Import-Module './lib/Fixture.psm1'"},
        @{Name='Test-Dot.ps1';Text=". './lib/Fixture.psm1'"},
        @{Name='Test-Invalid.ps1';Text='param(';}
    )
    $oracle={param($subject)
        foreach($item in $invalid){
            $path=[IO.Path]::Combine($scripts,$item.Name)
            [IO.File]::WriteAllText($path,$item.Text,$utf8)
            try{
                $rejected=$false
                try{$null=& $subject $fixture}catch{if($_.Exception.Message -like 'ScriptLayoutInvalid:*'){$rejected=$true}else{throw}}
                if(!$rejected){throw ('ScriptLayoutAcceptedInvalid: '+$item.Name+' '+$item.Text)}
            }finally{
                if($valid.Contains($item.Name)){[IO.File]::WriteAllText($path,$valid[$item.Name],$utf8)}else{[IO.File]::Delete($path)}
            }
        }
    }
    & $oracle (Get-Command Test-QuietScriptLayout)
    $source=(Get-Command Test-QuietScriptLayout).Definition
    $mutations=@(
        @('if(!$name.Success)','if($false)'),
        @('$node -is [Management.Automation.Language.FunctionDefinitionAst]','$false'),
        @("elseif(!`$relative.StartsWith('scripts/lib/',[StringComparison]::Ordinal))","elseif(`$false)"),
        @("-ieq 'Join-Path'","-ieq 'Never-Path'"),
        @('if(!$quietImport.Count)','if($false)'),
        @('if($errors.Count)','if($false)'),
        @("-match '\.psm1'","-match 'never-module'")
    )
    $killed=0
    foreach($mutation in $mutations){
        if(!$source.Contains($mutation[0])){throw 'ScriptLayoutMutationAnchorMissing'}
        $subject=[scriptblock]::Create($source.Replace($mutation[0],$mutation[1]))
        $detected=$false
        try{& $oracle $subject}catch{if($_.Exception.Message -like 'ScriptLayoutAcceptedInvalid:*'){$detected=$true}else{throw}}
        if(!$detected){throw 'ScriptLayoutSurvivingMutant'}
        $killed++
    }
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/ScriptShouldProcess.psm1')) -DisableNameChecking -ErrorAction Stop
    $wrapper=[IO.Path]::Combine($scripts,'Test-Delegate.ps1')
    $library=[IO.Path]::Combine($scripts,'lib/Delegate.psm1')
    $wrapperSource="[CmdletBinding(SupportsShouldProcess)]param()`nImport-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Delegate.psm1')) -DisableNameChecking -ErrorAction Stop`nInvoke-QuietScriptDelegate @PSBoundParameters`n"
    $librarySource="function Invoke-QuietScriptDelegate {[CmdletBinding(SupportsShouldProcess)]param();if(!`$PSCmdlet.ShouldProcess('fixture','write')){return}; throw 'ShouldNeverExecute'}`nExport-ModuleMember -Function Invoke-QuietScriptDelegate`n"
    [IO.File]::WriteAllText($wrapper,$wrapperSource,$utf8)
    [IO.File]::WriteAllText($library,$librarySource,$utf8)
    if((Get-QuietScriptShouldProcess $wrapper) -ne 'ShouldProcess'){throw 'DelegatedGuardNotRecognized'}
    foreach($damaged in @(
        $librarySource.Replace('SupportsShouldProcess','SupportsShouldProcess=$false'),
        $librarySource.Replace("if(!`$PSCmdlet.ShouldProcess('fixture','write')){return}","'`$PSCmdlet.ShouldProcess('"),
        $librarySource.Replace('Invoke-QuietScriptDelegate','Invoke-QuietScriptDifferent')
    )){
        [IO.File]::WriteAllText($library,$damaged,$utf8)
        if((Get-QuietScriptShouldProcess $wrapper) -eq 'ShouldProcess'){throw 'DelegatedGuardMutationAccepted'}
    }
    [IO.File]::WriteAllText($library,$librarySource,$utf8)
    # The guarded command throws if its business body is reached. ShouldProcess host text is not a pipeline receipt.
    $null=& $wrapper -WhatIf
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop
    $librarySources=@(Get-QuietSourceFiles -Root $fixture | Where-Object Path -Like 'scripts/lib/*')
    if($librarySources.Count -ne 2){throw 'ScriptLibrarySourcesExcluded'}
    # Resolve helper dependencies inside their owning modules, without caller-scope functions.
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/RuntimeTargets.psm1')) -DisableNameChecking -ErrorAction Stop
    $peDirectory=[IO.Path]::Combine($RunDirectory,'pe-publication')
    [void][IO.Directory]::CreateDirectory($peDirectory)
    $bytes=[byte[]]::new(128)
    $bytes[0]=0x4d;$bytes[1]=0x5a;$bytes[60]=64;$bytes[64]=0x50;$bytes[65]=0x45;$bytes[68]=0x64;$bytes[69]=0x86
    foreach($name in @('QuietCli.Engine.dll','apphost.exe')){[IO.File]::WriteAllBytes([IO.Path]::Combine($peDirectory,$name),$bytes)}
    Assert-QuietRuntimePublication -Directory $peDirectory -Target @{Rid='win-x64';NativeFormat='PE';ManagedMachine=0x8664;NativeMachine=0x8664;Apphost='apphost.exe'}
    $build=[IO.Path]::Combine($RunDirectory,'build-manifest')
    foreach($relative in @('Product/lib','FrenchExDev2.QuietCli.Core.PoSh')){[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($build,$relative))}
    foreach($item in @{'Product/Fixture.csproj'='<Project />';'global.json'='{}';'Directory.Packages.props'='<Project />';'FrenchExDev2.QuietCli.Core.PoSh/protocol.json'='{}';'Product/lib/fixture.dll'='inert fixture'}.GetEnumerator()){
        [IO.File]::WriteAllText([IO.Path]::Combine($build,$item.Key),$item.Value,$utf8)
    }
    $inputs=@(Get-QuietBinaryInputs -WorkspaceRoot $build -Project 'Product/Fixture.csproj')
    Write-QuietBuildManifest -WorkspaceRoot $build -Project 'Product/Fixture.csproj' -Output 'Product/lib' -Inputs $inputs
    $null=Test-QuietBuildManifest -WorkspaceRoot $build -Output 'Product/lib'
    $imageModule=Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/CiImages.psm1')) -PassThru -DisableNameChecking -ErrorAction Stop
    $resolved=& $imageModule { (Get-Command Resolve-QuietVirtEngine -ErrorAction Stop).Name }
    if($resolved -ne 'Resolve-QuietVirtEngine'){throw 'ImageModuleDependencyMissing'}
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/RuntimeDiagnosis.psm1')) -DisableNameChecking -ErrorAction Stop
    $stage=[IO.Path]::Combine($RunDirectory,'probe-inputs')
    $null=Copy-QuietRuntimeProbeInputs -ScriptsRoot ([IO.Path]::Combine($WorkspaceRoot,'scripts')) -Destination $stage -WhatIf
    if(Test-Path -LiteralPath $stage){throw 'ProbePreviewCreatedInputs'}
    $null=Copy-QuietRuntimeProbeInputs -ScriptsRoot ([IO.Path]::Combine($WorkspaceRoot,'scripts')) -Destination $stage -Confirm:$false
    $expected=@('Probe-ContainerRuntime.ps1','lib/Probe-ContainerRuntime.psm1','lib/Ci.Process.psm1','lib/RuntimeTargets.psm1','lib/BinaryHeaders.psm1','lib/RuntimeDiagnosis.psm1')
    $actual=@(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/')})
    if((($actual|Sort-Object) -join '|') -cne (($expected|Sort-Object) -join '|')){throw 'ProbeDependencyLayoutChanged'}
    foreach($relative in $expected){
        if((Get-FileHash -LiteralPath ([IO.Path]::Combine($stage,$relative))).Hash -cne (Get-FileHash -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'scripts',$relative))).Hash){throw 'ProbeInputChanged'}
    }
    # A clean process must bootstrap Core/Git for the real informational sniffer without preloaded test helpers.
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
    $repository=New-QuietCommitWorkspaceFixture -Root $RunDirectory -RealScriptsPath ([IO.Path]::Combine($WorkspaceRoot,'scripts'))
    $head=Get-QuietCommitWorkspaceHeadRevision $repository
    $driver=[IO.Path]::Combine($RunDirectory,'Invoke-CommitBootstrap.ps1')
    $driverSource=@'
#requires -Version 7.6
param([string]$SubjectRoot,[string]$Repository)
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
& ([IO.Path]::Combine($SubjectRoot,'scripts/Commit-Workspace.ps1')) -WorkspaceRoot $Repository -Message 'Bootstrap preview' -WhatIf
'@
    [IO.File]::WriteAllText($driver,$driverSource+"`n",$utf8)
    $observed=@{Lines=0;Bad=[Collections.Generic.List[string]]::new();Tail=[Collections.Generic.Queue[string]]::new()}
    $process=Invoke-CiProcess -FilePath ([IO.Path]::Combine($PSHOME,('pwsh'+$(if($IsWindows){'.exe'}else{''})))) -WorkingDirectory $repository -TimeoutSeconds 180 -ArgumentList @('-NoProfile','-NonInteractive','-File',$driver,'-SubjectRoot',$WorkspaceRoot,'-Repository',$repository) -State $observed -OnOutput {
        param($event,$state)
        $state.Lines++
        if($event.Text -match 'Register-QuietHandler|CommitFileSniffer: could not'){$state.Bad.Add($event.Text)}
        $state.Tail.Enqueue($event.Text.Substring(0,[Math]::Min(512,$event.Text.Length)))
        if($state.Tail.Count -gt 8){[void]$state.Tail.Dequeue()}
    }
    if($process.Outcome -ne 'Success' -or $observed.Bad.Count){throw ('FreshCommitBootstrapFailed: '+$process.Outcome+'; '+(($observed.Bad.ToArray()+$observed.Tail.ToArray()) -join ' | '))}
    if((Get-QuietCommitWorkspaceHeadRevision $repository) -cne $head -or (Test-Path -LiteralPath ([IO.Path]::Combine($repository,'repositories.lock.json')))){throw 'FreshCommitPreviewMutatedRepository'}
    [pscustomobject]@{ValidNames=33;Malformed=$invalid.Count;MutantsKilled=$killed;DelegatedGuardMutants=3;PreviewNoEffects=$true}
}
