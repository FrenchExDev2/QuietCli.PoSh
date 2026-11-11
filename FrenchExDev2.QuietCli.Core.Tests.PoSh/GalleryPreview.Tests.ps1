function Test-QuietPreviewVersionProperties {
    <#
    .SYNOPSIS
    Checks independent version examples, boundary corpora, uniqueness and ordering against an explicit factory.
    .PARAMETER Create
    Production or sandbox-mutated version function.
    .PARAMETER Iterations
    Seeded generated build pairs.
    #>
    param($Create,[int]$Iterations=128)
    $exact=& $Create -BaseVersion '0.2.0' -BuildNumber 42 -Attempt 3
    if($exact -cne '0.2.0-preview00000042a0003'){throw 'PreviewExactIdentity'}
    $random=[Random]::new(82719)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for($i=0;$i -lt $Iterations;$i++){
        $build=$random.Next(1,99999998);$attempt=$random.Next(1,9998)
        $version=& $Create '2.3.4' $build $attempt
        $rerun=& $Create '2.3.4' $build ($attempt+1)
        $next=& $Create '2.3.4' ($build+1) 1
        if($version -cnotmatch '^2\.3\.4-preview[0-9]{8}a[0-9]{4}\z' -or !$seen.Add($version)){throw 'PreviewIdentityOrCollision'}
        if([StringComparer]::Ordinal.Compare($version,$rerun) -ge 0 -or [StringComparer]::Ordinal.Compare($rerun,$next) -ge 0){throw 'PreviewOrder'}
        if($version -cne (& $Create '2.3.4' $build $attempt)){throw 'PreviewNotDeterministic'}
    }
    foreach($value in @('0','-1','100000000','9223372036854775808','',' ','1.2','1e3','+1',"1`n",'True','42;exit')){
        $rejected=$false;try{$null=& $Create '2.3.4' $value 1}catch{$rejected=$true}
        if(!$rejected){throw ('PreviewInvalidBuildAccepted: '+$value)}
    }
    foreach($value in @('0','-1','10000','9223372036854775808','','1.2',"1`n")){
        $rejected=$false;try{$null=& $Create '2.3.4' 1 $value}catch{$rejected=$true}
        if(!$rejected){throw 'PreviewInvalidAttemptAccepted'}
    }
    foreach($value in @('2.3','2.3.4-preview','2.3.4+build','../2.3.4')){
        $rejected=$false;try{$null=& $Create $value 1 1}catch{$rejected=$true}
        if(!$rejected){throw 'PreviewInvalidBaseAccepted'}
    }
    if((& $Create '2.3.4' 99999999 9999) -cne '2.3.4-preview99999999a9999'){throw 'PreviewInclusiveMaximum'}
}

