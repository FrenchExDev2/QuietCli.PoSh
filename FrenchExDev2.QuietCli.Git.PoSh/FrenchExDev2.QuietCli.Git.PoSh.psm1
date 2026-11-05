#requires -Version 7.6
$script:GitRoot=$PSScriptRoot
$script:GitModuleManifest=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Git.PoSh.psd1')
$script:GitModuleVersion=[string]$script:GitModuleManifest.ModuleVersion
if($script:GitModuleManifest.PrivateData.PSData.ContainsKey('Prerelease') -and $script:GitModuleManifest.PrivateData.PSData.Prerelease){$script:GitModuleVersion+='-'+$script:GitModuleManifest.PrivateData.PSData.Prerelease}
$script:GitContractRoot=$PSScriptRoot
$script:GitInventory=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'metadata/Git.Inventory.json') -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable -Depth 50
$script:GitSpecifications=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'metadata/Git.Contracts.json') -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable -Depth 50
$script:GitArgumentSchema=$null
$script:GitParserAssembly=$null
$script:GitArtifacts=@{}
$script:GitHandlerCatalogue=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'metadata/Git.HandlerCatalogue.json') -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
foreach($source in @('Managed','Arguments','ArgumentSchema','StatusRecords','Records','Diff','History','Repository','Semantics','RepositoryCommands','Queries','Commands')){. (Join-Path $PSScriptRoot "src/$source.ps1")}
$script:GitExecutors=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($entry in $script:GitHandlerCatalogue.Handlers.GetEnumerator()){
    if($entry.Value -notmatch '^Invoke-QuietGit[A-Za-z]+$'){throw 'InvalidGitHandlerFunction'}
    $script:GitExecutors.Add($entry.Key,(Get-Command $entry.Value -CommandType Function -ErrorAction Stop))
}
$script:GitHandlerCatalogue.Commands=@($script:GitExecutors.Keys)
Register-QuietHandler -Id 'FrenchExDev2.QuietCli.Git.PoSh' -Definition @{
 Binary='git';ModuleVersion=$script:GitModuleVersion;VersionRange='stable >=2.40.0 <2.57.0, including .windows.N'
 Summary='Observed Git operation.';Qualification='Partial'
 Documentation=@('https://git-scm.com/docs/git','https://git-scm.com/docs/git-status','https://git-scm.com/docs/git-commit','https://git-scm.com/docs/git-push')
 SupportedForms=@($script:GitExecutors.Keys)
 Probe={param($runtime)
    $r=quiet -AsObject -Role Probe -WorkingDirectory $runtime.Request.WorkingDirectory -Environment $runtime.Request.Environment -TimeoutSeconds $runtime.Request.TimeoutSeconds -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){if($r.Data.Length+$e.Text.Length -gt 1024){throw 'VersionProbeTooLarge'};[void]$r.Data.Append($e.Text)}} -Complete {param($r)if($r.Data.ToString() -notmatch '^git version (\S+)'){throw 'UnexpectedGitVersion'};$Matches[1]} -FilePath $runtime.Request.FilePath -ArgumentList @('--version')
    if($r.Outcome -ne 'Success'){throw 'GitVersionProbeFailed'}
    $r.Data
 }
 TestVersion={param($version)if($version -notmatch '^(2\.\d+\.\d+)(?:\.windows\.\d+)?$'){return $false};$numeric=[version]$Matches[1];$numeric -ge [version]'2.40.0' -and $numeric -lt [version]'2.57.0'}
 Match={param($request,$version)$parsed=Get-GitInvocation @{ArgumentList=$request.ArgumentList};!$parsed.Error}
 Execute={param($runtime)Invoke-QuietGitCommand $runtime}
}
$ExecutionContext.SessionState.Module.OnRemove={Unregister-QuietHandler -Id 'FrenchExDev2.QuietCli.Git.PoSh'}
Export-ModuleMember -Function Get-QuietGitCoverage,Remove-QuietGitArtifact
