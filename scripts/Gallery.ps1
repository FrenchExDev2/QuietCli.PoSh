function Copy-QuietGalleryCoreModule {
    <#
    .SYNOPSIS
    Copies the internal Core project into a public QuietCli staging directory without editing its sources.
    .PARAMETER SourceDirectory
    Verified internal Core package directory produced by New-WorkspacePackage.ps1.
    .PARAMETER ModuleDirectory
    New staging directory whose leaf name must be QuietCli.
    #>
    param([Parameter(Mandatory)][string]$SourceDirectory,[Parameter(Mandatory)][string]$ModuleDirectory)
    if([IO.Path]::GetFileName([IO.Path]::TrimEndingDirectorySeparator($ModuleDirectory)) -cne 'QuietCli'){throw 'GalleryStagingNameInvalid'}
    if(Test-Path -LiteralPath $ModuleDirectory){throw 'GalleryStagingAlreadyExists'}
    $sourceName='FrenchExDev2.QuietCli.Core.PoSh'
    $sourceManifest=Join-Path $SourceDirectory ($sourceName+'.psd1')
    $before=Import-PowerShellDataFile -LiteralPath $sourceManifest
    if($before.RootModule -cne ($sourceName+'.psm1')){throw 'GallerySourceRootModuleInvalid'}
    Copy-Item -LiteralPath $SourceDirectory -Destination $ModuleDirectory -Recurse
    Rename-Item -LiteralPath (Join-Path $ModuleDirectory ($sourceName+'.psm1')) -NewName 'QuietCli.psm1'
    Rename-Item -LiteralPath (Join-Path $ModuleDirectory ($sourceName+'.psd1')) -NewName 'QuietCli.psd1'
    $manifest=Join-Path $ModuleDirectory 'QuietCli.psd1'
    $text=[IO.File]::ReadAllTextAsync($manifest,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    $root=$ast.EndBlock.Statements[0].PipelineElements[0].Expression
    $pairs=@($root.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'RootModule'})
    if($errors.Count -or $pairs.Count -ne 1){throw 'GallerySourceRootModuleInvalid'}
    $value=$pairs[0].Item2.Extent
    $publicRootModule = 'QuietCli.psm1'
    $text=$text.Substring(0,$value.StartOffset)+"'$publicRootModule'"+$text.Substring($value.EndOffset)
    [void][IO.File]::WriteAllTextAsync($manifest,$text.Replace("`r`n","`n").Replace("`r","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $after=Import-PowerShellDataFile -LiteralPath $manifest
    if($after.RootModule -cne 'QuietCli.psm1' -or [string]$after.GUID -cne [string]$before.GUID -or (Get-QuietGalleryModuleVersion $after) -cne (Get-QuietGalleryModuleVersion $before)){throw 'GalleryStagedIdentityChanged'}
}

function Read-QuietGalleryManifest {
    <#
    .SYNOPSIS
    Reads a bounded, data-only module manifest from an archive without importing its code.
    .PARAMETER Entry
    Exact public manifest entry.
    #>
    param([IO.Compression.ZipArchiveEntry]$Entry)
    if(!$Entry -or $Entry.Length -gt 65536){throw 'GalleryModuleManifestInvalid'}
    $reader=[IO.StreamReader]::new($Entry.Open(),[Text.UTF8Encoding]::new($false,$true))
    try{$text=$reader.ReadToEndAsync().GetAwaiter().GetResult()}finally{$reader.Dispose()}
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if($errors.Count -or $ast.EndBlock.Statements.Count -ne 1 -or $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.PipelineAst] -or $ast.EndBlock.Statements[0].PipelineElements.Count -ne 1){throw 'GalleryModuleManifestInvalid'}
    $expression=$ast.EndBlock.Statements[0].PipelineElements[0]
    if($expression -isnot [Management.Automation.Language.CommandExpressionAst] -or $expression.Expression -isnot [Management.Automation.Language.HashtableAst]){throw 'GalleryModuleManifestInvalid'}
    try{return $expression.Expression.SafeGetValue()}catch{throw 'GalleryModuleManifestInvalid'}
}

function Get-QuietGalleryVersion {
    <#
    .SYNOPSIS
    Validates a Gallery-compatible stable or prerelease version without losing its suffix.
    .PARAMETER Version
    Numeric three-part version with an optional alphanumeric/hyphen prerelease label.
    #>
    param([string]$Version)
    if($Version -cnotmatch '^(\d+\.\d+\.\d+)(?:-([A-Za-z][A-Za-z0-9-]*))?$'){throw 'GalleryReleaseVersionMismatch'}
    $base=$Matches[1];$label=if($Matches.ContainsKey(2)){$Matches[2]}else{''}
    try{$null=[semver]$Version}catch{throw 'GalleryReleaseVersionMismatch'}
    return @{Version=$Version;BaseVersion=$base;Prerelease=$label}
}
function New-QuietGalleryPreviewVersion {
    <#
    .SYNOPSIS
    Creates a Gallery-compatible, lexically ordered preview identity without changing the target release.
    .PARAMETER BaseVersion
    Three-part numeric target release, without a prerelease label.
    .PARAMETER BuildNumber
    Positive workflow run number, at most eight decimal digits.
    .PARAMETER Attempt
    Positive packaging attempt, at most four decimal digits; changes on a workflow rerun.
    #>
    param([string]$BaseVersion,[string]$BuildNumber,[string]$Attempt='1')
    $info=Get-QuietGalleryVersion $BaseVersion
    if($info.Prerelease){throw 'GalleryPreviewBaseVersionInvalid'}
    $build=0L;$retry=0L
    if($BuildNumber -cnotmatch '^[0-9]+\z' -or ![long]::TryParse($BuildNumber,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$build) -or $build -lt 1 -or $build -gt 99999999){throw 'GalleryPreviewCounterInvalid'}
    if($Attempt -cnotmatch '^[0-9]+\z' -or ![long]::TryParse($Attempt,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$retry) -or $retry -lt 1 -or $retry -gt 9999){throw 'GalleryPreviewAttemptInvalid'}
    return '{0}-preview{1:D8}a{2:D4}' -f $BaseVersion,$build,$retry
}
function Set-QuietGalleryStagedPrerelease {
    <#
    .SYNOPSIS
    Changes only the prerelease identity of an explicitly staged module manifest, preserving its numeric version and GUID.
    .PARAMETER Path
    Manifest in the package staging directory; callers never pass a source manifest.
    .PARAMETER Prerelease
    Alphanumeric prerelease label, without a delimiter, dots or build metadata.
    #>
    param([string]$Path,[string]$Prerelease)
    if($Prerelease -cnotmatch '^[A-Za-z][A-Za-z0-9]*\z'){throw 'GalleryPreviewLabelInvalid'}
    $before=Import-PowerShellDataFile -LiteralPath $Path
    Update-ModuleManifest -Path $Path -Prerelease $Prerelease -ErrorAction Stop
    $text=[IO.File]::ReadAllTextAsync($Path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    [void][IO.File]::WriteAllTextAsync($Path,$text.Replace("`r`n","`n").Replace("`r","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $after=Import-PowerShellDataFile -LiteralPath $Path
    if([string]$before.ModuleVersion -cne [string]$after.ModuleVersion -or [string]$before.GUID -cne [string]$after.GUID -or (Get-QuietGalleryModuleVersion $after) -cne ([string]$before.ModuleVersion+'-'+$Prerelease)){throw 'GalleryStagedIdentityChanged'}
}
function Get-QuietGalleryModuleVersion {
    <#
    .SYNOPSIS
    Combines ModuleVersion and PSData.Prerelease into the actual package identity.
    .PARAMETER Manifest
    Safely imported module data; never executable module code.
    #>
    param([Collections.IDictionary]$Manifest)
    $version=[string]$Manifest.ModuleVersion
    if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'GalleryReleaseVersionMismatch'}
    if($Manifest.Contains('PrivateData') -and $Manifest.PrivateData.Contains('PSData') -and $Manifest.PrivateData.PSData.Contains('Prerelease')){
        $suffix=[string]$Manifest.PrivateData.PSData.Prerelease
        if($suffix){$version+='-'+$suffix}
    }
    return (Get-QuietGalleryVersion $version).Version
}
function Read-QuietGalleryXml {
    <#
    .SYNOPSIS
    Reads bounded package XML with external entities and DTDs disabled.
    .PARAMETER Entry
    The package nuspec entry.
    #>
    param([IO.Compression.ZipArchiveEntry]$Entry)
    if($Entry.Length -gt 65536){throw 'GalleryNuspecTooLarge'}
    $reader=[IO.StreamReader]::new($Entry.Open(),[Text.Encoding]::UTF8)
    try{
        $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=65536
        $xmlReader=[Xml.XmlReader]::Create($reader,$settings)
        try{$xml=[Xml.XmlDocument]::new();$xml.XmlResolver=$null;$xml.Load($xmlReader);return ,$xml}
        catch{throw [IO.InvalidDataException]::new('GalleryNuspecUnsafeXml',$_.Exception)}
        finally{$xmlReader.Dispose()}
    }finally{$reader.Dispose()}
}
function Test-QuietGalleryPackageSet {
    <#
    .SYNOPSIS
    Verifies the public Core nupkg, package identity, dependencies and architecture payloads without importing code.
    .PARAMETER PackageDirectory
    Prepared directory containing package-set.json and exactly one installable Core nupkg.
    .PARAMETER Version
    Optional release version required by the tag or manual workflow.
    #>
    param([string]$PackageDirectory,[string]$Version)
    $directory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
    $planPath=Join-Path $directory package-set.json
    if((Get-Item -LiteralPath $planPath).Length -gt 1MB){throw 'GalleryPlanTooLarge'}
    $plan=Get-Content $planPath -Encoding utf8 -Raw|ConvertFrom-Json
    $release=Get-QuietGalleryVersion $plan.Version
    if($plan.SchemaVersion -ne 1 -or ($Version -and $plan.Version -cne $Version) -or $plan.BaseVersion -cne $release.BaseVersion){throw 'GalleryReleaseVersionMismatch'}
    $required=@(Get-QuietRuntimeTargets (Split-Path $PSScriptRoot -Parent))
    if($plan.Targets.Count -ne $required.Count){throw 'GalleryTargetSetIncomplete'}
    foreach($target in $required){$actual=@($plan.Targets|Where-Object Rid -CEQ $target.Rid);if($actual.Count -ne 1 -or $actual[0].Apphost -cne $target.Apphost -or $actual[0].Pty -ne $target.Pty){throw 'GalleryTargetSetInvalid'}}
    $expected=@('QuietCli')
    if($plan.Packages.Count -ne 1 -or @(Get-ChildItem $directory -File -Filter '*.nupkg').Count -ne 1){throw 'GalleryPackageSetInvalid'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($package in $plan.Packages){
        if($package.Module -cnotin $expected -or !$seen.Add($package.Module) -or $package.File -cne ($package.Module+'.'+$plan.Version+'.nupkg')){throw 'GalleryPackageIdentityInvalid'}
        $path=Join-Path $directory $package.File
        if((Get-FileHash $path -Algorithm SHA256).Hash -cne $package.SHA256){throw 'GalleryPackageIntegrityFailed'}
        $zip=[IO.Compression.ZipFile]::OpenRead($path)
        try{
            if($zip.Entries.Count -gt 10000){throw 'GalleryPackageEntryLimit'}
            $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$bytes=0L
            foreach($entry in $zip.Entries){
                $name=[Uri]::UnescapeDataString($entry.FullName)
                $bytes+=$entry.Length
                if($name -match '(^/|\\|:|(^|/)\.\.(/|$)|[\x00-\x1f])' -or !$names.Add($name) -or $entry.Length -gt 128MB -or $bytes -gt 512MB){throw 'GalleryPackageUnsafeEntry'}
                if($name -match '(^|/)(engine|fixture|engine-tests|artifacts|\.git)/' -and $name -notlike 'lib/engine/*'){throw 'GalleryPackageContainsDevelopmentFiles'}
            }
            $nuspec=@($zip.Entries|Where-Object FullName -CEQ ($package.Module+'.nuspec'))
            if($nuspec.Count -ne 1){throw 'GalleryNuspecMissing'}
            if($nuspec[0].Length -gt 65536){throw 'GalleryNuspecTooLarge'}
            $reader=[IO.StreamReader]::new($nuspec[0].Open(),[Text.Encoding]::UTF8)
            try{
                $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=65536
                $xmlReader=[Xml.XmlReader]::Create($reader,$settings)
                try{$metadata=[Xml.XmlDocument]::new();$metadata.XmlResolver=$null;$metadata.Load($xmlReader)}catch{throw [IO.InvalidDataException]::new('GalleryNuspecUnsafeXml',$_.Exception)}finally{$xmlReader.Dispose()}
            }finally{$reader.Dispose()}
            $id=$metadata.SelectSingleNode("//*[local-name()='metadata']/*[local-name()='id']").InnerText
            $versionNode=$metadata.SelectSingleNode("//*[local-name()='metadata']/*[local-name()='version']").InnerText
            if($id -cne $package.Module -or $versionNode -cne $plan.Version){throw 'GalleryNuspecIdentityMismatch'}
            $dependencies=@($metadata.SelectNodes("//*[local-name()='dependency']"))
            if($package.Module -ceq $expected[0]){
                if($dependencies.Count){throw 'GalleryCoreDependencyUnexpected'}
                $manifest=Read-QuietGalleryManifest $zip.GetEntry('QuietCli.psd1')
                if($manifest.RootModule -cne 'QuietCli.psm1' -or !$names.Contains('QuietCli.psm1') -or (Get-QuietGalleryModuleVersion $manifest) -cne $plan.Version -or $names.Contains('FrenchExDev2.QuietCli.Core.PoSh.psd1') -or $names.Contains('FrenchExDev2.QuietCli.Core.PoSh.psm1')){throw 'GalleryModuleIdentityMismatch'}
                if($manifest.Contains('RequiredModules') -and $null -ne $manifest.RequiredModules -and @($manifest.RequiredModules).Count){throw 'GalleryCoreDependencyUnexpected'}
                foreach($frameworkDirectory in @('lib/inprocess/','lib/engine/')){
                    foreach($file in @('QuietCli.Engine.dll','QuietCli.Engine.runtimeconfig.json','protocol.json','build-manifest.json')){
                        if(!$names.Contains($frameworkDirectory+$file)){throw ('GalleryIntegratedEngineMissing: '+$frameworkDirectory+$file)}
                    }
                }
                foreach($target in $plan.Targets){
                    foreach($file in @('QuietCli.Engine.dll',$target.Apphost,'build-manifest.json')){
                        if(!$names.Contains('lib/engine/'+$target.Rid+'/'+$file)){throw ('GalleryRuntimeMissing: '+$target.Rid+'/'+$file)}
                    }
                    $sqlite=if($target.Rid -like 'win-*'){'e_sqlite3.dll'}else{'libe_sqlite3.so'}
                    if(!$names.Contains('resources/runtime/runtimes/'+$target.Rid+'/native/'+$sqlite)){throw 'GallerySqliteMissing'}
                    if($target.Pty -and !$names.Contains('resources/transport/'+$target.Rid+'/quietcli-pty')){throw 'GalleryPtyMissing'}
                    if($plan.PSObject.Properties['ReadyToRun'] -and $plan.ReadyToRun){
                        foreach($slot in @('inprocess','engine')){
                            $prefix='lib/'+$slot+'/'+$target.Rid+'/'
                            $entry=$zip.GetEntry($prefix+'build-manifest.json')
                            if(!$entry -or $entry.Length -gt 1MB){throw 'GalleryReadyToRunManifestMissing'}
                            $reader=[IO.StreamReader]::new($entry.Open(),[Text.UTF8Encoding]::new($false,$true))
                            try{$build=$reader.ReadToEndAsync().GetAwaiter().GetResult()|ConvertFrom-Json}finally{$reader.Dispose()}
                            if(!$build.ReadyToRun -or $build.RuntimeIdentifier -cne $target.Rid -or $build.Configuration -cne 'Release'){throw 'GalleryReadyToRunTargetMismatch'}
                            $entry=$zip.GetEntry($prefix+'QuietCli.Engine.dll')
                            if(!$entry -or $entry.Length -gt 32MB){throw 'GalleryReadyToRunImageMissing'}
                            $memory=[IO.MemoryStream]::new();$stream=$entry.Open();$pe=$null
                            try{
                                [void]$stream.CopyToAsync($memory).GetAwaiter().GetResult();$memory.Position=0
                                $pe=[Reflection.PortableExecutable.PEReader]::new($memory)
                                $header=$pe.PEHeaders.CorHeader
                                if(!$header -or $header.ManagedNativeHeaderDirectory.Size -lt 16){throw 'GalleryReadyToRunHeaderMissing'}
                                $native=$pe.GetSectionData($header.ManagedNativeHeaderDirectory.RelativeVirtualAddress).GetReader()
                                if($native.ReadUInt32() -ne 0x00525452){throw 'GalleryReadyToRunSignatureInvalid'}
                            }finally{if($pe){$pe.Dispose()};$stream.Dispose();$memory.Dispose()}
                        }
                    }
                }
            }
        }finally{$zip.Dispose()}
    }
    $plan
}
function Get-QuietGalleryRemoteIdentity {
    <#
    .SYNOPSIS
    Reads only the public package identity; distinguishes an absent release from a network or service failure.
    .PARAMETER Module
    Validated public module name.
    .PARAMETER Version
    Validated release version.
    #>
    param([string]$Module,[string]$Version)
    if($Module -cne 'QuietCli'){throw 'InvalidGalleryRemoteIdentity'}
    $null=Get-QuietGalleryVersion $Version
    $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(30)
    try{
        $url="https://www.powershellgallery.com/api/v2/Packages(Id='$Module',Version='$Version')"
        $response=$client.GetAsync($url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try{
            if($response.StatusCode -eq [Net.HttpStatusCode]::NotFound){return $false}
            if(!$response.IsSuccessStatusCode){throw ('GalleryPreflightHttpFailure: '+[int]$response.StatusCode)}
            return $true
        }finally{$response.Dispose()}
    }finally{$client.Dispose()}
}
