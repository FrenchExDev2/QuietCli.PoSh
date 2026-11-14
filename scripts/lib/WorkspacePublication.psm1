Import-Module ([IO.Path]::Combine($PSScriptRoot,'Common.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-WorkspacePublication {
    <#
    .SYNOPSIS
    Publishes into a fresh directory before replacing distribution files, including loaded Windows assemblies.
    .PARAMETER Arguments
    Exact dotnet publish arguments, including one absolute -o output directory.
    .PARAMETER WorkspaceRoot
    Checkout used as the native working directory and publication boundary.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$WorkspaceRoot)
    $outputIndex=[Array]::IndexOf($Arguments,'-o')
    if($Arguments[0] -cne 'publish' -or $outputIndex -lt 0 -or $outputIndex+1 -ge $Arguments.Count -or @($Arguments|Where-Object {$_ -ceq '-o'}).Count -ne 1){throw 'WorkspacePublicationArgumentsInvalid'}
    if(![IO.Path]::IsPathFullyQualified($Arguments[$outputIndex+1])){throw 'WorkspacePublicationOutputNotAbsolute'}
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot))
    $output=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Arguments[$outputIndex+1]))
    $relative=[IO.Path]::GetRelativePath($root,$output)
    if($relative -eq '.' -or $relative -eq '..' -or $relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -or [IO.Path]::IsPathRooted($relative)){throw 'WorkspacePublicationOutsideWorkspace'}
    for($path=$output;$path -ne $root;$path=[IO.Path]::GetDirectoryName($path)){
        if([IO.Directory]::Exists($path) -and ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint)){throw 'WorkspacePublicationLinkedDirectory'}
    }
    if(!$PSCmdlet.ShouldProcess($output,'Prepare and replace compiled distribution files')){return}
    $id=[guid]::NewGuid().ToString('N')
    $staging=[IO.Path]::Combine($output,('.quiet-publish-'+$id))
    $backup=[IO.Path]::Combine($output,('.quiet-previous-'+$id))
    [void][IO.Directory]::CreateDirectory($staging)
    $moved=[Collections.Generic.List[object]]::new()
    $published=$false
    $restored=$false
    try{
        $nativeArguments=[string[]]$Arguments.Clone()
        $nativeArguments[$outputIndex+1]=$staging
        $result=Invoke-WorkspaceNative dotnet $nativeArguments $WorkspaceRoot
        # Replace only published files; unrelated nested RID slots remain untouched.
        $files=@(Get-ChildItem -LiteralPath $staging -File -Force -Recurse | Sort-Object FullName)
        if(!$files.Count){throw 'WorkspacePublicationEmpty'}
        [void][IO.Directory]::CreateDirectory($backup)
        foreach($file in $files){
            $name=[IO.Path]::GetRelativePath($staging,$file.FullName)
            $destination=[IO.Path]::Combine($output,$name)
            $previous=[IO.Path]::Combine($backup,$name)
            for($path=[IO.Path]::GetDirectoryName($destination);$path -ne $output;$path=[IO.Path]::GetDirectoryName($path)){
                if([IO.Directory]::Exists($path) -and ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint)){throw 'WorkspacePublicationLinkedDirectory'}
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($previous))
            $entry=[pscustomobject]@{Destination=$destination;Previous=$previous;HadPrevious=[IO.File]::Exists($destination);Installed=$false}
            # Renaming leaves mapped assemblies usable by their existing processes on Windows.
            if($entry.HadPrevious){[IO.File]::Move($destination,$previous)}
            $moved.Add($entry)
            [IO.File]::Move($file.FullName,$destination)
            $entry.Installed=$true
        }
        $published=$true
        $result
    }catch{
        try{
            for($index=$moved.Count-1;$index -ge 0;$index--){
                $entry=$moved[$index]
                if($entry.Installed){[IO.File]::Delete($entry.Destination)}
                if($entry.HadPrevious){[IO.File]::Move($entry.Previous,$entry.Destination)}
            }
        }catch{
            throw ('WorkspacePublicationRollbackFailed: previous files retained at '+$backup+'; '+$_.Exception.Message)
        }
        $restored=$true
        throw
    }finally{
        if([IO.Directory]::Exists($staging)){[IO.Directory]::Delete($staging,$true)}
        if(($published -or $restored) -and [IO.Directory]::Exists($backup)){
            try{[IO.Directory]::Delete($backup,$true)}catch{
                $state=if($published){'Published'}else{'Restored'}
                Write-Warning ($state+' distribution; previous files still in use are retained at '+$backup+'. Close the sessions using the old assemblies before removing this directory.')
            }
        }
    }
}

Export-ModuleMember -Function Invoke-WorkspacePublication
