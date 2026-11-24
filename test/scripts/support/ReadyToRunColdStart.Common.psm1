function Get-QuietRuntimeTargets {
    param($WorkspaceRoot)
    if (![IO.Directory]::Exists($WorkspaceRoot)) { throw 'FixtureWorkspaceMissing' }
    [pscustomobject]@{ Rid='linux-musl-arm64'; PlatformTarget='ARM64' }
}
function Get-QuietBinaryInputs {
    param($WorkspaceRoot,$Project)
    Get-Item -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$Project)) -ErrorAction Stop
}
function Write-WorkspaceJson {
    param($Path,$Value)
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}
function Write-QuietBuildManifest {
    param($WorkspaceRoot,$Project,$Output,$Inputs,$Configuration,$RuntimeIdentifier,$PlatformTarget,[switch]$ReadyToRun)
    $path = [IO.Path]::Combine($WorkspaceRoot,$Output,'build-manifest.json')
    Write-WorkspaceJson $path @{
        Project=$Project; Configuration=$Configuration; Inputs=@($Inputs.Name)
        RuntimeIdentifier=$RuntimeIdentifier; PlatformTarget=$PlatformTarget; ReadyToRun=[bool]$ReadyToRun
    }
}
function Assert-QuietRuntimePublication {
    param($Directory,$Target)
    if ([IO.Path]::GetFileName($Directory) -cne $Target.Rid) { throw 'FixturePublicationRidMismatch' }
    $null = Get-Item -LiteralPath ([IO.Path]::Combine($Directory,'publish.json')) -ErrorAction Stop
}
function Resolve-QuietVirtEngine { 'docker' }
function Invoke-WorkspaceNative {
    param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
    if ($Arguments[0] -ceq 'publish') {
        if ($FilePath -cne 'dotnet') { throw 'FixturePublishCommandUnexpected' }
    }
    elseif ($FilePath -cne 'docker' -or $TimeoutSeconds -le 0) { throw 'FixtureContainerCommandUnexpected' }
    switch ($Arguments[0]) {
        'publish' {
            if (![IO.File]::Exists($Arguments[1])) { throw 'FixtureCandidateProjectMissing' }
            $output = $Arguments[1+[array]::IndexOf($Arguments,'-o')]
            [void][IO.Directory]::CreateDirectory($output)
            Write-WorkspaceJson ([IO.Path]::Combine($output,'publish.json')) @{ Arguments=$Arguments }
        }
        'create' {
            $stage = [IO.Path]::Combine($WorkingDirectory,'run','workspace')
            foreach ($option in '-BaselineModule','-CandidateModule') {
                $path = $Arguments[1+[array]::IndexOf($Arguments,$option)]
                if (!$path.StartsWith('/workspace/') -or ![IO.File]::Exists([IO.Path]::Combine($stage,$path.Substring('/workspace/'.Length)))) {
                    throw "FixtureGuestManifestMissing: $path"
                }
            }
        }
        'cp' {
            if ($Arguments[1] -like '*:/workspace/artifacts/coldstart') {
                [void][IO.Directory]::CreateDirectory($Arguments[2])
                Write-WorkspaceJson ([IO.Path]::Combine($Arguments[2],'ab-fixture.json')) @{ Environment=@{ RuntimeIdentifier='linux-musl-arm64' } }
            }
        }
    }
}
function Invoke-CiProcess {
    param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput)
    if ($FilePath -cne 'docker' -or $TimeoutSeconds -le 0) { throw 'FixtureContainerInspectionUnexpected' }
    $value = switch ($ArgumentList[2]) {
        '--format' { 'sha256:' + ('a' * 64) }
        '{{.State.Status}}' { 'exited' }
        '{{.State.ExitCode}}' { '0' }
    }
    & $OnOutput @{ Stream='stdout'; Text=$value } $State
    [pscustomobject]@{ Outcome='Success'; ExitCode=0 }
}
