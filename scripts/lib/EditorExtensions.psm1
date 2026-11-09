#requires -Version 7.6
# Objective: Export and synchronize an explicit extension inventory through the selected editor CLI.
. (Join-Path $PSScriptRoot '../Ci.Process.ps1')

function Resolve-DevelopmentEditorCli {
    <#
    .SYNOPSIS
    Resolves Stable/Insiders, including versioned Windows layouts, without executing a CMD wrapper.
    .PARAMETER Insiders
    Selects the Insiders channel.
    .PARAMETER EditorPath
    Explicit native editor executable or Linux CLI.
    #>
    param([switch]$Insiders,[string]$EditorPath)
    $channel=if($Insiders){'Insiders'}else{'Stable'}
    if(!$EditorPath){
        if($IsWindows){
            $folder=if($Insiders){'Microsoft VS Code Insiders'}else{'Microsoft VS Code'}
            $name=if($Insiders){'Code - Insiders.exe'}else{'Code.exe'}
            foreach($base in @($env:LOCALAPPDATA,$env:ProgramFiles)){
                if(!$base){continue}
                $candidate=Join-Path $base $(if($base -eq $env:LOCALAPPDATA){"Programs/$folder/$name"}else{"$folder/$name"})
                if(Test-Path -LiteralPath $candidate){$EditorPath=$candidate;break}
            }
        }else{$command=Get-Command $(if($Insiders){'code-insiders'}else{'code'}) -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command){$EditorPath=$command.Source}}
    }
    if(!$EditorPath -or !(Test-Path -LiteralPath $EditorPath -PathType Leaf)){throw "EditorExecutableNotFound: $channel; supply -EditorPath."}
    $EditorPath=[IO.Path]::GetFullPath($EditorPath)
    $prefix=@()
    if($IsWindows){
        if([IO.Path]::GetExtension($EditorPath) -ine '.exe'){throw 'EditorNativeExecutableRequired: supply Code.exe or Code - Insiders.exe.'}
        $base=Split-Path $EditorPath -Parent
        $cli=Join-Path $base 'resources/app/out/cli.js'
        if(!(Test-Path -LiteralPath $cli)){
            $wrapper=Join-Path $base $(if($Insiders){'bin/code-insiders.cmd'}else{'bin/code.cmd'})
            $cli=$null
            if(Test-Path -LiteralPath $wrapper){
                $text=[IO.File]::ReadAllTextAsync($wrapper,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
                $match=[regex]::Match($text,'"%~dp0\.\.[\\/]((?:[a-zA-Z0-9._-]+[\\/])?resources[\\/]app[\\/]out[\\/]cli\.js)"')
                if($match.Success){$candidate=[IO.Path]::GetFullPath((Join-Path $base $match.Groups[1].Value));if($candidate.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $candidate)){$cli=$candidate}}
            }
            if(!$cli){
                $candidates=@(Get-ChildItem -LiteralPath $base -Directory|ForEach-Object {Join-Path $_.FullName 'resources/app/out/cli.js'}|Where-Object {Test-Path -LiteralPath $_})
                if($candidates.Count -ne 1){throw 'EditorCliLayoutAmbiguous: cannot select the current versioned CLI.'}
                $cli=$candidates[0]
            }
        }
        $prefix=@($cli)
    }
    [pscustomobject]@{FilePath=$EditorPath;PrefixArguments=$prefix;Channel=$channel;Windows=[bool]$IsWindows}
}

function Invoke-DevelopmentEditorCli {
    <#
    .SYNOPSIS
    Executes an exact CLI vector with bounded output and restores all temporary Electron variables.
    .PARAMETER Cli
    Resolved editor CLI.
    .PARAMETER Arguments
    Extension-management arguments.
    #>
    param($Cli,[string[]]$Arguments)
    $previousElectron=$env:ELECTRON_RUN_AS_NODE;$previousDevelopment=$env:VSCODE_DEV
    $state=@{Lines=[Collections.Generic.List[string]]::new();Errors=[Collections.Generic.Queue[string]]::new();Characters=0}
    try{
        if($Cli.Windows){$env:ELECTRON_RUN_AS_NODE='1';$env:VSCODE_DEV=$null}
        $result=Invoke-CiProcess -FilePath $Cli.FilePath -ArgumentList (@($Cli.PrefixArguments)+$Arguments) -TimeoutSeconds 300 -State $state -OnOutput {
            param($e,$s)
            if($e.Stream -eq 'stdout'){
                if($s.Lines.Count -ge 8192 -or $s.Characters+$e.Text.Length -gt 1048576){throw 'EditorCliOutputLimitExceeded'}
                [void]$s.Lines.Add($e.Text);$s.Characters+=$e.Text.Length
            }else{if($s.Errors.Count -ge 8){[void]$s.Errors.Dequeue()};$s.Errors.Enqueue($e.Text)}
        }
        if($result.Outcome -ne 'Success'){throw "EditorCliFailed: exit $($result.ExitCode); $($state.Errors -join ' | '); $($state.Lines -join ' | ')"}
        [pscustomobject]@{Lines=@($state.Lines)}
    }finally{if($Cli.Windows){$env:ELECTRON_RUN_AS_NODE=$previousElectron;$env:VSCODE_DEV=$previousDevelopment}}
}

