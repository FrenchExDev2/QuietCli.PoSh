function Get-QuietConfigurationSchema {
    <# .SYNOPSIS
    Defines configuration defaults and validation once.
    #>
    $homePath=[Environment]::GetFolderPath('UserProfile')
    return [ordered]@{
        'tokenization.tokenizer'=@{Default='o200k_base';Type='enum';Values=@('off','o200k_base','cl100k_base')}
        'delivery.maxOutputBytes'=@{Default=4096;Type='integer';Min=256;Max=[int]::MaxValue}
        'delivery.maxItems'=@{Default=20;Type='integer';Min=0;Max=[int]::MaxValue}
        'delivery.maxTrackedRepresentations'=@{Default=256;Type='integer';Min=1;Max=65536}
        'execution.timeoutSeconds'=@{Default=600.0;Type='number';Min=0.001;Max=4294967.294}
        'execution.drainTimeoutSeconds'=@{Default=30.0;Type='number';Min=0.05;Max=300}
        'telemetry.enabled'=@{Default=$true;Type='boolean'}
        'telemetry.database'=@{Default=[IO.Path]::Combine($homePath,'.quietcli2','gains.sqlite');Type='path'}
        'engine.hosting'=@{Default='Auto';Type='enum';Values=@('Auto','Process','InProcess')}
        'engine.ipcTimeoutSeconds'=@{Default=30.0;Type='number';Min=0.05;Max=300}
        'streams.transport'=@{Default='Pipe';Type='enum';Values=@('Pipe','Pty')}
        'streams.stdoutMode'=@{Default='Text';Type='enum';Values=@('Text','Bytes')}
        'streams.stderrMode'=@{Default='Text';Type='enum';Values=@('Text','Bytes')}
        'streams.maxRecordBytes'=@{Default=1048576;Type='integer';Min=1;Max=[int]::MaxValue}
        'streams.readBlockBytes'=@{Default=16384;Type='integer';Min=1024;Max=16384}
        'recall.maxBytes'=@{Default='16MiB';Type='recallSize'}
        'recall.policy'=@{Default='Head';Type='enum';Values=@('Head','Tail','HeadAndTail')}
        'recall.root'=@{Default=$null;Type='optionalPath'}
        'gain.maxEvents'=@{Default=10000;Type='integer';Min=1;Max=1000000}
    }
}
function Get-QuietConfigurationPath {
    <# .SYNOPSIS
    Selects the automatic config.yaml location using the sole configuration environment override.
    #>
    $directory=[Environment]::GetEnvironmentVariable('QUIETCLI_CONFIG_DIRECTORY')
    if([string]::IsNullOrWhiteSpace($directory)){$directory='~/.quietcli'}
    return [IO.Path]::Combine((Resolve-QuietConfigurationPath $directory),'config.yaml')
}
function Resolve-QuietConfigurationPath {
    <# .SYNOPSIS
    Resolves a literal path, expanding only the user-home prefix.
    .PARAMETER Path
    Literal path; no environment or expression interpolation.
    .PARAMETER BaseDirectory
    Directory for relative paths.
    #>
    param([string]$Path,[string]$BaseDirectory=(Get-Location).Path)
    if($Path -eq '~'){$Path=[Environment]::GetFolderPath('UserProfile')}
    elseif($Path.StartsWith('~/') -or $Path.StartsWith('~\')){$Path=[IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'),$Path.Substring(2))}
    return [IO.Path]::GetFullPath($Path,$BaseDirectory)
}
function ConvertTo-QuietConfigurationValue {
    <# .SYNOPSIS
    Validates a scalar against the shared configuration contract.
    .PARAMETER Value
    Typed YAML scalar or explicit environment value.
    .PARAMETER Rule
    Closed scalar rule.
    .PARAMETER BaseDirectory
    Source directory used for relative paths.
    #>
    param([AllowNull()]$Value,[hashtable]$Rule,[string]$BaseDirectory)
    switch($Rule.Type){
        'enum' {if($Value -isnot [string] -or $Value -cnotin $Rule.Values){throw 'InvalidConfigurationEnum'}}
        'boolean' {if($Value -isnot [bool]){throw 'InvalidConfigurationBoolean'}}
        {$_ -in @('integer','number')} {
            if($Value -isnot [ValueType] -or $Value -is [bool] -or ![double]::IsFinite([double]$Value) -or [double]$Value -lt $Rule.Min -or [double]$Value -gt $Rule.Max){throw 'InvalidConfigurationNumber'}
            if($Rule.Type -eq 'integer'){
                if($Value -isnot [long] -and $Value -isnot [int]){throw 'InvalidConfigurationInteger'}
                return [int]$Value
            }
            return [double]$Value
        }
        {$_ -in @('path','optionalPath')} {
            if($null -eq $Value -and $Rule.Type -eq 'optionalPath'){return $null}
            if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)){throw 'InvalidConfigurationPath'}
            return Resolve-QuietConfigurationPath $Value $BaseDirectory
        }
        'recallSize' {
            if($Value -isnot [string] -and $Value -isnot [long] -and $Value -isnot [int]){throw 'InvalidConfigurationRecallSize'}
            Import-QuietManagedEngine
            $null=[FrenchExDev2.QuietCli.RecallOptions]::ParseSize([string]$Value)
            return [string]$Value
        }
    }
    return $Value
}
function ConvertTo-QuietConfigurationObject {
    <# .SYNOPSIS
    Builds a detached public sectioned view from scalar configuration values.
    .PARAMETER Values
    Flattened closed configuration map.
    #>
    param([Collections.IDictionary]$Values)
    $sections=[ordered]@{schemaVersion=1}
    foreach($key in $Values.Keys){
        $section,$name=$key.Split('.',2)
        if(!$sections.Contains($section)){$sections[$section]=[ordered]@{}}
        $sections[$section][$name]=$Values[$key]
    }
    $public=[ordered]@{schemaVersion=1}
    foreach($section in $sections.Keys){if($section -ne 'schemaVersion'){$public[$section]=[pscustomobject]$sections[$section]}}
    return [pscustomobject]$public
}
function Test-QuietCliConfiguration {
    <# .SYNOPSIS
    Validates inert YAML without starting an engine or creating any file or database.
    .PARAMETER Path
    Configuration path, default ~/.quietcli/config.yaml.
    #>
    [CmdletBinding()]param([string]$Path=(Get-QuietConfigurationPath))
    $resolved=Resolve-QuietConfigurationPath $Path
    $schema=Get-QuietConfigurationSchema;$values=[ordered]@{};$origins=[ordered]@{}
    foreach($key in $schema.Keys){$values[$key]=$schema[$key].Default;$origins[$key]='Default'}
    $errors=[Collections.Generic.List[object]]::new()
    if([IO.File]::Exists($resolved)){
        try{
            Import-QuietManagedEngine
            Assert-QuietResources 'resources/yaml/YamlDotNet.dll'
            $document=[FrenchExDev2.QuietCli.ConfigurationYaml]::ReadAsync($resolved,[IO.Path]::Combine($script:QuietRoot,'resources/yaml/YamlDotNet.dll')).GetAwaiter().GetResult()
            if(!$document.ContainsKey('schemaVersion') -or $document['schemaVersion'].Value -isnot [long] -or $document['schemaVersion'].Value -ne 1){
                $versionNode=if($document.ContainsKey('schemaVersion')){$document['schemaVersion']}else{$null}
                $errors.Add([pscustomobject]@{Code='UnsupportedConfigurationVersion';Key='schemaVersion';Line=$(if($versionNode){$versionNode.Line}else{0});Column=$(if($versionNode){$versionNode.Column}else{0})})
            }
            foreach($section in $document.Keys){
                if($section -ceq 'schemaVersion'){continue}
                $node=$document[$section]
                if($section -cnotin @('tokenization','delivery','execution','telemetry','engine','streams','recall','gain') -or $node.Value -isnot [Collections.IDictionary]){
                    $errors.Add([pscustomobject]@{Code='UnknownOrInvalidConfigurationSection';Key=$section;Line=$node.Line;Column=$node.Column});continue
                }
                foreach($name in $node.Value.Keys){
                    $key=$section+'.'+$name;$leaf=$node.Value[$name]
                    try{
                        if($key -cnotin $schema.Keys){throw 'UnknownConfigurationKey'}
                        $values[$key]=ConvertTo-QuietConfigurationValue $leaf.Value $schema[$key] ([IO.Path]::GetDirectoryName($resolved))
                        $origins[$key]='Yaml'
                    }catch{$errors.Add([pscustomobject]@{Code=$_.Exception.Message;Key=$key;Line=$leaf.Line;Column=$leaf.Column})}
                }
            }
        }catch{
            $errorObject=$_.Exception
            while($errorObject.InnerException){$errorObject=$errorObject.InnerException}
            $code=$errorObject.Message;$key='';$line=0;$column=0
            if($errorObject.PSObject.Properties['Code']){$code=$errorObject.Code;$key=$errorObject.Key;$line=$errorObject.Line;$column=$errorObject.Column}
            $errors.Add([pscustomobject]@{Code=$code;Key=$key;Line=$line;Column=$column})
        }
    }elseif([IO.Directory]::Exists($resolved)){$errors.Add([pscustomobject]@{Code='ConfigurationPathIsDirectory';Key='';Line=0;Column=0})}
    return [pscustomobject]@{IsValid=($errors.Count -eq 0);Path=$resolved;Exists=[IO.File]::Exists($resolved);Errors=$errors.ToArray();Warnings=@();Configuration=(ConvertTo-QuietConfigurationObject $values);Values=$values;Origins=$origins}
}
function Import-QuietCliConfiguration {
    <# .SYNOPSIS
    Atomically replaces the session's YAML snapshot; never restarts an active engine.
    .PARAMETER Path
    YAML path, default ~/.quietcli/config.yaml.
    #>
    [CmdletBinding()]param([string]$Path=(Get-QuietConfigurationPath))
    $candidate=Test-QuietCliConfiguration -Path $Path
    if(!$candidate.IsValid){throw ('InvalidQuietConfiguration: '+($candidate.Errors|ConvertTo-Json -Depth 4 -Compress))}
    $effective=Get-QuietEffectiveConfiguration $candidate
    if($script:QuietEngine){
        $current=Get-QuietEffectiveConfiguration (Get-QuietConfigurationSnapshot)
        if($effective.Values['telemetry.database'] -ne $script:QuietEngine.Database -or $effective.Values['engine.hosting'] -ne $current.Values['engine.hosting']){throw 'ConfigurationEngineChangeRequiresStop-QuietEngine'}
    }
    $script:QuietConfiguration=$candidate
    return Get-QuietCliConfiguration
}
function Get-QuietConfigurationSnapshot {
    <# .SYNOPSIS
    Reads the YAML snapshot lazily, without import-time side effects.
    #>
    if(!$script:QuietConfiguration){
        $candidate=Test-QuietCliConfiguration
        if(!$candidate.IsValid){throw ('InvalidQuietConfiguration: '+($candidate.Errors|ConvertTo-Json -Depth 4 -Compress))}
        $script:QuietConfiguration=$candidate
    }
    return $script:QuietConfiguration
}
function Get-QuietEffectiveConfiguration {
    <# .SYNOPSIS
    Copies the stable YAML snapshot without environment setting overrides.
    .PARAMETER Snapshot
    Validated YAML snapshot.
    #>
    param($Snapshot)
    $values=[ordered]@{};$origins=[ordered]@{}
    foreach($key in $Snapshot.Values.Keys){
        $values[$key]=$Snapshot.Values[$key];$origins[$key]=$Snapshot.Origins[$key]

    }
    return [pscustomobject]@{Path=$Snapshot.Path;Values=$values;Origins=$origins}
}
function Get-QuietCliConfiguration {
    <# .SYNOPSIS
    Returns detached effective values and their origins without starting an engine.
    #>
    [CmdletBinding()]param()
    $effective=Get-QuietEffectiveConfiguration (Get-QuietConfigurationSnapshot)
    return [pscustomobject]@{Path=$effective.Path;Configuration=(ConvertTo-QuietConfigurationObject $effective.Values);Origins=[pscustomobject]$effective.Origins}
}
function Get-QuietSetting {
    <# .SYNOPSIS
    Resolves one effective setting using the shared precedence rules.
    .PARAMETER Name
    Closed section.key setting name.
    #>
    param([string]$Name)
    return (Get-QuietConfigurationSnapshot).Values[$Name]
}
function New-QuietCliConfiguration {
    <# .SYNOPSIS
    Explicitly creates a complete UTF-8/LF template; never overwrites without Force.
    .PARAMETER Path
    Destination YAML path.
    .PARAMETER Force
    Explicitly permits replacement of an existing file.
    #>
    [CmdletBinding(SupportsShouldProcess)]param([string]$Path=(Get-QuietConfigurationPath),[switch]$Force)
    $resolved=Resolve-QuietConfigurationPath $Path
    if([IO.File]::Exists($resolved) -and !$Force){throw 'ConfigurationFileExists'}
    $schema=Get-QuietConfigurationSchema;$lines=[Collections.Generic.List[string]]::new();$lines.Add('schemaVersion: 1');$section=''
    foreach($key in $schema.Keys){
        $group,$name=$key.Split('.',2)
        if($group -ne $section){$lines.Add($group+':');$section=$group}
        $scalar=ConvertTo-Json -InputObject $schema[$key].Default -Compress
        $lines.Add('  '+$name+': '+$scalar)
    }
    if($PSCmdlet.ShouldProcess($resolved,'Write QuietCli configuration')){
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolved))
        $mode=if($Force){[IO.FileMode]::Create}else{[IO.FileMode]::CreateNew}
        $stream=[IO.FileStream]::new($resolved,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=$script:QuietUtf8.GetBytes(($lines -join "`n")+"`n");[void]$stream.WriteAsync($bytes,0,$bytes.Length).GetAwaiter().GetResult()}finally{[void]$stream.DisposeAsync().GetAwaiter().GetResult()}
        Get-Item -LiteralPath $resolved
    }
}
