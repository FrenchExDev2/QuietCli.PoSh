# Objectif : Afficher le projet et l’état des tests dans une fenêtre dédiée sans modifier l’exécution.
#requires -Version 7.6
<#
.SYNOPSIS
Read-only resizing monitor; closes automatically after a saved terminal result.
.PARAMETER RunDirectory
Directory containing status.json and summary.json.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$RunDirectory)
. (Join-Path $PSScriptRoot 'Monitor.Time.ps1')
function Read-RunState {
    <#
    .SYNOPSIS
    Reads only this run's status while allowing the writer to atomically replace the file on Windows.
    .PARAMETER Path
    Owned run status path.
    #>
    param([string]$Path)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
    try{return $reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose();$stream.Dispose()}
}
function Get-DisplayWidth {
    <#
.SYNOPSIS
Measures visible Unicode width, excluding ANSI sequences.
    .PARAMETER Text
    Visible cell text.
    #>
    param([string]$Text)
    $clean=[regex]::Replace($Text,'\x1B\[[0-?]*[ -/]*[@-~]','');$width=0
    foreach($rune in $clean.EnumerateRunes()){
        $category=[Text.Rune]::GetUnicodeCategory($rune)
        if($category -in @([Globalization.UnicodeCategory]::NonSpacingMark,[Globalization.UnicodeCategory]::EnclosingMark,[Globalization.UnicodeCategory]::Format)){continue}
        $value=$rune.Value
        $width+=if($value -ge 0x1100 -and ($value -le 0x115f -or $value -ge 0x2e80 -and $value -le 0xa4cf -or $value -ge 0xac00 -and $value -le 0xd7a3 -or $value -ge 0xf900 -and $value -le 0xfaff -or $value -ge 0x1f300)){2}else{1}
    }
    return $width
}
function Fit-Cell {
    <#
.SYNOPSIS
Clips and pads a cell without splitting a Unicode text element.
    .PARAMETER Text
    Cell text.
    .PARAMETER Width
    Available display columns.
    .PARAMETER Right
    Right-aligns numeric values.
    #>
    param([string]$Text,[int]$Width,[switch]$Right)
    $Text=$Text -replace '[\r\n]',' '
    if((Get-DisplayWidth $Text) -le $Width){$padding=' '*($Width-(Get-DisplayWidth $Text));if($Right){return $padding+$Text};return $Text+$padding}
    $enumerator=[Globalization.StringInfo]::GetTextElementEnumerator($Text);$result=''
    while($enumerator.MoveNext()){if((Get-DisplayWidth ($result+$enumerator.Current)) -gt $Width-1){break};$result+=$enumerator.Current}
    return $result+'…'+(' '*[Math]::Max(0,$Width-1-(Get-DisplayWidth $result)))
}
$interactive=![Console]::IsOutputRedirected
$previousCursor=$true
try{
    if($interactive){$previousCursor=[Console]::CursorVisible;[Console]::CursorVisible=$false}
    do{
        $path=Join-Path $RunDirectory 'status.json'
        $state=if(Test-Path -LiteralPath $path){try{Read-RunState $path}catch{$null}}else{$null}
        $width=if($interactive){[Math]::Max(20,[Console]::WindowWidth-1)}else{110}
        $height=if($interactive){[Math]::Max(5,[Console]::WindowHeight-1)}else{20}
        if($state){
            $duration=Get-QuietMonitorDuration -StartedUtc $state.StartedUtc -FinishedUtc $state.FinishedUtc
            $title="Projet : $($state.Project) | Tâche : $($state.Task)"
            if($interactive){[Console]::Title=$title}
            $lines=[Collections.Generic.List[string]]::new()
            $heading=if($width -lt 75){'P:'+($state.Project -replace 'FrenchExDev2.QuietCli.','' -replace '\.PoSh','')+' | T:Tests'}else{$title}
            $lines.Add((Fit-Cell $heading $width));$lines.Add((Fit-Cell $state.Workspace $width));$lines.Add((Fit-Cell $state.ProjectDirectory $width))
            if($width -ge 75){
                $columns=@([Math]::Max(12,$width-60),12,10,12,8,8)
                $border='┌'+(($columns|ForEach-Object{'─'*$_}) -join '┬')+'┐'
                $lines.Add((Fit-Cell $border $width))
                $identity=if($state.PSObject.Properties['ContainerId']){$state.ContainerId}else{[string]$state.ProcessId}
                $passed=if($null -eq $state.Passed){'-'}else{[string]$state.Passed};$failed=if($null -eq $state.Failed){'-'}else{[string]$state.Failed}
                $rowNumber=0
                foreach($row in @(@('Platform','State','Duration','Process','Passed','Failed'),@($state.Platform,$state.State,$duration,$identity,$passed,$failed))){$cells=for($i=0;$i -lt 6;$i++){Fit-Cell ([string]$row[$i]) $columns[$i] -Right:($rowNumber -gt 0 -and $i -ge 2)};$rowNumber++;$lines.Add((Fit-Cell ('|'+($cells -join '|')+'|') $width))}
                $lines.Add((Fit-Cell ('└'+(($columns|ForEach-Object{'─'*$_}) -join '┴')+'┘') $width))
            }else{$lines.Add((Fit-Cell "$($state.Platform) | $($state.State) | $duration | PID $($state.ProcessId)" $width));$lines.Add((Fit-Cell "Passed $($state.Passed) | Failed $($state.Failed)" $width))}
            $lines.Add((Fit-Cell $state.Case $width));$lines.Add((Fit-Cell "Rapport : $RunDirectory" $width))
            if($state.Error){$lines.Add((Fit-Cell $state.Error $width))}
            if($interactive){[Console]::SetCursorPosition(0,0);foreach($line in $lines|Select-Object -First $height){[Console]::WriteLine($line)}}else{$lines|ForEach-Object{[Console]::WriteLine($_)}}
            $terminal=$state.State -in @('Success','Failed','Crash','Timeout','Cancelled')
            if($terminal -and (Test-Path -LiteralPath (Join-Path $RunDirectory 'summary.json'))){break}
        }
        if(!$interactive){break}
        [void][Threading.Tasks.Task]::Delay(400).GetAwaiter().GetResult()
    }while($true)
}finally{if($interactive){[Console]::CursorVisible=$previousCursor}}
