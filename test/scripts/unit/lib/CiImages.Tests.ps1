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
