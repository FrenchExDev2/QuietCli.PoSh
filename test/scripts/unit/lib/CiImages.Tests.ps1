#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CiImages
}

Describe 'Unavailable GHCR cache during image preparation' {
    BeforeEach {
        $previousToken=$env:QUIETCLI_REGISTRY_TOKEN
        $env:QUIETCLI_REGISTRY_TOKEN=$null
        Mock -ModuleName CiImages Invoke-CiProcess {
            & $OnOutput ([pscustomobject]@{Stream='stdout';Text='{"OSType":"linux","Architecture":"aarch64"}'}) $State
            [pscustomobject]@{Outcome='Success'}
        }
        Mock -ModuleName CiImages Get-QuietCiRegistryDigest { 'sha256:'+('b'*64) }
        Mock -ModuleName CiImages Get-QuietCiBuildCacheOptions {}
        Mock -ModuleName CiImages Write-Warning {}
        Mock -ModuleName CiImages Invoke-WorkspaceNative {
            if($Arguments[0] -ceq 'pull'){throw 'Registry fixture: manifest unavailable'}
            if($Arguments[0] -cne 'build'){throw 'Unexpected native operation'}
        }
        Mock -ModuleName CiImages Get-QuietCiVerifiedImage { [pscustomobject]@{Id='local-image-id'} }
    }

    AfterEach {
        $env:QUIETCLI_REGISTRY_TOKEN=$previousToken
    }

    It 'builds and verifies a local image after a resolved digest fails to download' {
        $plan=[pscustomobject]@{
            Architecture='arm64'; Rid='linux-musl-arm64'; RegistryPath='fixture/alpine-arm64'
            Fingerprint=('a'*64); Source='https://example.invalid/source'; Arguments=@{}
            Base=$null; ContainerfileText='FROM scratch'
        }
        $receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory $TestDrive -WorkspaceRoot $TestDrive -ArtifactPrefix local -RegistryCache -ContainerRuntime docker

        $receipt.Image | Should -BeExactly 'local-image-id'
        $receipt.CacheHit | Should -BeFalse
        $receipt.RegistryDigest | Should -BeNullOrEmpty
        $receipt.Published | Should -BeFalse
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter { $Arguments[0] -ceq 'pull' }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter { $Arguments[0] -ceq 'build' }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 0 -Exactly -ParameterFilter { $Arguments[0] -ceq 'push' }
        Should -Invoke -ModuleName CiImages Get-QuietCiVerifiedImage -Times 1 -Exactly -ParameterFilter {
            $Reference -ceq ('ghcr.io/fixture/alpine-arm64:'+('a'*64))
        }
    }

    It 'returns a cache miss without building when the caller owns parent preparation' {
        $plan=[pscustomobject]@{
            Architecture='arm64'; Rid='linux-musl-arm64'; RegistryPath='fixture/alpine-arm64'
            Fingerprint=('a'*64)
        }
        Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory $TestDrive -WorkspaceRoot $TestDrive -ArtifactPrefix cache -RegistryCache -CacheOnly -ContainerRuntime docker |
            Should -BeNullOrEmpty

        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter { $Arguments[0] -ceq 'pull' }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 0 -Exactly -ParameterFilter { $Arguments[0] -cne 'pull' }
        Should -Invoke -ModuleName CiImages Get-QuietCiVerifiedImage -Times 0 -Exactly
    }

    It 'recovers from a registry HTTP timeout <Mode>' -ForEach @(
        @{Mode='during a regular build';CacheOnly=$false;Builds=1}
        @{Mode='while checking the final image before its parents';CacheOnly=$true;Builds=0}
    ) {
        Mock -ModuleName CiImages Get-QuietCiRegistryDigest {
            $timeout=[OperationCanceledException]::new('Registry fixture: HTTP client timeout',[TimeoutException]::new())
            [Threading.Tasks.Task]::FromException($timeout).GetAwaiter().GetResult()
        }
        $plan=[pscustomobject]@{
            Architecture='arm64'; Rid='linux-musl-arm64'; RegistryPath='fixture/alpine-arm64'
            Fingerprint=('a'*64); Source='https://example.invalid/source'; Arguments=@{}
            Base=$null; ContainerfileText='FROM scratch'
        }
        $receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory $TestDrive -WorkspaceRoot $TestDrive -ArtifactPrefix timeout -RegistryCache -CacheOnly:$CacheOnly -ContainerRuntime docker -ErrorAction Stop

        if($CacheOnly){$receipt|Should -BeNullOrEmpty}else{
            $receipt.Image|Should -BeExactly 'local-image-id'
            $receipt.CacheHit|Should -BeFalse
            $receipt.Published|Should -BeFalse
        }
        Should -Invoke -ModuleName CiImages Get-QuietCiRegistryDigest -Times 1 -Exactly
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times $Builds -Exactly -ParameterFilter { $Arguments[0] -ceq 'build' }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 0 -Exactly -ParameterFilter { $Arguments[0] -cne 'build' }
        Should -Invoke -ModuleName CiImages Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -ceq 'CI registry cache lookup timed out for linux-musl-arm64 (fixture/alpine-arm64).'
        }
    }

    It 'preserves a registry lookup error <Mode>' -ForEach @(
        @{Mode='for trusted publication';Publish=$true;ErrorText='Registry fixture: HTTP client timeout'}
        @{Mode='when registry metadata is invalid';Publish=$false;ErrorText='CiRegistryDigestInvalid'}
    ) {
        Mock -ModuleName CiImages Get-QuietCiRegistryDigest { throw 'CiRegistryDigestInvalid' }
        if($Publish){
            Mock -ModuleName CiImages Get-QuietCiRegistryDigest {
                $timeout=[OperationCanceledException]::new('Registry fixture: HTTP client timeout',[TimeoutException]::new())
                [Threading.Tasks.Task]::FromException($timeout).GetAwaiter().GetResult()
            }
        }
        $variables=@{GITHUB_REPOSITORY='FrenchExDev2/QuietCli.PoSh';GITHUB_REF='refs/heads/develop';GITHUB_EVENT_NAME='push'}
        $previous=@{}
        try{
            foreach($name in $variables.Keys){
                $previous[$name]=[Environment]::GetEnvironmentVariable($name)
                [Environment]::SetEnvironmentVariable($name,$variables[$name])
            }
            $plan=[pscustomobject]@{Architecture='arm64';Rid='linux-musl-arm64';RegistryPath='fixture/alpine-arm64';Fingerprint=('a'*64)}
            {Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory $TestDrive -WorkspaceRoot $TestDrive -ArtifactPrefix failed -RegistryCache -PublishCache:$Publish -ContainerRuntime docker -ErrorAction Stop}|Should -Throw "*$ErrorText*"
        }finally{
            foreach($name in $previous.Keys){[Environment]::SetEnvironmentVariable($name,$previous[$name])}
        }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 0 -Exactly
        Should -Invoke -ModuleName CiImages Write-Warning -Times 0 -Exactly
    }
}

