function Assert-QuietResources {
    <#
    .SYNOPSIS
    Checks the pinned resource inventory before loading code; hashes do not authenticate the distributor.
    .PARAMETER RelativePath
    Optional single managed resource for an explicit tokenizer load.
    #>
    param([string]$RelativePath)
    $path=Join-Path $script:QuietRoot 'resources/dependencies.lock.json'
    if(!(Test-Path -LiteralPath $path)){throw 'DependencyManifestMissing'}
    $manifest=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json
    $files=@($manifest.Files|Where-Object{!$RelativePath -or $_.Path -ceq $RelativePath})
    if(!$files.Count){throw 'DependencyNotInventoried'}
    foreach($file in $files){
        if($file.Path -notmatch '^resources/[A-Za-z0-9_./-]+$' -or $file.Path.Split('/') -contains '..'){throw 'DependencyUnsafePath'}
        $resource=Join-Path $script:QuietRoot $file.Path
        if(!(Test-Path -LiteralPath $resource) -or (Get-FileHash -LiteralPath $resource -Algorithm SHA256).Hash -cne $file.SHA256){throw ('DependencyIntegrityFailed: '+$file.Path)}
    }
}
