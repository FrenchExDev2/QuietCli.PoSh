function ConvertTo-QuietSnapshot {
    <#
    .SYNOPSIS
    Copies execution metadata into read-only dictionaries and collections; never receives business Data.
    .PARAMETER Value
    Execution, completeness or diagnostic metadata.
    #>
    param([AllowNull()]$Value)
    if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $copy=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach($key in $Value.Keys){$copy.Add([string]$key,(ConvertTo-QuietSnapshot $Value[$key]))}
        return ,([Collections.ObjectModel.ReadOnlyDictionary[string,object]]::new($copy))
    }
    if($Value -is [Collections.IEnumerable]){
        $copy=[Collections.Generic.List[object]]::new()
        foreach($item in $Value){$copy.Add((ConvertTo-QuietSnapshot $item))}
        return ,$copy.AsReadOnly()
    }
    $copy=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($property in $Value.PSObject.Properties){$copy.Add($property.Name,(ConvertTo-QuietSnapshot $property.Value))}
    return ,([Collections.ObjectModel.ReadOnlyDictionary[string,object]]::new($copy))
}
function ConvertTo-QuietErrorCodes {
    <#
    .SYNOPSIS
    Removes exception messages from persisted diagnostics while preserving local errors.
    .PARAMETER Errors
    Caller-local structured errors.
    #>
    param([AllowNull()]$Errors)
    return ,@(foreach($error in $Errors){@{Code=[string]$error.Code;Phase=[string]$error.Phase}})
}
function Set-QuietFinalProperty {
    <#
    .SYNOPSIS
    Installs a getter-only final metadata property without retaining the invocation runtime in its closure.
    .PARAMETER Target
    Local result envelope.
    .PARAMETER Name
    Final metadata property.
    .PARAMETER Value
    Detached read-only snapshot; never business Data.
    #>
    param($Target,[string]$Name,$Value)
    $getter={$Value}.GetNewClosure()
    $Target.PSObject.Properties.Remove($Name)
    $Target|Add-Member -MemberType ScriptProperty -Name $Name -Value $getter
}
function Set-QuietLifecycle {
    <#
    .SYNOPSIS
    Validates a monotonic invocation lifecycle transition.
    .PARAMETER Runtime
    Active caller-local runtime.
    .PARAMETER Next
    Next state; Finalized cannot transition again.
    #>
    param($Runtime,[ValidateSet('Running','Draining','Completing','Finalized')][string]$Next)
    $allowed=@{Created='Running';Running='Draining';Draining='Completing';Completing='Finalized'}
    if(!$allowed.ContainsKey($Runtime.Lifecycle) -or $allowed[$Runtime.Lifecycle] -cne $Next){throw "InvalidLifecycleTransition: $($Runtime.Lifecycle) -> $Next"}
    $Runtime.Lifecycle=$Next
}
function Invoke-QuietCallbackValue {
    <#
    .SYNOPSIS
    Enforces zero/one callback emissions and preserves a single array as one business value.
    .PARAMETER Callback
    Caller-owned callback, including its lexical scope.
    .PARAMETER Arguments
    Callback arguments.
    .PARAMETER NoOutput
    Requires zero emissions for streaming consumers.
    #>
    param([scriptblock]$Callback,[object[]]$Arguments,[switch]$NoOutput)
    $values=@(& $Callback @Arguments)
    if($values.Count -gt 1 -or $NoOutput -and $values.Count){throw 'CallbackUnexpectedOutput'}
    $result=[pscustomobject]@{HasValue=($values.Count -eq 1);Value=$null}
    if($result.HasValue){$result.Value=$values[0]}
    return $result
}
