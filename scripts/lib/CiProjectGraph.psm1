#requires -Version 7.6

Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop

function Read-QuietBuildXml {
    <#
    .SYNOPSIS
    Parses inert build XML while refusing external entities and DTDs.
    .PARAMETER Text
    XML source text, including an empty missing baseline.
    #>
    param([AllowEmptyString()][string]$Text)
    if(!$Text){$Text='<Project />'}
    if($Text -match '<!DOCTYPE|<!ENTITY'){throw 'CiBuildXmlDtdRejected'}
    $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($Text),$settings)
    try{$xml=[xml]::new();$xml.XmlResolver=$null;$xml.Load($reader);if($xml.DocumentElement.LocalName -cne 'Project'){throw 'CiBuildXmlRootInvalid'};return ,$xml}finally{$reader.Dispose()}
}

function Get-QuietPackageDeclarations {
    <#
    .SYNOPSIS
    Maps central package identifiers to semantic version, condition and property declarations.
    .PARAMETER Text
    Contents of a central package file at one revision.
    #>
    param([AllowEmptyString()][string]$Text)
    $xml=Read-QuietBuildXml $Text;$map=@{}
    foreach($item in $xml.SelectNodes('//PackageVersion')){
        $name=if($item.HasAttribute('Include')){$item.GetAttribute('Include')}else{$item.GetAttribute('Update')}
        if(!$name){continue}
        $version=if($item.HasAttribute('Version')){$item.GetAttribute('Version')}else{[string]$item.Version}
        $properties=@(foreach($match in [regex]::Matches($version,'\$\(([^)]+)\)')){
            $property=$match.Groups[1].Value
            foreach($value in $xml.SelectNodes('//PropertyGroup/*')|Where-Object Name -CEQ $property){$value.OuterXml}
        })
        $key=$name.ToLowerInvariant()
        $value=@($version,$item.GetAttribute('Condition'),$item.ParentNode.GetAttribute('Condition'),($properties -join '|')) -join '|'
        if(!$map.ContainsKey($key)){$map[$key]=[Collections.Generic.List[string]]::new()}
        $map[$key].Add($value)
    }
    $map
}

function Get-QuietChangedPackages {
    <#
    .SYNOPSIS
    Compares package semantics independently of XML whitespace and ordering.
    .PARAMETER Before
    Central package XML in the baseline revision.
    .PARAMETER After
    Central package XML in the candidate revision.
    #>
    param([AllowEmptyString()][string]$Before,[AllowEmptyString()][string]$After)
    $old=Get-QuietPackageDeclarations $Before;$new=Get-QuietPackageDeclarations $After
    foreach($name in @(@($old.Keys)+@($new.Keys)|Sort-Object -Unique)){
        $left=@($old[$name]|Sort-Object) -join [char]10;$right=@($new[$name]|Sort-Object) -join [char]10
        if($left -cne $right){$name}
    }
}

