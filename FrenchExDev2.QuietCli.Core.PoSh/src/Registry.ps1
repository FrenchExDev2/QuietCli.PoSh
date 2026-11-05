function Register-QuietHandler {
    <#
.SYNOPSIS
Registers inert handler metadata; import never launches a binary.
    .PARAMETER Id
    Stable module/handler identity.
    .PARAMETER Definition
    Binary, version policy, Probe, Match, Execute, schemas and documentation.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][hashtable]$Definition)
    foreach($field in @('Binary','Execute','VersionRange','TestVersion')){if(!$Definition.ContainsKey($field)){throw "MissingHandlerField: $field"}}
    if($script:QuietHandlers.Contains($Id)){throw "HandlerAlreadyRegistered: $Id"}
    $copy=$Definition.Clone();$copy.Id=$Id
    foreach($entry in @{Summary='Business command processed.';ModuleVersion='0.1.0';Documentation=@();SupportedForms=@();Qualification='NotQualified'}.GetEnumerator()){if(!$copy.ContainsKey($entry.Key)){$copy[$entry.Key]=$entry.Value}}
    $script:QuietHandlers[$Id]=$copy
}
function Unregister-QuietHandler {
    <#
.SYNOPSIS
Removes one session registration without process or filesystem changes.
    .PARAMETER Id
    Registered handler identity.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Id)
    $script:QuietHandlers.Remove($Id)
}
function Get-QuietHandler {
    <#
.SYNOPSIS
Inspects inert handler metadata without probing a binary.
    .PARAMETER Binary
    Optional executable name.
    #>
    [CmdletBinding()]param([string]$Binary)
    foreach($handler in $script:QuietHandlers.Values){if(!$Binary -or $handler.Binary -eq $Binary){[pscustomobject]@{Id=$handler.Id;Binary=$handler.Binary;VersionRange=$handler.VersionRange;ModuleVersion=$handler.ModuleVersion;Documentation=$handler.Documentation;SupportedForms=$handler.SupportedForms;Qualification=$handler.Qualification}}}
}
function Resolve-QuietHandler {
    <#
.SYNOPSIS
Resolves a versioned handler, caching successful probes by binary identity.
    .PARAMETER Runtime
    Invocation being resolved; probes become its measured children.
    #>
    param($Runtime)
    $binary=[IO.Path]::GetFileName($Runtime.Request.FilePath)
    if($IsWindows -and $binary.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)){$binary=$binary.Substring(0,$binary.Length-4)}
    $specific=$Runtime.Request.ContainsKey('HandlerId')
    $requested=if($specific){$Runtime.Request.HandlerId}else{$null}
    $candidates=@(foreach($handler in $script:QuietHandlers.Values){if($handler.Binary -eq $binary -and (!$specific -or $handler.Id -eq $requested)){$handler}})
    $matches=[Collections.Generic.List[object]]::new()
    foreach($handler in $candidates){
        Import-QuietManagedEngine
        $key=[FrenchExDev2.QuietCli.ProbeIdentity]::Build($handler.Id,$Runtime.Request.FilePath,$Runtime.Request.Environment)
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
