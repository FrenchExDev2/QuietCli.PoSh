#requires -Version 7.6
Set-StrictMode -Version Latest

function Read-MigrationXml {
    <#
    .SYNOPSIS
    Parses bounded build XML without resolving DTDs or external entities.
    .PARAMETER Path
    Absolute project or solution XML path.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 4MB
    $text = [IO.File]::ReadAllTextAsync($Path,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($text),$settings)
    try { $document = [Xml.XmlDocument]::new(); $document.XmlResolver=$null; $document.Load($reader); return ,$document }
    finally { $reader.Dispose() }
}

function Get-MigrationDependencyReport {
    <#
    .SYNOPSIS
    Inspects whitelisted source trees without importing scripts or evaluating MSBuild.
    .PARAMETER SourceRoot
    Existing workspace containing the whitelist's relative paths.
    .PARAMETER PolicyPath
    Explicit JSON selection and external dependency decisions.
    .PARAMETER ItemId
    Optional identifiers from that policy; unknown identifiers are refused.
    .PARAMETER MaximumFiles
    Bound on visited files, including ignored file types.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PolicyPath,
        [string[]]$ItemId,
        [ValidateRange(1,100000)][int]$MaximumFiles=30000)
    $ErrorActionPreference='Stop'
    $base=[IO.Path]::GetFullPath($SourceRoot)
    if(!(Test-Path -LiteralPath $base -PathType Container)){throw 'MigrationSourceRootMissing'}
    if((Get-Item -LiteralPath $base).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'MigrationRootIsLink'}
    if((Get-Item -LiteralPath $PolicyPath).Length -gt 4MB){throw 'MigrationPolicyTooLarge'}
    $policy=ConvertFrom-Json ([IO.File]::ReadAllTextAsync($PolicyPath,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()) -Depth 32
    if($policy.schemaVersion -ne 1 -or $policy.default -cne 'Exclude' -or !$policy.items.Count){throw 'MigrationPolicyInvalid'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $roots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $policy.items){
        if($item.id -cnotmatch '^[A-Za-z][A-Za-z0-9-]{0,63}$' -or !$seen.Add($item.id) -or
            $item.intent -cnotin @('Assess','Migrate','Create','Exclude') -or $item.approved -isnot [bool]){throw 'MigrationPolicyItemInvalid'}
        if([IO.Path]::IsPathRooted($item.path) -or $item.path -match '(^|[/\\])\.\.([/\\]|$)'){throw 'MigrationPolicyPathInvalid'}
        $candidate=[IO.Path]::GetFullPath((Join-Path $base $item.path))
        $relative=[IO.Path]::GetRelativePath($base,$candidate)
        if($relative -eq '.' -or $relative.StartsWith('..') -or !$roots.Add($candidate)){throw 'MigrationPolicyPathInvalid'}
    }
    foreach($id in $ItemId){if(!$seen.Contains($id)){throw "MigrationItemNotWhitelisted:$id"}}
    $selected=@($policy.items | Where-Object { $_.intent -cne 'Exclude' -and (!$ItemId -or $_.id -cin $ItemId) })
    $records=[Collections.Generic.List[object]]::new()
    $edges=[Collections.Generic.List[object]]::new()
    $issues=[Collections.Generic.List[string]]::new()
    $assessments=[Collections.Generic.List[object]]::new()
    $functions=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $fileCount=0
    $excluded=@('.git','.vs','bin','obj','node_modules','.tools','.cache','artifacts','packages')
    foreach($item in $selected){
        $itemRoot=[IO.Path]::GetFullPath((Join-Path $base $item.path))
        $owned=[Collections.Generic.List[object]]::new()
        $emptyDirectories=[Collections.Generic.List[string]]::new()
        $empty=$true; $itemIssues=[Collections.Generic.List[string]]::new()
        if(!(Test-Path -LiteralPath $itemRoot -PathType Container)){$itemIssues.Add('MissingSource');$empty=$false}
        else {
            $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($itemRoot)
            while($queue.Count){
                $directory=$queue.Dequeue()
                if((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){$itemIssues.Add("LinkNotTraversed:$directory");continue}
                $children=@(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
                if(!@($children | Where-Object {$_.PSIsContainer -or $_.Name -ne '.gitkeep'}).Count){$emptyDirectories.Add([IO.Path]::GetRelativePath($base,$directory).Replace('\','/'))}
                foreach($entry in $children){
                    if($entry.PSIsContainer){if($entry.Name -cnotin $excluded){$queue.Enqueue($entry.FullName)};continue}
                    $fileCount++;if($fileCount -gt $MaximumFiles){throw 'MigrationInventoryLimit'}
                    if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){$itemIssues.Add("LinkNotRead:$($entry.FullName)");continue}
                    if($entry.Name -eq '.gitkeep'){continue}
                    if($entry.Name -notin @('.gitignore','.gitattributes','.editorconfig')){$empty=$false}
                    $extension=$entry.Extension.ToLowerInvariant()
                    if($extension -cnotin @('.ps1','.psm1','.psd1','.csproj','.sln','.slnx','.props','.targets')){continue}
                    if($entry.Length -gt 4MB){$itemIssues.Add("FileTooLarge:$($entry.FullName)");continue}
                    $record=[pscustomobject]@{Item=$item.id;Path=[IO.Path]::GetRelativePath($base,$entry.FullName).Replace('\','/');Kind=$extension;Sha256=(Get-FileHash -LiteralPath $entry.FullName).Hash;Status='Inspected'}
                    $owned.Add($record);$records.Add($record)
                    try {
                        $references=[Collections.Generic.List[object]]::new()
                        $text=[IO.File]::ReadAllTextAsync($entry.FullName,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
                        if($extension -in @('.csproj','.slnx','.props','.targets')){
                            $xml=Read-MigrationXml $entry.FullName
                            foreach($node in $xml.SelectNodes('//*[local-name()="ProjectReference" or local-name()="Import" or local-name()="PackageReference" or local-name()="PackageVersion" or local-name()="Project"]')){
                                $kind=$node.LocalName
                                $target=if($kind -eq 'Import'){$node.GetAttribute('Project')}elseif($extension -eq '.slnx' -and $kind -eq 'Project'){$node.GetAttribute('Path')}else{$node.GetAttribute('Include')}
                                if(!$target -and $kind -in @('PackageReference','PackageVersion')){$target=$node.GetAttribute('Update')}
                                if(!$target){continue}
                                if($kind -eq 'Project'){$kind='ProjectReference'}
                                $version=$node.GetAttribute('Version')
                                if(!$version){$versionNode=$node.SelectSingleNode('*[local-name()="Version"]');if($versionNode){$version=$versionNode.InnerText}}
                                $conditional=$false
                                for($parent=$node;$null -ne $parent -and $parent -is [Xml.XmlElement];$parent=$parent.ParentNode){if($parent.HasAttribute('Condition')){$conditional=$true}}
                                $references.Add([pscustomobject]@{Kind=$kind;Target=$target;Version=$version;Conditional=$conditional;Line=$null})
                            }
                        } elseif($extension -eq '.sln'){
                            foreach($match in [regex]::Matches($text,'(?m)^Project\("[^"\r\n]+"\)\s*=\s*"[^"\r\n]+",\s*"(?<path>[^"\r\n]+\.(?:csproj|slnx))"')){
                                $references.Add([pscustomobject]@{Kind='ProjectReference';Target=$match.Groups['path'].Value;Version='';Conditional=$false;Line=$null})
                            }
                        } else {
                            $tokens=$null;$parseErrors=$null
                            $ast=[Management.Automation.Language.Parser]::ParseInput($text,$entry.FullName,[ref]$tokens,[ref]$parseErrors)
                            if($parseErrors.Count){throw "PowerShellParse:$($parseErrors[0].ErrorId)"}
                            foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
                                if(!$functions.ContainsKey($function.Name)){$functions[$function.Name]=[Collections.Generic.List[string]]::new()}
                                $functions[$function.Name].Add($record.Path)
                            }
                            foreach($required in $(if($null -ne $ast.ScriptRequirements){$ast.ScriptRequirements.RequiredModules})){
                                $minimum=$required.PSObject.Properties['Version'];$maximum=$required.PSObject.Properties['MaximumVersion']
                                $range=($null -ne $minimum -and $null -ne $minimum.Value) -or ($null -ne $maximum -and $null -ne $maximum.Value)
                                $requiredVersion=if($required.RequiredVersion){[string]$required.RequiredVersion}elseif($minimum -and $minimum.Value){[string]$minimum.Value}else{''}
                                $references.Add([pscustomobject]@{Kind='Module';Target=$required.Name;Version=$requiredVersion;Conditional=[bool]$range;Line=1})
                            }
                            foreach($statement in $ast.FindAll({param($n) $n -is [Management.Automation.Language.UsingStatementAst]},$true)){
                                if($statement.UsingStatementKind -in @('Module','Assembly')){$references.Add([pscustomobject]@{Kind=[string]$statement.UsingStatementKind;Target=$statement.Name.Value;Version='';Conditional=$false;Line=$statement.Extent.StartLineNumber})}
                            }
                            foreach($command in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)){
                                $name=$command.GetCommandName()
                                if($command.InvocationOperator -eq 'Dot'){
                                    $target=try{[string]$command.CommandElements[0].SafeGetValue()}catch{$command.CommandElements[0].Extent.Text}
                                    $references.Add([pscustomobject]@{Kind='Script';Target=$target;Version='';Conditional=$false;Line=$command.Extent.StartLineNumber})
                                } elseif(!$name -and $command.CommandElements[0] -isnot [Management.Automation.Language.ScriptBlockExpressionAst]){
                                    $references.Add([pscustomobject]@{Kind='DynamicCommand';Target=$command.CommandElements[0].Extent.Text;Version='';Conditional=$true;Line=$command.Extent.StartLineNumber})
                                } elseif($name -in @('Import-Module','ipmo','Add-Type')){
                                    $target=$null
                                    for($index=1;$index -lt $command.CommandElements.Count;$index++){
                                        $element=$command.CommandElements[$index]
                                        if($element -is [Management.Automation.Language.CommandParameterAst]){
                                            if($element.ParameterName -in @('Name','Path','LiteralPath','AssemblyName','FullyQualifiedName') -and $index+1 -lt $command.CommandElements.Count){$index++;$target=try{[string]$command.CommandElements[$index].SafeGetValue()}catch{$command.CommandElements[$index].Extent.Text};break}
                                            continue
                                        }
                                        $target=try{[string]$element.SafeGetValue()}catch{$element.Extent.Text};break
                                    }
                                    if(!$target){$target=$command.Extent.Text}
                                    $version='';$versionConditional=$false
                                    for($index=1;$index -lt $command.CommandElements.Count;$index++){
                                        $element=$command.CommandElements[$index]
                                        if($element -is [Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -in @('RequiredVersion','MinimumVersion','MaximumVersion')){
                                            $valueAst=if($element.Argument){$element.Argument}elseif($index+1 -lt $command.CommandElements.Count){$command.CommandElements[$index+1]}else{$null}
                                            if($null -eq $valueAst){$versionConditional=$true;continue}
                                            $version=try{[string]$valueAst.SafeGetValue()}catch{$valueAst.Extent.Text}
                                            if($element.ParameterName -ne 'RequiredVersion'){$versionConditional=$true}
                                        }
                                    }
                                    $references.Add([pscustomobject]@{Kind=if($name -eq 'Add-Type'){'Assembly'}else{'Module'};Target=$target;Version=$version;Conditional=$versionConditional;Line=$command.Extent.StartLineNumber})
                                } elseif($name -match '\.ps1$'){
                                    $references.Add([pscustomobject]@{Kind='Script';Target=$name;Version='';Conditional=$false;Line=$command.Extent.StartLineNumber})
                                } elseif($name){
                                    $references.Add([pscustomobject]@{Kind='Command';Target=$name;Version='';Conditional=$false;Line=$command.Extent.StartLineNumber})
                                }
                            }
                            if($extension -eq '.psd1'){
                                $data=Import-PowerShellDataFile -LiteralPath $entry.FullName -ErrorAction Stop
                                foreach($field in @('RootModule','RequiredModules','NestedModules','RequiredAssemblies','ScriptsToProcess')){
                                    foreach($dependency in $data[$field]){
                                        if(!$dependency){continue}
                                        $target=if($dependency -is [Collections.IDictionary]){$dependency.ModuleName}else{[string]$dependency}
                                        $version=if($dependency -is [Collections.IDictionary]){[string]$dependency.RequiredVersion}else{''}
                                        $references.Add([pscustomobject]@{Kind=if($field -in @('RootModule','NestedModules','ScriptsToProcess')){'Script'}elseif($field -eq 'RequiredAssemblies'){'Assembly'}else{'Module'};Target=$target;Version=$version;Conditional=$false;Line=$null})
                                    }
                                }
                            }
                        }
                        foreach($reference in $references){
                            $state='NeedsDecision';$resolved=$null
                            $target=[string]$reference.Target
                            $decision=@($policy.externalDependencies | Where-Object { $_.kind -ceq $reference.Kind -and $_.name -ceq $target -and $_.version -and $_.source })
                            if($reference.Conditional -or $target -match '\$|\*|\?|;' -or $reference.Version -match '\$|\*|\[|\]'){$state='NeedsEvaluation'}
                            elseif($reference.Kind -in @('ProjectReference','Import','Script') -or $target -match '[/\\]|\.(psd1|psm1|dll)$'){
                                $resolved=[IO.Path]::GetFullPath((Join-Path $entry.DirectoryName $target.Replace('\',[IO.Path]::DirectorySeparatorChar)))
                                $rel=[IO.Path]::GetRelativePath($base,$resolved)
                                if($rel.StartsWith('..') -or [IO.Path]::IsPathRooted($rel)){$state='OutsideSourceRoot'}
                                elseif(!(Test-Path -LiteralPath $resolved -PathType Leaf)){$state='Missing'}
                                else {
                                    $state='OutsideWhitelist'
                                    foreach($candidate in $selected){
                                        $allowed=[IO.Path]::GetFullPath((Join-Path $base $candidate.path))
                                        $within=[IO.Path]::GetRelativePath($allowed,$resolved)
                                        if(!$within.StartsWith('..') -and ![IO.Path]::IsPathRooted($within)){$state='ResolvedLocal';break}
                                    }
                                }
                            } elseif($decision.Count -eq 1){
                                $state=if($reference.Version -and $reference.Version -cne $decision[0].version){'VersionMismatch'}else{'DeclaredExternal'}
                            }
                            $edges.Add([pscustomobject]@{Item=$item.id;From=$record.Path;Kind=$reference.Kind;Target=$target;Version=$reference.Version;Resolved=$resolved;State=$state;Line=$reference.Line})
                        }
                        # MSBuild implicit SDK and ancestor imports require evaluated evidence, never a static pass.
                        if($extension -eq '.csproj'){$itemIssues.Add("EvaluatedBuildGraphRequired:$($record.Path)")}
                    } catch {$record.Status='Unreadable';$itemIssues.Add("ParseFailure:$($record.Path):$($_.Exception.Message)")}
                }
            }
        }
        $unresolved=@($edges | Where-Object {$_.Item -ceq $item.id -and $_.State -cnotin @('ResolvedLocal','DeclaredExternal')})
        if($unresolved.Count){$itemIssues.Add("UnresolvedDependencies:$($unresolved.Count)")}
        if(!$item.approved -or $item.intent -eq 'Assess'){$itemIssues.Add('SelectionNotApproved')}
        if($empty -and $item.intent -ne 'Create'){$itemIssues.Add('EmptySourceRequiresCreateDecision')}
        if($empty -and $item.intent -eq 'Create'){$itemIssues.Add('NoExistingBehaviorToMigrate')}
        foreach($issue in $itemIssues){$issues.Add("$($item.id):$issue")}
        $assessments.Add([pscustomobject]@{Id=$item.id;Path=$item.path;Intent=$item.intent;Approved=$item.approved;StructureOnly=$empty;EmptyDirectories=$emptyDirectories.ToArray();Eligibility=if($empty){'ScaffoldCandidate'}else{'AssessmentCandidate'};Files=$owned.Count;Unresolved=$unresolved.Count;DependencyGate=if($itemIssues.Count){'Blocked'}else{'Passed'};Issues=$itemIssues.ToArray();MigrationQualification='NotAssessed'})
    }
    # Local function names are only declarations; visibility and shadowing still require runtime qualification.
    foreach($edge in $edges){
        if($edge.Kind -ceq 'Command' -and $edge.State -ceq 'NeedsDecision' -and $functions.ContainsKey($edge.Target)){
            $edge.State='NeedsScopeQualification'
        }
    }
    $graph=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($record in $records){$graph[[IO.Path]::GetFullPath((Join-Path $base $record.Path))]=[Collections.Generic.List[string]]::new()}
    foreach($edge in $edges){
        if($edge.State -ceq 'ResolvedLocal' -and $graph.ContainsKey($edge.Resolved)){$graph[[IO.Path]::GetFullPath((Join-Path $base $edge.From))].Add($edge.Resolved)}
    }
    while($graph.Count){
        $ready=@($graph.Keys | Where-Object { $key=$_; @($graph[$key] | Where-Object {$graph.ContainsKey($_)}).Count -eq 0 })
        if(!$ready.Count){$issues.Add("DependencyCycle:$((@($graph.Keys) | Sort-Object) -join ',')");break}
        foreach($key in $ready){[void]$graph.Remove($key)}
    }
    [pscustomobject]@{SchemaVersion=1;Gate='MigrationDependencies';Passed=($assessments.Count -gt 0 -and !$issues.Count);SourceRoot=$base;PolicyPath=[IO.Path]::GetFullPath($PolicyPath);PolicySha256=(Get-FileHash -LiteralPath $PolicyPath).Hash;CheckerSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;VisitedFiles=$fileCount;Items=$assessments.ToArray();Files=$records.ToArray();Dependencies=$edges.ToArray();Issues=$issues.ToArray();MigrationQualification='NotAssessed';Limitations=@('Static declarations only; no script execution, module import, MSBuild restore/evaluation or C# semantic compilation.','Computed commands, reflection and runtime/native dependencies require explicit additional evidence.','An empty structure is a creation candidate, never a successful code migration.','A dependency report alone cannot authorize cutover; behavior, package restore and rollback gates remain mandatory.')}
}

function Export-MigrationDependencyReport {
    <#
    .SYNOPSIS
    Saves an explicit dependency report; preview performs no write.
    .PARAMETER Report
    Report produced by Get-MigrationDependencyReport.
    .PARAMETER Path
    New JSON report in an existing directory; existing evidence is never overwritten.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Report,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetExtension($full) -ine '.json' -or !(Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($full)) -PathType Container)){throw 'MigrationReportPathInvalid'}
    if(Test-Path -LiteralPath $full){throw 'MigrationReportExists'}
    if($PSCmdlet.ShouldProcess($full,'Create migration dependency evidence')){
        $content=(ConvertTo-Json $Report -Depth 32).Replace("`r`n","`n")+"`n"
        [void][IO.File]::WriteAllTextAsync($full,$content,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
}

function Test-MigrationQualification {
    <#
    .SYNOPSIS
    Checks fresh dependency evidence and requires qualification of the checker itself before migration.
    .PARAMETER DependencyReportPath
    Saved report whose source, policy and checker hashes are revalidated.
    .PARAMETER ToolingSummaryPath
    Complete monitored roadmap-tooling summary with property, fuzz and mutation results.
    .PARAMETER AcceptanceReceiptPath
    Optional product receipt binding tests, isolated package restore and recovery artifacts to this dependency report.
    .PARAMETER ExportSummaryPath
    Optional actual-import summaries covering selected PowerShell module entries.
    .PARAMETER DotNetBuildReportPath
    Real Release build report required when selected .NET solution/project entries are present.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DependencyReportPath,
        [Parameter(Mandatory)][string]$ToolingSummaryPath,[string]$AcceptanceReceiptPath,[string[]]$ExportSummaryPath,[string]$DotNetBuildReportPath)
    $ErrorActionPreference='Stop'
    $errors=[Collections.Generic.List[string]]::new()
    try{
        $report=Get-Content -LiteralPath $DependencyReportPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 64
        $summary=Get-Content -LiteralPath $ToolingSummaryPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 64
        if(!$report.Passed -or $report.Gate -cne 'MigrationDependencies'){$errors.Add('DependencyGateBlocked')}
        if((Get-FileHash -LiteralPath $report.PolicyPath).Hash -cne $report.PolicySha256){$errors.Add('StaleMigrationPolicy')}
        if((Get-FileHash -LiteralPath $PSCommandPath).Hash -cne $report.CheckerSha256){$errors.Add('StaleDependencyChecker')}
        foreach($file in $report.Files){
            $path=[IO.Path]::GetFullPath((Join-Path $report.SourceRoot $file.Path))
            $relative=[IO.Path]::GetRelativePath($report.SourceRoot,$path)
            if($relative.StartsWith('..') -or [IO.Path]::IsPathRooted($relative) -or (Get-FileHash -LiteralPath $path).Hash -cne $file.Sha256){$errors.Add("StaleOrInvalidSource:$($file.Path)")}
        }
        if($summary.State.State -cne 'Success' -or $summary.State.Failed -ne 0){$errors.Add('CheckerQualificationFailed')}
        foreach($category in @('property','fuzz','mutation')){
            $result=@($summary.Categories | Where-Object Category -CEQ $category)
            if($result.Count -ne 1 -or $result[0].Executed -lt 1 -or $result[0].Failed -ne 0){$errors.Add("MissingCheckerCampaign:$category")}
        }
        $dotNetEntries=@($report.Files | Where-Object {$_.Kind -in @('.slnx','.sln','.csproj')})
        $checkerNames=@('Migration.Dependencies.psm1','Migration.Exports.psm1')
        if($dotNetEntries.Count){$checkerNames+=@('Migration.DotNet.psm1')}
        foreach($name in $checkerNames){
            $path=Join-Path $PSScriptRoot $name
            $identity=@($summary.Sources | Where-Object Path -EQ $path)
            if($identity.Count -ne 1 -or $identity[0].Sha256 -cne (Get-FileHash -LiteralPath $path).Hash){$errors.Add("CheckerNotQualified:$name")}
        }
        if($dotNetEntries.Count){
            if(!$DotNetBuildReportPath){$errors.Add('MissingDotNetReleaseBuildEvidence')}
            else{
                $buildReport=Get-Content -LiteralPath $DotNetBuildReportPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
                if($buildReport.Mode -cne 'Build' -or $buildReport.Configuration -cne 'Release' -or !$buildReport.Complete -or !$buildReport.Passed -or $buildReport.State -cne 'Success' -or $buildReport.PolicySha256 -cne $report.PolicySha256){$errors.Add('DotNetReleaseBuildNotQualified')}
                foreach($entry in $dotNetEntries){
                    $source=[IO.Path]::GetFullPath((Join-Path $report.SourceRoot $entry.Path))
                    $build=@($buildReport.Results | Where-Object {$_.Path -eq $source -and $_.Selected -and $_.State -ceq 'Success' -and $_.ExitCode -eq 0 -and $_.Sha256 -ceq $entry.Sha256})
                    if($build.Count -ne 1){$errors.Add("MissingSuccessfulDotNetEntry:$($entry.Path)")}
                }
            }
        }
        $exportReports=@(foreach($path in $ExportSummaryPath){Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32})
        foreach($module in @($report.Files | Where-Object Kind -CEQ '.psm1')){
            $source=[IO.Path]::GetFullPath((Join-Path $report.SourceRoot $module.Path))
            $proof=@($exportReports | Where-Object {$_.State.State -ceq 'Success' -and $_.Qualification -ceq 'ExportContractPassed' -and $_.Observation.Comparison.Functions -and $_.Observation.Comparison.Cmdlets -and $_.Observation.OriginalModulePath -eq $source -and $_.Observation.LoadedModuleSha256 -ceq $module.Sha256})
            if(!$proof.Count){$errors.Add("MissingActualExportContract:$($module.Path)")}
        }
        if(!$AcceptanceReceiptPath){$errors.Add('MissingProductTestsRestoreRecoveryEvidence')}
        else{
            $receipt=Get-Content -LiteralPath $AcceptanceReceiptPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
            if($receipt.DependencyReportSha256 -cne (Get-FileHash -LiteralPath $DependencyReportPath).Hash){$errors.Add('AcceptanceScopeMismatch')}
            foreach($kind in @('Tests','Restore','Recovery')){
                $evidence=$receipt.$kind
                if($evidence.State -cne 'Passed' -or !$evidence.Artifacts.Count){$errors.Add("MissingAcceptanceEvidence:$kind");continue}
                foreach($artifact in $evidence.Artifacts){if((Get-FileHash -LiteralPath $artifact.Path).Hash -cne $artifact.Sha256){$errors.Add("AcceptanceArtifactChanged:$kind")}}
            }
        }
    }catch{$errors.Add("InvalidMigrationEvidence:$($_.Exception.Message)")}
    [pscustomobject]@{Gate='MigrationQualification';Passed=(!$errors.Count);Errors=$errors.ToArray();Scope='Evidence freshness and required gates; semantic adequacy of product acceptance requires the responsible reviewer.'}
}

Export-ModuleMember -Function Get-MigrationDependencyReport,Export-MigrationDependencyReport,Test-MigrationQualification
