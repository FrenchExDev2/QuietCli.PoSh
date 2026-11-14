function Test-QuietReportPaths {
    <#
    .SYNOPSIS
    Checks local/CI path isolation, generated workspaces, malformed categories and policy mutations.
    .PARAMETER WorkspaceRoot
    Monorepo containing the independently loaded path policy.
    #>
    param([string]$WorkspaceRoot)
    $source=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot 'scripts/lib/ReportPaths.psm1'),[Text.Encoding]::UTF8)
    $verify={param($source)
        & {
            param($source)
            . ([scriptblock]::Create($source))
            $random=[Random]::new(78051)
            $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            for($i=0;$i -lt 200;$i++){
                $workspace=Join-Path $temp ('checkout-é-'+$random.Next())
                $local=Get-QuietReportRoot $workspace tests -ContinuousIntegration $false
                $ci=Get-QuietReportRoot $workspace tests -ContinuousIntegration $true
                if(!$local.StartsWith((Join-Path $temp 'QuietCli2')+[IO.Path]::DirectorySeparatorChar) -or $local -eq $ci){return $false}
                if($ci -cne (Join-Path $workspace 'artifacts/tests')){return $false}
                if($local -cne (Get-QuietReportRoot ($workspace+[IO.Path]::DirectorySeparatorChar) tests -ContinuousIntegration $false)){return $false}
                if($local -ceq (Get-QuietReportRoot ($workspace+'-other') tests -ContinuousIntegration $false)){return $false}
                if((Get-QuietReportRoot $workspace tests -ContinuousIntegration $false) -ceq (Get-QuietReportRoot $workspace containers -ContinuousIntegration $false)){return $false}
            }
            foreach($bad in @('../escape','/root','a/b','a\b','..','','测试')+(1..100|ForEach-Object {'../'+$random.Next()})){
                $rejected=$false;try{$null=Get-QuietReportRoot $temp $bad -ContinuousIntegration $false}catch{$rejected=$true};if(!$rejected){return $false}
            }
            return $true
        } $source
    }
    if(!(& $verify $source)){throw 'Report path generated property or malformed category failed: seed 78051'}
    foreach($mutant in @($source.Replace('if($ContinuousIntegration)','if(!$ContinuousIntegration)'),$source.Replace("'QuietCli2/'+`$hash+'/'","'QuietCli2/shared/'"))){if($mutant -ceq $source){throw 'Report mutation did not change source'};if(& $verify $mutant){throw 'Report path policy mutant survived'}}
    Test-QuietHeadlessMonitorContract -WorkspaceRoot $WorkspaceRoot
}

function Test-QuietHeadlessMonitorContract {
    <#
    .SYNOPSIS
    Requires desktop monitor launches and reopen instructions to stay outside headless CI execution.
    .PARAMETER WorkspaceRoot
    Monorepo containing the host, container and Gallery launchers.
    #>
    param([string]$WorkspaceRoot)
    $verify={
        param([string]$Source)
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
        if($errors.Count){return $false}
        $surfaces=@($ast.FindAll({param($node)
            (($node -is [Management.Automation.Language.ExpandableStringExpressionAst] -or $node -is [Management.Automation.Language.StringConstantExpressionAst]) -and $node.Value.StartsWith('Monitor: pwsh')) -or
            ($node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process' -and $node.Extent.Text -match '-WindowStyle\s+Normal')
        },$true))
        if($surfaces.Count -ne 2){return $false}
        foreach($surface in $surfaces){
            $guarded=$false
            for($parent=$surface.Parent;$parent;$parent=$parent.Parent){
                if($parent -isnot [Management.Automation.Language.IfStatementAst]){continue}
                foreach($clause in $parent.Clauses){
                    $condition=$clause.Item1.Extent.Text -replace '\s',''
                    if($condition -notin @('!$Headless','-not$Headless')){continue}
                    if($surface.Extent.StartOffset -ge $clause.Item2.Extent.StartOffset -and $surface.Extent.EndOffset -le $clause.Item2.Extent.EndOffset){$guarded=$true}
                }
            }
            if(!$guarded){return $false}
        }
        return $true
    }
    $random=[Random]::new(20261110)
    foreach($name in @('Invoke-WorkspaceCi','Invoke-ContainerCi','Invoke-ContainerColdStart','Invoke-PublishedGallery')){
        $source=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot "scripts/$name.ps1"),[Text.Encoding]::UTF8)
        if(!(& $verify $source)){throw "HeadlessMonitorContractFailed: $name"}
        for($i=0;$i -lt 16;$i++){
            $spaces=' '*$random.Next(1,9)
            $variant=$source.Replace('!$Headless',"-not${spaces}`$Headless")
            if(!(& $verify $variant)){throw "HeadlessMonitorWhitespacePropertyFailed: $name; seed 20261110"}
        }
        foreach($bad in @('$Headless','$true','$null')){
            $mutant=$source.Replace('!$Headless',$bad)
            if($mutant -ceq $source -or (& $verify $mutant)){throw "HeadlessMonitorGuardMutantSurvived: $name; $bad"}
        }
        if(& $verify ($source + "`n`"Monitor: pwsh unguarded`"")){throw "HeadlessMonitorInstructionMutantSurvived: $name"}
        if(& $verify ($source + "`nif (")){throw "HeadlessMonitorMalformedSourceAccepted: $name"}
    }
}
