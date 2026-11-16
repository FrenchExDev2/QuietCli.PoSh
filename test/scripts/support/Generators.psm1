#Objective: Seeded, reproducible generators for property and fuzz tests (no global randomness).
#requires -Version 7.6

function Get-QuietTestSeed {
    <#
    .SYNOPSIS
    Returns QUIETCLI_TEST_SEED when it is a positive integer, otherwise the fixed default seed.
    #>
    $value=0
    if([int]::TryParse([string]$env:QUIETCLI_TEST_SEED,[ref]$value) -and $value -gt 0){return $value}
    return 61207
}

function New-QuietRandom {
    <#
    .SYNOPSIS
    Returns a deterministic System.Random for one seed.
    .PARAMETER Seed
    Seed; the same seed always yields the same sequence.
    #>
    param([Parameter(Mandatory)][int]$Seed)
    return [Random]::new($Seed)
}

function Get-QuietRandomItem {
    <#
    .SYNOPSIS
    Picks one item uniformly.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Items
    Non-empty candidate list.
    #>
    param([Parameter(Mandatory)][Random]$Random,[Parameter(Mandatory)][AllowNull()][AllowEmptyString()][AllowEmptyCollection()][object[]]$Items)
    if($Items.Count -eq 0){throw 'QuietRandomItemsEmpty'}
    return $Items[$Random.Next(0,$Items.Count)]
}

function Get-QuietRandomSubset {
    <#
    .SYNOPSIS
    Returns a random subset preserving the input order.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Items
    Candidates.
    .PARAMETER Probability
    Inclusion probability per item.
    #>
    param([Parameter(Mandatory)][Random]$Random,[AllowEmptyCollection()][object[]]$Items=@(),[double]$Probability=0.5)
    return ,[object[]]@(foreach($item in $Items){if($Random.NextDouble() -lt $Probability){$item}})
}

function Get-QuietShuffle {
    <#
    .SYNOPSIS
    Returns a Fisher-Yates permutation of the items.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Items
    Items to permute.
    #>
    param([Parameter(Mandatory)][Random]$Random,[AllowEmptyCollection()][object[]]$Items=@())
    $copy=[object[]]@($Items)
    for($index=$copy.Count-1;$index -gt 0;$index--){$other=$Random.Next(0,$index+1);$swap=$copy[$index];$copy[$index]=$copy[$other];$copy[$other]=$swap}
    return ,$copy
}

function New-QuietRandomString {
    <#
    .SYNOPSIS
    Returns a random string over an alphabet.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Alphabet
    Characters to draw from.
    .PARAMETER MinLength
    Minimum length.
    .PARAMETER MaxLength
    Maximum length.
    #>
    param([Parameter(Mandatory)][Random]$Random,[string]$Alphabet='abcdefghijklmnopqrstuvwxyz0123456789',[int]$MinLength=1,[int]$MaxLength=12)
    $length=$Random.Next($MinLength,$MaxLength+1)
    $builder=[Text.StringBuilder]::new()
    for($index=0;$index -lt $length;$index++){[void]$builder.Append($Alphabet[$Random.Next(0,$Alphabet.Length)])}
    return $builder.ToString()
}

function New-QuietFuzzPath {
    <#
    .SYNOPSIS
    Returns a hostile path-like string mixing separators, parent segments, control characters, Unicode and roots.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER MaxSegments
    Maximum number of segments.
    #>
    param([Parameter(Mandatory)][Random]$Random,[int]$MaxSegments=6)
    $segments=@('a','unit','lib','..','.','x.Tests.ps1',[string][char]0xE9,[char]::ConvertFromUtf32(0x1D11E),' ',[string][char]0,[string][char]9,'*','?','<','>','|',':','con','$env:TEMP','%TEMP%','~',('z'*300),'C:','\\server\share','/etc',[string][char]96,[string][char]39,[string][char]34)
    $separators=@('/','\','//','\\','')
    $count=$Random.Next(0,$MaxSegments+1)
    $builder=[Text.StringBuilder]::new()
    if($Random.Next(0,4) -eq 0){[void]$builder.Append((Get-QuietRandomItem $Random @('/','\','C:\','\\?\','//')))}
    for($index=0;$index -lt $count;$index++){
        if($index -gt 0){[void]$builder.Append((Get-QuietRandomItem $Random $separators))}
        [void]$builder.Append((Get-QuietRandomItem $Random $segments))
    }
    return $builder.ToString()
}

function New-QuietRandomSha256 {
    <#
    .SYNOPSIS
    Returns a random 64-character uppercase hexadecimal digest.
    .PARAMETER Random
    Seeded generator.
    #>
    param([Parameter(Mandatory)][Random]$Random)
    $bytes=[byte[]]::new(32);$Random.NextBytes($bytes)
    return [Convert]::ToHexString($bytes)
}

function New-QuietRandomDag {
    <#
    .SYNOPSIS
    Returns named nodes with acyclic dependencies; node 0 is the root (Core) every other node requires.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Count
    Number of nodes.
    .PARAMETER EdgeProbability
    Probability of each extra backward edge.
    #>
    param([Parameter(Mandatory)][Random]$Random,[ValidateRange(1,64)][int]$Count=4,[double]$EdgeProbability=0.3)
    $nodes=[Collections.Generic.List[object]]::new()
    for($index=0;$index -lt $Count;$index++){
        $name=if($index -eq 0){'Core'}else{'C'+$index+(New-QuietRandomString $Random 'abcdefghij' 1 4)}
        $requires=[Collections.Generic.List[string]]::new()
        if($index -gt 0){
            $requires.Add($nodes[0].Name)
            for($other=1;$other -lt $index;$other++){if($Random.NextDouble() -lt $EdgeProbability){$requires.Add($nodes[$other].Name)}}
        }
        $nodes.Add([pscustomobject][ordered]@{Name=$name;Requires=[string[]]$requires.ToArray()})
    }
    return ,$nodes.ToArray()
}

Export-ModuleMember -Function Get-QuietTestSeed,New-QuietRandom,Get-QuietRandomItem,Get-QuietRandomSubset,Get-QuietShuffle,New-QuietRandomString,New-QuietFuzzPath,New-QuietRandomSha256,New-QuietRandomDag