Describe 'GHCR image download' {
    BeforeEach {
        Mock -ModuleName CiImages Write-Warning {}
    }

    It 'pulls the immutable reference with <Runtime> and keeps a successful cache hit' -ForEach @(
        @{Runtime='docker';AuthArguments=@()}
        @{Runtime='podman';AuthArguments=@('--authfile','private.json')}
    ) {
        $reference='ghcr.io/fixture/image@sha256:'+('a'*64)
        $logPath=[IO.Path]::Combine($TestDrive,'pull.log')
        Mock -ModuleName CiImages Invoke-WorkspaceNative { [pscustomobject]@{Outcome='Success'} }

        InModuleScope CiImages -Parameters @{Runtime=$Runtime;AuthArguments=$AuthArguments;Reference=$reference;Root=$TestDrive;Log=$logPath} {
            Receive-QuietCiRegistryImage -Reference $Reference -ContainerRuntime $Runtime -AuthArguments $AuthArguments -WorkspaceRoot $Root -LogPath $Log |
                Should -BeTrue
        }

        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq $Runtime -and
            ($Arguments -join '|') -ceq ((@('pull')+$AuthArguments+@($reference)) -join '|') -and
            $WorkingDirectory -ceq $TestDrive -and $TimeoutSeconds -eq 600 -and $LogPath -ceq $logPath
        }
        Should -Invoke -ModuleName CiImages Write-Warning -Times 0 -Exactly
    }

    It 'reports an unavailable read-only image and retains the diagnostic reference' {
        $reference='ghcr.io/fixture/image@sha256:'+('b'*64)
        $pullLog=[IO.Path]::Combine($TestDrive,'pull.log')
        Mock -ModuleName CiImages Invoke-WorkspaceNative { throw 'Registry fixture: manifest download timed out' }

        InModuleScope CiImages -Parameters @{Reference=$reference;Root=$TestDrive;Log=$pullLog} {
            $received=Receive-QuietCiRegistryImage -Reference $Reference -ContainerRuntime docker -AuthArguments @() -WorkspaceRoot $Root -LogPath $Log
            $received | Should -BeOfType ([bool])
            $received | Should -BeFalse
        }

        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly
        Should -Invoke -ModuleName CiImages Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -ceq "CI registry cache pull failed for $reference. See $pullLog."
        }
    }

    It 'propagates the original download error in publication mode' {
        Mock -ModuleName CiImages Invoke-WorkspaceNative { throw 'Registry fixture: manifest unavailable' }

        InModuleScope CiImages -Parameters @{Root=$TestDrive} {
            { Receive-QuietCiRegistryImage -Reference ('ghcr.io/fixture/image@sha256:'+('b'*64)) -ContainerRuntime docker -WorkspaceRoot $Root -LogPath ([IO.Path]::Combine($Root,'pull.log')) -PublishCache } |
                Should -Throw -ExpectedMessage 'Registry fixture: manifest unavailable'
        }

        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly
        Should -Invoke -ModuleName CiImages Write-Warning -Times 0 -Exactly
    }
}

