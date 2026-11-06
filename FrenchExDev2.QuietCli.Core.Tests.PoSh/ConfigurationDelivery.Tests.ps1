function Invoke-QuietConfigurationDeliveryTests {
    <#
    .SYNOPSIS
    Runs configuration, tokenizer and unique-delivery regressions with deterministic generated inputs.
    .PARAMETER WorkspaceRoot
    Built monorepo under test.
    .PARAMETER RunDirectory
    Owned report and fixture directory.
    .PARAMETER OnProgress
    Shared visible-monitor progress callback.
    .PARAMETER Mutation
    Includes owned C# source mutations after the functional baseline.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[scriptblock]$OnProgress,[switch]$Mutation)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    . (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
    $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    $cases=[Collections.Generic.List[object]]::new();$passed=0;$failed=0
    $directory=Join-Path $RunDirectory 'configuration-delivery';[void][IO.Directory]::CreateDirectory($directory)
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $snapshot=Get-QuietTestConfiguration
    $initialValues=[ordered]@{};foreach($key in $snapshot.Values.Keys){$initialValues[$key]=$snapshot.Values[$key]}
    $initialConfigDirectory=$env:QUIETCLI_CONFIG_DIRECTORY
    $checks=[ordered]@{}
    $checks['configuration validates without engine or filesystem side effects']={
        Stop-QuietEngine
        $missing=Join-Path $directory 'absent/config.yaml'
        $test=Test-QuietCliConfiguration -Path $missing
        if(!$test.IsValid -or $test.Exists -or (Test-Path (Split-Path $missing)) -or (& $core {$null -ne $script:QuietEngine})){throw 'MissingConfigurationSideEffect'}
        if($test.Configuration.tokenization.tokenizer -ne 'o200k_base' -or $test.Configuration.recall.maxBytes -ne '16MiB'){throw 'DefaultConfigurationChanged'}
        $template=Join-Path $directory 'template/config.yaml'
        $null=New-QuietCliConfiguration -Path $template
        $test=Test-QuietCliConfiguration -Path $template
        if(!$test.IsValid){throw ($test.Errors|ConvertTo-Json -Compress)}
        if([IO.File]::ReadAllText($template).Contains("`r")){throw 'ConfigurationTemplateNotLf'}
        $rejected=$false;try{$null=New-QuietCliConfiguration -Path $template}catch{$rejected=$_.Exception.Message -eq 'ConfigurationFileExists'}
        if(!$rejected){throw 'ConfigurationTemplateOverwritten'}
    }
    $checks['YAML schema rejects malformed keys, types and generated boundary values']={
        $path=Join-Path $directory 'invalid.yaml'
        $inputs=@('schemaVersion: 2',"schemaVersion: 1`ndelivery:`n  maxItems: -1", "schemaVersion: 1`nunknown: 1", "schemaVersion: 1`ntelemetry:`n  enabled: 'false'", "schemaVersion: 1`nstreams:`n  readBlockBytes: 16385", "schemaVersion: 1`nrecall:`n  maxBytes: 'invalid'", "schemaVersion: 1`ntokenization:`n  tokenizer: unknown", "schemaVersion: 1`ndelivery:`n  maxItems: 1`n  maxItems: 2")
        $random=[Random]::new(38179)
        foreach($index in 1..32){$inputs+="schemaVersion: 1`ndelivery:`n  maxOutputBytes: $($random.Next(-10000,256))"}
        foreach($input in $inputs){[void][IO.File]::WriteAllTextAsync($path,$input,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult();$test=Test-QuietCliConfiguration -Path $path;if($test.IsValid -or $test.Errors.Count -eq 0){throw 'InvalidConfigurationAccepted'}}
        [void][IO.File]::WriteAllTextAsync($path,"schemaVersion: 1`ndelivery:`n  typo: 3`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $test=Test-QuietCliConfiguration -Path $path
        if($test.Errors[0].Key -ne 'delivery.typo' -or $test.Errors[0].Line -lt 1){throw 'ConfigurationDiagnosticLostKeyOrLine'}
        [void][IO.File]::WriteAllTextAsync($path,"schemaVersion: 99`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $test=Test-QuietCliConfiguration -Path $path
        if($test.IsValid -or $test.Errors[0].Key -ne 'schemaVersion' -or $test.Errors[0].Line -lt 1){throw 'ConfigurationVersionDiagnosticLostLocation'}
    }
    $checks['configuration snapshots reload atomically and ignore legacy environment settings']={
        Stop-QuietEngine
        $path=Join-Path $directory 'snapshot/config.yaml';[void][IO.Directory]::CreateDirectory((Split-Path $path))
        $body="schemaVersion: 1`ntokenization:`n  tokenizer: cl100k_base`ndelivery:`n  maxItems: 3`ntelemetry:`n  database: local.sqlite`n"
        [void][IO.File]::WriteAllTextAsync($path,$body,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $oldTokenizer=$env:QUIETCLI_TOKENIZER;$oldDatabase=$env:QUIETCLI_DATABASE;$oldMode=$env:QUIETCLI_ENGINE_MODE
        try{
            $env:QUIETCLI_TOKENIZER='off';$env:QUIETCLI_DATABASE='ignored.sqlite';$env:QUIETCLI_ENGINE_MODE='invalid'
            $loaded=Import-QuietCliConfiguration -Path $path
            if($loaded.Configuration.tokenization.tokenizer -ne 'cl100k_base' -or $loaded.Configuration.telemetry.database -ne (Join-Path (Split-Path $path) 'local.sqlite')){throw 'YamlPrecedenceOrRelativePathChanged'}
            [void][IO.File]::WriteAllTextAsync($path,$body.Replace('maxItems: 3','maxItems: 5'),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if((Get-QuietCliConfiguration).Configuration.delivery.maxItems -ne 3){throw 'ConfigurationReloadedImplicitly'}
            $null=Import-QuietCliConfiguration -Path $path
            if((Get-QuietCliConfiguration).Configuration.delivery.maxItems -ne 5){throw 'ExplicitReloadIgnored'}
            [void][IO.File]::WriteAllTextAsync($path,'schemaVersion: 99',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false;try{$null=Import-QuietCliConfiguration -Path $path}catch{$rejected=$true}
            if(!$rejected -or (Get-QuietCliConfiguration).Configuration.delivery.maxItems -ne 5){throw 'InvalidReloadReplacedSnapshot'}
            $detached=Get-QuietCliConfiguration;$detached.Configuration.delivery.maxItems=999
            if((Get-QuietCliConfiguration).Configuration.delivery.maxItems -ne 5){throw 'PublicConfigurationMutatedSnapshot'}
            $env:QUIETCLI_CONFIG_DIRECTORY=Split-Path $path
            if((Test-QuietCliConfiguration).Path -ne $path){throw 'ConfigDirectoryEnvironmentIgnored'}
        }finally{
            $env:QUIETCLI_TOKENIZER=$oldTokenizer;$env:QUIETCLI_DATABASE=$oldDatabase;$env:QUIETCLI_ENGINE_MODE=$oldMode
            & $core {param($saved)$script:QuietConfiguration=$saved} $snapshot
            $env:QUIETCLI_CONFIG_DIRECTORY=$initialConfigDirectory
        }
    }
    $checks['JSON and YAML count exact final Unicode text and deduplicate across tokenizers in both hosts']={
        foreach($mode in @('InProcess','Process')){
            Stop-QuietEngine;$snapshot.Values['engine.hosting']=$mode;$snapshot.Values['telemetry.enabled']=$true
            $context='unique-'+[guid]::NewGuid().ToString('N')
            $r=quiet -AsObject -C $context -Data ([ordered]@{Label='é漢字😀';Count=1}) -Output {param($e,$runtime)} $dotnet $fixture emit 8192
            if($r.Measurement.OutputTokens -ne $null -or $r.Deliveries.Count){throw 'AsObjectTokenizedData'}
            $text=ConvertTo-QuietJson $r
            if($r.Measurement.StorageError){throw $r.Measurement.StorageError}
            $id=$r.Deliveries[0].DeliveryId
            $counter=[Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding('o200k_base',$null,$null)
            if($r.Deliveries[0].AlreadyDelivered -or $r.Measurement.OutputTokens -ne $counter.CountTokens($text)){throw 'DefaultTokenCountOrFirstReceiptChanged'}
            $text2=Out-QuietResult $r -AsJson
            if($text2 -cne $text -or !$r.Deliveries[0].AlreadyDelivered -or $r.Deliveries[0].DeliveryId -ne $id){throw 'IdenticalJsonDuplicated'}
            $text3=ConvertTo-QuietJson $r -Tokenizer cl100k_base
            $other=[Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding('cl100k_base',$null,$null)
            if($text3 -cne $text -or $r.Measurement.OutputTokens -ne $other.CountTokens($text) -or $r.Deliveries[0].DeliveryId -ne $id){throw 'TokenizerDuplicatedRepresentation'}
            $null=ConvertTo-QuietJson $r -Tokenizer off
            if($null -ne $r.Measurement.OutputTokens -or !$r.Deliveries[0].AlreadyDelivered){throw 'DisabledTokenizerChangedIdentity'}
            $yaml=ConvertTo-QuietYaml $r
            if($r.Deliveries[0].DeliveryId -eq $id -or $r.Deliveries[0].AlreadyDelivered -or $r.Measurement.OutputTokens -ne $counter.CountTokens($yaml)){throw 'YamlIdentityOrTokensChanged'}
            $null=ConvertTo-QuietJson $r
            if($r.Deliveries[0].DeliveryId -ne $id -or !$r.Deliveries[0].AlreadyDelivered){throw 'PriorRepresentationLost'}
            $report=Get-QuietCliGain -C $context
            if($report.RootDeliveries -ne 2 -or $report.RootDeliveryBytes -ne ([Text.Encoding]::UTF8.GetByteCount($text)+[Text.Encoding]::UTF8.GetByteCount($yaml))){throw 'DeliveriesOrBytesDuplicated'}
            $profiles=@($report.DeliveredTokensByProfile)
            if($profiles.Count -ne 2 -or @($profiles|Where-Object TokenProfile -EQ o200k_base)[0].MeasuredDeliveries -ne 2 -or @($profiles|Where-Object TokenProfile -EQ cl100k_base)[0].UnmeasuredDeliveries -ne 1){throw 'ProfileCoverageChanged'}
            $null=Get-QuietCliGain -C $context -AsJson -Compress;$null=Get-QuietCliGain -C $context -AsYaml
            if((Get-QuietCliGain -C $context).RootDeliveries -ne 2){throw 'GainReportRecordedDelivery'}
            $path=Join-Path $directory ('engine-change-'+$mode+'.yaml')
            [void][IO.File]::WriteAllTextAsync($path,"schemaVersion: 1`ntelemetry:`n  database: another.sqlite`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false;try{$null=Import-QuietCliConfiguration -Path $path}catch{$rejected=$_.Exception.Message -match 'RequiresStop-QuietEngine'}
            if(!$rejected -or (Get-QuietEngine).Mode -ne $mode){throw 'ActiveEngineReconfigured'}
        }
    }
    $checks['generated representations preserve receipt bounds, truncation and object-only privacy']={
        Stop-QuietEngine;$snapshot.Values['engine.hosting']='InProcess';$snapshot.Values['telemetry.enabled']=$false;$snapshot.Values['delivery.maxTrackedRepresentations']=2
        $r=quiet -AsObject -Data ([ordered]@{Value=0;Long='漢字😀'*100}) -Output {param($e,$runtime)} $dotnet $fixture emit 1
        $first=ConvertTo-QuietJson $r -MaxOutputBytes 256
        if($r.Measurement.OutputTokens -ne [Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding('o200k_base',$null,$null).CountTokens($first)){throw 'TruncatedTextTokensChanged'}
        $null=ConvertTo-QuietJson $r -MaxOutputBytes 4096
        $r.Data.Value=2
        $rejected=$false;try{$null=ConvertTo-QuietJson $r -MaxOutputBytes 4096}catch{$rejected=$_.Exception.Message -eq 'DeliveryRepresentationLimit'}
        if(!$rejected -or $r.Internal.DeliveryReceipts.Count -ne 2){throw 'ReceiptBudgetNotEnforced'}
        $r.Data.Value=0;$again=ConvertTo-QuietJson $r -MaxOutputBytes 256
        if($again -cne $first -or !$r.Deliveries[0].AlreadyDelivered){throw 'ReceiptHistoryLost'}
        $data=[pscustomobject]@{Value=1};$data|Add-Member ScriptProperty Forbidden {throw 'AsObjectInspectedBusinessData'}
        $object=quiet -AsObject -Data $data -Output {param($e,$runtime)} $dotnet $fixture emit 1
        if($object.Measurement.OutputTokens -ne $null -or $object.Deliveries.Count){throw 'ObjectOnlyTokensInvented'}
    }
    $checks['storage failures retry the same receipt and offline conversions remain local']={
        $snapshot.Values['delivery.maxTrackedRepresentations']=256;$snapshot.Values['telemetry.enabled']=$true
        $r=quiet -AsObject -C ('retry-'+[guid]::NewGuid().ToString('N')) -Data @{Value=1} -Output {param($e,$runtime)} $dotnet $fixture emit 1
        & $core {
            param($result)
            $send=${function:Send-QuietRequest}
            try{
                function Send-QuietRequest {
                    <#
                    .SYNOPSIS
                    Injects a delivery-write failure while preserving other engine requests.
                    .PARAMETER Header
                    Closed engine control metadata.
                    #>
                    param($Header)
                    if($Header.Action -eq 'save'){throw 'InjectedStorageFailure'}
                    & $send $Header
                }
                $null=Out-QuietResult $result
                if($result.Measurement.Status -ne 'StorageUnavailable'){throw 'StorageFailureHidden'}
            }finally{${function:Send-QuietRequest}=$send}
        } $r
        $id=$r.Deliveries[0].DeliveryId;$null=ConvertTo-QuietJson $r
        if($r.Measurement.StorageError -or $r.Deliveries[0].DeliveryId -ne $id -or !$r.Deliveries[0].AlreadyDelivered -or (Get-QuietCliGain -C $r.Context).RootDeliveries -ne 1){throw 'StorageRetryDuplicatedOrLostDelivery'}
        $captured=quiet -Recall -AsObject -RecallMaxBytes 64 -Output {} $dotnet $fixture emit 16
        $offline=Invoke-QuietRecall $captured -Output {param($e,$runtime)} -Complete {param($runtime)[pscustomobject]@{Local=$true}}
        $null=ConvertTo-QuietYaml $offline;$id=$offline.Deliveries[0].DeliveryId;$null=ConvertTo-QuietYaml $offline
        if(!$offline.Deliveries[0].AlreadyDelivered -or $offline.Deliveries[0].DeliveryId -ne $id -or $offline.Measurement.OutputTokens -lt 1){throw 'OfflineReceiptChanged'}
    }
    try{
        foreach($entry in $checks.GetEnumerator()){
            if($OnProgress){& $OnProgress $entry.Key 'Running' $passed $failed}
            try{$null=& $entry.Value;$passed++;$cases.Add(@{Name=$entry.Key;State='Passed'})}
            catch{$failed++;$cases.Add(@{Name=$entry.Key;State='Failed';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace})}
            if($OnProgress){& $OnProgress $entry.Key 'Completed' $passed $failed}
        }
        . (Join-Path $PSScriptRoot 'ConfigurationDelivery.Mutation.ps1')
        $compiled=Invoke-QuietConfigurationDeliveryEngine -WorkspaceRoot $WorkspaceRoot -RunDirectory $directory -Mutation:$Mutation -OnProgress $OnProgress
        $passed+=$compiled.Passed;$failed+=$compiled.Failed
        $summary=[pscustomobject]@{Passed=$passed;Failed=$failed;Cases=$cases.ToArray();Compiled=$compiled;Seeds=@(38179,47291);GeneratedYamlCases=104;FuzzCorpusCases=10}
        Write-WorkspaceJson (Join-Path $directory 'results.json') $summary
        return $summary
    }finally{
        Stop-QuietEngine
        foreach($key in $initialValues.Keys){$snapshot.Values[$key]=$initialValues[$key]}
        & $core {param($saved)$script:QuietConfiguration=$saved} $snapshot
        $env:QUIETCLI_CONFIG_DIRECTORY=$initialConfigDirectory
    }
}
