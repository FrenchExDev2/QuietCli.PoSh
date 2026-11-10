function Read-QuietProtocolSpecification {
    <#
    .SYNOPSIS
    Reads strict UTF-8 protocol constants using host .NET APIs without cmdlet-module autoloading.
    .PARAMETER Path
    Protocol JSON file containing integer constants and the supported framing bounds.
    #>
    param([string]$Path)
    $text=[IO.File]::ReadAllTextAsync($Path,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $values=[Text.Json.JsonSerializer]::Deserialize[Collections.Generic.Dictionary[string,int]]($text)
    if($null -eq $values -or !$values.ContainsKey('Version') -or !$values.ContainsKey('BlockSize') -or !$values.ContainsKey('HeaderLimit') -or $values['Version'] -ne 1 -or $values['BlockSize'] -gt 16384 -or $values['BlockSize'] -lt 1024 -or $values['HeaderLimit'] -gt 1048576 -or $values['HeaderLimit'] -lt 65536){throw 'UnsafeProtocolSpecification'}
    return $values
}

function Resolve-QuietManagedTarget {
    <#
    .SYNOPSIS
    Selects a compatible build from the actual host CLR, independent of the PowerShell release channel.
    .PARAMETER RuntimeMajor
    Actual CLR major version; explicit values allow independent compatibility assertions.
    .PARAMETER ModuleRoot
    Module directory containing portable manifests and optional ReadyToRun slots.
    .PARAMETER RuntimeIdentifier
    Actual host RID. Explicit values support platform-selection regression tests.
    #>
    param([int]$RuntimeMajor=[Environment]::Version.Major,[string]$ModuleRoot=$script:QuietRoot,[string]$RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)
    $target=if($RuntimeMajor -ge 11){@{Framework='net11.0';Directory='lib/engine'}}elseif($RuntimeMajor -eq 10){@{Framework='net10.0';Directory='lib/inprocess'}}else{throw 'ManagedEngineRequiresNet10OrLater'}
    $portable=[IO.Path]::Combine($ModuleRoot,$target.Directory,'build-manifest.json')
    if(![IO.File]::Exists($portable)){return $target}
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    $manifest=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllTextAsync($portable,$utf8).GetAwaiter().GetResult())
    $selected=$false
    try{
        $slots=[Text.Json.JsonElement]::new()
        if($manifest.RootElement.TryGetProperty('ReadyToRunTargets',[ref]$slots)){
            foreach($slot in $slots.EnumerateArray()){if($slot.GetString() -ceq $RuntimeIdentifier){$selected=$true}}
        }
    }finally{$manifest.Dispose()}
    if(!$selected){return $target}
    if($RuntimeIdentifier -cnotmatch '^(win|linux|linux-musl)-(x64|arm64)\z'){throw 'ManagedEngineRuntimeIdentifierInvalid'}
    $directory=$target.Directory+'/'+$RuntimeIdentifier
    $manifest=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllTextAsync([IO.Path]::Combine($ModuleRoot,$directory,'build-manifest.json'),$utf8).GetAwaiter().GetResult())
    try{
        if(!$manifest.RootElement.GetProperty('ReadyToRun').GetBoolean() -or $manifest.RootElement.GetProperty('RuntimeIdentifier').GetString() -cne $RuntimeIdentifier){throw 'ManagedEngineReadyToRunTargetMismatch'}
    }finally{$manifest.Dispose()}
    $target.Directory=$directory
    return $target
}
function Import-QuietManagedEngine {
    <#
    .SYNOPSIS
    Loads the verified build compatible with the actual CLR, including PowerShell preview hosts.
    #>
    if($script:QuietManagedAssembly){return}
    $target=Resolve-QuietManagedTarget
    $directory=[IO.Path]::Combine($script:QuietRoot,$target.Directory)
    # Host .NET APIs only: cmdlet-module autoloading would dominate the import cost.
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    $build=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllTextAsync([IO.Path]::Combine($directory,'build-manifest.json'),$utf8).GetAwaiter().GetResult())
    $hash=$null;$engineEntries=0
    try{
        foreach($file in $build.RootElement.GetProperty('Binaries').EnumerateArray()){
            $name=$file.GetProperty('Path').GetString()
            if([IO.Path]::GetFileName($name) -cne $name){throw 'EngineBuildIdentityUnsafePath'}
            $stream=[IO.File]::OpenRead([IO.Path]::Combine($directory,$name))
            try{$actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashDataAsync($stream).AsTask().GetAwaiter().GetResult())}finally{$stream.Dispose()}
            if($actual -cne $file.GetProperty('SHA256').GetString()){throw 'EngineBinaryIntegrityFailed'}
            # The engine assembly was just hashed; keep that value as its loaded identity instead of hashing it a second time.
            if($name -ceq 'QuietCli.Engine.dll'){$hash=$actual;$engineEntries++}
        }
    }finally{$build.Dispose()}
    if($engineEntries -ne 1){throw 'EngineBuildIdentityInvalid'}
    $configuration=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllTextAsync([IO.Path]::Combine($directory,'QuietCli.Engine.runtimeconfig.json'),$utf8).GetAwaiter().GetResult())
    try{$tfm=$configuration.RootElement.GetProperty('runtimeOptions').GetProperty('tfm').GetString()}finally{$configuration.Dispose()}
    if($tfm -cne $target.Framework){throw 'ManagedEngineTargetMismatch'}
    $assembly=[IO.Path]::Combine($directory,'QuietCli.Engine.dll')
    $loaded=[AppDomain]::CurrentDomain.GetData('QuietCli2.ManagedEngineIdentity')
    if($loaded -and $loaded -cne $hash){throw 'ManagedEngineAlreadyLoaded: restart PowerShell after rebuilding.'}
    $script:QuietManagedAssembly=[Reflection.Assembly]::LoadFrom($assembly)
    [AppDomain]::CurrentDomain.SetData('QuietCli2.ManagedEngineIdentity',$hash)
}
