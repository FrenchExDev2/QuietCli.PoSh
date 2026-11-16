#requires -Version 7.6
function Resolve-QuietWorkspacePath {
    <#
    .SYNOPSIS
    Resolves a module identity or its child path in a grouped checkout or an isolated legacy fixture.
    .PARAMETER WorkspaceRoot
    Explicit checkout or fixture root.
    .PARAMETER RelativePath
    Module identity followed by an optional slash-separated child path.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RelativePath)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    if([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Replace('\','/').Split('/') -contains '..'){throw 'WorkspaceRelativePathInvalid'}
    $portable=$RelativePath.Replace('\','/')
    if($portable -cmatch '\Asrc/[A-Z][A-Za-z0-9]*/(?:src|test)/(?<module>FrenchExDev2\.QuietCli\.[A-Za-z0-9.]+\.PoSh)(?:/(?<tail>.*))?\z'){
        $module=$Matches.module;$tail=$Matches.tail
        $grouped=if($tail){$portable.Substring(0,$portable.Length-$tail.Length-1)}else{$portable}
        $legacy=[IO.Path]::Combine($root,$module)
        if(!(Test-Path -LiteralPath ([IO.Path]::Combine($root,$grouped)) -PathType Container) -and (Test-Path -LiteralPath $legacy -PathType Container)){
            if($tail){return [IO.Path]::Combine($legacy,$tail)}
            return $legacy
        }
    }
    $parts=$RelativePath.Replace('\','/').Split('/',2)
    if($parts[0] -cnotmatch '\AFrenchExDev2\.QuietCli\.(?<group>[A-Za-z0-9.]+?)(?<test>\.Tests)?\.PoSh\z'){return [IO.Path]::Combine($root,$RelativePath)}
    $module=$parts[0];$group=$Matches.group;$category=if($Matches.test){'test'}else{'src'}
    $conventional=[IO.Path]::Combine($root,'src',$group,$category,$module)
    if(Test-Path -LiteralPath $conventional -PathType Container){
        if($parts.Count -eq 2){return [IO.Path]::Combine($conventional,$parts[1])}
        return $conventional
    }
    $homes=@($root);if(Test-Path -LiteralPath ([IO.Path]::Combine($root,'src')) -PathType Container){$homes+=([IO.Path]::Combine($root,'src'))}
    $candidates=@($homes | ForEach-Object {Get-ChildItem -LiteralPath $_ -Directory} | Where-Object Name -CMatch '\A[A-Z][A-Za-z0-9]*\z' | ForEach-Object {
        $candidate=[IO.Path]::Combine($_.FullName,$category,$module)
        if(Test-Path -LiteralPath $candidate -PathType Container){$candidate}
    })
    if($candidates.Count -gt 1){throw ('WorkspaceProjectNameCollision: '+$module)}
    $directory=if($candidates.Count){$candidates[0]}elseif(Test-Path -LiteralPath ([IO.Path]::Combine($root,$module)) -PathType Container){[IO.Path]::Combine($root,$module)}else{[IO.Path]::Combine($root,'src',$group,$category,$module)}
    if($parts.Count -eq 2){[IO.Path]::Combine($directory,$parts[1])}else{$directory}
}

function Move-QuietWorkspaceProjects {
    <#
    .SYNOPSIS
    Moves flat modules into their declared source/test groups and rewrites literal module path prefixes.
    .PARAMETER WorkspaceRoot
    Selected checkout; every source and destination must remain inside it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $projects=@(Get-QuietWorkspaceProjects $root)
    $moves=@(foreach($project in $projects){
        $target='src/'+$project.SolutionGroup+'/'+$(if($project.IsTest){'test'}else{'src'})+'/'+$project.Name
        if($project.Path -ceq $target){continue}
        $destination=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$target))
        if(!$destination.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'WorkspaceMigrationEscapedRoot'}
        if(Test-Path -LiteralPath $destination){throw ('WorkspaceMigrationDestinationExists: '+$target)}
        [pscustomobject]@{Project=$project;Target=$target;Destination=$destination}
    })
    if(!$moves.Count){return}
    $files=@(Get-QuietSourceFiles $root)
    if(!$PSCmdlet.ShouldProcess($root,('Migrate '+$moves.Count+' module directories and their literal path references'))){return}
    $projects=@(Get-QuietWorkspaceProjects $root)
    foreach($file in $files){
        if($file.Path -match '^docs/audits/' -or [IO.Path]::GetExtension($file.Path) -notin @('.ps1','.psm1','.psd1','.cs','.csproj','.json','.yml','.yaml','.md','.slnx','.props','.targets','.code-workspace','.gitignore','.ignore','.txt')){continue}
        $path=[IO.Path]::Combine($root,$file.Path)
        $text=[IO.File]::ReadAllTextAsync($path,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
        $updated=$text
        $newFile=$file.Path
        foreach($move in $moves){if($file.Path.StartsWith($move.Project.Path+'/',[StringComparison]::Ordinal)){$newFile=$move.Target+$file.Path.Substring($move.Project.Path.Length);break}}
        $oldBase=[IO.Path]::GetDirectoryName($path)
        $newBase=[IO.Path]::GetDirectoryName([IO.Path]::Combine($root,$newFile))
        if([IO.Path]::GetExtension($file.Path) -ceq '.md'){
            $updated=[regex]::Replace($updated,'\]\((?<url>(?:\.\./|\./)[^)\s]+)\)',{
                param($match)
                $url=$match.Groups['url'].Value;$parts=$url.Split('#',2)
                $target=[IO.Path]::GetFullPath($parts[0],$oldBase)
                foreach($move in $moves){if($target.StartsWith($move.Project.Directory+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$target=$move.Destination+$target.Substring($move.Project.Directory.Length);break}}
                $relative=[IO.Path]::GetRelativePath($newBase,$target).Replace('\','/')
                if($parts.Count -gt 1){$relative+='#'+$parts[1]}
                ']('+$relative+')'
            })
        }
        foreach($move in $moves){
            $name=$move.Project.Name
            if($move.Project.Path -cne $name){$updated=[regex]::Replace($updated,'(?<![A-Za-z0-9./])'+[regex]::Escape($move.Project.Path)+'/',($move.Target+'/'))}
            $updated=[regex]::Replace($updated,'(?:\.\./)+'+[regex]::Escape($name)+'/',([IO.Path]::GetRelativePath($newBase,$move.Destination).Replace('\','/')+'/'))
            $updated=$updated.Replace('./'+$name+'/',('./'+$move.Target+'/'))
            $updated=[regex]::Replace($updated,'(?<![A-Za-z0-9./])'+[regex]::Escape($name)+'/',($move.Target+'/'))
            # Release tags identify public packages, independently of their source directory.
            $updated=[regex]::Replace($updated,[regex]::Escape($move.Target)+'/v(?=[0-9*])',($name+'/v'))
        }
        if($updated -cne $text){[void][IO.File]::WriteAllTextAsync($path,$updated.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
    }
    foreach($move in $moves){
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($move.Destination))
        Move-Item -LiteralPath $move.Project.Directory -Destination $move.Destination -ErrorAction Stop
        $manifest=[IO.Path]::Combine($move.Destination,($move.Project.Name+'.psd1'))
        $text=[IO.File]::ReadAllTextAsync($manifest,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
        if($text -notmatch 'SolutionGroup\s*='){
            $text=[regex]::Replace($text,'QuietCli\s*=\s*@\{',('QuietCli=@{SolutionGroup='''+$move.Project.SolutionGroup+''';'),1)
            [void][IO.File]::WriteAllTextAsync($manifest,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }
        [pscustomobject]@{Source=$move.Project.Path;Destination=$move.Target}
    }
}
function Repair-QuietWorkspaceReferences {
    <#
    .SYNOPSIS
    Replaces root-relative module path assumptions with the shared layout resolver.
    .PARAMETER WorkspaceRoot
    Selected checkout whose script consumers are migrated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $files=@(Get-ChildItem ([IO.Path]::Combine($root,'scripts')) -Recurse -File | Where-Object Extension -In @('.ps1','.psm1'))
    $files+=@(Get-ChildItem ([IO.Path]::Combine($root,'src')) -Recurse -File -Include '*.ps1','*.psm1' | Where-Object {$_.FullName -match '[\\/]test[\\/]' -and $_.FullName -notmatch '[\\/](bin|obj|lib)[\\/]'})
    $projects=@(Get-QuietWorkspaceProjects $root)
    foreach($file in $files){
        if($file.Name -ceq 'WorkspaceLayout.psm1'){continue}
        $text=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8);$updated=$text
        $member=@($projects|Where-Object {$file.FullName.StartsWith($_.Directory+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}|Select-Object -First 1)
        if($member.Count){
            $subdirectory=[IO.Path]::GetRelativePath($member[0].Directory,$file.Directory.FullName).Replace('\','/')
            $oldDepth=1+$(if($subdirectory -ceq '.') {0}else{$subdirectory.Split('/').Count})
            $updated=[regex]::Replace($updated,'(?<prefix>\$PSScriptRoot[\s,]+[''"])(?<parents>(?:\.\./)+)scripts/',{
                param($m)
                if(($m.Groups['parents'].Value.Length/3) -eq $oldDepth){$m.Groups['prefix'].Value+('../'*($oldDepth+3))+'scripts/'}else{$m.Value}
            })
        }
        foreach($project in $projects){
            $pattern='(?<prefix>(?:Combine\(\$(?:WorkspaceRoot|sourceRoot|root|checkout),|Join-Path \$(?:WorkspaceRoot|sourceRoot|root|checkout)\s+))(?<q>[''"])'+[regex]::Escape($project.Name)+'\k<q>'
            $updated=[regex]::Replace($updated,$pattern,{
                param($m)
                $m.Groups['prefix'].Value+$m.Groups['q'].Value+$project.Path+$m.Groups['q'].Value
            },[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        $updated=[regex]::Replace($updated,'\[IO\.Path\]::Combine\((?<root>\$(?:WorkspaceRoot|sourceRoot|root)),(?<arg>\$[A-Za-z][A-Za-z0-9_.]*)(?<end>[,)])',{
            param($m)
            $resolved='(Resolve-QuietWorkspacePath -WorkspaceRoot '+$m.Groups['root'].Value+' -RelativePath '+$m.Groups['arg'].Value+')'
            if($m.Groups['end'].Value -ceq ','){'[IO.Path]::Combine('+$resolved+','}else{$resolved}
        },[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $updated=[regex]::Replace($updated,'\[IO\.Path\]::Combine\((?<root>\$(?:WorkspaceRoot|sourceRoot|root)),(?<q>[''"])(?<path>(?:FrenchExDev2\.QuietCli\.|\$(?:name|moduleName|sourceName)/)[^''"]+)\k<q>\)',{
            param($m)
            '(Resolve-QuietWorkspacePath -WorkspaceRoot '+$m.Groups['root'].Value+' -RelativePath '+$m.Groups['q'].Value+$m.Groups['path'].Value+$m.Groups['q'].Value+')'
        },[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $updated=$updated.Replace('$expected=[IO.Path]::ChangeExtension($manifest,''.psm1'')','$expected=[IO.Path]::GetFullPath([IO.Path]::ChangeExtension($manifest,''.psm1''))')
        if($updated -cne $text){
            if($updated.Contains('Resolve-QuietWorkspacePath') -and !$updated.Contains("'WorkspaceLayout.psm1'" ) -and !$updated.Contains("'lib/WorkspaceLayout.psm1'")){
                $relative=[IO.Path]::GetRelativePath($file.Directory.FullName,[IO.Path]::Combine($root,'scripts/lib/WorkspaceLayout.psm1')).Replace('\','/')
                $import="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'$relative')) -DisableNameChecking -ErrorAction Stop`n"
                # Imports must follow the parameter block; insert before the first executable error-preference/import statement.
                $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($updated,[ref]$tokens,[ref]$errors)
                if($errors.Count){throw ('WorkspaceMigrationSyntaxInvalid: '+$file.Name)}
                $end=if($ast.ParamBlock){$ast.ParamBlock.Extent.EndOffset}else{0}
                if($end -eq 0 -and $updated.StartsWith('#requires')){$end=$updated.IndexOf("`n")+1}
                $updated=$updated.Insert($end,"`n"+$import)
            }
            if($PSCmdlet.ShouldProcess($file.FullName,'Resolve module paths through the workspace catalogue')){[IO.File]::WriteAllText($file.FullName,$updated.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))}
        }
    }
}
Export-ModuleMember -Function Resolve-QuietWorkspacePath,Move-QuietWorkspaceProjects,Repair-QuietWorkspaceReferences
