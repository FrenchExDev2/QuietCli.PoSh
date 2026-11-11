#requires -Version 7.6
<#
.SYNOPSIS
Accepts an All qualification receipt only for this exact revision and workflow attempt.
.PARAMETER ReceiptPath
Receipt downloaded from the current workflow run, never from an earlier run.
.PARAMETER Revision
Expected immutable workflow revision.
.PARAMETER RunId
Expected GitHub workflow run ID.
.PARAMETER RunAttempt
Expected GitHub workflow attempt.
.PARAMETER OutputPath
GitHub output file receiving qualified_sha after acceptance only.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][ValidatePattern('\A[1-9][0-9]*\z')][string]$RunId,[Parameter(Mandatory)][ValidatePattern('\A[1-9][0-9]*\z')][string]$RunAttempt,
    [Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($ReceiptPath,'Validate current-run qualification and emit accepted revision')){return}
$ErrorActionPreference='Stop'
$file=Get-Item -LiteralPath $ReceiptPath -Force
if($file.Length -gt 16384 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'QualificationReceiptInvalid'}
$text=[IO.File]::ReadAllText($file.FullName,[Text.UTF8Encoding]::new($false,$true))
$document=[Text.Json.JsonDocument]::Parse($text)
try{
    if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'QualificationReceiptInvalid'}
    $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($property in $document.RootElement.EnumerateObject()){if(!$keys.Add($property.Name)){throw 'QualificationReceiptDuplicateField'}}
}finally{$document.Dispose()}
$receipt=$text|ConvertFrom-Json
if($receipt.Ready -isnot [bool] -or !$receipt.Ready -or $receipt.Revision -cne $Revision -or $receipt.Suite -cne 'All' -or
    $receipt.Windows -cne 'success' -or $receipt.Linux -cne 'success' -or $receipt.Mutation -cne 'skipped' -or
    $receipt.MutationRequired -isnot [bool] -or $receipt.MutationRequired -or $receipt.TtyQualification -cne 'Excluded' -or
    [string]$receipt.RunId -cne $RunId -or [string]$receipt.RunAttempt -cne $RunAttempt){throw 'QualificationReceiptRejected'}
[IO.File]::AppendAllText($OutputPath,"qualified_sha=$Revision`n",[Text.UTF8Encoding]::new($false))
