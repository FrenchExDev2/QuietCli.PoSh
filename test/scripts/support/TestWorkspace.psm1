#Objective: Locates the scripts under test and builds isolated fixture workspaces for script tests.
#requires -Version 7.6

function Get-QuietTestScriptsRoot {
    <#
    .SYNOPSIS
    Returns the scripts root under test: QUIETCLI_SCRIPTS_ROOT (a mutated copy) or the repository scripts directory.
    #>
    if(![string]::IsNullOrWhiteSpace($env:QUIETCLI_SCRIPTS_ROOT)){return [IO.Path]::GetFullPath($env:QUIETCLI_SCRIPTS_ROOT)}
    return [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..','..','scripts'))
}

function Get-QuietTestWorkspaceRoot {
    <#
    .SYNOPSIS
    Returns the repository root (QUIETCLI_WORKSPACE_ROOT when set by the runner).
    #>
    if(![string]::IsNullOrWhiteSpace($env:QUIETCLI_WORKSPACE_ROOT)){return [IO.Path]::GetFullPath($env:QUIETCLI_WORKSPACE_ROOT)}
    return [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..','..'))
}

function Import-QuietTestLibrary {
    <#
    .SYNOPSIS
    Imports scripts/lib/<Name>.psm1 from the scripts root under test, globally, replacing a previous import.
    .PARAMETER Name
    Library base name, for example CiImpact.
    #>
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9.-]*$')][string]$Name)
    $path=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'lib',$Name+'.psm1')
    if(![IO.File]::Exists($path)){throw "QuietTestLibraryMissing: $Name"}
    Import-Module $path -Force -DisableNameChecking -Global -ErrorAction Stop -PassThru
}

function New-QuietTestFile {
    <#
    .SYNOPSIS
    Writes a UTF-8 (no BOM, LF) fixture file, creating its directory.
    .PARAMETER Path
    Destination file.
    .PARAMETER Text
    File content.
    #>
    param([Parameter(Mandatory)][string]$Path,[AllowEmptyString()][string]$Text='')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    [IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    return [IO.Path]::GetFullPath($Path)
}

function Invoke-QuietTestScript {
    <#
    .SYNOPSIS
    Runs one entry point in a child pwsh and returns its exit code and captured output.
    .PARAMETER ScriptPath
    Entry point to run with -File.
    .PARAMETER ArgumentList
    Arguments after the script path.
    .PARAMETER Environment
    Extra environment variables for the child.
    .PARAMETER TimeoutSeconds
    Wall-clock limit; the child tree is killed and TimedOut set on expiry.
    #>
    param([Parameter(Mandatory)][string]$ScriptPath,[string[]]$ArgumentList=@(),[hashtable]$Environment=@{},[int]$TimeoutSeconds=600)
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $info=[Diagnostics.ProcessStartInfo]::new($runner)
    foreach($argument in @('-NoProfile','-NonInteractive','-File',$ScriptPath)+$ArgumentList){$info.ArgumentList.Add($argument)}
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.UseShellExecute=$false
    foreach($entry in $Environment.GetEnumerator()){$info.Environment[[string]$entry.Key]=[string]$entry.Value}
    $process=[Diagnostics.Process]::Start($info)
    try{
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $timedOut=!$process.WaitForExit($TimeoutSeconds*1000)
        if($timedOut){$process.Kill($true);$process.WaitForExit()}
        [pscustomobject]@{ExitCode=$process.ExitCode;TimedOut=$timedOut;Output=$stdout.GetAwaiter().GetResult();Error=$stderr.GetAwaiter().GetResult()}
    }finally{$process.Dispose()}
}

Export-ModuleMember -Function Get-QuietTestScriptsRoot,Get-QuietTestWorkspaceRoot,Import-QuietTestLibrary,New-QuietTestFile,Invoke-QuietTestScript
