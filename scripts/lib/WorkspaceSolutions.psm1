#requires -Version 7.6

Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietWorkspaceSolutions {
    <#
    .SYNOPSIS
    Creates deterministic solution definitions from discovered modules without executing them.
    .PARAMETER WorkspaceRoot
    Checkout containing grouped source/test modules.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $projects=@(Get-QuietWorkspaceProjects $root)
    if(!@($projects|Where-Object {$_.Path.StartsWith('src/',[StringComparison]::Ordinal)}).Count){return}
    $groups=@($projects.SolutionGroup|Sort-Object -Unique)
    foreach($scope in @('')+$groups){
        $relative=if($scope){'src/'+$scope+'/'+$scope+'.slnx'}else{'Quietly.slnx'}
        $base=[IO.Path]::GetDirectoryName((Resolve-QuietWorkspacePath -WorkspaceRoot $root -RelativePath $relative))
        $lines=[Collections.Generic.List[string]]::new();$lines.Add('<Solution>')
        $folders=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($project in $projects|Where-Object {!$scope -or $_.SolutionGroup -ceq $scope}|Sort-Object Path){
            $category=if($project.IsTest){'test'}else{'src'}
            $prefix=if($scope){'/'}else{'/'+$project.SolutionGroup+'/'}
            foreach($folder in @($prefix,($prefix+$category+'/'))){
                if($folder -cne '/' -and $folders.Add($folder)){$lines.Add('  <Folder Name="'+$folder+'" />')}
            }
            $folder=$prefix+$category+'/'+$project.Name+'/'
            $lines.Add('  <Folder Name="'+$folder+'">')
            foreach($file in Get-QuietSourceFiles $project.Directory){
                $extension=[IO.Path]::GetExtension($file.Path)
                if($extension -cnotin @('.csproj','.ps1','.psm1','.psd1','.md')){continue}
                $path=[IO.Path]::GetRelativePath($base,[IO.Path]::Combine($project.Directory,$file.Path)).Replace('\','/')
                $kind=if($extension -ceq '.csproj'){'Project'}else{'File'}
                $lines.Add('    <'+$kind+' Path="'+[Security.SecurityElement]::Escape($path)+'" />')
            }
            $lines.Add('  </Folder>')
        }
        $lines.Add('</Solution>')
        [pscustomobject]@{Path=$relative;Content=($lines -join "`n")+"`n"}
    }
}

function Sync-QuietWorkspaceSolutions {
    <#
    .SYNOPSIS
    Checks solution drift or explicitly writes the generated global and local solutions.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER Apply
    Writes missing or stale definitions; default checks without writes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[switch]$Apply)
    foreach($entry in Get-QuietWorkspaceSolutions $WorkspaceRoot){
        $path=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $entry.Path)
        if((Test-Path -LiteralPath $path) -and [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq $entry.Content){continue}
        if(!$Apply){throw ('WorkspaceSolutionDrift: '+$entry.Path)}
        if($PSCmdlet.ShouldProcess($path,'Synchronize generated solution')){
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            [void][IO.File]::WriteAllTextAsync($path,$entry.Content,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }
    }
}
Export-ModuleMember -Function Get-QuietWorkspaceSolutions,Sync-QuietWorkspaceSolutions
