# Objective: Run pure PTY decoders under coverage-guided libFuzzer, ASan and UBSan.
function Invoke-PtyFuzz {
    <#
    .SYNOPSIS
    Compiles a pure decoder target and requires the requested libFuzzer execution count.
    .PARAMETER WorkspaceRoot
    QuietCli2 monorepo root.
    .PARAMETER RunDirectory
    Owned evidence directory for the target, corpus, diagnostics and crash reproducers.
    .PARAMETER Runs
    Required execution budget, including the initial corpus.
    .PARAMETER Seed
    Explicit reproducible PRNG seed.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[ValidateRange(1000,10000000)][int]$Runs=20000,[uint32]$Seed=633419)
    if(!$IsLinux){throw 'Native fuzz qualification requires the Linux CI image.'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $corpus=Join-Path $RunDirectory corpus;[void][IO.Directory]::CreateDirectory($corpus)
    $crashes=Join-Path $RunDirectory crashes;[void][IO.Directory]::CreateDirectory($crashes)
    $source=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-fuzz.c'
    $compiler=(Get-Command clang -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $version=Invoke-PtyOperation $compiler @('--version')
    if($version.Outcome -ne 'Success'){throw 'FuzzCompilerVersionUnavailable'}
    $help=Invoke-PtyOperation $compiler @('--help')
    if($help.Outcome -ne 'Success'){throw 'FuzzCompilerHelpUnavailable'}
    $runtime=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $resourceDirectory=$env:QUIETCLI_PTY_LLVM_RESOURCE_DIR
    $runtimeSource=$null
    if($resourceDirectory){
        $resourceDirectory=[IO.Path]::GetFullPath($resourceDirectory)
        $manifestPath=Join-Path $resourceDirectory build.json
        if(!(Test-Path -LiteralPath $manifestPath)){throw 'LLVMRuntimeManifestMissing'}
        $manifest=[IO.File]::ReadAllTextAsync($manifestPath,[Text.Encoding]::UTF8).GetAwaiter().GetResult()|ConvertFrom-Json
        if($manifest.State -cne 'Success' -or $manifest.SourceCommit -notmatch '^[a-f0-9]{40}$' -or $manifest.RuntimeIdentifier -cne $runtime){throw 'LLVMRuntimeManifestMismatch'}
        $verified=[Collections.Generic.List[object]]::new()
        foreach($name in @('fuzzer','asan','asan_cxx','asan_static','ubsan_standalone')){
            $relative='lib/'+$manifest.Target+'/libclang_rt.'+$name+'.a'
            $entries=@($manifest.Files|Where-Object Path -CEQ $relative)
            $path=[IO.Path]::GetFullPath((Join-Path $resourceDirectory $relative))
            if(!$path.StartsWith($resourceDirectory.TrimEnd('/')+'/',[StringComparison]::Ordinal) -or $entries.Count -ne 1 -or !(Test-Path -LiteralPath $path)){throw 'LLVMRuntimeArtifactMissing'}
            $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if($hash -cne $entries[0].SHA256){throw 'LLVMRuntimeArtifactHashMismatch'}
            $verified.Add(@{Path=$relative;SHA256=$hash})
        }
        $runtimeSource=@{SourceCommit=$manifest.SourceCommit;SourceBranch=$manifest.SourceBranch;Target=$manifest.Target;ResourceDirectory=$resourceDirectory;ManifestSHA256=(Get-FileHash $manifestPath).Hash;VerifiedArtifacts=@($verified)}
    }
    $versionMatch=[regex]::Match([string]::Join("`n",$version.Diagnostics),'\bclang version ([0-9]+)')
    $clangMajor=if($versionMatch.Success){[int]$versionMatch.Groups[1].Value}else{$null}
    # Legacy ASan 14 can crash before main with high-entropy PIE placement.
    # Only this test executable uses a fixed address; shipped bridges stay PIE.
    $fixedAddress=$runtime -ceq 'linux-x64' -and $clangMajor -eq 14 -and !$resourceDirectory
    $binary=Join-Path $RunDirectory pty-fuzz
    $arguments=@('-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fno-omit-frame-pointer','-fno-sanitize-recover=all','-fsanitize=fuzzer,address,undefined','-pthread',$source,'-lutil','-o',$binary)
    if($resourceDirectory){$arguments=@('-resource-dir='+$resourceDirectory)+$arguments}
    if($fixedAddress){$arguments=@('-fno-pie','-no-pie')+$arguments}
    $compile=Invoke-PtyOperation $compiler $arguments -TimeoutSeconds 180
    Write-WorkspaceJson (Join-Path $RunDirectory compiler.json) @{Version=$version;Arguments=$arguments;Result=$compile}
    if($compile.Outcome -ne 'Success'){throw 'FuzzTargetCompilationFailed; see fuzz/compiler.json'}
    $header=[byte[]]::new(18);$stream=[IO.File]::OpenRead($binary)
    try{$read=$stream.ReadAsync($header,0,$header.Length).GetAwaiter().GetResult()}finally{$stream.Dispose()}
    if($read -ne 18 -or $header[0] -ne 127 -or $header[1] -ne 69 -or $header[2] -ne 76 -or $header[3] -ne 70){throw 'FuzzTargetElfHeaderInvalid'}
    $elfType=[BitConverter]::ToUInt16($header,16)
    if($fixedAddress -and $elfType -ne 2){throw 'FuzzTargetFixedAddressLayoutUnconfirmed'}
    $seeds=@{
        'dimension-one'=[Text.Encoding]::UTF8.GetBytes('1')
        'dimension-max'=[Text.Encoding]::UTF8.GetBytes('1000')
        'dimension-zero'=[Text.Encoding]::UTF8.GetBytes('0')
        'dimension-leading-zeros'=[Text.Encoding]::UTF8.GetBytes('000001')
        'dimension-overflow'=[Text.Encoding]::UTF8.GetBytes(('9'*256))
        'dimension-invalid'=[Text.Encoding]::UTF8.GetBytes("-1x`n")
        'resize-min'=[byte[]]@(1,0,1,0,1)
        'resize-max'=[byte[]]@(1,3,232,3,232)
        'resize-zero'=[byte[]]@(1,0,0,0,1)
        'resize-overflow'=[byte[]]@(1,3,233,0,1)
        'resize-truncated'=[byte[]]@(1,0,80,0)
        'resize-overlong'=[byte[]]@(1,0,80,0,24,0)
        'resize-unknown'=[byte[]]@(255,0,80,0,24)
    }
    foreach($item in $seeds.GetEnumerator()){[void][IO.File]::WriteAllBytesAsync((Join-Path $corpus $item.Key),$item.Value).GetAwaiter().GetResult()}
    $externalLimit=0L
    foreach($path in @('/sys/fs/cgroup/memory.max','/sys/fs/cgroup/memory/memory.limit_in_bytes')){
        if(Test-Path -LiteralPath $path){
            $text=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Trim()
            $value=0L
            if([long]::TryParse($text,[ref]$value) -and $value -gt 0 -and (!$externalLimit -or $value -lt $externalLimit)){$externalLimit=$value}
        }
    }
    $musl=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier -like 'linux-musl-*'
    if($musl -and (!$externalLimit -or $externalLimit -gt 1073741824)){throw 'MuslFuzzRequiresExternalMemoryLimitOfAtMost1GiB'}
    # LLVM 22's RSS-monitor allocation leaks on musl; retain LSan and enforce the cgroup instead.
    $rss=if($musl){0}else{512}
    $fuzzerArguments=@("-runs=$Runs","-seed=$Seed",'-max_len=4096','-timeout=2',"-rss_limit_mb=$rss",'-malloc_limit_mb=512','-detect_leaks=1','-print_final_stats=1',('-artifact_prefix='+$crashes+'/'),$corpus)
    $execution=Invoke-PtyOperation $binary $fuzzerArguments -TimeoutSeconds 180
    $count=$null
    foreach($line in $execution.Diagnostics){if($line -match '^stat::number_of_executed_units:\s*(\d+)'){$count=[long]$Matches[1]}}
    $report=@{State=$(if($execution.Outcome -eq 'Success' -and $count -ge $Runs){'Success'}else{'Failed'});RequestedRuns=$Runs;ExecutedRuns=$count;Seed=$Seed;FixedAddressCompatibility=$fixedAddress;TargetElfType=$elfType;CompilerMajor=$clangMajor;RuntimeSource=$runtimeSource;Sanitizers=@('address','undefined');LeakDetection='Enabled';RssMonitorMB=$rss;ExternalMemoryLimitBytes=$externalLimit;Scope='Pure dimension and resize decoders only';Compiler=$version;Arguments=$fuzzerArguments;Execution=$execution;TargetSHA256=(Get-FileHash $source -Algorithm SHA256).Hash;Corpus=@(Get-ChildItem $corpus -File|ForEach-Object {@{Name=$_.Name;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})}
    Write-WorkspaceJson (Join-Path $RunDirectory report.json) $report
    return $report
}
