#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-DotNetMigrationBuildPlan {
    <#
    .SYNOPSIS
    Discovers .NET solutions/projects without invoking MSBuild or writing files.
    .PARAMETER SourceRoot
    Source workspace containing Net/FrenchExDev and whitelist-relative paths.
    .PARAMETER PolicyPath
    Explicit deny-by-default migration candidate policy.
    .PARAMETER ItemId
    Optional exact whitelist identifiers limiting build entry points.
    .PARAMETER Target
    Optional exact paths relative to Net/FrenchExDev; no wildcards or traversal.
    .PARAMETER AllDiscovered
    Explicitly assesses all discovered entry points without selecting them for migration.
    .PARAMETER NoRestore
    Adds --no-restore to the explicit Release build command.
    .PARAMETER MaximumEntries
    Bound on directories and matching build files, including unselected targets.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PolicyPath,
        [string[]]$ItemId,[string[]]$Target,[switch]$AllDiscovered,[switch]$NoRestore,
        [ValidateRange(1,200000)][int]$MaximumEntries=100000)
    $ErrorActionPreference='Stop'
    if($AllDiscovered -and $ItemId){throw 'DotNetSelectionConflict'}
    if($PSBoundParameters.ContainsKey('Target') -and !$Target.Count -or $PSBoundParameters.ContainsKey('ItemId') -and !$ItemId.Count){throw 'DotNetEmptySelection'}
    $base=[IO.Path]::GetFullPath($SourceRoot)
    $netRoot=Join-Path $base 'Net/FrenchExDev'
    if(!(Test-Path -LiteralPath $netRoot -PathType Container)){throw 'DotNetSourceRootMissing'}
    if((Get-Item -LiteralPath $PolicyPath).Length -gt 4MB){throw 'DotNetPolicyTooLarge'}
    $policy=ConvertFrom-Json ([IO.File]::ReadAllTextAsync($PolicyPath,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()) -Depth 32
    if($policy.schemaVersion -ne 1 -or $policy.default -cne 'Exclude'){throw 'DotNetPolicyInvalid'}
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $scopes=[Collections.Generic.List[object]]::new()
    foreach($item in $policy.items){
        if(!$item.id -or !$ids.Add($item.id) -or $item.intent -cnotin @('Assess','Create','Migrate','Exclude')){throw 'DotNetPolicyItemInvalid'}
        if([IO.Path]::IsPathRooted($item.path) -or $item.path -match '(^|[/\\])\.\.([/\\]|$)'){throw 'DotNetPolicyPathInvalid'}
        if($item.intent -cne 'Exclude' -and (!$ItemId -or $item.id -cin $ItemId)){$scopes.Add([pscustomobject]@{Id=$item.id;Path=[IO.Path]::GetFullPath((Join-Path $base $item.path))})}
    }
    foreach($id in $ItemId){if(!$ids.Contains($id)){throw "DotNetItemNotWhitelisted:$id"}}
    $requested=@(foreach($path in $Target){
        if([IO.Path]::IsPathRooted($path) -or $path -match '(^|[/\\])\.\.([/\\]|$)|[*?\r\n]'){throw 'DotNetTargetPathInvalid'}
        $path.Replace('\','/')
    })
    $targets=[Collections.Generic.List[object]]::new()
    $gaps=[Collections.Generic.List[string]]::new()
    $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($netRoot)
    $visited=0
    $options=[IO.EnumerationOptions]::new();$options.AttributesToSkip=0;$options.IgnoreInaccessible=$false;$options.MatchCasing=[IO.MatchCasing]::CaseInsensitive
    $skip=@('.git','.vs','.tools','.fake','.packages','.coverage','.integration-results','.cache','.quality-gate','bin','obj','node_modules','artifacts','packages','StrykerOutput','coverage-results','TestResults')
    while($queue.Count){
        $directory=$queue.Dequeue()
        if((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){$gaps.Add("LinkNotTraversed:$directory");continue}
        $info=[IO.DirectoryInfo]::new($directory)
        foreach($child in $info.EnumerateDirectories('*',$options)){
            $visited++;if($visited -gt $MaximumEntries){throw "DotNetDiscoveryLimit:$directory"}
            if($child.Name -notin $skip){$queue.Enqueue($child.FullName)}
        }
        $matches=[Collections.Generic.List[object]]::new()
        foreach($mask in @('*.slnx','*.sln','*.csproj')){foreach($entry in $info.EnumerateFiles($mask,$options)){
            $visited++;if($visited -gt $MaximumEntries){throw "DotNetDiscoveryLimit:$directory"};$matches.Add($entry)
        }}
        foreach($entry in $matches){
            if($entry.Extension.ToLowerInvariant() -cnotin @('.slnx','.sln','.csproj')){continue}
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$gaps.Add("LinkNotRead:$($entry.FullName)");continue}
            $relative=[IO.Path]::GetRelativePath($netRoot,$entry.FullName).Replace('\','/')
            $owner=$null
            foreach($scope in $scopes){
                if($entry.FullName.StartsWith($scope.Path+[IO.Path]::DirectorySeparatorChar,$comparison)){
                    if($owner){throw 'DotNetOverlappingWhitelist'}
                    $owner=$scope.Id
                }
            }
            $matchTarget=!$requested.Count -or @($requested | Where-Object {$_.Equals($relative,$comparison)}).Count -gt 0
            $selected=($AllDiscovered -or $null -ne $owner) -and $matchTarget
            $arguments=@('build',$entry.FullName,'--configuration','Release','--nologo','--tl:off','--disable-build-servers','-maxcpucount:1')
            if($NoRestore){$arguments+=@('--no-restore')}
            $targets.Add([pscustomobject]@{Path=$entry.FullName;RelativePath=$relative;Kind=$entry.Extension.ToLowerInvariant();ItemId=$owner;Selected=$selected;Selection=if($selected){if($AllDiscovered){'ExplicitAllAssessment'}else{'WhitelistedAssessment'}}elseif(!$matchTarget){'NotRequested'}else{'NotWhitelisted'};Sha256=(Get-FileHash -LiteralPath $entry.FullName).Hash;Executable='dotnet';Arguments=$arguments;WorkingDirectory=$entry.DirectoryName;State=if($selected){'Planned'}else{'NotSelected'};ExitCode=$null;DurationMs=$null;SdkVersion=$null;LogPath=$null;LogTruncated=$false;OutputLines=0;Diagnostics=@();Error=$null})
        }
    }
    foreach($path in $requested){
        $found=@($targets | Where-Object {$_.RelativePath.Equals($path,$comparison)})
        if($found.Count -ne 1){throw "DotNetTargetUnknown:$path"}
        if(!$found[0].Selected){throw "DotNetTargetNotWhitelisted:$path"}
    }
    [pscustomobject]@{SchemaVersion=1;Kind='DotNetMigrationBuild';Mode='Plan';SourceRoot=$base;DotNetRoot=$netRoot;PolicyPath=[IO.Path]::GetFullPath($PolicyPath);PolicySha256=(Get-FileHash -LiteralPath $PolicyPath).Hash;Configuration='Release';NoRestore=[bool]$NoRestore;AllDiscovered=[bool]$AllDiscovered;State='NotRun';Complete=$false;Passed=$false;SelectedCount=@($targets | Where-Object Selected).Count;DiscoveredCount=$targets.Count;Results=@($targets | Sort-Object RelativePath -CaseSensitive);DiscoveryGaps=$gaps.ToArray();RunDirectory=$null;ReportPath=$null;MonitorCommand=$null;Scope='Build entry points only; MSBuild can build referenced projects. Building does not approve migration, execute tests or prove an isolated package/evaluated dependency graph.'}
}

function Get-DotNetBuildOutcome {
    <#
    .SYNOPSIS
    Maps the independent process outcome and exit code without inferring success from output text.
    .PARAMETER Native
    Native process receipt returned by Invoke-CiProcess.
    #>
    param($Native)
    if($null -eq $Native){return 'Crash'}
    if($Native.Outcome -ceq 'Timeout'){return 'Timeout'}
    if($Native.Outcome -ceq 'Success' -and $Native.ExitCode -eq 0){return 'Success'}
    return 'Failed'
}

function Invoke-DotNetMigrationBuild {
    <#
    .SYNOPSIS
    Executes selected Release builds in a monitored owned worker; WhatIf only returns a plan.
    .PARAMETER SourceRoot
    Workspace containing Net/FrenchExDev.
    .PARAMETER PolicyPath
    Explicit whitelist policy.
    .PARAMETER ItemId
    Exact configured candidate IDs.
    .PARAMETER Target
    Optional exact Net/FrenchExDev-relative build files.
    .PARAMETER AllDiscovered
    Explicitly assesses every discovered entry point, without migration approval.
    .PARAMETER NoRestore
    Disables implicit restore when an existing assets file is deliberately reused.
    .PARAMETER RunDirectory
    New external progress/log/JSON directory.
    .PARAMETER JsonPath
    Optional additional new JSON report in an existing directory.
    .PARAMETER TimeoutSeconds
    Per-target deadline including SDK resolution.
    .PARAMETER TotalTimeoutSeconds
    Whole worker deadline, retaining terminal diagnostics on timeout/crash.
    .PARAMETER WorkspaceRoot
    Tooling root containing the shared worker supervisor and monitor.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$PolicyPath,
        [string[]]$ItemId,[string[]]$Target,[switch]$AllDiscovered,[switch]$NoRestore,
        [string]$RunDirectory,[string]$JsonPath,[ValidateRange(1,7200)][int]$TimeoutSeconds=300,
        [ValidateRange(1,86400)][int]$TotalTimeoutSeconds=1800,
        [string]$WorkspaceRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
    $ErrorActionPreference='Stop'
    if($PSBoundParameters.ContainsKey('Target') -and !$Target.Count -or $PSBoundParameters.ContainsKey('ItemId') -and !$ItemId.Count){throw 'DotNetEmptySelection'}
    $selection=@{SourceRoot=$SourceRoot;PolicyPath=$PolicyPath;AllDiscovered=$AllDiscovered;NoRestore=$NoRestore}
    if($ItemId){$selection.ItemId=$ItemId};if($Target){$selection.Target=$Target}
    $plan=Get-DotNetMigrationBuildPlan @selection
    if($JsonPath){
        $JsonPath=[IO.Path]::GetFullPath($JsonPath)
        if([IO.Path]::GetExtension($JsonPath) -ine '.json' -or !(Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($JsonPath)) -PathType Container) -or (Test-Path -LiteralPath $JsonPath)){throw 'DotNetJsonDestinationInvalid'}
    }
    if($WhatIfPreference){$plan.Mode='WhatIf';return $plan}
    if(!$plan.SelectedCount){$plan.State='NoTargets';return $plan}
    if(!$IsWindows){throw 'DotNetLocalVisibleMonitorRequiresWindows'}
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'migration-builds') ([guid]::NewGuid().ToString('N'))}
    $RunDirectory=[IO.Path]::GetFullPath($RunDirectory)
    if(Test-Path -LiteralPath $RunDirectory){throw 'DotNetBuildRunExists'}
    if(!$PSCmdlet.ShouldProcess($plan.DotNetRoot,"Run $($plan.SelectedCount) Release builds and write reports to $RunDirectory $JsonPath")){$plan.State='Declined';return $plan}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $plan.RunDirectory=$RunDirectory;$plan.ReportPath=Join-Path $RunDirectory 'build-results.json'
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $workerPath=Join-Path $WorkspaceRoot 'scripts/workers/Invoke-DotNetMigrationBuild.ps1'
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $plan.MonitorCommand="pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    Write-WorkspaceJson (Join-Path $RunDirectory 'request.json') @{Plan=$plan;TimeoutSeconds=$TimeoutSeconds;TotalTimeoutSeconds=$TotalTimeoutSeconds}
    $worker=Start-Process $runner -WindowStyle Hidden -ArgumentList @('-File',(ConvertTo-CiArgument $workerPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
    try{$monitor=Start-Process $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log') -PassThru}catch{if(!$worker.HasExited){$worker.Kill($true)};throw}
    Write-Verbose $plan.MonitorCommand
    $summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TotalTimeoutSeconds
    if($summary.PSObject.Properties['BuildReport']){$report=$summary.BuildReport}
    else{
        $report=$plan;$report.Mode='Build';$report.State=$summary.State.State
        foreach($row in $report.Results | Where-Object Selected){if($row.State -in @('Planned','Running')){$row.State='NotCompleted';$row.Error='Worker terminated without a complete target receipt'}}
        Write-WorkspaceJson $report.ReportPath $report
    }
    if($JsonPath){Write-WorkspaceJson $JsonPath $report}
    return $report
}

function Format-DotNetMigrationBuildTable {
    <#
    .SYNOPSIS
    Renders a bounded static Unicode table; JSON retains full paths and diagnostics.
    .PARAMETER Report
    Plan or build report.
    .PARAMETER Width
    Explicit width or the current console width; redirected fallback is 110.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report,[ValidateRange(0,500)][int]$Width=0)
    Import-Module (Join-Path $PSScriptRoot 'RunFormat.psm1')
    if(!$Width){$Width=if([Console]::IsOutputRedirected){110}else{[Math]::Max(40,[Console]::WindowWidth-1)}}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($row in $Report.Results | Where-Object Selected){$rows.Add(@($row.RelativePath,$row.State,$(if($null -eq $row.ExitCode){'-'}else{[string]$row.ExitCode}),(Format-RunDuration $row.DurationMs)))}
    $names=@($Report.Results | Where-Object Selected | ForEach-Object {if($_.ItemId){$_.ItemId}else{[IO.Path]::GetFileNameWithoutExtension($_.Path)}} | Sort-Object -Unique)
    Format-DotNetBuildCell ("Projet : .NET $($names -join ', ') | Tâche : build Release") $Width
    Format-DotNetBuildCell $Report.SourceRoot $Width
    Format-DotNetBuildCell ("Discovered: $($Report.DiscoveredCount) | Selected: $($Report.SelectedCount) | State: $($Report.State) | Mode: $($Report.Mode)") $Width
    # Unicode grapheme clipping is local presentation; the shared formatter's character-count sizing is not used.
    $columns=@([Math]::Max(8,$Width-37),14,6,12)
    if($Width -lt 48){
        foreach($row in $rows){Format-DotNetBuildCell ([string]$row[0]) $Width;Format-DotNetBuildCell ("$($row[1]) | $($row[2]) | $($row[3])") $Width}
        return
    }
    '┌'+(($columns | ForEach-Object {'─'*$_}) -join '┬')+'┐'
    '│'+((0..3 | ForEach-Object {Format-DotNetBuildCell (@('Target','State','Exit','Duration')[$_]) $columns[$_]}) -join '│')+'│'
    '├'+(($columns | ForEach-Object {'─'*$_}) -join '┼')+'┤'
    foreach($row in $rows){'│'+((0..3 | ForEach-Object {Format-DotNetBuildCell ([string]$row[$_]) $columns[$_] -Right:($_ -ge 2)}) -join '│')+'│'}
    '└'+(($columns | ForEach-Object {'─'*$_}) -join '┴')+'┘'
}

function Format-DotNetBuildCell {
    <#
    .SYNOPSIS
    Measures/clips grapheme cells, strips terminal controls and preserves UTF-8 accents.
    .PARAMETER Text
    Untrusted visible cell text; full original paths remain in JSON.
    .PARAMETER Width
    Available display cells.
    .PARAMETER Right
    Right-aligns numeric cells.
    #>
    param([string]$Text,[int]$Width,[switch]$Right)
    $clean=[regex]::Replace($Text,'\x1B\[[0-?]*[ -/]*[@-~]','') -replace '[\x00-\x1f\x7f]',' '
    $elements=[Globalization.StringInfo]::GetTextElementEnumerator($clean)
    $parts=[Collections.Generic.List[object]]::new();$total=0
    while($elements.MoveNext()){
        $element=[string]$elements.Current;$cells=0
        foreach($rune in $element.EnumerateRunes()){
            $value=$rune.Value;$category=[Text.Rune]::GetUnicodeCategory($rune)
            if($value -in @(0xfe0f,0x20e3)){$cells=2;continue}
            if($category -in @([Globalization.UnicodeCategory]::NonSpacingMark,[Globalization.UnicodeCategory]::EnclosingMark,[Globalization.UnicodeCategory]::Format)){continue}
            $wide=$value -ge 0x1100 -and ($value -le 0x115f -or $value -in @(0x2329,0x232a) -or $value -ge 0x2e80 -and $value -le 0xa4cf -or $value -ge 0xac00 -and $value -le 0xd7a3 -or $value -ge 0xf900 -and $value -le 0xfaff -or $value -ge 0xfe10 -and $value -le 0xfe19 -or $value -ge 0xfe30 -and $value -le 0xfe6f -or $value -ge 0xff00 -and $value -le 0xff60 -or $value -ge 0xffe0 -and $value -le 0xffe6 -or $value -ge 0x1f1e6 -and $value -le 0x1faff -or $value -ge 0x20000 -and $value -le 0x3fffd)
            $cells=[Math]::Max($cells,$(if($wide){2}else{1}))
        }
        $parts.Add([pscustomobject]@{Text=$element;Cells=$cells});$total+=$cells
    }
    $result=[Text.StringBuilder]::new();$used=0;$limit=if($total -gt $Width){[Math]::Max(0,$Width-1)}else{$Width}
    foreach($part in $parts){if($used+$part.Cells -gt $limit){break};[void]$result.Append($part.Text);$used+=$part.Cells}
    if($total -gt $Width){[void]$result.Append('…');$used++}
    $padding=' '*[Math]::Max(0,$Width-$used)
    if($Right){$padding+$result.ToString()}else{$result.ToString()+$padding}
}

Export-ModuleMember -Function Get-DotNetMigrationBuildPlan,Invoke-DotNetMigrationBuild,Format-DotNetMigrationBuildTable