function Invoke-QuietGalleryPreviewTests {
    <#
    .SYNOPSIS
    Runs offline preview version properties, mutation checks, real package preparation and publication-boundary fixtures.
    .PARAMETER WorkspaceRoot
    Built QuietCli2 checkout.
    .PARAMETER RunDirectory
    External report directory owned by the shared launcher.
    .PARAMETER Mutation
    Executes the complete targeted version-function catalogue.
    .PARAMETER OnProgress
    Existing visible-monitor progress callback.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[switch]$Mutation,[scriptblock]$OnProgress)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    . (Join-Path $WorkspaceRoot 'scripts/Gallery.ps1')
    $previewRoot=Join-Path $RunDirectory 'gallery-preview';[void][IO.Directory]::CreateDirectory($previewRoot)
    $cases=[ordered]@{};$results=[Collections.Generic.List[object]]::new();$mutants=[Collections.Generic.List[object]]::new()
    $identityEvidence=[Collections.Generic.List[object]]::new()
    $cases['public QuietCli staging preserves sources and rejects executable manifests']={
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/GalleryIdentity.Tests.ps1')
        $identity=Invoke-QuietGalleryIdentityTests -RunDirectory $previewRoot -Mutation:$Mutation
        $identityEvidence.Add($identity)
        foreach($mutant in $identity.Mutations){$mutants.Add($mutant)}
    }
    $cases['timestamp preview tags preserve manifest versions and enforce local creation boundaries']={
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/PreviewTag.Tests.ps1')
        Invoke-QuietPreviewTagTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation:$Mutation
    }
    $cases['preview identities have deterministic ordering, uniqueness and strict generated boundaries']={
        Test-QuietPreviewVersionProperties -Create (Get-Command New-QuietGalleryPreviewVersion)
    }
    $cases['qualified preview checkpoints remain publishable when develop advances']={
        $directory=Join-Path $previewRoot 'checkpoint';[void][IO.Directory]::CreateDirectory($directory)
        $script=Join-Path $WorkspaceRoot 'scripts/Assert-GalleryCheckpoint.ps1'
        $revision='a'*40;$version='0.2.0-preview00000042a0001'
        $preview=@{SourceRevision=$revision;QualifiedRevision=$revision;Version=$version}
        Write-WorkspaceJson (Join-Path $directory preview.json) $preview
        Write-WorkspaceJson (Join-Path $directory package-set.json) @{Version=$version}
        $previous=$env:GITHUB_SHA
        try{
            foreach($index in 1..64){
                $env:GITHUB_SHA=('{0:x40}' -f $index)
                $result=& $script -PackageDirectory $directory -QualifiedRevision $revision -Version $version
                if($result.State -cne 'CheckpointValidated' -or $result.BranchHeadQueried -or $result.QualifiedRevision -cne $revision){throw 'QualifiedCheckpointDependsOnCurrentBranchHead'}
            }
        }finally{$env:GITHUB_SHA=$previous}
        foreach($field in @('SourceRevision','QualifiedRevision','Version')){
            $damaged=$preview.Clone();$damaged[$field]='mismatch'
            Write-WorkspaceJson (Join-Path $directory preview.json) $damaged
            $rejected=$false;try{$null=& $script -PackageDirectory $directory -QualifiedRevision $revision -Version $version}catch{$rejected=$true}
            if(!$rejected){throw 'WrongGalleryCheckpointAccepted'}
        }
        foreach($bad in @('[]','[{},{}]','null','{"broken":')){
            [void][IO.File]::WriteAllTextAsync((Join-Path $directory preview.json),$bad,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $rejected=$false;try{$null=& $script -PackageDirectory $directory -QualifiedRevision $revision -Version $version}catch{$rejected=$true}
            if(!$rejected){throw 'MalformedGalleryCheckpointAccepted'}
        }
        Write-WorkspaceJson (Join-Path $directory preview.json) $preview
        $source=[IO.File]::ReadAllText($script,[Text.Encoding]::UTF8)
        $mutant=[scriptblock]::Create($source.Replace("if(`$preview.SourceRevision -cne `$QualifiedRevision -or `$preview.QualifiedRevision -cne `$QualifiedRevision)",'if($false)'))
        $damaged=$preview.Clone();$damaged.SourceRevision='b'*40;Write-WorkspaceJson (Join-Path $directory preview.json) $damaged
        $accepted=$false;try{$null=& $mutant -PackageDirectory $directory -QualifiedRevision $revision -Version $version;$accepted=$true}catch{}
        if(!$accepted){throw 'GalleryCheckpointInvalidMutant'}
        $workflow=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/publish-psgallery.yml'),[Text.Encoding]::UTF8)
        if($workflow.Contains('/git/ref/heads/develop') -or $workflow.Contains('steps.current.outputs.allowed') -or !$workflow.Contains('Get-QuietReleasePlan.ps1')){throw 'GalleryPublicationStillDependsOnCurrentHead'}
        Write-WorkspaceJson (Join-Path $directory campaign.json) @{BranchAdvanceProperties=64;DamagedFields=3;MalformedMetadata=4;MutantsKilled=1;ExternalPublication=$false}
    }
    $cases['staged labels preserve numeric version, GUID, Unicode metadata and source bytes']={
        $directory=Join-Path $previewRoot 'manifest';[void][IO.Directory]::CreateDirectory($directory)
        $path=Join-Path $directory 'Sample.psd1';$module=Join-Path $directory 'Sample.psm1'
        [void][IO.File]::WriteAllTextAsync($module,'Export-ModuleMember',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $text="@{RootModule='Sample.psm1';ModuleVersion='2.3.4';GUID='36a6a091-2740-4a82-b834-4d61a0291507';Author='Test';Description='é 漢';PrivateData=@{PSData=@{Prerelease='preview';Tags=@('sample')}}}`n"
        [void][IO.File]::WriteAllTextAsync($path,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        foreach($bad in @('preview.1','preview+42','../bad','',"preview`n")){
            $rejected=$false;try{Set-QuietGalleryStagedPrerelease $path $bad}catch{$rejected=$true}
            if(!$rejected -or [IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult() -cne $text){throw 'InvalidStagedLabelChangedFile'}
        }
        Set-QuietGalleryStagedPrerelease $path 'preview00000042a0001'
        $data=Import-PowerShellDataFile $path
        if($data.ModuleVersion -cne '2.3.4' -or [string]$data.GUID -cne '36a6a091-2740-4a82-b834-4d61a0291507' -or $data.Description -cne 'é 漢' -or @($data.PrivateData.PSData.Tags)[0] -cne 'sample'){throw 'StagedMetadataChanged'}
        $bytes=[IO.File]::ReadAllBytesAsync($path).GetAwaiter().GetResult()
        if($bytes[0] -eq 0xEF -or ([Text.UTF8Encoding]::new($false,$true).GetString($bytes)).Contains("`r")){throw 'StagedEncodingChanged'}
    }
    $cases['invalid preview counters, output boundaries and qualification identities fail before packaging']={
        $scriptPath=Join-Path $WorkspaceRoot 'scripts/New-QuietPreviewPackage.ps1'
        foreach($options in @(
            @{OutputDirectory=(Join-Path $previewRoot 'invalid-counter');BuildNumber='0'},
            @{OutputDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/unexpected-preview-output');BuildNumber='1'},
            @{OutputDirectory=(Join-Path $previewRoot 'invalid-revision');BuildNumber='1';QualifiedRevision=('0'*40)}
        )){
            $rejected=$false;try{$null=& $scriptPath -WorkspaceRoot $WorkspaceRoot @options}catch{$rejected=$true}
            if(!$rejected -or [IO.Directory]::Exists($options.OutputDirectory)){throw 'InvalidPreviewCreatedPackages'}
        }
    }
    $cases['preview preparation is offline and leaves both source manifests unchanged']={
        $sourceFiles=@(foreach($name in @('Core','Git')){Join-Path $WorkspaceRoot "FrenchExDev2.QuietCli.$name.PoSh/FrenchExDev2.QuietCli.$name.PoSh.psd1"})
        $before=@($sourceFiles|ForEach-Object{(Get-FileHash -LiteralPath $_).Hash})
        $sourceManifest=Import-PowerShellDataFile -LiteralPath $sourceFiles[0]
        $expectedVersion=[string]$sourceManifest.ModuleVersion+'-preview00000042a0003'
        $expectedSourceVersion=[string]$sourceManifest.ModuleVersion
        if($sourceManifest.PrivateData.PSData.ContainsKey('Prerelease') -and $sourceManifest.PrivateData.PSData.Prerelease){$expectedSourceVersion+='-'+$sourceManifest.PrivateData.PSData.Prerelease}
        $prepared=& (Join-Path $WorkspaceRoot 'scripts/New-QuietPreviewPackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory (Join-Path $previewRoot 'packages') -BuildNumber 42 -Attempt 3
        if($prepared.Version -cne $expectedVersion -or $prepared.Published){throw 'PreparedPreviewIdentity'}
        for($i=0;$i -lt $sourceFiles.Count;$i++){if((Get-FileHash -LiteralPath $sourceFiles[$i]).Hash -cne $before[$i]){throw 'SourceManifestChanged'}}
        $plan=Test-QuietGalleryPackageSet (Join-Path $previewRoot 'packages') -Version $prepared.Version
        if($plan.SourceVersion -cne $expectedSourceVersion){throw 'PreviewSourceVersionLost'}
        $preview=Get-Content -LiteralPath (Join-Path $previewRoot 'packages/preview.json') -Raw -Encoding utf8|ConvertFrom-Json
        $hasRepository=Test-Path -LiteralPath (Join-Path $WorkspaceRoot '.git')
        if($preview.Published -or ($hasRepository -and $preview.SourceRevision -cnotmatch '^[a-f0-9]{40}\z') -or (!$hasRepository -and $null -ne $preview.SourceRevision)){throw 'PreviewProvenanceMissing'}
        foreach($package in $plan.Packages){
            $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $previewRoot ('packages/'+$package.File)))
            try{
                $entry=$zip.GetEntry($package.Module+'.psd1');$reader=[IO.StreamReader]::new($entry.Open(),[Text.UTF8Encoding]::new($false,$true))
                try{$body=$reader.ReadToEndAsync().GetAwaiter().GetResult()}finally{$reader.Dispose()}
                $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
                $manifest=$ast.EndBlock.Statements[0].PipelineElements[0].Expression.SafeGetValue()
                if((Get-QuietGalleryModuleVersion $manifest) -cne $prepared.Version){throw 'EmbeddedPreviewManifestMismatch'}
            }finally{$zip.Dispose()}
        }
    }
    $cases['prepared previews import and execute from an isolated installation']={
        $probe=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Probe-GalleryInstall.ps1'
        $capture=@{Report=$null;Lines=[Collections.Generic.Queue[object]]::new()}
        $execution=Invoke-CiProcess -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -WorkingDirectory $WorkspaceRoot -ArgumentList @('-NoProfile','-File',$probe,'-PackageDirectory',(Join-Path $previewRoot 'packages'),'-InstallationDirectory',(Join-Path $previewRoot 'installed')) -State $capture -OnOutput {
            param($line,$data)
            if($data.Lines.Count -ge 16){$null=$data.Lines.Dequeue()}
            $data.Lines.Enqueue(@{Stream=$line.Stream;Text=$line.Text.Substring(0,[Math]::Min(2048,$line.Text.Length))})
            if($line.Stream -eq 'stdout' -and $line.Text.StartsWith('{')){$data.Report=$line.Text|ConvertFrom-Json}
        }
        $expected=Get-Content -LiteralPath (Join-Path $previewRoot 'packages/package-set.json') -Raw -Encoding utf8|ConvertFrom-Json
        Write-WorkspaceJson (Join-Path $RunDirectory 'gallery-install-diagnostics.json') @{Outcome=$execution.Outcome;ExitCode=$execution.ExitCode;Lines=@($capture.Lines);Report=$capture.Report}
        if($execution.Outcome -cne 'Success' -or $capture.Report.ModuleName -cne $expected.Packages[0].Module -or !$capture.Report.GeneratedScript -or $capture.Report.ScaffoldDependency -cne $expected.Packages[0].Module -or $capture.Report.GitModuleLoaded -or $capture.Report.NativeExecution -cne 'Success' -or !$capture.Report.Installed -or $capture.Report.PackageVersion -cne $expected.Version){throw ('PreviewInstallationFailed: '+((@($capture.Lines)|ConvertTo-Json -Compress -Depth 3)))}
    }
    $cases['publication uses the validated artifacts in Core-only scope without real credentials or network']={
        $previewPublicationCalls=[Collections.Generic.List[string]]::new()
        function Invoke-PreviewFixtureRepository {
            <# .SYNOPSIS
            Returns only the fixture's expected Gallery URI.
            #>
            param([string]$Name,[object]$ErrorAction)
            [pscustomobject]@{Uri=[uri]'https://www.powershellgallery.com/api/v2'}
        }
        function Invoke-PreviewFixtureIdentity {
            <# .SYNOPSIS
            Reports an unpublished fixture identity without network access.
            #>
            param([string]$Module,[string]$Version)
            return $false
        }
        function Invoke-PreviewFixturePublication {
            <# .SYNOPSIS
            Observes a publication attempt without sending any request.
            #>
            param([string]$NupkgPath,[string]$Repository,[string]$ApiKey,[switch]$SkipDependenciesCheck,[object]$ErrorAction)
            if(!$NupkgPath.EndsWith('.nupkg') -or $Repository -cne 'PSGallery'){throw 'PreviewPublicationDestination'}
            if(![IO.Path]::GetFileName($NupkgPath).StartsWith('FrenchExDev2.QuietCli.Core.PoSh.',[StringComparison]::Ordinal) -or $SkipDependenciesCheck -or $previewPublicationCalls.Count){throw 'OnlyCorePublicationAllowed'}
            $previewPublicationCalls.Add([IO.Path]::GetFileName($NupkgPath))
        }
        Set-Alias Get-PSResourceRepository Invoke-PreviewFixtureRepository -Scope Local
        Set-Alias Get-QuietGalleryRemoteIdentity Invoke-PreviewFixtureIdentity -Scope Local
        Set-Alias Publish-PSResource Invoke-PreviewFixturePublication -Scope Local
        $savedKey=$env:PSGALLERY_API_KEY
        try{
            $env:PSGALLERY_API_KEY='non-secret-fixture'
            $expected=Get-Content -LiteralPath (Join-Path $previewRoot 'packages/package-set.json') -Raw -Encoding utf8|ConvertFrom-Json
            $publication=& (Join-Path $WorkspaceRoot 'scripts/Publish-QuietGallery.ps1') -PackageDirectory (Join-Path $previewRoot 'packages') -Version $expected.Version -Confirm:$false
            if($publication.State -cne 'Published' -or $previewPublicationCalls.Count -ne 1){throw 'PreviewPublicationFixtureFailed'}
        }finally{$env:PSGALLERY_API_KEY=$savedKey}
    }
    $cases['public package validation rejects Git and unexpected archives before any network or credential use']={
        $directory=Join-Path $previewRoot 'packages'
        $path=Join-Path $directory 'package-set.json'
        $original=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
        $extra=Join-Path $directory 'FrenchExDev2.QuietCli.Git.PoSh.fixture.nupkg'
        try{
            foreach($variant in @('extra-archive','git-identity','source-identity','extra-plan-entry')){
                $plan=$original|ConvertFrom-Json
                if($variant -eq 'extra-archive'){[void][IO.File]::WriteAllBytesAsync($extra,[byte[]]@(1)).GetAwaiter().GetResult()}
                elseif($variant -eq 'git-identity'){$plan.Packages[0].Module='FrenchExDev2.QuietCli.Git.PoSh'}
                elseif($variant -eq 'source-identity'){$plan.Packages[0].Module='QuietCli'}
                else{$plan.Packages+=@{Module='FrenchExDev2.QuietCli.Git.PoSh';File='forbidden.nupkg'}}
                Write-WorkspaceJson $path $plan
                $rejected=$false
                try{$null=& (Join-Path $WorkspaceRoot 'scripts/Publish-QuietGallery.ps1') -PackageDirectory $directory -Version $plan.Version -ValidateOnly}catch{$rejected=$_.Exception.Message -in @('GalleryPackageSetInvalid','GalleryPackageIdentityInvalid')}
                if(!$rejected){throw ('GitPublicationWasNotRejected: '+$variant)}
                if(Test-Path -LiteralPath $extra){Remove-Item -LiteralPath $extra}
            }
        }finally{
            [void][IO.File]::WriteAllTextAsync($path,$original,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if(Test-Path -LiteralPath $extra){Remove-Item -LiteralPath $extra}
        }
    }
    if($Mutation){
        $cases['compiled module identity mutations are detected without changing source projects']={
            . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/ConfigurationDelivery.Mutation.ps1')
            $directory=Join-Path $previewRoot 'compiled-identity';[void][IO.Directory]::CreateDirectory($directory)
            $compiled=Invoke-QuietConfigurationDeliveryEngine -WorkspaceRoot $WorkspaceRoot -RunDirectory $directory -Mutation -MutationName @('module-session-identity','module-session-validation','script-module-identity','scaffold-module-identity')
            Write-WorkspaceJson (Join-Path $directory 'summary.json') $compiled
            if($compiled.Failed -or $compiled.Mutations.Count -ne 4 -or @($compiled.Mutations|Where-Object State -CNE Killed).Count){throw 'CompiledModuleIdentityMutationFailed'}
        }
        $cases['version mutations are all detected by independent examples, properties and malformed inputs']={
            $path=Join-Path $WorkspaceRoot 'scripts/Gallery.ps1';$source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            $catalogue=@(
                @{Name='build-minimum';From='$build -lt 1';To='$build -lt 0'},
                @{Name='build-maximum';From='$build -gt 99999999';To='$build -gt 100000000'},
                @{Name='attempt-minimum';From='$retry -lt 1';To='$retry -lt 0'},
                @{Name='attempt-maximum';From='$retry -gt 9999';To='$retry -gt 10000'},
                @{Name='build-padding';From='preview{1:D8}';To='preview{1:D2}'},
                @{Name='attempt-padding';From='a{2:D4}';To='a{2:D1}'},
                @{Name='build-identity';From='$BaseVersion,$build,$retry';To='$BaseVersion,1L,$retry'},
                @{Name='attempt-identity';From='$BaseVersion,$build,$retry';To='$BaseVersion,$build,1L'},
                @{Name='base-prerelease';From='if($info.Prerelease)';To='if($false)'}
            )
            foreach($mutant in $catalogue){
                $outcome='Invalid';$message=$null
                if([regex]::Matches($source,[regex]::Escape($mutant.From)).Count -eq 1){
                    $tokens=$null;$errors=$null;$changed=$source.Replace($mutant.From,$mutant.To)
                    [void][Management.Automation.Language.Parser]::ParseInput($changed,[ref]$tokens,[ref]$errors)
                    if($errors.Count){$outcome='Invalid'}else{
                        try{
                            & {param($text) . ([scriptblock]::Create($text)); Test-QuietPreviewVersionProperties -Create (Get-Command New-QuietGalleryPreviewVersion) -Iterations 64} $changed
                            $outcome='Survived'
                        }catch{$outcome='Killed';$message=$_.Exception.Message}
                    }
                }
                $mutants.Add([pscustomobject]@{Name=$mutant.Name;Outcome=$outcome;Error=$message})
            }
            Write-WorkspaceJson (Join-Path $previewRoot 'mutations.json') @{Seed=82719;Iterations=64;Results=$mutants.ToArray()}
            if(@($mutants|Where-Object Outcome -CNE Killed).Count){throw 'PreviewMutationQualificationFailed'}
        }
    }
    $passed=0;$failed=0
    foreach($entry in $cases.GetEnumerator()){
        $errorText=$null
        try{$null=& $entry.Value;$passed++;$state='Passed'}catch{$failed++;$state='Failed';$errorText=$_.Exception.Message}
        $results.Add([pscustomobject]@{Name=$entry.Key;State=$state;Error=$errorText})
        if($OnProgress){$null=& $OnProgress $entry.Key $state $passed $failed}
    }
    $summary=[pscustomobject]@{Project='GalleryPreview';Passed=$passed;Failed=$failed;Seed=82719;GeneratedInputs=128;PublicIdentity=$identityEvidence.ToArray();Cases=$results.ToArray();Mutations=$mutants.ToArray();ExternalPublication=$false}
    Write-WorkspaceJson (Join-Path $previewRoot 'summary.json') $summary
    return $summary
}
