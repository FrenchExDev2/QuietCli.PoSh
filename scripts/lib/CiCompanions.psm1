#requires -Version 7.6
function Get-QuietCiCompanionOrder {
    <# .SYNOPSIS
    Topologically orders product dependencies and rejects cycles or unknown references.
    .PARAMETER Companions
    Validated companion map.
    .PARAMETER Roots
    Product roots required by the selected test suites.
    #>
    param([Collections.IDictionary]$Companions,[string[]]$Roots)
    $active=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ordered=[Collections.Generic.List[string]]::new()
    function Visit-Companion([string]$name) {
        if($name -cnotin $Companions.Keys){throw ('CiCompanionUnknown: '+$name)}
        if($done.Contains($name)){return}
        if(!$active.Add($name)){throw ('CiCompanionCycle: '+$name)}
        foreach($dependency in $Companions[$name].requires){Visit-Companion $dependency}
        [void]$active.Remove($name);[void]$done.Add($name);$ordered.Add($name)
    }
    foreach($name in $Roots){Visit-Companion $name}
    $ordered.ToArray()
}

function Read-QuietCiCompanions {
    <# .SYNOPSIS
    Reads the closed, duplicate-key-checked companion YAML without loading the product engine.
    .PARAMETER WorkspaceRoot
    Checkout owning the checksum-pinned YAML reader.
    .PARAMETER ConfigurationPath
    YAML declaration; defaults to build/companions.yml in the selected checkout.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string]$ConfigurationPath)
    if(!$ConfigurationPath){$ConfigurationPath=Join-Path $WorkspaceRoot 'build/companions.yml'}
    $file=Get-Item -LiteralPath $ConfigurationPath -Force -ErrorAction Stop
    if($file.Length -gt 262144 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'CiCompanionsFileInvalid'}
    . (Join-Path $PSScriptRoot '../Resources.ps1')
    $null=Ensure-QuietResource -WorkspaceRoot $WorkspaceRoot -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder
    $text=[IO.File]::ReadAllText($file.FullName,[Text.UTF8Encoding]::new($false,$true))
    $builder=[YamlDotNet.Serialization.DeserializerBuilder]::new().WithDuplicateKeyChecking().WithMaximumRecursion(32).WithAttemptingUnquotedStringTypeDeserialization()
    $document=$builder.Build().Deserialize($text)
    if($document -isnot [Collections.IDictionary] -or $document.Count -ne 3 -or 'schema' -cnotin $document.Keys -or $null -eq $document['schema'] -or $document['schema'].GetType() -notin @([byte],[int16],[int],[long],[uint16],[uint32],[uint64]) -or $document['schema'] -ne 1 -or 'companions' -cnotin $document.Keys -or $document['companions'] -isnot [Collections.IDictionary] -or !$document['companions'].Count -or 'suites' -cnotin $document.Keys -or $document['suites'] -isnot [Collections.IDictionary] -or !$document['suites'].Count){throw 'CiCompanionsSchemaInvalid'}
    $companions=[ordered]@{}
    foreach($name in $document['companions'].Keys){
        if($name -isnot [string] -or $name -cnotmatch '\A[A-Z][A-Za-z0-9]*\z' -or $name -ieq 'All'){throw 'CiCompanionNameInvalid'}
        $entry=$document['companions'][$name]
        if($entry -isnot [Collections.IDictionary]){throw ('CiCompanionDeclarationInvalid: '+$name)}
        foreach($key in $entry.Keys){if($key -cnotin @('requires','image')){throw ('CiCompanionFieldUnknown: '+$key)}}
        foreach($key in @('requires')){
            if($key -cnotin $entry.Keys -or $entry[$key] -isnot [Collections.IList]){throw ('CiCompanionDependenciesInvalid: '+$name)}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($dependency in $entry[$key]){if($dependency -isnot [string] -or $dependency -ceq $name -or !$seen.Add($dependency)){throw ('CiCompanionDependenciesInvalid: '+$name)}}
        }
        if($entry['image'] -cnotin @('base','overlay','none')){throw ('CiCompanionPolicyInvalid: '+$name)}
        $companions.Add($name,[pscustomobject]@{Name=$name;requires=@($entry['requires']);Image=$entry['image']})
    }
    $bases=@($companions.Values|Where-Object Image -CEQ base)
    if($bases.Count -ne 1){throw 'CiCompanionBaseNotUnique'}
    if($bases[0].Name -cne 'Core' -or $bases[0].requires.Count){throw 'CiCompanionBaseInvalid'}
    $null=Get-QuietCiCompanionOrder $companions @($companions.Keys)
    $suites=[ordered]@{}
    foreach($name in $document['suites'].Keys){
        if($name -isnot [string] -or $name -cnotmatch '\A[A-Z][A-Za-z0-9]*\z' -or $name -ieq 'All'){throw 'CiSuiteNameInvalid'}
        $entry=$document['suites'][$name]
        if($entry -isnot [Collections.IDictionary]){throw 'CiSuiteDeclarationInvalid'}
        foreach($key in $entry.Keys){if($key -cnotin @('test_project','command','requires','core_evidence','qualification')){throw ('CiSuiteFieldUnknown: '+$key)}}
        if($entry['test_project'] -cnotmatch '\AFrenchExDev2\.QuietCli\.[A-Za-z0-9.]+\.Tests\.PoSh\z' -or $entry['command'] -cnotmatch '\AInvoke-Quiet[A-Za-z0-9]+Tests\z' -or $entry['requires'] -isnot [Collections.IList] -or !$entry['requires'].Count -or $entry['core_evidence'] -isnot [bool]){throw 'CiSuiteDeclarationInvalid'}
        $manifestPath=Join-Path $WorkspaceRoot ($entry['test_project']+'/'+$entry['test_project']+'.psd1')
        if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-Item -LiteralPath $manifestPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('CiSuiteTestProjectMissing: '+$name)}
        $null=[IO.File]::ReadAllText($manifestPath,[Text.UTF8Encoding]::new($false,$true))
        $manifest=Import-PowerShellDataFile -LiteralPath $manifestPath
        if($manifest.FunctionsToExport -cnotcontains $entry['command']){throw ('CiSuiteCommandNotExported: '+$name)}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($dependency in $entry['requires']){if($dependency -isnot [string] -or $dependency -cnotin $companions.Keys -or !$seen.Add($dependency)){throw ('CiSuiteDependencyInvalid: '+$name)}}
        $policies=@()
        if('qualification' -cin $entry.Keys){
            if($entry['qualification'] -isnot [Collections.IList]){throw 'CiCompanionQualificationInvalid'}
            foreach($policy in $entry['qualification']){
                if($policy -isnot [Collections.IDictionary] -or $policy.Count -ne 3 -or $policy['rid'] -cnotmatch '\A(?:win|linux|linux-musl)-(?:x64|arm64)\z' -or $null -eq $policy['runtime_major'] -or $policy['runtime_major'].GetType() -notin @([byte],[int16],[int],[long],[uint16],[uint32],[uint64]) -or $policy['runtime_major'] -lt 10 -or $policy['runtime_major'] -gt 99 -or $policy['environment'] -isnot [Collections.IDictionary]){throw 'CiCompanionQualificationInvalid'}
                foreach($key in $policy['environment'].Keys){if($key -cnotmatch '\AQUIETCLI_[A-Z0-9_]+_MUTATION\z' -or [string]$policy['environment'][$key] -cne '1'){throw 'CiCompanionEnvironmentInvalid'}}
                $policies+=,$policy
            }
        }
        $suites.Add($name,[pscustomobject]@{Name=$name;Requires=@($entry['requires']);CoreEvidence=$entry['core_evidence'];Qualification=$policies;TestsModule=$entry['test_project'];TestsManifest=$manifestPath;Command=$entry['command']})
    }
    [pscustomobject]@{Path=$file.FullName;SHA256=(Get-FileHash -LiteralPath $file.FullName).Hash;Companions=$companions;Suites=$suites;Base=$bases[0].Name}
}

