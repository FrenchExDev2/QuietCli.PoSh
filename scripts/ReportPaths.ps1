# Shared local report locations; explicit run paths remain authoritative.
function Get-QuietReportRoot {
    <#
    .SYNOPSIS
    Separates local temporary reports by workspace while retaining CI artifact upload paths.
    .PARAMETER WorkspaceRoot
    Absolute or current-directory-relative monorepo root.
    .PARAMETER Category
    Single report category, never a relative path.
    .PARAMETER ContinuousIntegration
    Uses workspace artifacts for existing CI upload contracts.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$Category,[bool]$ContinuousIntegration=($env:CI -ceq 'true' -or $env:GITHUB_ACTIONS -ceq 'true'))
    $workspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path))
    if($ContinuousIntegration){return Join-Path $workspace ('artifacts/'+$Category)}
    $identity=if($IsWindows){$workspace.ToUpperInvariant()}else{$workspace}
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))).Substring(0,12).ToLowerInvariant()
    return Join-Path ([IO.Path]::GetTempPath()) ('QuietCli2/'+$hash+'/'+$Category)
}
