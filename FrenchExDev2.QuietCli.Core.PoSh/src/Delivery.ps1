function Get-QuietProjection {
    <#
.SYNOPSIS
Builds only a bounded delivery view; never called by AsObject.
    .PARAMETER Value
    Business value to present.
    .PARAMETER State
    Omission counters shared by the delivery.
    .PARAMETER MaxItems
    Maximum collection entries per container.
    .PARAMETER MaxCharacters
    Maximum characters per string.
    .PARAMETER Depth
    Remaining structural depth.
    #>
    param([AllowNull()]$Value,[hashtable]$State,[int]$MaxItems,[int]$MaxCharacters,[int]$Depth=24)
    if($null -eq $Value){return $null}
    $State.Nodes++
    if($Depth -le 0 -or $State.Nodes -gt 512){$State.Omitted++;$State.UnknownOmissions=$true;return '[StructureLimit]'}
    if($Value -is [string]){if($Value.Length -gt $MaxCharacters){$State.Omitted++;$limit=$MaxCharacters;if($limit -gt 0 -and [char]::IsHighSurrogate($Value[$limit-1])){$limit--};return $Value.Substring(0,$limit)+'…'};return $Value}
    if($Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $copy=[ordered]@{};$count=0
        foreach($key in $Value.Keys){if($count++ -ge $MaxItems){$State.Omitted+=$Value.Count-$MaxItems;break};$copy[[string]$key]=Get-QuietProjection $Value[$key] $State $MaxItems $MaxCharacters ($Depth-1)}
        return $copy
    }
    if($Value -is [Collections.IEnumerable]){
        $copy=[Collections.Generic.List[object]]::new();$count=0
        foreach($item in $Value){if($count++ -ge $MaxItems){if($Value -is [Collections.ICollection]){$State.Omitted+=$Value.Count-$MaxItems}else{$State.Omitted++;$State.UnknownOmissions=$true};break};$copy.Add((Get-QuietProjection $item $State $MaxItems $MaxCharacters ($Depth-1)))}
        return ,$copy.ToArray()
    }
    $copy=[ordered]@{};$count=0
    foreach($property in $Value.PSObject.Properties){if($count++ -ge $MaxItems){$State.Omitted++;continue};$copy[$property.Name]=Get-QuietProjection $property.Value $State $MaxItems $MaxCharacters ($Depth-1)}
    return $copy
}
function ConvertTo-QuietYamlValue {
    <#
.SYNOPSIS
Emits YAML directly, without an intermediate JSON document.
    .PARAMETER Value
    Normalized bounded delivery graph.
    .PARAMETER Indent
    Current indentation.
    #>
    param([AllowNull()]$Value,[int]$Indent=0)
    Import-QuietManagedEngine
    Assert-QuietResources 'resources/yaml/YamlDotNet.dll'
    return [FrenchExDev2.QuietCli.BoundedYaml]::Render($Value,$script:QuietRoot,$Indent,[Func[object,string]]{param($scalar)ConvertTo-Json -InputObject $scalar -Depth 4 -Compress})
}
function Out-QuietResult {
    <#
.SYNOPSIS
Produces and measures one actual bounded delivery; no whole-result serialization.
    .PARAMETER InputObject
    Local QuietCli2 result.
    .PARAMETER AsJson
    Selects JSON, the default.
    .PARAMETER AsYaml
    Selects YAML directly.
    .PARAMETER MaxItems
    Maximum presented entries per container.
    .PARAMETER MaxOutputBytes
    Final encoded envelope budget, at least 256 bytes.
    .PARAMETER Tokenizer
    off, o200k_base or cl100k_base; only actual delivery text is counted.
    #>
    [CmdletBinding()]param([Parameter(Mandatory,ValueFromPipeline)]$InputObject,[switch]$AsJson,[switch]$AsYaml,[int]$MaxItems=20,[int]$MaxOutputBytes=4096,[ValidateSet('off','o200k_base','cl100k_base')][string]$Tokenizer='off')
    process{
        if($AsJson -and $AsYaml){throw 'OutputFormatsAreExclusive'}
        if($MaxOutputBytes -lt 256 -or $MaxItems -lt 0){throw 'InvalidDeliveryBudget'}
        $watch=[Diagnostics.Stopwatch]::StartNew();$state=@{Omitted=0L;UnknownOmissions=$false;Nodes=0};$business=$InputObject.Data
        if($InputObject.Internal.Request.ContainsKey('Projection')){$business=& $InputObject.Internal.Request.Projection $business @{MaxItems=$MaxItems;MaxOutputBytes=$MaxOutputBytes}}
        $view=Get-QuietProjection $business $state $MaxItems ([Math]::Min(2048,$MaxOutputBytes))
        $safeError=Get-QuietProjection $InputObject.Error $state $MaxItems 256
        $document=[ordered]@{SchemaVersion=1;Outcome=$InputObject.Outcome;InvocationId=$InputObject.InvocationId;Context=$InputObject.Context;Data=$view;Completeness=$InputObject.Completeness;Error=$safeError;Truncation=@{Applied=($state.Omitted -gt 0);Omitted=$state.Omitted;OmittedExact=(!$state.UnknownOmissions)}}
        if($AsYaml){$document.Completeness=@{Source=$InputObject.Completeness.Source;Analysis=$InputObject.Completeness.Analysis};$text=ConvertTo-QuietYamlValue $document}
        else{$text=ConvertTo-Json -InputObject $document -Depth 48 -Compress}
        $size=$script:QuietUtf8.GetByteCount($text)
        if($size -gt $MaxOutputBytes){
            $document=[ordered]@{SchemaVersion=1;Outcome=$InputObject.Outcome;Data=$null;Completeness=@{Source=$InputObject.Completeness.Source;Analysis=$InputObject.Completeness.Analysis};Truncation=@{Applied=$true;Reason='OutputBudget'}}
            if($InputObject.Error){$first=@($InputObject.Error)[0];$code=[string]$first.Code;if($code.Length -gt 64){$code=$code.Substring(0,64)};$document.Error=@{Code=$code}}
            $text=if($AsYaml){ConvertTo-QuietYamlValue $document}else{ConvertTo-Json -InputObject $document -Depth 8 -Compress};$size=$script:QuietUtf8.GetByteCount($text)
        }
        if($size -gt $MaxOutputBytes){throw 'OutputBudgetTooSmall'}
        $serializationMs=$watch.Elapsed.TotalMilliseconds
        $tokens=$null;$tokenVersion=$null
        if($Tokenizer -ne 'off'){
            foreach($name in @('Microsoft.Bcl.Memory','Microsoft.ML.Tokenizers','Microsoft.ML.Tokenizers.Data.O200kBase','Microsoft.ML.Tokenizers.Data.Cl100kBase')){Assert-QuietResources "resources/tokenizers/$name.dll";[void][Reflection.Assembly]::LoadFrom((Join-Path $script:QuietRoot "resources/tokenizers/$name.dll"))}
            $counter=[Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding($Tokenizer,$null,$null)
            $tokens=$counter.CountTokens($text);$tokenVersion='Microsoft.ML.Tokenizers/'+[Microsoft.ML.Tokenizers.TiktokenTokenizer].Assembly.GetName().Version.ToString()
        }
        $deliveryId=[guid]::NewGuid().ToString('N')
        $InputObject.Deliveries.Clear()
        $InputObject.Deliveries.Add([pscustomobject]@{DeliveryId=$deliveryId;Format=$(if($AsYaml){'yaml'}else{'json'});Text=$text;Bytes=$size;Tokens=$tokens})
        $InputObject.Measurement.OutputBytes=$size;$InputObject.Measurement.OutputTokens=$tokens;$InputObject.Measurement.Status='Delivered'
        Import-QuietManagedEngine
        $InputObject.Measurement.ReductionBytes=[FrenchExDev2.QuietCli.MeasurementTelemetry]::Reduction($InputObject.Internal.Sources.Values,$InputObject.Completeness,$size,$script:QuietMetadataAdapter)
        if($env:QUIETCLI2_TRACKING -ne '0'){
            try{$metadata=Get-QuietMetadata $InputObject;$metadata.DeliveryId=$deliveryId;$metadata.OutputBytes=$size;$metadata.OutputTokens=$tokens;$metadata.TokenProfile=$Tokenizer;$metadata.TokenVersion=$tokenVersion;$metadata.Format=if($AsYaml){'yaml'}else{'json'};$metadata.Truncated=$document.Truncation.Applied;$metadata.SerializationMs=$serializationMs;$null=Send-QuietRequest @{Action='save';Kind='delivery';Metadata=$metadata}}
            catch{$InputObject.Measurement.StorageError=$_.Exception.Message;$InputObject.Measurement.Status='StorageUnavailable'}
        }
        return $text
    }
}
function ConvertTo-QuietJson {
    <#
.SYNOPSIS
Produces a JSON delivery from a local result, measuring only the produced text.
    .PARAMETER InputObject
    Local QuietCli2 result.
    .PARAMETER MaxItems
    Presented entries per container.
    .PARAMETER MaxOutputBytes
    Final UTF-8 byte budget.
    #>
    [CmdletBinding()]param([Parameter(Mandatory,ValueFromPipeline)]$InputObject,[int]$MaxItems=20,[int]$MaxOutputBytes=4096)
    process{Out-QuietResult -InputObject $InputObject -AsJson -MaxItems $MaxItems -MaxOutputBytes $MaxOutputBytes}
}
