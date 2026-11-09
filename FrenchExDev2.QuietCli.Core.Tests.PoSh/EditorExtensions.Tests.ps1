function Test-QuietEditorExtensions {
    <#
    .SYNOPSIS
    Checks extension inventories, update/preview boundaries and Windows CLI layouts with independent fixtures.
    .PARAMETER WorkspaceRoot
    Repository containing the extension synchronizer.
    .PARAMETER RunDirectory
    Owned temporary fixtures and qualification receipt.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $path=Join-Path $WorkspaceRoot 'scripts/lib/EditorExtensions.psm1'
    $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace(". (Join-Path `$PSScriptRoot '../Ci.Process.ps1')",'# Independent native executor fixture.')
    $verify={param($candidate,$output)
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseInput($candidate,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'InvalidEditorCandidateSyntax'}
        $module=New-Module -Name ('EditorFixture'+[guid]::NewGuid().ToString('N')) -ScriptBlock ([scriptblock]::Create($candidate))
        try{& $module {
            param($output)
            [void][IO.Directory]::CreateDirectory($output)
            $random=[Random]::new(461203)
            for($i=0;$i -lt 250;$i++){
                $id='Publisher'+$random.Next(0,99999)+'.extension-'+$i
                $version='1.'+$random.Next(0,500)+'.'+$random.Next(0,500)
                $records=@(ConvertFrom-EditorExtensionList @($id+'@'+$version))
                if($records.Count -ne 1 -or $records[0].Id -cne $id.ToLowerInvariant() -or $records[0].InstalledVersion -cne $version){throw 'Identifier/version property failed'}
                foreach($bad in @(($id+' --uninstall-extension@'+$version),($id+"`n@"+$version),('../'+$id+'@'+$version))){$rejected=$false;try{$null=ConvertFrom-EditorExtensionList @($bad)}catch{$rejected=$true};if(!$rejected){throw 'Malformed identifier accepted'}}
            }
            $rejected=$false;try{$null=ConvertFrom-EditorExtensionList @('a.b@1.0.0','A.B@2.0.0')}catch{$rejected=$true};if(!$rejected){throw 'Duplicate extension accepted'}
            $manifest=Join-Path $output 'extensions.json'
            $entries=@([pscustomobject]@{Id='fixture.installed';InstalledVersion='1.0.0';PreRelease=$false},[pscustomobject]@{Id='fixture.missing';InstalledVersion='2.0.0';PreRelease=$true})
            [void][IO.File]::WriteAllTextAsync($manifest,(@{SchemaVersion=1;Extensions=$entries}|ConvertTo-Json -Depth 5)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if(@(Read-EditorExtensionManifest $manifest).Count -ne 2){throw 'Manifest roundtrip failed'}
            $script:Calls=[Collections.Generic.List[object]]::new()
            function script:Invoke-DevelopmentEditorCli {
                <#
                .SYNOPSIS
                Supplies a native-boundary fixture and records exact vectors without executing the editor.
                #>
                param($Cli,$Arguments)
                [void]$script:Calls.Add(@($Arguments))
                if($Arguments[0] -ceq '--install-extension' -and $Arguments[1] -ceq 'fixture.fail'){throw 'Fixture Marketplace failure'}
                if($Arguments[0] -ceq '--list-extensions'){return [pscustomobject]@{Lines=@('fixture.installed@1.0.0')}}
                [pscustomobject]@{Lines=@('fixture editor')}
            }
            $cli=[pscustomobject]@{Channel='Insiders'}
            $missing=Sync-EditorExtensionManifest $cli $entries -ShouldApply {$true}
            $installs=@($script:Calls|Where-Object {$_[0] -ceq '--install-extension'})
            if($missing.Failed -or $installs.Count -ne 1 -or $installs[0][1] -cne 'fixture.missing' -or $installs[0] -contains '--force'){throw 'Missing-only mode changed an installed extension'}
            $script:Calls.Clear()
            $updated=Sync-EditorExtensionManifest $cli $entries -Update -ShouldApply {$true}
            $installs=@($script:Calls|Where-Object {$_[0] -ceq '--install-extension'})
            if($updated.Failed -or $installs.Count -ne 2){throw 'Update did not cover the explicit inventory'}
            foreach($call in $installs){if($call -notcontains '--force'){throw 'Update omitted force'};if(($call -contains '--pre-release') -ne ($call[1] -ceq 'fixture.missing')){throw 'Prerelease preference lost'}}
            if(@($script:Calls|Where-Object {$_ -contains '--update-extensions' -or $_ -contains '--uninstall-extension'}).Count){throw 'Unlisted extensions could be changed'}
            $script:Calls.Clear()
            $preview=Sync-EditorExtensionManifest $cli $entries -Update -Preview -ShouldApply {$false}
            if($preview.State -cne 'Planned' -or $script:Calls.Count){throw 'Preview started an editor process'}
            $preview=Sync-EditorExtensionManifest $cli $entries -Update -Preview -ShouldApply {$true}
            if($preview.State -cne 'Planned' -or $script:Calls.Count){throw 'Preview depended on caller approval to prevent execution'}
            $before=[IO.File]::ReadAllTextAsync($manifest,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            $export=Export-EditorExtensionManifest $cli $manifest -ShouldApply {$false}
            if($export.State -cne 'Planned' -or $script:Calls.Count -or [IO.File]::ReadAllTextAsync($manifest,[Text.Encoding]::UTF8).GetAwaiter().GetResult() -cne $before){throw 'Export preview performed an effect'}
            $export=Export-EditorExtensionManifest $cli $manifest -ShouldApply {$true}
            if($export.Count -ne 1 -or @(Read-EditorExtensionManifest $manifest).Count -ne 1){throw 'Exported snapshot invalid'}
            $failure=Sync-EditorExtensionManifest $cli @([pscustomobject]@{Id='fixture.fail';InstalledVersion='1.0.0';PreRelease=$false},$entries[1]) -Update -ShouldApply {$true}
            if($failure.State -cne 'Failed' -or $failure.Failed -ne 1 -or @($failure.Results|Where-Object State -EQ Success).Count -ne 1){throw 'Extension failure was hidden or stopped the remaining inventory'}
            if($IsWindows){
                $base=Join-Path $output 'versioned-editor'
                foreach($version in @('aaaa1111','bbbb2222')){$directory=Join-Path $base ($version+'/resources/app/out');[void][IO.Directory]::CreateDirectory($directory);[void][IO.File]::WriteAllTextAsync((Join-Path $directory 'cli.js'),'fixture',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
                [void][IO.Directory]::CreateDirectory((Join-Path $base 'bin'))
                $exe=Join-Path $base 'Code - Insiders.exe';[void][IO.File]::WriteAllTextAsync($exe,'fixture',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $wrapper='"%~dp0..\Code - Insiders.exe" "%~dp0..\bbbb2222\resources\app\out\cli.js" %*'
                [void][IO.File]::WriteAllTextAsync((Join-Path $base 'bin/code-insiders.cmd'),$wrapper,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $resolved=Resolve-DevelopmentEditorCli -Insiders -EditorPath $exe
                if($resolved.PrefixArguments[0] -cne (Join-Path $base 'bbbb2222/resources/app/out/cli.js')){throw 'Wrong versioned CLI selected'}
            }
        } $output}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
    }
    & $verify $source (Join-Path $RunDirectory 'editor-baseline')
    $mutants=@(
        @{Id='allow-duplicate';Find='if($entries.ContainsKey($id))';Replace='if($false)'},
        @{Id='omit-update-force';Find='if($Update){$arguments+=';Replace='if($false){$arguments+='},
        @{Id='lose-prerelease';Find='if($entry.PreRelease)';Replace='if($false)'},
        @{Id='query-in-preview';Find='if(!$Preview){$query=';Replace='if($true){$query='},
        @{Id='write-in-export-preview';Find='if(!(& $ShouldApply $Path';Replace='if($false -and !(& $ShouldApply $Path'},
        @{Id='reinstall-without-update';Find='if($Update -or $installed -inotcontains $entry.Id)';Replace='if($true)'},
        @{Id='ignore-preview-contract';Find='if($Preview -or !$approved)';Replace='if(!$approved)'}
    )
    foreach($mutant in $mutants){$candidate=$source.Replace($mutant.Find,$mutant.Replace);if($candidate -ceq $source){throw ('InvalidEditorMutant: '+$mutant.Id)};$killed=$false;try{& $verify $candidate (Join-Path $RunDirectory ('editor-'+$mutant.Id))}catch{if($_.Exception.Message -ceq 'InvalidEditorCandidateSyntax'){throw};$killed=$true};if(!$killed){throw ('EditorMutantSurvived: '+$mutant.Id)}}
    $scriptPath=Join-Path $WorkspaceRoot 'scripts/Sync-DevelopmentEditorExtensions.ps1'
    $snapshot=Join-Path $WorkspaceRoot 'build/vscode-extensions.json'
    $hash=(Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
    $electron=$env:ELECTRON_RUN_AS_NODE;$development=$env:VSCODE_DEV
    $preview=& $scriptPath -Insiders -Update -WhatIf -EditorPath (Join-Path $RunDirectory 'not-an-installed-editor.exe')
    if($preview.State -cne 'Planned' -or $preview.Count -ne (Get-Content -LiteralPath $snapshot -Raw -Encoding utf8|ConvertFrom-Json).Extensions.Count){throw 'Standalone update preview failed without an installed editor'}
    $unused=Join-Path $RunDirectory 'export-must-not-exist.json'
    $preview=& $scriptPath -Insiders -Export -WhatIf -Path $unused
    if($preview.State -cne 'Planned' -or (Test-Path -LiteralPath $unused)){throw 'Standalone export preview wrote a file'}
    if((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -cne $hash -or $env:ELECTRON_RUN_AS_NODE -cne $electron -or $env:VSCODE_DEV -cne $development){throw 'Standalone preview changed the inventory or environment'}
    $report=@{State='Success';Seed=461203;Properties=250;MalformedInputs=750;MutantsKilled=$mutants.Count;Scope='Inventory, native argument vectors, previews and local layout fixtures; no extension installed or updated'}
    [void][IO.File]::WriteAllTextAsync((Join-Path $RunDirectory 'editor-extensions.json'),($report|ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [pscustomobject]$report
}
