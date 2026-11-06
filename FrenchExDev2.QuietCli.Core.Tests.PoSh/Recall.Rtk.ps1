function Invoke-QuietRecallRtkComparison {
    <#
    .SYNOPSIS
    Compares explicit command cases or the shared Git and C# fixture corpus in an isolated worker.
    .PARAMETER RunDirectory
    Owned monitored report directory.
    .PARAMETER RtkPath
    Optional explicit installed or temporary RTK executable; never installs software.
    .PARAMETER Cases
    Optional inert case records with FilePath, Arguments, RtkArguments, WorkingDirectory and independent expectations.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RunDirectory,[string]$RtkPath,[object[]]$Cases)
    if(!$RtkPath){$tool=Get-Command rtk -CommandType Application -ErrorAction SilentlyContinue;if($tool){$RtkPath=$tool.Source}}
    if(!$RtkPath){return [pscustomobject]@{State='Unavailable';Reason='RTK is not installed. No comparison was executed.';Version=$null;BinarySHA256=$null}}
    $workspace=Split-Path $PSScriptRoot -Parent
    $arguments=@('-File',(Join-Path $PSScriptRoot 'Recall.Corpus.Worker.ps1'),'-WorkspaceRoot',$workspace,'-RunDirectory',$RunDirectory,'-RtkPath',(Get-Item -LiteralPath $RtkPath).FullName)
    if($PSBoundParameters.ContainsKey('Cases')){
        $path=Join-Path $RunDirectory 'recall-comparison-cases.json'
        [void][IO.File]::WriteAllTextAsync($path,(ConvertTo-Json -InputObject $Cases -Depth 16).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $arguments+=@('-CasesPath',$path)
    }
    $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 300 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList $arguments
    if($result.Outcome -ne 'Success'){throw ('RecallComparisonWorkerFailed: '+($result.Error|ConvertTo-Json -Compress))}
    return $result.Data
}