function ConvertFrom-EditorExtensionList {
    <#
    .SYNOPSIS
    Validates CLI id@version records and returns a sorted inventory, rejecting malformed records.
    .PARAMETER Lines
    Stdout from --list-extensions --show-versions.
    #>
    param([AllowEmptyCollection()][string[]]$Lines=@())
    $entries=@{}
    if($Lines.Count -gt 4096){throw 'EditorExtensionCountExceeded'}
    foreach($line in $Lines){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        if($line -cnotmatch '^(?<id>[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9][A-Za-z0-9._-]*)@(?<version>[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)$'){throw "EditorExtensionRecordInvalid: $line"}
        $id=$Matches.id.ToLowerInvariant();$version=$Matches.version
        if($entries.ContainsKey($id)){throw "EditorExtensionDuplicate: $id"}
        $entries[$id]=[pscustomobject]@{Id=$id;InstalledVersion=$version;PreRelease=$false}
    }
    @($entries.Values|Sort-Object Id)
}

function Read-EditorExtensionManifest {
    <#
    .SYNOPSIS
    Reads a bounded repository inventory; identifiers cannot become paths or command options.
    .PARAMETER Path
    UTF-8 inventory file.
    #>
    param([string]$Path)
    if((Get-Item -LiteralPath $Path).Length -gt 4194304){throw 'EditorExtensionManifestTooLarge'}
    $document=Get-Content -LiteralPath $Path -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String
    if($document -isnot [Collections.IDictionary] -or $document.SchemaVersion -ne 1 -or !$document.ContainsKey('Extensions') -or $document.Extensions -isnot [array]){throw 'EditorExtensionManifestInvalid'}
    $lines=@(foreach($entry in $document.Extensions){
        if($entry -isnot [Collections.IDictionary] -or !$entry.ContainsKey('Id') -or !$entry.ContainsKey('InstalledVersion') -or !$entry.ContainsKey('PreRelease') -or $entry.PreRelease -isnot [bool]){throw 'EditorExtensionManifestEntryInvalid'}
        if($entry.Id -isnot [string] -or $entry.InstalledVersion -isnot [string]){throw 'EditorExtensionManifestEntryInvalid'}
        $entry.Id+'@'+$entry.InstalledVersion
    })
    $entries=@(ConvertFrom-EditorExtensionList $lines)
    foreach($entry in $entries){$original=@($document.Extensions|Where-Object Id -IEQ $entry.Id)[0];$entry.PreRelease=$original.PreRelease}
    $entries
}

