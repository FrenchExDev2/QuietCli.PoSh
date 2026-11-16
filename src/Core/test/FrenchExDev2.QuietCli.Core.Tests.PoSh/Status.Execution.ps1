function Invoke-QuietStatusComparison {
    <#
    .SYNOPSIS
    Compares Core callbacks with independently run human-readable Git status records.
    .PARAMETER RepositoryPath
    Repository or explicitly isolated non-repository directory to inspect.
    .PARAMETER GitPath
    Exact Git executable shared by subject and reference.
    .PARAMETER CoreImportMs
    Separately measured import duration, when available.
    .PARAMETER WarmIterations
    Number of additional calls after starting one fresh engine session.
    #>
    param([string]$RepositoryPath,[string]$GitPath,[double]$CoreImportMs=0,[ValidateRange(1,10)][int]$WarmIterations=3)
    $git=$GitPath
    $module=Get-Module FrenchExDev2.QuietCli.Core.PoSh
function Invoke-StatusReference {
    <#
    .SYNOPSIS
    Reads Git independently through the shared CI runner and hashes normalized lines.
    #>
    $state=@{stdout=(New-QuietStatusAccumulator);stderr=(New-QuietStatusAccumulator)}
    try{
        $result=Invoke-CiProcess -FilePath $git -ArgumentList @('status') -WorkingDirectory $RepositoryPath -TimeoutSeconds 120 -State $state -OnOutput {
            param($record,$state)
            Add-QuietStatusRecord $state[$record.Stream] $record.Text
        }
        if($result.Outcome -ne 'Success' -or $result.ExitCode -ne 0){throw 'ReferenceGitStatusFailed'}
        [pscustomobject]@{ElapsedMs=$result.ElapsedMs;Stdout=(Complete-QuietStatusAccumulator $state.stdout);Stderr=(Complete-QuietStatusAccumulator $state.stderr)}
    }finally{$state.stdout.Hash.Dispose();$state.stderr.Hash.Dispose()}
}

function Assert-StatusSummary {
    <#
    .SYNOPSIS
    Compares record counts, UTF-8 volume and independently exercised streaming output digests.
    .PARAMETER Actual
    Core callback result.
    .PARAMETER Reference
    Independent Git invocation on an unchanged repository.
    #>
    param($Actual,$Reference)
    foreach($stream in @('Stdout','Stderr')){
        foreach($property in @('Lines','Utf8Bytes','SHA256')){
            if($Actual.$stream.$property -cne $Reference.$stream.$property){throw "RealStatusMismatch: $stream/$property"}
        }
    }
}

$samples=[Collections.Generic.List[object]]::new()
$engine=$null
try{
    $reference=Invoke-StatusReference
    foreach($iteration in 0..$WarmIterations){
        $data=@{stdout=(New-QuietStatusAccumulator);stderr=(New-QuietStatusAccumulator);CompleteCalls=0}
        try{
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $result=quiet -AsObject -WorkingDirectory $RepositoryPath -TimeoutSeconds 120 -RecordDelimiter "`n" -MaxRecordBytes 131072 -Data $data -Output {
                param($event,$runtime)
                Add-QuietStatusRecord $runtime.Data[$event.Stream] $event.Text
            } -Complete {
                param($runtime)
                $runtime.Data.CompleteCalls++
                [pscustomobject]@{Stdout=(Complete-QuietStatusAccumulator $runtime.Data.stdout);Stderr=(Complete-QuietStatusAccumulator $runtime.Data.stderr)}
            } -FilePath $git -ArgumentList @('status')
            $watch.Stop()
            if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Execution.Native.ExitCode -ne 0 -or $result.Error.Count){throw ('RealGitStatusFailed: '+($result.Error|ConvertTo-Json -Compress))}
            if($data.CompleteCalls -ne 1 -or $result.Execution.Children -ne 0 -or $result.Data.Stdout.Lines -lt 1){throw 'RealStatusCallbackInvariant'}
            $after=Invoke-StatusReference
            try{Assert-StatusSummary $reference $after}catch{throw 'RealRepositoryChangedDuringSample'}
            Assert-StatusSummary $result.Data $reference
            if((Get-Module FrenchExDev2.QuietCli.Git.PoSh) -or @(Get-QuietHandler).Count){throw 'GitModuleLoadedDuringRealStatus'}
            if(!$engine){$engine=Get-QuietEngine}
            $samples.Add(@{
                Iteration=$iteration;Kind=$(if($iteration){'WarmEngine'}else{'FirstCallWithColdEngine'})
                InvocationMs=$watch.Elapsed.TotalMilliseconds;ExecutionMs=$result.Execution.ElapsedMs
                NativeMs=$result.Execution.Native.ElapsedMs;CallbackMs=$result.Execution.CallbackMs
                ReferenceMs=$reference.ElapsedMs;StdoutBytes=$result.Execution.Native.StdoutBytesRead
                StderrBytes=$result.Execution.Native.StderrBytesRead;CompleteCalls=$data.CompleteCalls
                Business=$result.Data;Outcome=$result.Outcome;SourceComplete=$result.Completeness.Source;AnalysisComplete=$result.Completeness.Analysis
            })
            $reference=$after
        }finally{$data.stdout.Hash.Dispose();$data.stderr.Hash.Dispose()}
    }
    [pscustomobject]@{
        RepositoryPath=[IO.Path]::GetFullPath($RepositoryPath);Command=@($git,'status')
        CorePath=$module.Path;GitModuleLoaded=[bool](Get-Module FrenchExDev2.QuietCli.Git.PoSh)
        RegisteredHandlers=@(Get-QuietHandler).Count;CoreImportMs=$CoreImportMs
        Samples=$samples.ToArray();Engine=$engine;PowerShellVersion=$PSVersionTable.PSVersion.ToString()
        RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        Limits='Existing working tree, warm filesystem caches. No optional Git locks; no repository writes requested. References bracket every observed status; changing output fails the run. Human-readable output is compared as CR-normalized LF records without retention. Invocation timing includes Core startup/dispatch/telemetry; NativeMs is the engine-reported interval, not an independent process stopwatch. First call includes lazy engine startup; following calls reuse it.'
    }
}finally{Stop-QuietEngine}

}
