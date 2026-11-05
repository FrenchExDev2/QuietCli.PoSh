function Test-QuietReportPaths {
    <#
    .SYNOPSIS
    Checks local/CI path isolation, generated workspaces, malformed categories and policy mutations.
    .PARAMETER WorkspaceRoot
    Monorepo containing the independently loaded path policy.
    #>
    param([string]$WorkspaceRoot)
    $source=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot 'scripts/ReportPaths.ps1'),[Text.Encoding]::UTF8)
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
}
