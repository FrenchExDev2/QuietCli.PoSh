function Test-QuietProtocolSpecification {
    <#
    .SYNOPSIS
    Checks generated protocol bounds, malformed UTF-8/JSON and targeted validation mutants.
    .PARAMETER WorkspaceRoot
    Local monorepo used to resolve the isolated temporary report root.
    #>
    param([string]$WorkspaceRoot)
    . (Join-Path $WorkspaceRoot 'scripts/ReportPaths.ps1')
    $directory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'protocol-specification') ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $path=Join-Path $directory 'protocol.json'
    $utf8=[Text.UTF8Encoding]::new($false)
    $verify={
        $random=[Random]::new(73593)
        foreach($iteration in 0..65){
            $block=if($iteration -eq 0){1024}elseif($iteration -eq 1){16384}else{$random.Next(1024,16385)}
            $header=if($iteration -eq 0){65536}elseif($iteration -eq 1){1048576}else{$random.Next(65536,1048577)}
            $json='{"Version":1,"BlockSize":'+$block+',"HeaderLimit":'+$header+',"QueueBlocks":16,"ReadFrameTimeoutSeconds":15,"WriteFrameTimeoutSeconds":30}'
            [void][IO.File]::WriteAllTextAsync($path,$json,$utf8).GetAwaiter().GetResult()
            $value=Read-QuietProtocolSpecification $path
            if($value.Version -ne 1 -or $value.BlockSize -ne $block -or $value.HeaderLimit -ne $header -or $value.QueueBlocks -ne 16 -or $value.ReadFrameTimeoutSeconds -ne 15 -or $value.WriteFrameTimeoutSeconds -ne 30){throw 'ProtocolSpecificationProperty: seed 73593'}
        }
        $bad=@('null','[]','{}','{','{"Version":1,}', '{"Version":1,"BlockSize":1024}',
            '{"Version":1,"BlockSize":1.5,"HeaderLimit":65536}',
            '{"Version":1,"BlockSize":null,"HeaderLimit":65536}',
            '{"Version":1,"BlockSize":"1024","HeaderLimit":65536}',
            '{"Version":1,"BlockSize":2147483648,"HeaderLimit":65536}')
        foreach($iteration in 0..127){
            $version=1;$block=1024;$header=65536
            switch($iteration%5){
                0 {$version=$random.Next(2,100)}
                1 {$block=$random.Next(-1024,1024)}
                2 {$block=$random.Next(16385,32769)}
                3 {$header=$random.Next(-65536,65536)}
                4 {$header=$random.Next(1048577,2097153)}
            }
            $bad+=('{"Version":'+$version+',"BlockSize":'+$block+',"HeaderLimit":'+$header+'}')
        }
        $bad+=@('{"Version":1,"BlockSize":1023,"HeaderLimit":65536}',
            '{"Version":1,"BlockSize":16385,"HeaderLimit":65536}',
            '{"Version":1,"BlockSize":1024,"HeaderLimit":65535}',
            '{"Version":1,"BlockSize":1024,"HeaderLimit":1048577}')
        $index=0
        foreach($json in $bad){
            [void][IO.File]::WriteAllTextAsync($path,$json,$utf8).GetAwaiter().GetResult()
            $rejected=$false
            try{$null=Read-QuietProtocolSpecification $path}catch{$rejected=$true}
            if(!$rejected){throw "ProtocolSpecificationMalformedAccepted: seed 73593, case $index"}
            $index++
        }
        $malformedUtf8=[byte[]]($utf8.GetBytes('{"Version":1,"BlockSize":1024,"HeaderLimit":65536,"')+@(0xc3,0x28)+$utf8.GetBytes('":1}'))
        [void][IO.File]::WriteAllBytesAsync($path,$malformedUtf8).GetAwaiter().GetResult()
        $rejected=$false
        try{$null=Read-QuietProtocolSpecification $path}catch{$rejected=$true}
        if(!$rejected){throw 'ProtocolSpecificationInvalidUtf8Accepted'}
    }
    & $verify
    $definition=(Get-Command Read-QuietProtocolSpecification).Definition
    $mutations=@(@("`$values['Version'] -ne 1","`$values['Version'] -ne 2"),
        @('-lt 1024','-lt 1023'),@('-gt 16384','-gt 16385'),@('-lt 65536','-lt 65535'),@('-gt 1048576','-gt 1048577'),
        @('[Text.UTF8Encoding]::new($false,$true)','[Text.UTF8Encoding]::new($false,$false)'))
    $outcomes=@(foreach($mutation in $mutations){
        if(!$definition.Contains($mutation[0])){throw 'ProtocolSpecificationMutantInvalid'}
        $detected=& {
            param($body,$verify)
            . ([scriptblock]::Create('function Read-QuietProtocolSpecification {'+$body+'}'))
            try{& $verify;$false}catch{$true}
        } $definition.Replace($mutation[0],$mutation[1]) $verify
        if(!$detected){throw ('ProtocolSpecificationMutantSurvived: '+$mutation[0])}
        @{Original=$mutation[0];Replacement=$mutation[1];State='Killed'}
    })
    $evidence=[pscustomobject]@{Seed=73593;Properties=66;MalformedCases=143;Mutations=$outcomes;Directory=$directory}
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'summary.json'),(ConvertTo-Json $evidence -Depth 6).Replace("`r`n","`n"),$utf8).GetAwaiter().GetResult()
    $evidence
}
