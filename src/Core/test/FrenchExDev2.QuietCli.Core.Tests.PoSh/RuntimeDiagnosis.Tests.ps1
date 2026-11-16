function Test-QuietRuntimeDiagnosis {
    <#
    .SYNOPSIS
    Checks independent runtime/ABI conclusions, malformed observations and targeted policy mutations.
    .PARAMETER WorkspaceRoot
    Workspace containing the infrastructure-only policy module.
    .PARAMETER RunDirectory
    Owned evidence directory for deterministic seeds and mutation outcomes.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $path=Join-Path $WorkspaceRoot 'scripts/lib/RuntimeDiagnosis.psm1'
    Import-Module $path -Force
    $image=@{Architecture='amd64';Os='linux'}
    $checks=0
    function New-DiagnosisObservation {
        <# .SYNOPSIS
        Creates independently specified successful host observations, without using production policy.
        .PARAMETER Rid
        Expected portable target.
        .PARAMETER Reported
        Actual reported identity, preserved even when it differs.
        .PARAMETER Name
        Default or explicit-root control name.
        #>
        param([string]$Rid='linux-musl-x64',[string]$Reported='linux-musl-x64',[string]$Name='Default')
        $arm=$Rid.EndsWith('arm64')
        @{Name=$Name;Outcome='Success';Probe=@{SchemaVersion=1;Phase='Complete';Linux=$true;RuntimeIdentifier=$Reported;FrameworkMajor=10;
            ProcessArchitecture=if($arm){'arm64'}else{'x64'};OSArchitecture=if($arm){'arm64'}else{'x64'};ElfMachine=if($arm){183}else{62};Libc=if($Rid.Contains('musl')){'Musl'}else{'Gnu'};
            RawNative=@{Outcome=if($Reported -ceq $Rid){'Success'}else{'Missing'};HashMatches=$true};ExpectedNative=@{Outcome='Success';HashMatches=$true}}}
    }
    function Assert-DiagnosisDecision {
        <# .SYNOPSIS
        Asserts one business conclusion and the invariant that a diagnostic cannot qualify the product.
        .PARAMETER Observations
        Independent fixture controls.
        .PARAMETER Expected
        Required conclusion.
        #>
        param([object[]]$Observations,[string]$Expected)
        $result=Get-QuietRuntimeDiagnosis -Image $image -Observations $Observations -ExpectedRuntimeIdentifier 'linux-musl-x64'
        Assert-QuietEqual $result.Decision $Expected
        Assert-QuietEqual $result.WholeProductCompatibilityProven $false
        $recreate=if($Expected -in @('BootstrapAndAssetSelection','AssetSelection','BootstrapConfiguration','ArchitectureMismatch')){$false}else{$null}
        Assert-QuietEqual $result.RecreateUnchangedContainerFixesIssue $recreate
        return $result
    }
    $healthy=New-DiagnosisObservation
    $null=Assert-DiagnosisDecision @($healthy) 'NoMismatchObserved';$checks++
    $failed=@{Name='Default';Outcome='Failed';Probe=$null}
    $root=New-DiagnosisObservation -Reported 'alpine.3.24-x64' -Name Root0
    $result=Assert-DiagnosisDecision @($failed,$root) 'BootstrapAndAssetSelection';$checks++
    Assert-QuietEqual $result.ReportedRuntimeIdentifiers[0] 'alpine.3.24-x64'
    $null=Assert-DiagnosisDecision @((New-DiagnosisObservation -Reported 'alpine.3.24-x64')) 'AssetSelection';$checks++
    $null=Assert-DiagnosisDecision @($failed,(New-DiagnosisObservation -Name Root0)) 'BootstrapConfiguration';$checks++
    $null=Assert-DiagnosisDecision @($failed) 'HostUnavailable';$checks++
    $null=Assert-DiagnosisDecision @((New-DiagnosisObservation -Name Root0)) 'Inconclusive';$checks++
    foreach($change in @(@{Key='ElfMachine';Value=183},@{Key='Libc';Value='Unknown'},@{Key='FrameworkMajor';Value=11},@{Key='RuntimeIdentifier';Value=''},@{Key='Phase';Value='Identity'})){
        $row=New-DiagnosisObservation;$row.Probe[$change.Key]=$change.Value
        $null=Assert-DiagnosisDecision @($row) 'Inconclusive';$checks++
    }
    $row=New-DiagnosisObservation;$row.Probe.OSArchitecture='arm64'
    $null=Assert-DiagnosisDecision @($row) 'ArchitectureMismatch';$checks++
    $row=New-DiagnosisObservation;$row.Probe.ExpectedNative.HashMatches=$false
    $null=Assert-DiagnosisDecision @($row) 'NativeAssetsUnusable';$checks++
    $row=New-DiagnosisObservation;$row.Probe.RawNative.Outcome='Missing'
    $null=Assert-DiagnosisDecision @($row) 'NativeAssetsUnusable';$checks++
    $row=New-DiagnosisObservation;$row.Probe.ExpectedNative.HashMatches=1
    $null=Assert-DiagnosisDecision @($row) 'NativeAssetsUnusable';$checks++
    $seed=20261109;$random=[Random]::new($seed)
    foreach($index in 1..200){
        $arm=$random.Next(2) -eq 1;$rid='linux-musl-'+$(if($arm){'arm64'}else{'x64'})
        $actual='alpine.'+$random.Next(3,9)+'.'+$random.Next(0,30)+'-'+$(if($arm){'arm64'}else{'x64'})
        $observation=New-DiagnosisObservation -Rid $rid -Reported $actual
        $result=Get-QuietRuntimeDiagnosis -Image @{Architecture=if($arm){'arm64'}else{'amd64'};Os='linux'} -Observations @($observation) -ExpectedRuntimeIdentifier $rid
        Assert-QuietEqual $result.Decision 'AssetSelection' "seed=$seed iteration=$index"
        Assert-QuietEqual $result.ReportedRuntimeIdentifiers[0] $actual
        Assert-QuietEqual $result.WholeProductCompatibilityProven $false
    }
    $fuzz=0
    foreach($index in 1..100){
        foreach($field in @('SchemaVersion','Phase','Linux','RuntimeIdentifier','ElfMachine','FrameworkMajor','Libc')){
            $values=[Collections.Generic.List[object]]::new()
            foreach($bad in @($null,@{},@('malformed',$random.Next().ToString()),'unrecognized')){$values.Add($bad)}
            # A single-element array must remain an array, even when its element is otherwise valid.
            $values.Add([object[]]@($healthy.Probe[$field]))
            foreach($bad in $values){
                $observation=New-DiagnosisObservation;$observation.Probe[$field]=$bad
                $result=Get-QuietRuntimeDiagnosis -Image $image -Observations @($observation) -ExpectedRuntimeIdentifier 'linux-musl-x64'
                if($result.Decision -eq 'NoMismatchObserved' -or $result.WholeProductCompatibilityProven){throw "MalformedDiagnosisAccepted: seed=$seed iteration=$index field=$field"}
                $fuzz++
            }
        }
    }
    $mutants=@(
        @{Name='bootstrap-fault-hidden';From='$bootstrapFault=$defaultObserved -and !$defaultSucceeded -and $usable.Count -gt 0';To='$bootstrapFault=$false';Expected='BootstrapAndAssetSelection';Rows=@($failed,$root)},
        @{Name='elf-machine-ignored';From='-or $elfMachine -ne $machine';To='';Expected='Inconclusive';Rows=@($( $o=New-DiagnosisObservation;$o.Probe.ElfMachine=183;$o ))},
        @{Name='libc-ignored';From='$observedLibc -cne $libc';To='$false';Expected='Inconclusive';Rows=@($( $o=New-DiagnosisObservation;$o.Probe.Libc='Unknown';$o ))},
        @{Name='native-hash-ignored';From='$hashMatches -eq $true';To='$true';Expected='NativeAssetsUnusable';Rows=@($( $o=New-DiagnosisObservation;$o.Probe.ExpectedNative.HashMatches=$false;$o ))},
        @{Name='asset-selection-hidden';From='{$selectionFault=$true}';To='{$selectionFault=$false}';Expected='AssetSelection';Rows=@((New-DiagnosisObservation -Reported 'alpine.3.24-x64'))},
        @{Name='partial-probe-accepted';From="-or `$phase -cne 'Complete'";To='';Expected='Inconclusive';Rows=@($( $o=New-DiagnosisObservation;$o.Probe.Phase='Identity';$o ))},
        @{Name='diagnostic-promoted-to-qualification';From='WholeProductCompatibilityProven=$false';To='WholeProductCompatibilityProven=$true';Expected='NoMismatchObserved';Rows=@($healthy)}
    )
    $original=[IO.File]::ReadAllTextAsync($path,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $outcomes=@(foreach($mutant in $mutants){
        if(([regex]::Matches($original,[regex]::Escape($mutant.From))).Count -ne 1){throw ('RuntimeDiagnosisMutationAnchorInvalid: '+$mutant.Name)}
        $text=$original.Replace($mutant.From,$mutant.To)
        $module=New-Module -Name ('RuntimeDiagnosisMutant'+[guid]::NewGuid().ToString('N')) -ScriptBlock {param($code). ([scriptblock]::Create($code))} -ArgumentList $text
        try{
            $observed=& $module {param($i,$rows) Get-QuietRuntimeDiagnosis -Image $i -Observations $rows -ExpectedRuntimeIdentifier 'linux-musl-x64'} $image $mutant.Rows
            $killed=$observed.Decision -cne $mutant.Expected -or $observed.WholeProductCompatibilityProven
            if(!$killed){throw ('RuntimeDiagnosisMutantSurvived: '+$mutant.Name)}
            @{Name=$mutant.Name;Outcome='Killed'}
        }finally{Remove-Module $module -Force}
    })
    Write-WorkspaceJson (Join-Path $RunDirectory 'runtime-diagnosis-policy.json') @{Seed=$seed;Examples=$checks;Properties=200;MalformedInputs=$fuzz;Mutations=$outcomes;SourceSHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
