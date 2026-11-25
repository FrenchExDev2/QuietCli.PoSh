#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop

function Resolve-QuietVirtEngine {
    param($ContainerRuntime,$WorkspaceRoot)
    if ($ContainerRuntime -cne 'docker' -or ![IO.Directory]::Exists($WorkspaceRoot)) { throw 'FixtureContainerRuntimeInvalid' }
    $ContainerRuntime
}

function Copy-QuietContainerInputs {
    [CmdletBinding(SupportsShouldProcess)]
    param($WorkspaceRoot,$Destination,[switch]$NativeOnly,$ContainerRuntime)
    if ($NativeOnly -or $ContainerRuntime -cne 'docker' -or ![IO.Directory]::Exists($WorkspaceRoot)) { throw 'FixtureStagingInvalid' }
    if ($PSCmdlet.ShouldProcess($Destination,'Stage fixture inputs')) { [void][IO.Directory]::CreateDirectory($Destination) }
}

function Get-QuietWorkspaceIdentity {
    param($WorkspaceRoot,$Suite,[switch]$IncludeBinaries)
    @{ Workspace=$WorkspaceRoot; Suite=$Suite; IncludesBinaries=[bool]$IncludeBinaries }
}

function Invoke-WorkspaceNative {
    param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
    if ($FilePath -cne 'docker' -or $TimeoutSeconds -le 0 -or ![IO.Directory]::Exists($WorkingDirectory)) { throw 'FixtureNativeCommandInvalid' }
    if ($Arguments[0] -ceq 'create') {
        $network = [Array]::IndexOf($Arguments,'--network')
        if ($network -lt 0 -or $Arguments[$network+1] -cne 'none' -or $Arguments -cnotcontains 'QUIETCLI_TEST_TOOLS_OFFLINE=1') { throw 'FixtureContainerMustRunOffline' }
    }
    if ($Arguments[0] -ceq 'cp' -and $Arguments[1] -like '*:/workspace/artifacts/tests/container-run') {
        [void][IO.Directory]::CreateDirectory($Arguments[2])
        $path = [IO.Path]::Combine($Arguments[2],'summary.json')
        if ($env:QUIETCLI_FIXTURE_TERMINAL -ceq 'malformed') {
            [IO.File]::WriteAllText($path,'{"State":"incomplete',[Text.UTF8Encoding]::new($false))
        } else {
            Write-WorkspaceJson $path @{ State=@{ State='Success'; Platform='linux-musl-arm64'; Passed=42; Failed=0; TestPassed=39; TestFailed=0 } }
        }
    }
}

function Invoke-CiProcess {
    param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput)
    if ($FilePath -cne 'docker' -or $TimeoutSeconds -le 0) { throw 'FixtureNativeProbeInvalid' }
    switch ($ArgumentList[0]) {
        'image' { & $OnOutput @{ Stream='stdout'; Text='sha256:' + ('a' * 64) } $State }
        'cp' {
            $script:copies = 1 + [int]$script:copies
            $script:reportDirectory = [IO.Path]::GetDirectoryName($ArgumentList[2])
            if ($script:copies -eq 1) {
                Write-WorkspaceJson $ArgumentList[2] @{ Task='Core tests'; Case='Last complete progress'; Passed=17; Failed=3; TestPassed=16; TestFailed=2; ProcessId=21 }
            } else {
                [IO.File]::WriteAllText($ArgumentList[2],'{"Task":"Core tes',[Text.UTF8Encoding]::new($false))
            }
        }
        'inspect' {
            if ($ArgumentList[2] -ceq '{{.State.Status}}') {
                $status = Get-Content -LiteralPath ([IO.Path]::Combine($script:reportDirectory,'status.json')) -Raw -Encoding utf8 | ConvertFrom-Json
                if ($status.Passed -ne 17 -or $status.TestPassed -ne 16 -or $status.TestFailed -ne 2 -or $status.Case -cne 'Last complete progress') { throw 'FixtureProgressLost' }
                $value = if ($script:copies -eq 1) { 'running' } else { 'exited' }
            } else {
                $value = if ($env:QUIETCLI_FIXTURE_TERMINAL -ceq 'nonzero') { '1' } else { '0' }
            }
            & $OnOutput @{ Stream='stdout'; Text=$value } $State
        }
    }
    [pscustomobject]@{ Outcome='Success'; ExitCode=0 }
}

Export-ModuleMember -Function Resolve-QuietVirtEngine,Copy-QuietContainerInputs,Get-QuietWorkspaceIdentity,
    Invoke-WorkspaceNative,Invoke-CiProcess,Write-WorkspaceJson