function Get-QuietCiProjectGraph {
    <#
    .SYNOPSIS
    Discovers project ownership, imports, package consumers and project-reference edges without building.
    .PARAMETER WorkspaceRoot
    Checkout whose inert module manifests determine group ownership.
    .PARAMETER Evaluate
    Resolves explicit imports and property-based references with evaluation-only MSBuild queries.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[switch]$Evaluate)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $documents=@{}
    foreach($module in Get-QuietWorkspaceProjects $root){
        foreach($source in Get-QuietSourceFiles $module.Directory|Where-Object Path -CLike '*.csproj'){
            $path=$module.Path+'/'+$source.Path
            $absolute=(Resolve-QuietWorkspacePath -WorkspaceRoot $root -RelativePath $path)
            $xml=Read-QuietBuildXml ([IO.File]::ReadAllText($absolute,[Text.Encoding]::UTF8))
            $packages=@(foreach($item in $xml.SelectNodes('//PackageReference')){
                $name=if($item.HasAttribute('Include')){$item.GetAttribute('Include')}else{$item.GetAttribute('Update')}
                [pscustomobject]@{Name=$name;Condition=$item.GetAttribute('Condition');Version=$item.GetAttribute('Version');VersionOverride=$item.GetAttribute('VersionOverride')}
            })
            $references=@(foreach($item in $xml.SelectNodes('//ProjectReference[@Include]')){
                $include=$item.GetAttribute('Include')
                if($include -match '[$*?;]'){continue}
                [IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($include,[IO.Path]::GetDirectoryName($absolute))).Replace('\','/')
            })
            $imports=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $directory=[IO.Path]::GetDirectoryName($absolute)
            while($directory -and ($directory -eq $root -or $directory.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
                foreach($name in @('Directory.Build.props','Directory.Build.targets','Directory.Packages.props','NuGet.Config','nuget.config')){
                    $candidate=[IO.Path]::Combine($directory,$name)
                    if(Test-Path -LiteralPath $candidate){[void]$imports.Add([IO.Path]::GetRelativePath($root,$candidate).Replace('\','/'))}
                }
                $directory=[IO.Path]::GetDirectoryName($directory)
            }
            foreach($item in $xml.SelectNodes('//Import[@Project]')){
                $include=$item.GetAttribute('Project')
                if($include -notmatch '[$*?;]'){
                    $candidate=[IO.Path]::GetFullPath($include,[IO.Path]::GetDirectoryName($absolute))
                    if(!$candidate.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'CiBuildImportOutsideWorkspace'}
                    [void]$imports.Add([IO.Path]::GetRelativePath($root,$candidate).Replace('\','/'))
                }
            }
            # Inherited build files may themselves declare references or import other files.
            # Read literal edges transitively, retaining conditions as a union of possible consumers.
            $pending=[Collections.Generic.Queue[string]]::new()
            foreach($inputPath in $imports){if($inputPath -match '\.(props|targets)$'){$pending.Enqueue($inputPath)}}
            $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $requiresEvaluation=($xml.OuterXml -match '<Import|Include="\$\(')
            while($pending.Count){
                $inputPath=$pending.Dequeue();if(!$visited.Add($inputPath)){continue}
                $inputAbsolute=Resolve-QuietWorkspacePath $root $inputPath
                if(!(Test-Path -LiteralPath $inputAbsolute)){continue}
                if(!$documents.ContainsKey($inputPath)){$documents[$inputPath]=Read-QuietBuildXml ([IO.File]::ReadAllText($inputAbsolute,[Text.Encoding]::UTF8))}
                $inputXml=$documents[$inputPath]
                if($inputXml.OuterXml -match '<Import|Include="\$\('){$requiresEvaluation=$true}
                foreach($item in $inputXml.SelectNodes('//PackageReference')){
                    $name=if($item.HasAttribute('Include')){$item.GetAttribute('Include')}else{$item.GetAttribute('Update')}
                    $packages+=@([pscustomobject]@{Name=$name;Condition=$item.GetAttribute('Condition');Version=$item.GetAttribute('Version');VersionOverride=$item.GetAttribute('VersionOverride')})
                }
                foreach($item in $inputXml.SelectNodes('//ProjectReference[@Include]|//Import[@Project]')){
                    $isReference=$item.LocalName -ceq 'ProjectReference'
                    $include=$item.GetAttribute($(if($isReference){'Include'}else{'Project'}))
                    if($include -match '[$*?;]'){$requiresEvaluation=$true;continue}
                    $candidate=[IO.Path]::GetFullPath($include,[IO.Path]::GetDirectoryName($inputAbsolute))
                    if(!$candidate.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'CiBuildImportOutsideWorkspace'}
                    $relative=[IO.Path]::GetRelativePath($root,$candidate).Replace('\','/')
                    if($isReference){$references+=@($relative)}elseif($imports.Add($relative)){$pending.Enqueue($relative)}
                }
            }
            $record=[pscustomobject]@{Path=$path;Module=$module.Name;Group=$module.SolutionGroup;IsTest=$module.IsTest;Packages=$packages;References=@($references|Sort-Object -Unique);Imports=@($imports|Sort-Object);Frameworks=@($xml.SelectNodes('//TargetFramework|//TargetFrameworks')|ForEach-Object {$_.InnerText.Split(';')});RequiresEvaluation=$requiresEvaluation;EvaluationFailure=$null}
            if($Evaluate -and $record.RequiresEvaluation){
                try{
                    $evaluations=@(Get-QuietEvaluatedProjectInputs -WorkspaceRoot $root -Project $record)
                    if(!$evaluations.Count){throw 'CiProjectEvaluationEmpty'}
                    foreach($evaluation in $evaluations){
                        foreach($item in $evaluation.Items.PackageReference){if($item.Identity){$record.Packages+=@([pscustomobject]@{Name=[string]$item.Identity;Condition='Evaluated';Version=[string]$item.Version;VersionOverride=[string]$item.VersionOverride})}}
                        foreach($item in $evaluation.Items.ProjectReference){
                            $target=[IO.Path]::GetFullPath([string]$item.Identity,[IO.Path]::GetDirectoryName($absolute))
                            if(!$target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'CiProjectReferenceOutsideWorkspace'}
                            $record.References+=@([IO.Path]::GetRelativePath($root,$target).Replace('\','/'))
                        }
                        foreach($target in ([string]$evaluation.Properties.MSBuildAllProjects).Split(';',[StringSplitOptions]::RemoveEmptyEntries)){
                            if($target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){[void]$imports.Add([IO.Path]::GetRelativePath($root,$target).Replace('\','/'))}
                        }
                    }
                    $record.Imports=@($imports|Sort-Object);$record.References=@($record.References|Sort-Object -Unique)
                }catch{$record.EvaluationFailure=$_.Exception.Message}
            }
            $record
        }
    }
}

function Get-QuietEvaluatedProjectInputs {
    <#
    .SYNOPSIS
    Resolves imported or property-based references with MSBuild evaluation only, without executing targets.
    .PARAMETER WorkspaceRoot
    Checkout owning the pinned SDK.
    .PARAMETER Project
    One project graph record.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)]$Project)
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
    $frameworks=if(@($Project.Frameworks).Count){@($Project.Frameworks)}else{@('')}
    foreach($framework in $frameworks){
        $state=@{Text=[Text.StringBuilder]::new()}
        $arguments=@('msbuild',(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $Project.Path),'-nologo','-p:Configuration=Release','-getItem:PackageReference,ProjectReference','-getProperty:MSBuildAllProjects')
        if($framework -and $framework -notmatch '\$\('){$arguments+=('-p:TargetFramework='+$framework)}
        $result=Invoke-CiProcess -FilePath dotnet -ArgumentList $arguments -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {
            param($event,$state)
            if($event.Stream -eq 'stdout'){
                if($state.Text.Length+$event.Text.Length -gt 4194304){throw 'CiEvaluationOutputBudget'}
                [void]$state.Text.AppendLine($event.Text)
            }
        }
        if($result.Outcome -ne 'Success'){throw ('CiProjectEvaluationFailed: '+$Project.Path)}
        $state.Text.ToString()|ConvertFrom-Json -AsHashtable
    }
}
Export-ModuleMember -Function Read-QuietBuildXml,Get-QuietPackageDeclarations,Get-QuietChangedPackages,Get-QuietCiProjectGraph,Get-QuietEvaluatedProjectInputs
