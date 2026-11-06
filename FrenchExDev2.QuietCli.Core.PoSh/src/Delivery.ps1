function ConvertTo-QuietYamlValue {
    <#
.SYNOPSIS
Emits YAML directly, without an intermediate JSON document.
    .PARAMETER Value
    Normalized bounded graph.
    .PARAMETER Indent
    Current indentation.
    #>
    param([AllowNull()]$Value,[int]$Indent=0)
    Assert-QuietResources 'resources/yaml/YamlDotNet.dll'
    return [FrenchExDev2.QuietCli.BoundedYaml]::Render($Value,$script:QuietRoot,$Indent,[Func[object,string]]{param($scalar)ConvertTo-Json -InputObject $scalar -Depth 4 -Compress})
}
