function ConvertTo-QuietSnapshotBaseline {
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
        foreach($key in $Value.Keys){$copy.Add([string]$key,(ConvertTo-QuietSnapshotBaseline $Value[$key]))}
        return ,([Collections.ObjectModel.ReadOnlyDictionary[string,object]]::new($copy))
    }
    if($Value -is [Collections.IEnumerable]){
        $copy=[Collections.Generic.List[object]]::new()
        foreach($item in $Value){$copy.Add((ConvertTo-QuietSnapshotBaseline $item))}
        return ,$copy.AsReadOnly()
    }
    $copy=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($property in $Value.PSObject.Properties){$copy.Add($property.Name,(ConvertTo-QuietSnapshotBaseline $property.Value))}
    return ,([Collections.ObjectModel.ReadOnlyDictionary[string,object]]::new($copy))
}

function ConvertTo-QuietYamlValueBaseline {
    <#
.SYNOPSIS
Emits YAML directly, without an intermediate JSON document.
    .PARAMETER Value
    Normalized bounded delivery graph.
    .PARAMETER Indent
    Current indentation.
    #>
    param([AllowNull()]$Value,[int]$Indent=0)
    $pad=' '*$Indent
    if($null -eq $Value){return 'null'}
    if($Value -is [string] -or $Value -is [ValueType]){return ConvertTo-Json -InputObject $Value -Depth 4 -Compress}
    if($Value -is [Collections.IDictionary]){
        if(!$Value.Count){return '{}'}
        $lines=foreach($key in $Value.Keys){$child=$Value[$key];$name=ConvertTo-Json -InputObject ([string]$key) -Compress;$rendered=ConvertTo-QuietYamlValueBaseline $child ($Indent+2);if($child -is [Collections.IDictionary] -and $child.Count -or $child -is [array] -and $child.Count){$pad+$name+':'+"`n"+$rendered}else{$pad+$name+': '+$rendered}}
        return $lines -join "`n"
    }
    if($Value -is [array]){
        if(!$Value.Count){return '[]'}
        $lines=foreach($child in $Value){$rendered=ConvertTo-QuietYamlValueBaseline $child ($Indent+2);if($child -is [Collections.IDictionary] -and $child.Count -or $child -is [array] -and $child.Count){$pad+'-'+"`n"+$rendered}else{$pad+'- '+$rendered}}
        return $lines -join "`n"
    }
    throw 'UnsupportedYamlValue'
}

function Resolve-QuietHandlerBaseline {
    <#
.SYNOPSIS
Resolves a versioned handler, caching successful probes by binary identity.
    .PARAMETER Runtime
    Invocation being resolved; probes become its measured children.
    #>
    param($Runtime)
    $binary=[IO.Path]::GetFileName($Runtime.Request.FilePath)
    if($IsWindows -and $binary.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)){$binary=$binary.Substring(0,$binary.Length-4)}
    $candidates=@($script:QuietHandlers.Values|Where-Object{$_.Binary -eq $binary})
    if($Runtime.Request.ContainsKey('HandlerId')){$candidates=@($candidates|Where-Object Id -EQ $Runtime.Request.HandlerId)}
    $matches=[Collections.Generic.List[object]]::new()
    foreach($handler in $candidates){
        $file=Get-Item -LiteralPath $Runtime.Request.FilePath
        $key=$handler.Id+'|'+$file.FullName+'|'+$file.Length+'|'+$file.LastWriteTimeUtc.Ticks+'|'+($Runtime.Request.Environment|ConvertTo-Json -Compress)
        if(!$script:QuietProbeCache.ContainsKey($key)){
            if(!$handler.ContainsKey('Probe')){continue}
            $version=@(& $handler.Probe $Runtime)
            if($version.Count -ne 1){throw 'VersionProbeMustReturnOneValue'}
            $script:QuietProbeCache[$key]=$version[0]
        }
        $version=$script:QuietProbeCache[$key]
        $versionMatch=@(& $handler.TestVersion $version)
        if($versionMatch.Count -ne 1 -or $versionMatch[0] -isnot [bool]){throw 'VersionPredicateMustReturnOneBoolean'}
        if(!$versionMatch[0]){continue}
        $shapeMatch=@($true)
        if($handler.ContainsKey('Match')){$shapeMatch=@(& $handler.Match $Runtime.Request $version)}
        if($shapeMatch.Count -ne 1 -or $shapeMatch[0] -isnot [bool]){throw 'ShapePredicateMustReturnOneBoolean'}
        if($shapeMatch[0]){$Runtime.State.DetectedVersion=$version;$matches.Add($handler)}
    }
    if($matches.Count -gt 1){throw 'AmbiguousHandler'}
    if($matches.Count){return $matches[0]}
    return $null
}
