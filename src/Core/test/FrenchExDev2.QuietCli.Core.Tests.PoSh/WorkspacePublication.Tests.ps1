function Test-QuietWorkspacePublication {
    <#
    .SYNOPSIS
    Exercises publication with renameable locks, rollback, generated payloads and targeted mutants.
    .PARAMETER WorkspaceRoot
    Checkout containing the publication helper.
    .PARAMETER RunDirectory
    Owned temporary fixture and evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $module=Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/WorkspacePublication.psm1')) -DisableNameChecking -PassThru -ErrorAction Stop
    & $module {
        param($RunDirectory)
        $original=Get-Command Invoke-WorkspaceNative
        try{
            function script:Invoke-WorkspaceNative {
                <#
                .SYNOPSIS
                Simulates native publication into the staging directory with controlled payloads and failures.
                .PARAMETER FilePath
                Executable supplied by the publication helper; no process is started.
                .PARAMETER Arguments
                Publish arguments whose output directory receives the fixture payload.
                .PARAMETER WorkingDirectory
                Workspace supplied by the publication helper.
                #>
                param($FilePath,$Arguments,$WorkingDirectory)
                $script:PublicationCalls++
                $target=$Arguments[[Array]::IndexOf($Arguments,'-o')+1]
                if($target -ceq $script:PublicationOutput){throw 'PublicationBypassedStaging'}
                foreach($name in $script:PublicationPayload.Keys){
                    $path=[IO.Path]::Combine($target,$name)
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
                    [IO.File]::WriteAllText($path,$script:PublicationPayload[$name],[Text.UTF8Encoding]::new($false))
                }
                if($script:PublicationFailNative){throw 'PublicationFixtureNativeFailed'}
            }
            $subject=(Get-Command Invoke-WorkspacePublication).ScriptBlock
            $oracle={
                param([scriptblock]$Subject,[string]$Name)
                $root=[IO.Path]::Combine($RunDirectory,('publication-'+$Name))
                $script:PublicationOutput=[IO.Path]::Combine($root,'lib')
                [void][IO.Directory]::CreateDirectory($script:PublicationOutput)
                $file=[IO.Path]::Combine($script:PublicationOutput,'a.dll')
                [IO.File]::WriteAllText($file,'old',[Text.UTF8Encoding]::new($false))
                $sentinel=[IO.Path]::Combine($script:PublicationOutput,'win-x64/keep.dll')
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($sentinel))
                [IO.File]::WriteAllText($sentinel,'slot',[Text.UTF8Encoding]::new($false))
                $arguments=@('publish','fixture.csproj','--no-build','-o',$script:PublicationOutput)
                $script:PublicationPayload=@{'a.dll'='new';'runtimes/native-é.dll'='nested'}
                $script:PublicationCalls=0;$script:PublicationFailNative=$false
                $null=& $Subject $arguments $root -WhatIf
                if($script:PublicationCalls -or [IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -cne 'old' -or @(Get-ChildItem $script:PublicationOutput -Directory -Filter '.quiet-*').Count){throw 'PublicationPreviewChangedFiles'}
                # Simulate Windows mapped-image sharing: reads/deletion allowed, overwrites forbidden.
                $handle=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
                try{
                    $null=& $Subject $arguments $root -WarningAction SilentlyContinue
                    if([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -cne 'new'){throw 'PublicationNewBytesMissing'}
                    $reader=[IO.StreamReader]::new($handle,[Text.Encoding]::UTF8,$false,1024,$true)
                    try{if($reader.ReadToEnd() -cne 'old'){throw 'PublicationChangedExistingReader'}}finally{$reader.Dispose()}
                }finally{$handle.Dispose()}
                if([IO.File]::ReadAllText($sentinel,[Text.Encoding]::UTF8) -cne 'slot' -or [IO.File]::ReadAllText([IO.Path]::Combine($script:PublicationOutput,'runtimes/native-é.dll'),[Text.Encoding]::UTF8) -cne 'nested'){throw 'PublicationNestedFilesChanged'}
                $script:PublicationFailNative=$true
                $rejected=$false
                try{$null=& $Subject $arguments $root}catch{$rejected=$_.Exception.Message -ceq 'PublicationFixtureNativeFailed'}
                if(!$rejected -or [IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -cne 'new'){throw 'PublicationNativeFailureChangedDistribution'}
                $script:PublicationFailNative=$false
                # Fail after a.dll was replaced, proving that its original bytes are restored.
                $blocked=[IO.Path]::Combine($script:PublicationOutput,'z.dll')
                [IO.File]::WriteAllText($blocked,'blocked',[Text.UTF8Encoding]::new($false))
                $script:PublicationPayload=@{'a.dll'='replacement';'z.dll'='replacement'}
                $handle=[IO.File]::Open($blocked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                try{
                    if($IsWindows){
                        $rejected=$false
                        try{$null=& $Subject $arguments $root}catch{$rejected=$true}
                        if(!$rejected -or [IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -cne 'new' -or [IO.File]::ReadAllText($blocked,[Text.Encoding]::UTF8) -cne 'blocked'){throw 'PublicationRollbackLostPreviousFiles'}
                    }
                }finally{$handle.Dispose()}
                $random=[Random]::new(20261114)
                [IO.File]::Delete($blocked)
                [void][IO.Directory]::CreateDirectory($blocked)
                try{
                    $rejected=$false
                    try{$null=& $Subject $arguments $root}catch{$rejected=$true}
                    if(!$rejected -or [IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -cne 'new'){throw 'PublicationPortableRollbackLostPreviousFiles'}
                }finally{[IO.Directory]::Delete($blocked)}
                foreach($index in 1..24){
                    $script:PublicationPayload=@{'a.dll'=('é漢'+$random.Next());'deep/path/payload.json'=('value-'+$index)}
                    $null=& $Subject $arguments $root
                    foreach($name in $script:PublicationPayload.Keys){if([IO.File]::ReadAllText([IO.Path]::Combine($script:PublicationOutput,$name),[Text.Encoding]::UTF8) -cne $script:PublicationPayload[$name]){throw 'PublicationPayloadPropertyFailed'}}
                }
                foreach($invalid in @(@('build','-o',$script:PublicationOutput),@('publish'),@('publish','-o',$root),@('publish','-o',[IO.Path]::GetDirectoryName($root)),@('publish','-o',$script:PublicationOutput,'-o',$script:PublicationOutput))){
                    $before=$script:PublicationCalls;$rejected=$false
                    try{$null=& $Subject $invalid $root}catch{$rejected=$true}
                    if(!$rejected -or $script:PublicationCalls -ne $before){throw 'PublicationMalformedArgumentsAccepted'}
                }
            }
            & $oracle $subject 'baseline'
            $source=$subject.ToString()
            $mutants=@(
                $source.Replace('[IO.File]::Move($destination,$previous)','[IO.File]::Copy($destination,$previous)'),
                $source.Replace('[IO.File]::Move($entry.Previous,$entry.Destination)','[void]0'),
                $source.Replace('$nativeArguments[$outputIndex+1]=$staging','$nativeArguments[$outputIndex+1]=$output')
            )
            $killed=0
            foreach($mutant in $mutants){
                if($mutant -ceq $source){throw 'PublicationMutationAnchorMissing'}
                try{& $oracle ([scriptblock]::Create($mutant)) ('mutant-'+$killed)}catch{$killed++;continue}
                throw 'PublicationMutantSurvived'
            }
            [pscustomobject]@{Seed=20261114;GeneratedPayloads=24;MalformedInputs=5;MutantsKilled=$killed;WindowsLockRegression=$IsWindows}
        }finally{
            Set-Item Function:script:Invoke-WorkspaceNative -Value $original.ScriptBlock
        }
    } $RunDirectory
}
