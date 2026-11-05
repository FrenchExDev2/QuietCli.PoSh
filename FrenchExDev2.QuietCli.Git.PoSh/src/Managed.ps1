function Resolve-QuietGitParserTarget {
    <#
    .SYNOPSIS
    Chooses the client assembly from the actual host CLR, including preview and future hosts.
    .PARAMETER RuntimeMajor
    Actual CLR major; injectable for independent compatibility assertions.
    #>
    param([int]$RuntimeMajor=[Environment]::Version.Major)
    if($RuntimeMajor -ge 11){return 'net11.0'}
    if($RuntimeMajor -eq 10){return 'net10.0'}
    throw 'GitParserRequiresNet10OrLater'
}
function Import-QuietGitParser {
    <#
    .SYNOPSIS
    Loads only the verified caller-local Git library, without starting an engine or native command.
    #>
    if($script:GitParserAssembly){return}
    $framework=Resolve-QuietGitParserTarget
    $directory=Join-Path $script:GitRoot ('lib/parser/'+$framework)
    $manifest=Get-Content -LiteralPath (Join-Path $directory 'build-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    if(@($manifest.Binaries|Where-Object Path -CEQ 'QuietCli.Git.Parser.dll').Count -ne 1){throw 'GitParserBuildIdentityInvalid'}
    foreach($file in $manifest.Binaries){
        if([IO.Path]::GetFileName($file.Path) -cne $file.Path){throw 'GitParserBuildIdentityUnsafePath'}
        if((Get-FileHash -LiteralPath (Join-Path $directory $file.Path) -Algorithm SHA256).Hash -cne $file.SHA256){throw 'GitParserBinaryIntegrityFailed'}
    }
    $path=Join-Path $directory 'QuietCli.Git.Parser.dll';$hash=(Get-FileHash -LiteralPath $path).Hash
    $loaded=[AppDomain]::CurrentDomain.GetData('QuietCli2.Git.ParserIdentity')
    if($loaded -and $loaded -cne $hash){throw 'GitParserAlreadyLoaded: restart PowerShell after rebuilding.'}
    $script:GitParserAssembly=[Reflection.Assembly]::LoadFrom($path)
    $actual=$script:GitParserAssembly.GetCustomAttributes([System.Runtime.Versioning.TargetFrameworkAttribute],$false)[0].FrameworkName
    if($actual -cne ('.NETCoreApp,Version=v'+$framework.Substring(3))){throw 'GitParserTargetMismatch'}
    [AppDomain]::CurrentDomain.SetData('QuietCli2.Git.ParserIdentity',$hash)
}
