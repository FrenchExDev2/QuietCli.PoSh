function Invoke-QuietConfigurationDeliveryEngine {
    <#
    .SYNOPSIS
    Executes the compiled baseline and bounded source mutants using owned source copies.
    .PARAMETER WorkspaceRoot
    Built monorepo.
    .PARAMETER RunDirectory
    Owned output directory.
    .PARAMETER Mutation
    Enables the targeted source catalogue.
    .PARAMETER OnProgress
    Shared visible-monitor callback.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[switch]$Mutation,[scriptblock]$OnProgress)
    $native=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
    $yaml=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    $runCases={
        param($assembly)
        $capture=@{Report=$null}
        $execution=Invoke-CiProcess -FilePath dotnet -ArgumentList @($assembly,$native,'--configuration-delivery-only',$yaml) -TimeoutSeconds 60 -State $capture -OnOutput {
            param($line,$state)
            if($line.Stream -eq 'stdout' -and $line.Text.StartsWith('{"Passed":')){$state.Report=$line.Text|ConvertFrom-Json}
        }
        if(!$capture.Report -or $execution.Outcome -eq 'Timeout'){throw 'ConfigurationDeliveryEngineCrashedOrTimedOut'}
        return [pscustomobject]@{Execution=$execution;Report=$capture.Report}
    }
    $baseline=& $runCases (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests/QuietCli.Engine.Tests.dll')
    Write-WorkspaceJson (Join-Path $RunDirectory 'compiled-baseline.json') $baseline
    if($baseline.Execution.Outcome -ne 'Success' -or $baseline.Report.Failed){throw 'ConfigurationDeliveryEngineBaselineFailed'}
    $outcomes=[Collections.Generic.List[object]]::new();$passed=$baseline.Report.Passed;$failed=0
    if($Mutation){
        $catalogue=@(
            @{Name='yaml-size-limit';File='ConfigurationYaml.cs';From='if (count > 65536)';To='if (false)'},
            @{Name='yaml-inert-tags';File='ConfigurationYaml.cs';From='if (value != null && value.GetType().GetProperty("IsEmpty")?.GetValue(value) is false)';To='if (false)'},
            @{Name='delivery-initial-profile';File='MeasurementStore.cs';From='ON CONFLICT(id) DO NOTHING';To='ON CONFLICT(id) DO UPDATE SET payload=excluded.payload'},
            @{Name='token-conflict-transaction';File='MeasurementStore.cs';From='if ((long)stored["output_tokens"] != token.OutputTokens)';To='if (false)'}
        )
        foreach($mutant in $catalogue){
            if($OnProgress){& $OnProgress ('C# mutation: '+$mutant.Name) 'Running' $passed $failed}
            $directory=Join-Path $RunDirectory ('mutations/'+$mutant.Name)
            [void][IO.Directory]::CreateDirectory($directory)
            foreach($relative in @('FrenchExDev2.QuietCli.Core.PoSh/engine','FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests','FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools')){
                foreach($file in Get-QuietSourceFiles (Join-Path $WorkspaceRoot $relative)){
                    $destination=Join-Path $directory ($relative+'/'+$file.Path)
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                    [IO.File]::Copy((Join-Path $WorkspaceRoot ($relative+'/'+$file.Path)),$destination)
                }
            }
            foreach($relative in @('global.json','FrenchExDev2.QuietCli.Core.PoSh/protocol.json')){[IO.File]::Copy((Join-Path $WorkspaceRoot $relative),(Join-Path $directory $relative))}
            $path=Join-Path $directory ('FrenchExDev2.QuietCli.Core.PoSh/engine/'+$mutant.File)
            $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw ('ConfigurationDeliveryMutationAnchorInvalid: '+$mutant.Name)}
            [void][IO.File]::WriteAllTextAsync($path,$source.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $build=Invoke-CiProcess -FilePath dotnet -ArgumentList @('build',(Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj'),'-f','net11.0','-c','Release','-o',(Join-Path $directory 'out'),'--nologo') -WorkingDirectory $directory -TimeoutSeconds 120
            if($build.Outcome -ne 'Success'){throw ('InvalidConfigurationDeliveryMutant: '+$mutant.Name)}
            $run=& $runCases (Join-Path $directory 'out/QuietCli.Engine.Tests.dll')
            $outcome=if($run.Execution.Outcome -eq 'Failed' -and $run.Report.Failed -gt 0){'Killed'}elseif($run.Execution.Outcome -eq 'Success' -and !$run.Report.Failed){'Survived'}else{'InfrastructureFailure'}
            $result=@{Name=$mutant.Name;State=$outcome;Run=$run;SourceSHA256=(Get-FileHash $path -Algorithm SHA256).Hash}
            Write-WorkspaceJson (Join-Path $directory 'result.json') $result;$outcomes.Add($result)
            if($outcome -eq 'Killed'){$passed++}else{$failed++}
        }
        $psMutations=& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
            param($dotnet,$fixture)
            $original=${function:Out-QuietResult};$validator=${function:ConvertTo-QuietConfigurationValue};$savedTracking=Get-QuietSetting 'telemetry.enabled'
            (Get-QuietConfigurationSnapshot).Values['telemetry.enabled']=$false
            $check={
                $result=quiet -AsObject -Data @{Label='é漢字😀'} -Output {param($e,$r)} $dotnet $fixture emit 1
                $text=Out-QuietResult $result
                $id=$result.Deliveries[0].DeliveryId
                $expected=[Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding('o200k_base',$null,$null).CountTokens($text)
                if($result.Measurement.OutputTokens -ne $expected){throw 'ExactDeliveryTokensInvariant'}
                $null=Out-QuietResult $result
                if(!$result.Deliveries[0].AlreadyDelivered -or $result.Deliveries[0].DeliveryId -ne $id){throw 'UniqueDeliveryReceiptInvariant'}
            }
            try{
                & $check
                $mutations=@(
                    @('ps-receipt-dedup','$alreadyDelivered=$receipts.ContainsKey($fingerprint)','$alreadyDelivered=$false'),
                    @('ps-token-count','[long]$script:QuietTokenizers[$Tokenizer].CountTokens($text)','0L')
                )
                foreach($mutation in $mutations){
                    if(!$original.ToString().Contains($mutation[1])){throw 'PowerShellDeliveryMutationAnchorInvalid'}
                    ${function:Out-QuietResult}=[scriptblock]::Create($original.ToString().Replace($mutation[1],$mutation[2]))
                    $killed=$false
                    try{& $check}catch{if($_.Exception.Message -in @('ExactDeliveryTokensInvariant','UniqueDeliveryReceiptInvariant')){$killed=$true}else{throw}}
                    ${function:Out-QuietResult}=$original
                    [pscustomobject]@{Name=$mutation[0];State=$(if($killed){'Killed'}else{'Survived'})}
                }
                $rangeCheck={
                    $rejected=$false
                    try{$null=ConvertTo-QuietConfigurationValue -Value (-1L) -Rule (Get-QuietConfigurationSchema)['delivery.maxItems'] -BaseDirectory ([IO.Path]::GetTempPath())}
                    catch{if($_.Exception.Message -eq 'InvalidConfigurationNumber'){$rejected=$true}else{throw}}
                    if(!$rejected){throw 'NonnegativeConfigurationBudgetInvariant'}
                }
                & $rangeCheck
                if(!$validator.ToString().Contains('[double]$Value -lt $Rule.Min')){throw 'ConfigurationValidatorMutationAnchorInvalid'}
                ${function:ConvertTo-QuietConfigurationValue}=[scriptblock]::Create($validator.ToString().Replace('[double]$Value -lt $Rule.Min','$false'))
                $killed=$false
                try{& $rangeCheck}catch{if($_.Exception.Message -eq 'NonnegativeConfigurationBudgetInvariant'){$killed=$true}else{throw}}
                [pscustomobject]@{Name='ps-configuration-budget-range';State=$(if($killed){'Killed'}else{'Survived'})}
            }finally{${function:Out-QuietResult}=$original;${function:ConvertTo-QuietConfigurationValue}=$validator;(Get-QuietConfigurationSnapshot).Values['telemetry.enabled']=$savedTracking}
        } (Get-Command dotnet -CommandType Application|Select-Object -First 1).Source (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll')
        foreach($result in $psMutations){$outcomes.Add($result);if($result.State -eq 'Killed'){$passed++}else{$failed++}}
    }
    return [pscustomobject]@{Passed=$passed;Failed=$failed;Baseline=$baseline.Report;Mutations=$outcomes.ToArray()}
}
