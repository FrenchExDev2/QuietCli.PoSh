#requires -Version 7.6
function Get-QuietModulePackageIdentity {
    <#
    .SYNOPSIS
    Reads a script module and its optional literal manifest without executing either file.
    .PARAMETER Path
    Existing .psm1 whose filename defines the package name.
    .PARAMETER RequireManifest
    Requires a matching sibling .psd1 for packaging and release consumers.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[switch]$RequireManifest)
    $modulePath=[IO.Path]::GetFullPath($Path,$PWD.Path)
    if([IO.Path]::GetExtension($modulePath) -cne '.psm1' -or !(Test-Path -LiteralPath $modulePath -PathType Leaf)){throw 'ModulePackageScriptModuleRequired'}
    $name=[IO.Path]::GetFileNameWithoutExtension($modulePath)
    if($name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_.-]*\z'){throw 'ModulePackageNameInvalid'}
    if((Get-Item -LiteralPath $modulePath).Length -gt 8MB){throw 'ModulePackageSourceTooLarge'}
    $encoding=[Text.UTF8Encoding]::new($false,$true)
    $text=[IO.File]::ReadAllText($modulePath,$encoding)
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'ModulePackageSourceParseFailed'}
    $manifestPath=[IO.Path]::ChangeExtension($modulePath,'.psd1')
    $hasManifest=Test-Path -LiteralPath $manifestPath -PathType Leaf
    if($RequireManifest -and !$hasManifest){throw 'ModulePackageManifestRequired'}
    $manifest=$null;$version=$null;$guid=$null;$publishable=$null;$dependencies=@()
    if($hasManifest){
        if((Get-Item -LiteralPath $manifestPath).Length -gt 1MB){throw 'ModulePackageManifestTooLarge'}
        $text=[IO.File]::ReadAllText($manifestPath,$encoding)
        $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
        if($errors.Count -or $ast.EndBlock.Statements.Count -ne 1 -or $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.PipelineAst] -or $ast.EndBlock.Statements[0].PipelineElements.Count -ne 1){throw 'ModulePackageManifestInvalid'}
        $expression=$ast.EndBlock.Statements[0].PipelineElements[0]
        if($expression -isnot [Management.Automation.Language.CommandExpressionAst] -or $expression.Expression -isnot [Management.Automation.Language.HashtableAst]){throw 'ModulePackageManifestInvalid'}
        try{$manifest=$expression.Expression.SafeGetValue()}catch{throw 'ModulePackageManifestMustBeLiteral'}
        if($manifest['RootModule'] -cne [IO.Path]::GetFileName($modulePath)){throw 'ModulePackageRootModuleMismatch'}
        if(!$manifest['ModuleVersion']){throw 'ModulePackageVersionRequired'}
        try{$null=[version]$manifest['ModuleVersion']}catch{throw 'ModulePackageVersionInvalid'}
        $version=[string]$manifest['ModuleVersion'];$guid=[string]$manifest['GUID']
        $private=$manifest['PrivateData']
        if($private -is [Collections.IDictionary]){
            $psData=$private['PSData'];$policy=$private['QuietCli']
            if($psData -is [Collections.IDictionary] -and $psData['Prerelease']){$version+='-'+[string]$psData['Prerelease']}
            if($policy -is [Collections.IDictionary]){
                if($policy.Contains('PackageName') -and $policy['PackageName'] -cne $name){throw 'ModulePackageDeclaredNameMismatch'}
                $publishable=$policy['Publishable']
            }
        }
        if($manifest['RequiredModules']){$dependencies=@($manifest['RequiredModules'])}
    }
    [pscustomobject]@{Name=$name;Version=$version;GUID=$guid;ModulePath=$modulePath;ManifestPath=$(if($hasManifest){$manifestPath}else{$null});HasManifest=[bool]$hasManifest;Publishable=$publishable;Dependencies=$dependencies}
}
Export-ModuleMember -Function Get-QuietModulePackageIdentity
