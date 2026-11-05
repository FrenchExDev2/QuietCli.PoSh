function New-QuietStatusAccumulator {
    <#
    .SYNOPSIS
    Creates bounded business state for normalized text-record counts and a streaming digest.
    #>
    [pscustomobject]@{Lines=0L;Utf8Bytes=0L;Hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)}
}

function Add-QuietStatusRecord {
    <#
    .SYNOPSIS
    Hashes one complete record with a normalized LF, retaining no repository output.
    .PARAMETER State
    Caller-owned accumulator.
    .PARAMETER Text
    Complete UTF-8-decoded line without LF; a terminal CR is normalized.
    #>
    param($State,[AllowEmptyString()][string]$Text)
    $bytes=[Text.Encoding]::UTF8.GetBytes($Text.TrimEnd("`r")+"`n")
    $State.Hash.AppendData($bytes)
    $State.Lines++;$State.Utf8Bytes+=$bytes.Length
}

function Complete-QuietStatusAccumulator {
    <#
    .SYNOPSIS
    Finalizes one bounded record summary; the caller disposes the hash.
    .PARAMETER State
    Accumulator containing explicitly retained business counters only.
    #>
    param($State)
    [pscustomobject]@{Lines=$State.Lines;Utf8Bytes=$State.Utf8Bytes;SHA256=[Convert]::ToHexString($State.Hash.GetHashAndReset())}
}

function Test-QuietStatusAggregation {
    <#
    .SYNOPSIS
    Checks generated Unicode and boundary records against independent whole-input hashing.
    #>
    $verify={
        $random=[Random]::new(73592)
        foreach($iteration in 0..64){
            $lines=@(for($i=0;$i -lt $iteration;$i++){('é漢🙂 '+$random.Next()+('x'*$random.Next(0,80)))+$(if($i%2){"`r"}else{''})})
            $state=New-QuietStatusAccumulator
            try{
                foreach($line in $lines){Add-QuietStatusRecord $state $line}
                $actual=Complete-QuietStatusAccumulator $state
                $text=($lines|ForEach-Object {$_.TrimEnd("`r")+"`n"}) -join ''
                $expectedBytes=[Text.Encoding]::UTF8.GetBytes($text)
                $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes))
                if($actual.Lines -ne $iteration -or $actual.Utf8Bytes -ne $expectedBytes.Length -or $actual.SHA256 -cne $expectedHash){throw 'StatusAggregationProperty: seed 73592'}
            }finally{$state.Hash.Dispose()}
        }
        foreach($line in @('',"`r",[string][char]0,('z'*65535),"é`r漢",[string][char]0xd800)){
            $state=New-QuietStatusAccumulator
            try{
                Add-QuietStatusRecord $state $line
                $s=Complete-QuietStatusAccumulator $state
                $expected=[Text.Encoding]::UTF8.GetBytes($line.TrimEnd("`r")+"`n")
                if($s.Lines -ne 1 -or $s.Utf8Bytes -ne $expected.Length -or $s.SHA256 -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected))){throw 'StatusAggregationBoundary'}
            }finally{$state.Hash.Dispose()}
        }
    }
    & $verify
    $definition=(Get-Command Add-QuietStatusRecord).Definition
    $mutations=@(@('$State.Lines++','$State.Lines+=2'),@('$State.Utf8Bytes+=$bytes.Length','$State.Utf8Bytes+=$Text.Length'),@('$State.Hash.AppendData($bytes)','$null=$bytes'))
    $outcomes=@(foreach($mutation in $mutations){
        if(!$definition.Contains($mutation[0])){throw 'StatusAggregationMutantInvalid'}
        $detected=& {
            param($body,$verify)
            . ([scriptblock]::Create('function Add-QuietStatusRecord {'+$body+'}'))
            try{& $verify;$false}catch{$true}
        } $definition.Replace($mutation[0],$mutation[1]) $verify
        if(!$detected){throw 'StatusAggregationMutantSurvived'}
        @{Original=$mutation[0];Replacement=$mutation[1];State='Killed'}
    })
    [pscustomobject]@{Seed=73592;Properties=65;BoundaryCases=6;Mutations=$outcomes}
}