function Resolve-QuietCiCompanions {
    <# .SYNOPSIS
    Separates selected test suites, product dependencies and test-only image requirements.
    .PARAMETER Configuration
    Validated YAML configuration.
    .PARAMETER Suite
    One declared suite or All; All automatically includes future companions.
    .PARAMETER RuntimeIdentifier
    Actual qualification target, used only for declared environment controls.
    .PARAMETER RuntimeMajor
    Selected PowerShell CLR major, never inferred from a module name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration,[string]$Suite='All',[string]$RuntimeIdentifier,[int]$RuntimeMajor=[Environment]::Version.Major)
    $map=$Configuration.Companions
    $suites=$Configuration.Suites
    $selected=@(if($Suite -ieq 'All'){$suites.Keys}else{$canonical=@($suites.Keys|Where-Object {$_ -ieq $Suite});if($canonical.Count -ne 1){throw ('CiCompanionSuiteUnknown: '+$Suite)};$canonical[0]})
    $roots=@(foreach($name in $selected){$suites[$name].Requires})
    $order=@(Get-QuietCiCompanionOrder $map $roots)
    if($order -cnotcontains $Configuration.Base){throw 'CiCompanionBaseDependencyMissing'}
    $images=@($order|Where-Object {$map[$_].Image -cne 'none'})
    if($images[0] -cne $Configuration.Base){throw 'CiCompanionOverlayBaseDependencyMissing'}
    $environment=[ordered]@{}
    foreach($entry in $suites.Values){foreach($policy in $entry.Qualification){foreach($key in $policy['environment'].Keys){$environment[$key]='0'}}}
    foreach($name in $selected){foreach($policy in $suites[$name].Qualification){
        if($policy['rid'] -ceq $RuntimeIdentifier -and $policy['runtime_major'] -eq $RuntimeMajor){foreach($key in $policy['environment'].Keys){$environment[$key]=[string]$policy['environment'][$key]}}
    }}
    [pscustomobject]@{Suite=$Suite;Selected=$selected;Dependencies=$order;Images=$images;HasCoreEvidence=(@($selected|Where-Object {$suites[$_].CoreEvidence}).Count -gt 0);Environment=$environment;ConfigurationSHA256=$Configuration.SHA256}
}

