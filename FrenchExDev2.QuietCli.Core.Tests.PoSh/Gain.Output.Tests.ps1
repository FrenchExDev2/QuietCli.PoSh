function Test-QuietGainOutput {
    <#
    .SYNOPSIS
    Checks report formats, generated filter inputs, invalid options and read-only telemetry.
    .DESCRIPTION
    Runs against the real metadata engine in the launcher's private database. Targeted
    mutations exercise the same independent assertions and restore the function afterwards.
    #>
    param()
    & (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
        $original=${function:Get-QuietCliGain}
        $send=${function:Send-QuietRequest}
        $script:gainTestWrites=0
        function Send-QuietRequest {
            param($Request)
            if($Request.Action -eq 'save'){$script:gainTestWrites++}
            & $send $Request
        }
        $context='gain-output-'+[guid]::NewGuid().ToString('N')
        $null=& $send @{Action='save';Kind='invocation';Metadata=@{InvocationId=$context;Context=$context;Command='gain-fixture';Role='Business';Outcome='Success'}}
        $null=& $send @{Action='save';Kind='delivery';Metadata=@{InvocationId=$context;DeliveryId=$context+'-delivery';Context=$context;Command='gain-fixture';Role='Business';Outcome='Success';OutputBytes=17L}}
        $from=[DateTimeOffset]::UtcNow.AddMinutes(-1);$to=$from.AddMinutes(2)
        $check={
            $options=@{Context=$context;From=$from;To=$to}
            $object=Get-QuietCliGain @options
            if($object.GetType().FullName -ne 'System.Management.Automation.PSCustomObject' -or $object.Invocations -ne 1 -or $object.RootDeliveries -ne 1 -or $object.RootDeliveryBytes -ne 17){throw 'GainDefaultObjectInvariant'}
            foreach($groupBy in @('Context','Command','Session','Module','Role','Outcome')){
                $report=Get-QuietCliGain @options -GroupBy $groupBy
                if($report.Invocations -ne 1 -or !$report.Complete){throw 'GainFilterProperty'}
            }
            $json=Get-QuietCliGain @options -AsJson
            $compact=Get-QuietCliGain @options -AsJson -Compress
            if($json -notmatch '\r?\n' -or $compact -match '\r?\n'){throw 'GainJsonWhitespaceInvariant'}
            if(($json|ConvertFrom-Json).Invocations -ne 1 -or ($compact|ConvertFrom-Json).RootDeliveries -ne 1){throw 'GainJsonCountersInvariant'}
            $yaml=Get-QuietCliGain @options -AsYaml
            if($yaml -notmatch '"Invocations": 1' -or $yaml -notmatch '"Groups":' -or $yaml -match '^\s*\{'){throw 'GainYamlMappingInvariant'}
            foreach($invalid in @(@{Compress=$true},@{AsYaml=$true;Compress=$true},@{AsYaml=$true;AsJson=$true},@{AsObject=$true;AsJson=$true},@{AsObject=$true;AsYaml=$true},@{Compress=$false})){
                $rejected=$false
                try{$null=Get-QuietCliGain @options @invalid}catch{$rejected=$_.Exception.Message -in @('CompressRequiresAsJson','OutputFormatsAreExclusive')}
                if(!$rejected){throw 'GainInvalidFormatsAccepted'}
            }
            $random=[Random]::new(68131)
            foreach($index in 1..16){
                $absent=$context+'-é-'+$random.Next()
                $empty=Get-QuietCliGain -C $absent -MaxEvents ($random.Next(1,1000))
                if($empty.GetType().FullName -ne 'System.Management.Automation.PSCustomObject' -or $empty.Invocations -ne 0 -or $empty.Groups.Count -ne 0){throw 'GainEmptyFilterProperty'}
            }
            $after=Get-QuietCliGain @options -AsObject
            if($after.Invocations -ne 1 -or $after.RootDeliveries -ne 1 -or $after.RootDeliveryBytes -ne 17 -or $script:gainTestWrites -ne 0){throw 'GainReportRecordedTelemetry'}
        }
        try{
            & $check
            $mutations=@(
                @('DefaultJson','return $report','return (ConvertTo-Json -InputObject $report -Depth 20)'),
                @('IgnoreCompress','-Compress:$Compress','-Compress'),
                @('TrackReport','$query=@{Action=''gain'';','$null=Send-QuietRequest @{Action=''save'';Kind=''invocation'';Metadata=@{InvocationId=[guid]::NewGuid().ToString();Context=$Context;Command=''mutant''}}; $query=@{Action=''gain'';')
            )
            foreach($mutation in $mutations){
                $source=$original.ToString()
                if(!$source.Contains($mutation[1])){throw 'GainMutationAnchorMissing'}
                ${function:Get-QuietCliGain}=[scriptblock]::Create($source.Replace($mutation[1],$mutation[2]))
                $killed=$false
                try{& $check}catch{
                    if($_.Exception.Message -notin @('GainDefaultObjectInvariant','GainJsonWhitespaceInvariant','GainReportRecordedTelemetry')){throw}
                    $killed=$true
                }
                if(!$killed){throw "GainMutantSurvived:$($mutation[0])"}
                ${function:Get-QuietCliGain}=$original
            }
            [pscustomobject]@{Seed=68131;GeneratedFilters=16;InvalidFormats=6;MutantsKilled=3;State='Success'}
        }finally{
            ${function:Get-QuietCliGain}=$original
            ${function:Send-QuietRequest}=$send
            Remove-Variable gainTestWrites -Scope Script
        }
    }
}
