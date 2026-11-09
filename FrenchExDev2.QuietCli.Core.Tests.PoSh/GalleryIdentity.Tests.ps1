function Test-QuietGalleryStagingProperties {
    <#
    .SYNOPSIS
    Checks public identity, source preservation and exclusive staging over generated metadata.
    .PARAMETER CopyCommand
    Real staging function or a source-checked mutant.
    .PARAMETER Root
    New owned directory for the generated cases.
    #>
    param([scriptblock]$CopyCommand,[string]$Root)
    $random=[Random]::new(82723)
    foreach($index in 0..11){
        $caseRoot=Join-Path $Root ("case-$index-é")
        $source=Join-Path $caseRoot 'internal source'
        [void][IO.Directory]::CreateDirectory($source)
        $bytes=[byte[]]::new(16);$random.NextBytes($bytes);$guid=[guid]::new($bytes)
        $version="2.3.$index";$suffix=if($index%2){'preview'}else{''}
        $name='FrenchExDev2.QuietCli.Core.PoSh'
        $body="@{RootModule='$name.psm1';ModuleVersion='$version';GUID='$guid';Author='Fixture';Description='é 漢 $index';FunctionsToExport=@();CmdletsToExport=@();AliasesToExport=@();PrivateData=@{PSData=@{Prerelease='$suffix';Tags=@('identity','$index')}}}"+[char]10
        $manifest=Join-Path $source ($name+'.psd1')
        [void][IO.File]::WriteAllTextAsync($manifest,$body,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        [void][IO.File]::WriteAllTextAsync((Join-Path $source ($name+'.psm1')),"throw 'StagingExecutedModuleCode'"+[char]10,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $destination=Join-Path $caseRoot 'QuietCli'
        $output=@(& $CopyCommand -SourceDirectory $source -ModuleDirectory $destination)
        $publicManifest=Join-Path $destination 'QuietCli.psd1'
        $data=Import-PowerShellDataFile -LiteralPath $publicManifest
        if($output.Count -or $data.RootModule -cne 'QuietCli.psm1' -or [string]$data.GUID -cne [string]$guid -or [string]$data.ModuleVersion -cne $version -or $data.Description -cne "é 漢 $index" -or $data.PrivateData.PSData.Prerelease -cne $suffix -or $data.PrivateData.PSData.Tags[1] -cne [string]$index){throw 'PublicStagingMetadataChanged'}
        if(!(Test-Path -LiteralPath (Join-Path $destination 'QuietCli.psm1')) -or (Test-Path -LiteralPath (Join-Path $destination ($name+'.psd1'))) -or (Test-Path -LiteralPath (Join-Path $destination ($name+'.psm1')))){throw 'PublicStagingLayoutInvalid'}
        if([IO.File]::ReadAllTextAsync($manifest,[Text.Encoding]::UTF8).GetAwaiter().GetResult() -cne $body){throw 'SourceManifestWasEdited'}
        $publicBytes=[IO.File]::ReadAllBytesAsync($publicManifest).GetAwaiter().GetResult()
        if($publicBytes[0] -eq 0xef -or [Text.Encoding]::UTF8.GetString($publicBytes).Contains([char]13)){throw 'PublicStagingEncodingInvalid'}
        $before=(Get-FileHash -LiteralPath $publicManifest).Hash
        $rejected=$false;try{& $CopyCommand -SourceDirectory $source -ModuleDirectory $destination}catch{$rejected=$true}
        if(!$rejected -or (Get-FileHash -LiteralPath $publicManifest).Hash -cne $before){throw 'StagingReplacedExistingModule'}
        $invalid=Join-Path $caseRoot 'NotQuietCli'
        $rejected=$false;try{& $CopyCommand -SourceDirectory $source -ModuleDirectory $invalid}catch{$rejected=$true}
        if(!$rejected -or (Test-Path -LiteralPath $invalid)){throw 'StagingAcceptedInternalPublicName'}
    }
}

function Test-QuietGalleryManifestCorpus {
    <#
    .SYNOPSIS
    Checks manifest values and rejects executable or malformed archive entries without evaluation.
    .PARAMETER ReadCommand
    Real archive manifest reader or a source-checked mutant.
    .PARAMETER Root
    Owned directory containing the execution sentinel.
    #>
    param([scriptblock]$ReadCommand,[string]$Root)
    [void][IO.Directory]::CreateDirectory($Root)
    $sentinel=Join-Path $Root 'must-not-exist'
    $valid="@{RootModule='QuietCli.psm1';ModuleVersion='2.3.4';Description='é 漢'}"
    $attack='@{RootModule=$([IO.File]::WriteAllText(''__PATH__'',''executed''))}'.Replace('__PATH__',$sentinel.Replace("'","''"))
    $samples=[Collections.Generic.List[object]]::new()
    $samples.Add(@{Text=$valid;Valid=$true})
    foreach($text in @('',"@{", '@{}; Write-Output injected', '@{X=(Get-Date)}', '@{X=$env:PATH}', $attack, ($valid+(' '*65536)))){
        $samples.Add(@{Text=$text;Valid=$false})
    }
    foreach($index in 0..47){$samples.Add(@{Text=("@{Value=(Write-Output $index)}");Valid=$false})}
    $samples.Add(@{Bytes=[byte[]]@(0xc3,0x28);Valid=$false})
    foreach($sample in $samples){
        $stream=[IO.MemoryStream]::new()
        try{
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
            $entry=$zip.CreateEntry('QuietCli.psd1')
            $payload=if($sample.ContainsKey('Bytes')){,([byte[]]$sample.Bytes)}else{,([Text.UTF8Encoding]::new($false,$true).GetBytes($sample.Text))}
            $entryStream=$entry.Open()
            try{[void]$entryStream.WriteAsync($payload,0,$payload.Length).GetAwaiter().GetResult()}finally{$entryStream.Dispose();$zip.Dispose()}
            $stream.Position=0
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
            try{
                $rejected=$false;$data=$null
                try{$data=& $ReadCommand -Entry $zip.GetEntry('QuietCli.psd1')}catch{$rejected=$true}
                if($sample.Valid){
                    if($rejected -or $data.RootModule -cne 'QuietCli.psm1' -or $data.ModuleVersion -cne '2.3.4' -or $data.Description -cne 'é 漢'){throw 'PublicManifestRoundTripFailed'}
                }elseif(!$rejected){throw 'UnsafePublicManifestAccepted'}
                if(Test-Path -LiteralPath $sentinel){throw 'ManifestReaderExecutedCode'}
            }finally{$zip.Dispose()}
        }finally{$stream.Dispose()}
    }
    $rejected=$false;try{$null=& $ReadCommand -Entry $null}catch{$rejected=$true}
    if(!$rejected){throw 'MissingPublicManifestAccepted'}
}

function Invoke-QuietGalleryIdentityTests {
    <#
    .SYNOPSIS
    Runs public packaging properties, malformed manifest inputs and bounded PowerShell mutations.
    .PARAMETER RunDirectory
    Existing owned campaign directory.
    .PARAMETER Mutation
    Executes source-checked staging and archive-reader mutants after their baseline passes.
    #>
    param([string]$RunDirectory,[switch]$Mutation)
    $root=Join-Path $RunDirectory 'public-identity'
    $copy=(Get-Command Copy-QuietGalleryCoreModule).ScriptBlock
    $read=(Get-Command Read-QuietGalleryManifest).ScriptBlock
    Test-QuietGalleryStagingProperties -CopyCommand $copy -Root (Join-Path $root 'baseline')
    Test-QuietGalleryManifestCorpus -ReadCommand $read -Root (Join-Path $root 'parser')
    foreach($name in @('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Git.PoSh','quietcli',("QuietCli"+[char]10),"QuietCli';unexpected")){
        $rejected=$false;try{$null=Get-QuietGalleryRemoteIdentity -Module $name -Version 2.3.4}catch{$rejected=$_.Exception.Message -ceq 'InvalidGalleryRemoteIdentity'}
        if(!$rejected){throw 'NonpublicRemoteIdentityAccepted'}
    }
    $outcomes=[Collections.Generic.List[object]]::new()
    if($Mutation){
        $catalogue=@(
            @{Name='public-root-module';Kind='Copy';From='$publicRootModule = ''QuietCli.psm1''';To='$publicRootModule = ''Wrong.psm1'''},
            @{Name='source-manifest-preservation';Kind='Copy';From='WriteAllTextAsync($manifest,';To='WriteAllTextAsync($sourceManifest,'},
            @{Name='manifest-value-preservation';Kind='Read';From='return $expression.Expression.SafeGetValue()';To='return @{}'},
            @{Name='manifest-size-bound';Kind='Read';From='$Entry.Length -gt 65536';To='$false'}
        )
        foreach($spec in $catalogue){
            $source=if($spec.Kind -eq 'Copy'){$copy.ToString()}else{$read.ToString()}
            $state='Invalid';$message=$null
            if([regex]::Matches($source,[regex]::Escape($spec.From)).Count -eq 1){
                $tokens=$null;$errors=$null
                $changed=[Management.Automation.Language.Parser]::ParseInput($source.Replace($spec.From,$spec.To),[ref]$tokens,[ref]$errors)
                if(!$errors.Count){
                    $candidate=[scriptblock]::Create($changed.Extent.Text)
                    try{
                        if($spec.Kind -eq 'Copy'){Test-QuietGalleryStagingProperties -CopyCommand $candidate -Root (Join-Path $root $spec.Name)}
                        else{Test-QuietGalleryManifestCorpus -ReadCommand $candidate -Root (Join-Path $root $spec.Name)}
                        $state='Survived'
                    }catch{$state='Killed';$message=$_.Exception.Message}
                }
            }
            $outcomes.Add(@{Name=$spec.Name;Outcome=$state;Error=$message})
        }
        if(@($outcomes|Where-Object Outcome -CNE Killed).Count){throw 'GalleryIdentityMutationSurvivedOrInvalid'}
    }
    return @{Seed=82723;StagingCases=12;MalformedManifestCases=57;Mutations=$outcomes.ToArray();ExternalNetwork=$false}
}