function Get-QuietCiSuiteImagePlan {
    <# .SYNOPSIS
    Composes declared image layers without building, querying a registry or reading credentials.
    .PARAMETER WorkspaceRoot
    Checkout containing generic image scripts and module-owned image declarations.
    .PARAMETER Selection
    Resolved companion selection.
    .PARAMETER RuntimeIdentifier
    Native Linux target.
    #>
    param([string]$WorkspaceRoot,$Selection,[string]$RuntimeIdentifier)
    $plan=& (Join-Path $PSScriptRoot '../New-CiImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -PlanOnly
    foreach($name in @($Selection.Images|Select-Object -Skip 1)){
        $plan=& (Join-Path $PSScriptRoot '../New-CiModuleImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -Module $name -ParentPlan $plan -PlanOnly
    }
    $plan
}

function Invoke-QuietCiSuiteImage {
    <# .SYNOPSIS
    Builds or reuses a base and its ordered overlays, preserving one ephemeral credential across layers.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER Selection
    Validated companion selection.
    .PARAMETER RuntimeIdentifier
    Native Linux target.
    .PARAMETER ContainerRuntime
    Explicit container adapter.
    .PARAMETER RegistryCache
    Requests verified registry reuse.
    .PARAMETER PublishCache
    Requests publication under the existing develop-only guard.
    .PARAMETER ResolveOnly
    Verifies an existing registry configuration without pulling layers; a miss still prepares the image.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot,$Selection,[string]$RuntimeIdentifier,[string]$ContainerRuntime,[switch]$RegistryCache,[switch]$PublishCache,[switch]$ResolveOnly)
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Prepare declared companion image layers')){return}
    if($ResolveOnly -and !$RegistryCache){throw 'CiImageRegistryResolutionRequiresCache'}
    $credential=$env:QUIETCLI_REGISTRY_TOKEN
    try{
        if($RegistryCache){
            . (Join-Path $PSScriptRoot '../Common.ps1')
            . (Join-Path $PSScriptRoot '../CiImages.ps1')
            $finalPlan=Get-QuietCiSuiteImagePlan $WorkspaceRoot $Selection $RuntimeIdentifier
            if($ResolveOnly){
                $identity=Get-QuietCiRegistryDigest $finalPlan $credential $env:GITHUB_ACTOR -IncludeConfiguration
                if($identity){
                    $receipt=[pscustomobject]@{Image=$identity.Reference;RuntimeIdentifier=$RuntimeIdentifier;Fingerprint=$finalPlan.Fingerprint;RegistryDigest=$identity.Digest;CacheHit=$true;Published=$false;RegistryOnly=$true}
                    Write-WorkspaceJson (Join-Path $WorkspaceRoot ('artifacts/ci-images/resolved-'+$RuntimeIdentifier+'/image.json')) $receipt
                    return $receipt
                }
            }
            $cached=Invoke-QuietCiImageBuild -Plan $finalPlan -ContextDirectory (Join-Path $WorkspaceRoot '.github/containers') -WorkspaceRoot $WorkspaceRoot -ArtifactPrefix ('suite-'+$RuntimeIdentifier) -RegistryCache -CacheOnly -ContainerRuntime $ContainerRuntime
            $env:QUIETCLI_REGISTRY_TOKEN=$credential
            if($cached){return $cached}
        }
        $plan=& (Join-Path $PSScriptRoot '../New-CiImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -PlanOnly
        $image=& (Join-Path $PSScriptRoot '../New-CiImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -RegistryCache:$RegistryCache -PublishCache:$PublishCache -ContainerRuntime $ContainerRuntime
        foreach($name in @($Selection.Images|Select-Object -Skip 1)){
            $env:QUIETCLI_REGISTRY_TOKEN=$credential
            $image=& (Join-Path $PSScriptRoot '../New-CiModuleImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -Module $name -ParentPlan $plan -ParentImage $image.Image -RegistryCache:$RegistryCache -PublishCache:$PublishCache -ContainerRuntime $ContainerRuntime
            $plan=& (Join-Path $PSScriptRoot '../New-CiModuleImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier -Module $name -ParentPlan $plan -PlanOnly
        }
        $image
    }finally{$credential=$null;$env:QUIETCLI_REGISTRY_TOKEN=$null}
}

Export-ModuleMember -Function Read-QuietCiCompanions,Resolve-QuietCiCompanions,Get-QuietCiSuiteImagePlan,Invoke-QuietCiSuiteImage
