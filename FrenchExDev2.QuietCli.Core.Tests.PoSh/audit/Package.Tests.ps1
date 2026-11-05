# Objectif : Fournir des attaques de packaging de petite taille et un témoin positif sans code externe.
function New-AuditPackageFixture {
    <#
    .SYNOPSIS
    Creates four small synthetic module packages with independently calculated manifests.
    .PARAMETER Path
    New package directory.
    .PARAMETER Attack
    Optional controlled boundary violation.
    #>
    param([string]$Path,[ValidateSet('normal','foreign','case','traversal')][string]$Attack='normal')
    [void][IO.Directory]::CreateDirectory($Path)
    foreach($name in @('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh')){
        $entries=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $entries[$name+'.psd1']="@{RootModule='$name.psm1';ModuleVersion='0.0.1';FunctionsToExport=@()}"
        $entries[$name+'.psm1']="[void][IO.File]::WriteAllTextAsync((Join-Path `$PSScriptRoot 'audit-import-marker.txt'),'synthetic',[Text.UTF8Encoding]::new(`$false)).GetAwaiter().GetResult()"
        $isCore=$name -ceq 'FrenchExDev2.QuietCli.Core.PoSh'
        if($isCore -and $Attack -eq 'case'){$entries['README.md']='a';$entries['readme.md']='b'}
        if($isCore -and $Attack -eq 'traversal'){$entries['../outside.ps1']=$entries[$name+'.psm1'];$entries.Remove($name+'.psm1')}
        $manifest=[Collections.Generic.List[object]]::new()
        $zip=[IO.Compression.ZipFile]::Open((Join-Path $Path ($name+'.zip')),[IO.Compression.ZipArchiveMode]::Create)
        try{
            foreach($item in $entries.GetEnumerator()){
                $bytes=[Text.Encoding]::UTF8.GetBytes($item.Value)
                $manifest.Add(@{Path=$item.Key;Bytes=$bytes.Length;SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})
                $entryPath=$name+'/'+$item.Key
                if($isCore -and $Attack -eq 'foreign' -and $item.Key.EndsWith('.psm1')){$entryPath='FrenchExDev2.QuietCli.Git.PoSh/foreign.psm1'}
                $stream=$zip.CreateEntry($entryPath).Open()
                try{[void]$stream.WriteAsync($bytes,0,$bytes.Length).GetAwaiter().GetResult()}finally{$stream.Dispose()}
            }
        }finally{$zip.Dispose()}
        Write-WorkspaceJson (Join-Path $Path ($name+'.manifest.json')) @{Module=$name;Files=$manifest.ToArray()}
    }
}
function Invoke-AuditPackageChecks {
    <#
    .SYNOPSIS
    Checks package module boundaries, duplicate paths, traversal, quotas and a non-executing positive verification.
    .PARAMETER WorkspaceRoot
    Verifier workspace.
    .PARAMETER RunDirectory
    Dedicated synthetic fixture directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    foreach($case in @(@{Name='data-only';Attack='normal';Reason=$null},@{Name='foreign';Attack='foreign';Reason='ArchiveModuleBoundaryViolation'},@{Name='case';Attack='case';Reason='DuplicatePackagePath'},@{Name='traversal';Attack='traversal';Reason='ArchiveUnsafePath'},@{Name='file-quota';Attack='normal';Reason='ArchiveDirectoryLimit';Files=1},@{Name='byte-quota';Attack='normal';Reason='ArchiveSizeLimit';Bytes=1})){
        $path=Join-Path $RunDirectory ('packages-'+$case.Name)
        New-AuditPackageFixture $path $case.Attack
        if($case.ContainsKey('Files')){
            foreach($file in Get-ChildItem -LiteralPath $path -Filter '*.manifest.json'){
                $manifest=Get-Content $file.FullName -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable
                $manifest.Files=@($manifest.Files[0]);Write-WorkspaceJson $file.FullName $manifest
            }
        }
        $arguments=@('-File',(Join-Path $PSScriptRoot 'Probe-Package.ps1'),'-WorkspaceRoot',$WorkspaceRoot,'-PackageDirectory',$path,'-ExtractionDirectory',($path+'-extracted'))
        if($case.ContainsKey('Files')){$arguments+=@('-MaxFiles',[string]$case.Files)}
        if($case.ContainsKey('Bytes')){$arguments+=@('-MaxTotalBytes',[string]$case.Bytes)}
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} -FilePath pwsh -ArgumentList $arguments
        $safe=if($case.Reason){$r.Outcome -eq 'Success' -and $r.Data.Rejected -and $r.Data.Reason -eq $case.Reason}else{$r.Outcome -eq 'Success' -and $r.Data.Verified -and !$r.Data.ImportTested}
        $markers=@(Get-ChildItem -LiteralPath $RunDirectory -Recurse -File -Filter audit-import-marker.txt)
        [pscustomobject]@{Id=('SEC-01-'+$case.Name);Resolved=($safe -and $markers.Count -eq 0);Evidence=@{ExpectedReason=$case.Reason;Decision=$r.Data;Markers=$markers.Count}}
    }
}
