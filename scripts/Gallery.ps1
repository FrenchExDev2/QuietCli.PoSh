# Objectif : Valider les paquets installables et leurs dépendances avant toute publication PSGallery.
function Test-QuietGalleryPackageSet {
    <#
    .SYNOPSIS
    Verifies the exact Core/Git nupkg set, package identity, dependencies and architecture payloads without importing code.
    .PARAMETER PackageDirectory
    Prepared directory containing package-set.json and exactly two installable nupkg files.
    .PARAMETER Version
    Optional release version required by the tag or manual workflow.
    #>
    param([string]$PackageDirectory,[string]$Version)
    $directory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
    $planPath=Join-Path $directory package-set.json
    if((Get-Item -LiteralPath $planPath).Length -gt 1MB){throw 'GalleryPlanTooLarge'}
    $plan=Get-Content $planPath -Encoding utf8 -Raw|ConvertFrom-Json
    if($plan.SchemaVersion -ne 1 -or $plan.Version -notmatch '^\d+\.\d+\.\d+$' -or ($Version -and $plan.Version -cne $Version)){throw 'GalleryReleaseVersionMismatch'}
    if($plan.CoreDependencyVersion -notmatch '^\d+\.\d+\.\d+$' -or [version]$plan.CoreDependencyVersion -gt [version]$plan.Version){throw 'GalleryCoreDependencyUnsatisfied'}
    $required=@(Get-QuietRuntimeTargets (Split-Path $PSScriptRoot -Parent))
    if($plan.Targets.Count -ne $required.Count){throw 'GalleryTargetSetIncomplete'}
    foreach($target in $required){$actual=@($plan.Targets|Where-Object Rid -CEQ $target.Rid);if($actual.Count -ne 1 -or $actual[0].Apphost -cne $target.Apphost -or $actual[0].Pty -ne $target.Pty){throw 'GalleryTargetSetInvalid'}}
    $expected=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Git.PoSh')
    if($plan.Packages.Count -ne 2 -or @(Get-ChildItem $directory -File -Filter '*.nupkg').Count -ne 2){throw 'GalleryPackageSetInvalid'}
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
                foreach($target in $plan.Targets){
                    foreach($file in @('QuietCli.Engine.dll',$target.Apphost,'build-manifest.json')){
                        if(!$names.Contains('lib/engine/'+$target.Rid+'/'+$file)){throw ('GalleryRuntimeMissing: '+$target.Rid+'/'+$file)}
                    }
                    $sqlite=if($target.Rid -like 'win-*'){'e_sqlite3.dll'}else{'libe_sqlite3.so'}
                    if(!$names.Contains('resources/runtime/runtimes/'+$target.Rid+'/native/'+$sqlite)){throw 'GallerySqliteMissing'}
                    if($target.Pty -and !$names.Contains('resources/transport/'+$target.Rid+'/quietcli-pty')){throw 'GalleryPtyMissing'}
                }
            }elseif($dependencies.Count -ne 1 -or $dependencies[0].id -cne $expected[0] -or $dependencies[0].version -notin @($plan.CoreDependencyVersion,('['+$plan.CoreDependencyVersion+',)'))){throw 'GalleryGitDependencyInvalid'}
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
    if($Module -notmatch '^FrenchExDev2\.QuietCli\.(Core|Git)\.PoSh$' -or $Version -notmatch '^\d+\.\d+\.\d+$'){throw 'InvalidGalleryRemoteIdentity'}
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