Describe 'CI image bundle handoff' {
    BeforeEach {
        $directory=[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $revision='a'*40
        $plan=@{Rid='linux-musl-arm64';Fingerprint=('b'*64)}
        $imageId='sha256:'+('c'*64)
        $consumerId='sha256:'+('d'*64)
        $transferRef='quietcli-ci-transfer:'+('b'*64)
        $receipts=@([pscustomobject]@{RuntimeIdentifier=$plan.Rid;Fingerprint=$plan.Fingerprint;Image=$imageId})
        Mock -ModuleName CiImages Invoke-WorkspaceNative {
            if($Arguments[1] -ceq 'save'){[IO.File]::WriteAllText($Arguments[3],'archive',[Text.Encoding]::UTF8)}
        }
        Mock -ModuleName CiImages Get-QuietCiVerifiedImage { [pscustomobject]@{Id=('sha256:'+('d'*64))} }
    }

    It 'saves and loads the exact verified image without a registry operation' {
        Export-QuietCiImageBundle -WorkspaceRoot $TestDrive -RuntimeIdentifier $plan.Rid -Directory $directory -Revision $revision -RunId 314 -Receipts $receipts
        Import-QuietCiImageBundle -Directory $directory -Plan $plan -Revision $revision -RunId 314 | Should -BeExactly $consumerId
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 3 -Exactly
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'docker' -and ($Arguments -join '|') -ceq ('image|tag|'+$imageId+'|'+$transferRef)
        }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'docker' -and ($Arguments -join '|') -ceq ('image|save|--output|'+[IO.Path]::Combine($directory,'images.tar')+'|'+$transferRef)
        }
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'docker' -and ($Arguments -join '|') -ceq ('image|load|--input|'+[IO.Path]::Combine($directory,'images.tar'))
        }
        Should -Invoke -ModuleName CiImages Get-QuietCiVerifiedImage -Times 1 -Exactly -ParameterFilter {
            $Reference -ceq $transferRef -and $Plan.Fingerprint -ceq ('b'*64) -and $ContainerRuntime -ceq 'docker'
        }
    }

    It 'rejects a <Field> mismatch before loading' -ForEach @(
        @{Field='SchemaVersion';Value=1;ErrorText='RunIdentityMismatch'}
        @{Field='Revision';Value=('f'*40);ErrorText='RunIdentityMismatch'}
        @{Field='RunId';Value='315';ErrorText='RunIdentityMismatch'}
        @{Field='RuntimeIdentifier';Value='linux-arm64';ErrorText='RunIdentityMismatch'}
        @{Field='Fingerprints';Value=@(('f'*64));ErrorText='ExpectedImageMissing'}
        @{Field='Fingerprints';Value=@(('B'*64));ErrorText='ExpectedImageMissing'}
        @{Field='ArchiveSha256';Value=('F'*64);ErrorText='ArchiveMismatch'}
    ) {
        Export-QuietCiImageBundle -WorkspaceRoot $TestDrive -RuntimeIdentifier $plan.Rid -Directory $directory -Revision $revision -RunId 314 -Receipts $receipts
        $path=[IO.Path]::Combine($directory,'bundle.json')
        $receipt=Get-Content -LiteralPath $path -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
        $receipt[$Field]=$Value
        [IO.File]::WriteAllText($path,($receipt|ConvertTo-Json -Depth 5),[Text.Encoding]::UTF8)
        {Import-QuietCiImageBundle -Directory $directory -Plan $plan -Revision $revision -RunId 314}|Should -Throw "*CiImageBundle$ErrorText*"
        Should -Invoke -ModuleName CiImages Invoke-WorkspaceNative -Times 0 -Exactly -ParameterFilter { $Arguments[1] -ceq 'load' }
    }
}
