function Test-QuietEnvFiles {
    <#
    .SYNOPSIS
    Checks literal dotenv round trips, malformed inputs, safe previews and deterministic CI presets.
    .PARAMETER WorkspaceRoot
    Checkout containing the shared editor and initialization scripts.
    .PARAMETER RunDirectory
    Owned temporary fixtures; no real credentials are read or printed.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot scripts/EnvFile.ps1)
    $fixture=Join-Path $RunDirectory 'dotenv-fixture';$path=Join-Path $fixture '.env'
    if($null -ne (Get-QuietEnvValue -Path $path -Key KEY)){throw 'MissingEnvFileReturnedValue'}
    $null=Set-QuietEnvValue -Path $path -Key KEY -Value value -WhatIf
    if(Test-Path -LiteralPath $fixture){throw 'EnvPreviewCreatedDirectory'}
    [void][IO.Directory]::CreateDirectory($fixture)
    $initial="# retained comment`nSECRET=`"private-fixture-0123`"`nkey=`"case-sensitive`"`nKEY=old`n`n"
    [void][IO.File]::WriteAllTextAsync($path,$initial,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $seed=20261110;$random=[Random]::new($seed)
    $tokens=@('a','é','漢','🙂',' ','#','$','\','"',"'",'=',':',';','(',')')
    foreach($iteration in 1..64){
        $value=-join @(for($index=0;$index -lt $random.Next(0,40);$index++){$tokens[$random.Next($tokens.Count)]})
        $result=Set-QuietEnvValue -Path $path -Key KEY -Value $value -Confirm:$false
        if((Get-QuietEnvValue -Path $path -Key KEY) -cne $value -or (Get-QuietEnvValue -Path $path -Key key) -cne 'case-sensitive'){throw 'EnvLiteralRoundTripPropertyFailed'}
        $text=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true))
        if(!$text.Contains('SECRET="private-fixture-0123"') -or !$text.StartsWith('# retained comment') -or !$text.EndsWith("`n`n") -or $text.Contains("`r") -or ($result|ConvertTo-Json -Compress).Contains('private-fixture-0123')){throw 'EnvEditorChangedUnrelatedContentOrExposedValue'}
        $hash=(Get-FileHash $path).Hash
        if((Set-QuietEnvValue -Path $path -Key KEY -Value $value -Confirm:$false).Changed -or (Get-FileHash $path).Hash -cne $hash){throw 'EnvEditorNotIdempotent'}
    }
    $readCases=@(
        @{Text='KEY=podman # note';Value='podman'},@{Text='export KEY = "docker" # note';Value='docker'},
        @{Text="KEY='é漢 # literal'";Value='é漢 # literal'},@{Text='KEY="a\\b\"c"';Value='a\b"c'},
        @{Text='KEY=$(throw "never execute")';Value='$(throw "never execute")'},@{Text='KEY=""';Value=''}
    )
    foreach($case in $readCases){[void][IO.File]::WriteAllTextAsync($path,$case.Text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult();if((Get-QuietEnvValue $path KEY) -cne $case.Value){throw 'EnvLiteralExampleChanged'}}
    $bad=@('KEY="unclosed',"KEY='unclosed",'KEY="closed" unexpected',"KEY=a`nKEY=b")
    foreach($value in $bad){[void][IO.File]::WriteAllTextAsync($path,$value,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult();$rejected=$false;try{$null=Get-QuietEnvValue $path KEY}catch{$rejected=$true};if(!$rejected){throw 'MalformedEnvValueAccepted'}}
    foreach($value in @("line`nnext","line`rnext",("a"+[char]0+"b"))){$rejected=$false;try{$null=Set-QuietEnvValue $path KEY $value -Confirm:$false}catch{$rejected=$_.Exception.Message -eq 'EnvValueMustBeSingleLine'};if(!$rejected){throw 'EnvMultilineOrNullAccepted'}}
    $null=Set-QuietEnvValue $path KEY repaired -Confirm:$false
    if((Get-QuietEnvValue $path KEY) -cne 'repaired'){throw 'EnvDuplicateRepairFailed'}
    $limited=Join-Path $fixture oversized.env
    [void][IO.File]::WriteAllBytesAsync($limited,[byte[]]::new(1048577)).GetAwaiter().GetResult()
    $rejected=$false;try{$null=Get-QuietEnvValue $limited KEY}catch{$rejected=$_.Exception.Message -eq 'EnvFileSizeLimit'}
    if(!$rejected){throw 'OversizedEnvFileAccepted'}
    [void][IO.File]::WriteAllBytesAsync($limited,[byte[]]@(0xc3,0x28)).GetAwaiter().GetResult()
    $rejected=$false;try{$null=Get-QuietEnvValue $limited KEY}catch{$rejected=$_.Exception.GetBaseException() -is [Text.DecoderFallbackException]}
    if(!$rejected){throw 'MalformedUtf8EnvAccepted'}
    [void][IO.File]::WriteAllTextAsync($limited,"KEY=`"same`"`r`nOTHER=retained`r`n",[Text.UTF8Encoding]::new($true)).GetAwaiter().GetResult()
    $hash=(Get-FileHash $limited).Hash
    $null=Set-QuietEnvValue $limited KEY same -WhatIf
    if((Get-FileHash $limited).Hash -cne $hash){throw 'EnvNormalizationPreviewWroteFile'}
    if(!(Set-QuietEnvValue $limited KEY same -Confirm:$false).Changed -or [IO.File]::ReadAllBytes($limited)[0] -eq 239 -or [IO.File]::ReadAllText($limited).Contains("`r")){throw 'EnvNormalizationWasNotDeterministic'}
    $decodeSource=(Get-Command ConvertFrom-QuietEnvLiteral).ScriptBlock.ToString()
    $anchor='$value[++$index]'
    if(!$decodeSource.Contains($anchor)){throw 'EnvLiteralMutationAnchorMissing'}
    $mutant=[scriptblock]::Create($decodeSource.Replace($anchor,'$value[$index++]'))
    if((& $mutant '"a\"b"') -ceq 'a"b'){throw 'EnvEscapeMutationSurvived'}
    $initializer=Join-Path $WorkspaceRoot scripts/Initialize-CiEnvironment.ps1
    foreach($target in @('Local','GitHub')){
        $workspace=Join-Path $fixture $target
        $null=& $initializer -WorkspaceRoot $workspace -Target $target -WhatIf
        if(Test-Path -LiteralPath $workspace){throw 'CiEnvironmentPreviewWroteFiles'}
        $result=& $initializer -WorkspaceRoot $workspace -Target $target -Confirm:$false
        $expected=if($target -eq 'GitHub'){'docker'}else{'podman'}
        if($result.ContainerRuntime -cne $expected -or (Get-QuietEnvValue (Join-Path $workspace .env) QUIET_CONTAINER_RUNTIME) -cne $expected){throw 'CiEnvironmentPresetChanged'}
        if((& $initializer -WorkspaceRoot $workspace -Target $target -Confirm:$false).Changed){throw 'CiEnvironmentPresetNotIdempotent'}
    }
    $editor=Join-Path $WorkspaceRoot scripts/Update-EnvFile.ps1
    $null=& $editor -Path $path -Key KEY -Value 'quoted-é漢' -Confirm:$false
    if((& $editor -Path $path -Key KEY -Read) -cne 'quoted-é漢'){throw 'EnvEditorEntryPointChanged'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'dotenv-campaign.json') @{Seed=$seed;RoundTrips=64;ReadExamples=$readCases.Count;MalformedCases=($bad.Count+2);KilledMutants=1;Presets=@('Local','GitHub');Preview='No writes';Secrets='Synthetic values only'}
}