function Export-EditorExtensionManifest {
    <#
    .SYNOPSIS
    Exports CLI identifiers/versions plus release preferences, excluding local paths and private settings.
    .PARAMETER Cli
    Source editor channel.
    .PARAMETER Path
    Repository snapshot destination.
    .PARAMETER ShouldApply
    ShouldProcess callback, evaluated before any CLI invocation or filesystem mutation.
    #>
    param($Cli,[string]$Path,[scriptblock]$ShouldApply)
    if(!(& $ShouldApply $Path ('Export '+$Cli.Channel+' extension inventory'))){return [pscustomobject]@{State='Planned';Path=$Path;Count=$null}}
    $listed=Invoke-DevelopmentEditorCli $Cli @('--list-extensions','--show-versions')
    $entries=@(ConvertFrom-EditorExtensionList $listed.Lines)
    if(!$entries.Count){throw 'EditorExtensionExportEmpty: refusing to replace the saved inventory.'}
    $registry=Join-Path $HOME $(if($Cli.Channel -ceq 'Insiders'){'.vscode-insiders/extensions/extensions.json'}else{'.vscode/extensions/extensions.json'})
    if(Test-Path -LiteralPath $registry){
        $metadata=@(Get-Content -LiteralPath $registry -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String)
        foreach($entry in $entries){
            $installed=@($metadata|Where-Object {$_.identifier.id -ieq $entry.Id -and $_.version -ceq $entry.InstalledVersion})
            if($installed.Count -eq 1 -and $installed[0].ContainsKey('metadata')){
                $preference=$installed[0].metadata
                $entry.PreRelease=($preference['preRelease'] -eq $true -or $preference['isPreReleaseVersion'] -eq $true)
            }
        }
    }
    $version=Invoke-DevelopmentEditorCli $Cli @('--version')
    $document=[ordered]@{SchemaVersion=1;SourceEditor=$Cli.Channel;SourceEditorVersion=($version.Lines|Select-Object -First 1);ExportedUtc=[DateTimeOffset]::UtcNow.ToString('o');Extensions=$entries}
    $text=($document|ConvertTo-Json -Depth 6).Replace("`r`n","`n")+"`n"
    [void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($Path)) -Parent))
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{[void][IO.File]::WriteAllTextAsync($temporary,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult();[IO.File]::Move($temporary,$Path,$true)}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    [pscustomobject]@{State='Success';Path=[IO.Path]::GetFullPath($Path);Count=$entries.Count;Channel=$Cli.Channel}
}

function Sync-EditorExtensionManifest {
    <#
    .SYNOPSIS
    Installs missing listed extensions; Update ensures the latest version of each listed extension only.
    .PARAMETER Cli
    Target editor channel.
    .PARAMETER Entries
    Validated snapshot records.
    .PARAMETER AdditionalExtension
    Required workstation identifiers to ensure alongside the snapshot.
    .PARAMETER Update
    Uses --install-extension ID --force, respecting each extension's prerelease preference.
    .PARAMETER ShouldApply
    Per-extension ShouldProcess callback.
    .PARAMETER Preview
    Plans from the manifest without starting any editor process.
    #>
    param($Cli,[object[]]$Entries,[string[]]$AdditionalExtension=@(),[switch]$Update,[scriptblock]$ShouldApply,[switch]$Preview)
    $selected=@{}
    foreach($entry in $Entries){$selected[$entry.Id]=$entry}
    foreach($id in $AdditionalExtension){
        $record=@(ConvertFrom-EditorExtensionList @($id+'@0.0.0'))[0]
        if(!$selected.ContainsKey($record.Id)){$selected[$record.Id]=$record}
    }
    $installed=@()
    if(!$Preview){$query=Invoke-DevelopmentEditorCli $Cli @('--list-extensions','--show-versions');$installed=@(ConvertFrom-EditorExtensionList $query.Lines|ForEach-Object Id)}
    $results=[Collections.Generic.List[object]]::new()
    foreach($entry in $selected.Values|Sort-Object Id){
        $action=if($Update){'EnsureLatest'}else{'InstallMissing'}
        $row=[ordered]@{Id=$entry.Id;Action=$action;State='AlreadyInstalled';Error=$null}
        if($Update -or $installed -inotcontains $entry.Id){
            $approved=& $ShouldApply ($Cli.Channel+'/'+$entry.Id) $action
            if($Preview -or !$approved){$row.State='Planned'}
            else{
                try{
                    $arguments=@('--install-extension',$entry.Id)
                    if($Update){$arguments+='--force'}
                    if($entry.PreRelease){$arguments+='--pre-release'}
                    $null=Invoke-DevelopmentEditorCli $Cli $arguments
                    $row.State='Success'
                }catch{$row.State='Failed';$row.Error=$_.Exception.Message}
            }
        }
        [void]$results.Add([pscustomobject]$row)
    }
    $failed=@($results|Where-Object State -EQ Failed).Count
    [pscustomobject]@{State=$(if($failed){'Failed'}elseif(@($results|Where-Object State -EQ Planned).Count){'Planned'}else{'Success'});Channel=$Cli.Channel;Count=$results.Count;Failed=$failed;Results=@($results)}
}

Export-ModuleMember -Function Resolve-DevelopmentEditorCli,ConvertFrom-EditorExtensionList,Read-EditorExtensionManifest,Export-EditorExtensionManifest,Sync-EditorExtensionManifest
