#requires -Version 7.6

Describe 'Get-QuietCompanions' {
    BeforeAll {
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
        $null=Import-QuietTestLibrary -Name CiCompanions
        $catalogue=@{Companions=[ordered]@{
            Box2=[pscustomobject]@{Name='Box2';Mutation=@{environment=@{QUIETCLI_BOX_MUTATION='1'}};Workstation=$false}
            Demo=[pscustomobject]@{Name='Demo';Mutation=$null;Workstation=$true}
        }}
    }
    It 'validates against new declarations in catalogue order and canonicalises names' {
        @(Get-QuietCompanions -Configuration $catalogue -Name demo,box2,Box2)|Should -BeExactly @('Box2','Demo')
        @(Get-QuietCompanions -Configuration $catalogue -Name box2 -Capability Mutation)|Should -BeExactly @('Box2')
        @(Get-QuietCompanions -Configuration $catalogue -Name demo -Capability Workstation)|Should -BeExactly @('Demo')
    }
    It 'refuses unknown names and missing capabilities' {
        {Get-QuietCompanions -Configuration $catalogue -Name Ghost}|Should -Throw '*CiCompanionNotAvailable*'
        {Get-QuietCompanions -Configuration $catalogue -Name Demo -Capability Mutation}|Should -Throw '*CiCompanionNotAvailable*'
    }
}
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CiCompanions
    $seed=Get-QuietTestSeed
    # The real checkout provides the pinned YamlDotNet and the suite manifests; the YAML itself is a fixture.
    $workspace=Get-QuietTestWorkspaceRoot
    $valid=@'
schema: 1
companions:
  Core:
    requires: []
    image: base
  Git:
    requires: [Core]
    image: overlay
suites:
  Core:
    test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh
    command: Invoke-QuietCoreTests
    requires: [Core]
    core_evidence: true
  Git:
    test_project: FrenchExDev2.QuietCli.Git.Tests.PoSh
    command: Invoke-QuietGitTests
    requires: [Git]
    core_evidence: false
    qualification:
      - rid: win-x64
        runtime_major: 11
        environment:
          QUIETCLI_GIT_PUSH_MUTATION: '1'

'@.Replace("`r`n","`n")
    $read={param([string]$Text)
        $path=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'yaml',[guid]::NewGuid().ToString('N')+'.yml')) $Text
        Read-QuietCiCompanions -WorkspaceRoot $workspace -ConfigurationPath $path
    }
    # Companions from a random DAG, written in a shuffled key order; one Core suite requires a random subset.
    $newDocument={param([Random]$Random)
        $nodes=[object[]](New-QuietRandomDag $Random ($Random.Next(1,8)))
        $images=@{};foreach($node in $nodes){$images[$node.Name]=if($node.Name -ceq 'Core'){'base'}else{Get-QuietRandomItem $Random @('overlay','none')}}
        $roots=[object[]](Get-QuietRandomSubset $Random @($nodes.Name) 0.5);if(!$roots.Count){$roots=@($nodes[-1].Name)}
        $text=[Text.StringBuilder]::new("schema: 1`ncompanions:`n")
        foreach($node in (Get-QuietShuffle $Random $nodes)){[void]$text.Append("  $($node.Name):`n    requires: [$($node.Requires -join ', ')]`n    image: $($images[$node.Name])`n")}
        [void]$text.Append("suites:`n  Core:`n    test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh`n    command: Invoke-QuietCoreTests`n    requires: [$($roots -join ', ')]`n    core_evidence: true`n")
        [pscustomobject]@{Text=$text.ToString();Nodes=$nodes;Images=$images;Roots=[string[]]$roots}
    }
    $errorText={param($ErrorRecord)
        $exception=$ErrorRecord.Exception
        while($exception -is [Management.Automation.RuntimeException] -and $exception.InnerException -and $exception.Message -notmatch '^Ci'){$exception=$exception.InnerException}
        [pscustomobject]@{Message=$exception.Message;Type=$exception.GetType().FullName}
    }
}

Describe 'Read-QuietCiCompanions' {
    It 'reads the build catalogue and resolves old checkout fixtures when it is absent' {
        $root=[IO.Path]::Combine($TestDrive,'catalogue-path')
        $null=New-Item -Path ([IO.Path]::Combine($root,'build')) -ItemType Directory -Force
        [IO.File]::WriteAllText([IO.Path]::Combine($root,'.companions.yaml'),'obsolete root file',[Text.UTF8Encoding]::new($false))
        Get-QuietCiCompanionCataloguePath -WorkspaceRoot $root | Should -BeNullOrEmpty
        $legacy=[IO.Path]::Combine($root,'build','companions.yml')
        [IO.File]::WriteAllText($legacy,'legacy',[Text.UTF8Encoding]::new($false))
        Get-QuietCiCompanionCataloguePath -WorkspaceRoot $root | Should -BeExactly $legacy
        $current=[IO.Path]::Combine($root,'build','companions.yaml')
        [IO.File]::WriteAllText($current,'current',[Text.UTF8Encoding]::new($false))
        Get-QuietCiCompanionCataloguePath -WorkspaceRoot $root | Should -BeExactly $current
    }

    It 'reads the repository catalogue with Core as the unique base' {
        $configuration=Read-QuietCiCompanions -WorkspaceRoot $workspace
        $configuration.Path | Should -BeExactly ([IO.Path]::Combine($workspace,'build','companions.yaml'))
        @(Get-QuietCompanions -WorkspaceRoot $workspace) | Should -BeExactly @('Core','Git','Vagrant')
        $configuration.Base|Should -BeExactly 'Core'
        $configuration.SHA256|Should -Match '\A[A-F0-9]{64}\z'
        foreach($name in $configuration.Companions.Keys){$configuration.Companions[$name].Image|Should -BeIn @('base','overlay','none')}
        foreach($name in $configuration.Suites.Keys){[IO.File]::Exists($configuration.Suites[$name].TestsManifest)|Should -BeTrue}
    }

    It 'resolves Core when another companion source is absent from the checkout' {
        $missing='src/Git/src/Absent.Git.PoSh'
        [IO.Directory]::Exists([IO.Path]::Combine($workspace,$missing))|Should -BeFalse
        $configuration=& $read ($valid.Replace('    image: overlay',"    image: overlay`n    src: $missing"))
        $configuration.Companions['Git'].SourcePath|Should -BeExactly $missing
        (Resolve-QuietCiCompanions $configuration -Suite Core).Dependencies|Should -BeExactly @('Core')
    }

    It 'rejects malformed paths even when the checkout can omit a companion' -ForEach @(
        @{Path='src/Git/src/..'},
        @{Path='src/Git/test/FrenchExDev2.QuietCli.Git.PoSh'},
        @{Path='../Git/src/FrenchExDev2.QuietCli.Git.PoSh'}
    ) {
        {& $read ($valid.Replace('    image: overlay',"    image: overlay`n    src: $Path"))}|
            Should -Throw -ExpectedMessage 'CiCompanionPathInvalid: Git/src'
    }

    It 'round-trips random acyclic catalogues and resolves them in dependency order' {
        $null=Invoke-QuietProperty -Name 'companions-roundtrip' -Seed $seed -Count 40 -Generator {param($random)& $newDocument $random} -Property {param($case)
            $configuration=& $read $case.Text
            if(@($configuration.Companions.Keys).Count -ne $case.Nodes.Count){throw 'count'}
            foreach($node in $case.Nodes){
                $entry=$configuration.Companions[$node.Name]
                if(($entry.requires -join ',') -cne ($node.Requires -join ',') -or $entry.Image -cne $case.Images[$node.Name]){throw "entry $($node.Name)"}
            }
            $selection=Resolve-QuietCiCompanions $configuration -Suite All
            $order=@($selection.Dependencies)
            # Every dependency precedes its dependent, each once, and the closure of the roots is complete.
            if(@($order|Select-Object -Unique).Count -ne $order.Count){throw 'duplicate'}
            foreach($name in $order){foreach($dependency in $configuration.Companions[$name].requires){if($order.IndexOf($dependency) -lt 0 -or $order.IndexOf($dependency) -gt $order.IndexOf($name)){throw "order $dependency>$name"}}}
            foreach($root in $case.Roots){if($root -cnotin $order){throw "root $root"}}
            if($order[0] -cne 'Core'){throw 'Core first'}
            $images=@($order|Where-Object {$case.Images[$_] -cne 'none'})
            ((@($selection.Images) -join ',') -ceq ($images -join ',')) -and $selection.Images[0] -ceq 'Core' -and $selection.HasCoreEvidence
        }
    }

    It 'rejects <Name>' -ForEach @(
        @{Name='another schema';From='schema: 1';To='schema: 2';Error='CiCompanionsSchemaInvalid'}
        @{Name='a quoted schema';From='schema: 1';To="schema: '1'";Error='CiCompanionsSchemaInvalid'}
        @{Name='an extra top-level key';From='schema: 1';To="schema: 1`nextra: 1";Error='CiCompanionsSchemaInvalid'}
        @{Name='empty companions';From="companions:`n  Core:`n    requires: []`n    image: base`n  Git:`n    requires: [Core]`n    image: overlay`n";To="companions: {}`n";Error='CiCompanionsSchemaInvalid'}
        @{Name='a lower-case companion';From="  Git:`n    requires: [Core]";To="  git:`n    requires: [Core]";Error='CiCompanionNameInvalid'}
        @{Name='a companion named All';From="  Git:`n    requires: [Core]";To="  ALL:`n    requires: [Core]";Error='CiCompanionNameInvalid'}
        @{Name='a scalar companion';From="  Git:`n    requires: [Core]`n    image: overlay";To='  Git: overlay';Error='CiCompanionDeclarationInvalid: Git'}
        @{Name='an unknown companion field';From='    image: overlay';To="    image: overlay`n    extra: 1";Error='CiCompanionFieldUnknown: extra'}
        @{Name='missing requires';From="  Git:`n    requires: [Core]`n";To="  Git:`n";Error='CiCompanionDependenciesInvalid: Git'}
        @{Name='scalar requires';From="  Git:`n    requires: [Core]";To="  Git:`n    requires: Core";Error='CiCompanionDependenciesInvalid: Git'}
        @{Name='a self dependency';From="  Git:`n    requires: [Core]";To="  Git:`n    requires: [Core, Git]";Error='CiCompanionDependenciesInvalid: Git'}
        @{Name='a duplicate dependency';From="  Git:`n    requires: [Core]";To="  Git:`n    requires: [Core, Core]";Error='CiCompanionDependenciesInvalid: Git'}
        @{Name='an unknown image policy';From='    image: overlay';To='    image: Overlay';Error='CiCompanionPolicyInvalid: Git'}
        @{Name='two bases';From='    image: overlay';To='    image: base';Error='CiCompanionBaseNotUnique'}
        @{Name='no base';From='    image: base';To='    image: none';Error='CiCompanionBaseNotUnique'}
        @{Name='a base other than Core';From="    requires: []`n    image: base";To="    requires: []`n    image: none`n  Other:`n    requires: []`n    image: base";Error='CiCompanionBaseInvalid'}
        @{Name='a base with dependencies';From="  Core:`n    requires: []";To="  Core:`n    requires: [Git]";Error='CiCompanionBaseInvalid'}
        @{Name='a dependency cycle';From='    image: overlay';To="    image: overlay`n  A:`n    requires: [Core, B]`n    image: none`n  B:`n    requires: [A]`n    image: none";Error='CiCompanionCycle: A'}
        @{Name='an unknown dependency';From="  Git:`n    requires: [Core]";To="  Git:`n    requires: [Core, Nope]";Error='CiCompanionUnknown: Nope'}
        @{Name='a lower-case suite';From="  Git:`n    test_project";To="  gitSuite:`n    test_project";Error='CiSuiteNameInvalid'}
        @{Name='an unknown suite field';From='    core_evidence: true';To="    core_evidence: true`n    extra: 1";Error='CiSuiteFieldUnknown: extra'}
        @{Name='a foreign test project';From='test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh';To='test_project: Other.Core.Tests.PoSh';Error='CiSuiteDeclarationInvalid'}
        @{Name='a foreign command';From='command: Invoke-QuietCoreTests';To='command: Invoke-CoreTests';Error='CiSuiteDeclarationInvalid'}
        @{Name='empty suite requirements';From="    requires: [Core]`n    core_evidence: true";To="    requires: []`n    core_evidence: true";Error='CiSuiteDeclarationInvalid'}
        @{Name='a textual core evidence';From='core_evidence: true';To="core_evidence: 'true'";Error='CiSuiteDeclarationInvalid'}
        @{Name='a missing test project';From='test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh';To='test_project: FrenchExDev2.QuietCli.Nope.Tests.PoSh';Error='CiSuiteTestProjectMissing: Core'}
        @{Name='an unexported command';From='command: Invoke-QuietCoreTests';To='command: Invoke-QuietNopeTests';Error='CiSuiteCommandNotExported: Core'}
        @{Name='an unknown suite dependency';From="    requires: [Core]`n    core_evidence: true";To="    requires: [Nope]`n    core_evidence: true";Error='CiSuiteDependencyInvalid: Core'}
        @{Name='a duplicate suite dependency';From="    requires: [Core]`n    core_evidence: true";To="    requires: [Core, Core]`n    core_evidence: true";Error='CiSuiteDependencyInvalid: Core'}
        @{Name='scalar qualification';From="    qualification:`n      - rid: win-x64`n        runtime_major: 11`n        environment:`n          QUIETCLI_GIT_PUSH_MUTATION: '1'";To='    qualification: win-x64';Error='CiCompanionQualificationInvalid'}
        @{Name='an unknown runtime identifier';From='rid: win-x64';To='rid: win-x86';Error='CiCompanionQualificationInvalid'}
        @{Name='an old runtime major';From='runtime_major: 11';To='runtime_major: 9';Error='CiCompanionQualificationInvalid'}
        @{Name='a textual runtime major';From='runtime_major: 11';To="runtime_major: '11'";Error='CiCompanionQualificationInvalid'}
        @{Name='an extra qualification key';From='runtime_major: 11';To="runtime_major: 11`n        extra: 1";Error='CiCompanionQualificationInvalid'}
        @{Name='a foreign environment variable';From='QUIETCLI_GIT_PUSH_MUTATION:';To='QUIETCLI_GIT_PUSH:';Error='CiCompanionEnvironmentInvalid'}
        @{Name='a suite named All';From="suites:`n  Core:";To="suites:`n  All:";Error='CiSuiteNameInvalid'}
        @{Name='a scalar suite';From="          QUIETCLI_GIT_PUSH_MUTATION: '1'`n";To="          QUIETCLI_GIT_PUSH_MUTATION: '1'`n  Extra: 1`n";Error='CiSuiteDeclarationInvalid'}
        @{Name='a suite declared as a list of mappings';From="          QUIETCLI_GIT_PUSH_MUTATION: '1'`n";To="          QUIETCLI_GIT_PUSH_MUTATION: '1'`n  Extra:`n    - bogus: 1`n";Error='CiSuiteDeclarationInvalid'}
        @{Name='a single qualification mapping';From="    qualification:`n      - rid: win-x64`n        runtime_major: 11";To="    qualification:`n        rid: win-x64`n        runtime_major: 11";Error='CiCompanionQualificationInvalid'}
        @{Name='a runtime major above 99';From='runtime_major: 11';To='runtime_major: 100';Error='CiCompanionQualificationInvalid'}
        @{Name='a disabled environment value';From="QUIETCLI_GIT_PUSH_MUTATION: '1'";To="QUIETCLI_GIT_PUSH_MUTATION: '0'";Error='CiCompanionEnvironmentInvalid'}
    ) {
        $valid.Contains($From)|Should -BeTrue -Because 'the case must change the valid document'
        $text=$valid.Replace($From,$To)
        $message=try{$null=& $read $text;'<no error>'}catch{(& $errorText $_).Message}
        $message|Should -BeExactly $Error
    }

    It 'rejects a duplicate key through the YAML reader' {
        {& $read ($valid.Replace('    image: overlay',"    image: overlay`n    image: none"))}|Should -Throw
    }

    It 'rejects an oversized file before parsing it' {
        {& $read ($valid+('#'*262145))}|Should -Throw -ExpectedMessage 'CiCompanionsFileInvalid'
    }

    It 'accepts a file of exactly the size limit' {
        $text=$valid+'#'
        $text+=('#'*(262144-[Text.Encoding]::UTF8.GetByteCount($text)))
        [Text.Encoding]::UTF8.GetByteCount($text)|Should -Be 262144
        (& $read $text).Base|Should -BeExactly 'Core'
    }

    It 'rejects a document that is not valid UTF-8' {
        $path=[IO.Path]::Combine($TestDrive,'invalid-utf8.yml')
        [IO.File]::WriteAllBytes($path,[byte[]]@([Text.Encoding]::UTF8.GetBytes($valid+'# ')+[byte]0xFF+[byte]0x0A))
        $failure=try{$null=Read-QuietCiCompanions -WorkspaceRoot $workspace -ConfigurationPath $path;$null}catch{$_.Exception}
        while($failure -and $failure -isnot [Text.DecoderFallbackException]){$failure=$failure.InnerException}
        $failure|Should -BeOfType ([Text.DecoderFallbackException]) -Because 'an invalid byte must not decode to U+FFFD'
    }

    It 'accepts the runtime major bound <Major>' -ForEach @(@{Major=10},@{Major=99}) {
        $configuration=& $read ($valid.Replace('runtime_major: 11',"runtime_major: $Major"))
        $configuration.Suites['Git'].Qualification[0]['runtime_major']|Should -Be $Major
    }

    It 'returns each suite with its group, test project, command, requirements, evidence and manifest' {
        $configuration=& $read $valid
        @($configuration.Suites.Values|ForEach-Object {'{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Name,$_.Group,$_.TestsModule,$_.Command,($_.Requires -join ','),$_.CoreEvidence}) -join "`n"|
            Should -BeExactly "Core|Core|FrenchExDev2.QuietCli.Core.Tests.PoSh|Invoke-QuietCoreTests|Core|True`nGit|Git|FrenchExDev2.QuietCli.Git.Tests.PoSh|Invoke-QuietGitTests|Git|False"
        [IO.Path]::GetFileName($configuration.Suites['Git'].TestsManifest)|Should -BeExactly 'FrenchExDev2.QuietCli.Git.Tests.PoSh.psd1'
    }

    It 'fails only with typed Ci errors or YAML reader errors on fuzzed documents' {
        $null=Invoke-QuietProperty -Name 'companions-fuzz' -Seed $seed -Count 120 -Generator {param($random)
            $text=$valid
            for($step=0;$step -lt $random.Next(1,4);$step++){
                $position=$random.Next(0,$text.Length)
                $text=switch($random.Next(0,4)){
                    0{$text.Remove($position,[Math]::Min($random.Next(1,12),$text.Length-$position))}
                    1{$text.Insert($position,(Get-QuietRandomItem $random @(':','-','[',']','{','}',"'",'"','#','&','*','!','|','>','%','@',"`n",' ','~','null','0x1','A','[a, b]')))}
                    2{$lines=$text.Split("`n");$index=$random.Next(0,$lines.Count);($lines[0..$index]+$lines[$index..($lines.Count-1)]) -join "`n"}
                    default{$lines=[Collections.Generic.List[string]]$text.Split("`n");$index=$random.Next(0,$lines.Count);$lines.RemoveAt($index);$lines -join "`n"}
                }
            }
            $text
        } -Property {param($text)
            try{$configuration=& $read $text}catch{
                $failure=& $errorText $_
                if($failure.Message -cmatch '\ACi[A-Za-z]+(?::|\z)' -or $failure.Type -like 'YamlDotNet.*'){return $true}
                throw ("untyped {0}: {1}" -f $failure.Type,$failure.Message)
            }
            $configuration.Base -ceq 'Core'
        }
    }
}

Describe 'Read-QuietCiCompanions suite groups' {
    BeforeAll {
        # A fixture checkout: the pinned YAML reader copied from the real Core module, and a hand-written test manifest.
        $resourcesOf={param([string]$Root)[IO.Path]::Combine($Root,'src','Core','src','FrenchExDev2.QuietCli.Core.PoSh','resources')}
        $manifestPathOf={param([string]$Root)[IO.Path]::Combine($Root,'src','Box','test','FrenchExDev2.QuietCli.Box.Tests.PoSh','FrenchExDev2.QuietCli.Box.Tests.PoSh.psd1')}
        $newWorkspace={param([byte[]]$Manifest)
            $root=[IO.Path]::Combine($TestDrive,'ws-'+[guid]::NewGuid().ToString('N'))
            $resources=& $resourcesOf $root
            [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($resources,'yaml'))
            foreach($relative in 'dependencies.lock.json','yaml/YamlDotNet.dll'){[IO.File]::Copy([IO.Path]::Combine((& $resourcesOf $workspace),$relative),[IO.Path]::Combine($resources,$relative))}
            $path=& $manifestPathOf $root
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllBytes($path,$Manifest)
            $null=New-QuietTestFile ([IO.Path]::Combine($root,'build','companions.yml')) "schema: 1`ncompanions:`n  Core:`n    requires: []`n    image: base`n  Box:`n    requires: [Core]`n    image: none`nsuites:`n  BoxSuite:`n    test_project: FrenchExDev2.QuietCli.Box.Tests.PoSh`n    command: Invoke-QuietBoxTests`n    requires: [Box]`n    core_evidence: false`n"
            $root
        }
        $manifestOf={param([string]$QuietCli)[Text.Encoding]::UTF8.GetBytes("@{ModuleVersion='1.0.0';FunctionsToExport=@('Invoke-QuietBoxTests');PrivateData=@{QuietCli=@{$QuietCli}}}`n")}
    }

    It 'takes the group <Expected> from the manifest QuietCli data "<QuietCli>"' -ForEach @(
        @{QuietCli="SolutionGroup='Box'";Expected='Box'}
        @{QuietCli='';Expected='BoxSuite'}
        @{QuietCli="SolutionGroup=''";Expected='BoxSuite'}
    ) {
        $root=& $newWorkspace (& $manifestOf $QuietCli)
        $suite=(Read-QuietCiCompanions -WorkspaceRoot $root).Suites['BoxSuite']
        $suite.Group|Should -BeExactly $Expected
        $suite.TestsManifest|Should -BeExactly (& $manifestPathOf $root)
    }

    It 'rejects the group <Group>' -ForEach @(@{Group='box'},@{Group='Box-Suite'},@{Group='1Box'}) {
        $root=& $newWorkspace (& $manifestOf "SolutionGroup='$Group'")
        {Read-QuietCiCompanions -WorkspaceRoot $root}|Should -Throw -ExpectedMessage ('CiSuiteGroupInvalid: '+$Group)
    }

    It 'rejects a test manifest that is not valid UTF-8' {
        $root=& $newWorkspace ([byte[]]@((& $manifestOf "SolutionGroup='Box'")+[byte[]][Text.Encoding]::UTF8.GetBytes('# ')+[byte]0xFF+[byte]0x0A))
        $failure=try{$null=Read-QuietCiCompanions -WorkspaceRoot $root;$null}catch{$_.Exception}
        while($failure -and $failure -isnot [Text.DecoderFallbackException]){$failure=$failure.InnerException}
        $failure|Should -BeOfType ([Text.DecoderFallbackException])
    }
}

Describe 'Resolve-QuietCiCompanions' {
    BeforeAll {
        $configuration=& $read ($valid.Replace("  Git:`n    requires: [Core]`n    image: overlay","  Git:`n    requires: [Core]`n    image: overlay`n  Vagrant:`n    requires: [Core]`n    image: none")+@'
  Vagrant:
    test_project: FrenchExDev2.QuietCli.Vagrant.Tests.PoSh
    command: Invoke-QuietVagrantTests
    requires: [Vagrant]
    core_evidence: false
'@.Replace("`r`n","`n"))
    }

    It 'selects <Suite> as <Selected> with dependencies <Dependencies> and images <Images>' -ForEach @(
        @{Suite='All';Selected='Core,Git,Vagrant';Dependencies='Core,Git,Vagrant';Images='Core,Git';Evidence=$true}
        @{Suite='all';Selected='Core,Git,Vagrant';Dependencies='Core,Git,Vagrant';Images='Core,Git';Evidence=$true}
        @{Suite='Git';Selected='Git';Dependencies='Core,Git';Images='Core,Git';Evidence=$false}
        @{Suite='git';Selected='Git';Dependencies='Core,Git';Images='Core,Git';Evidence=$false}
        @{Suite='Vagrant';Selected='Vagrant';Dependencies='Core,Vagrant';Images='Core';Evidence=$false}
        @{Suite='Core';Selected='Core';Dependencies='Core';Images='Core';Evidence=$true}
    ) {
        $selection=Resolve-QuietCiCompanions $configuration -Suite $Suite -RuntimeIdentifier linux-x64 -RuntimeMajor 11
        ($selection.Selected -join ',')|Should -BeExactly $Selected
        ($selection.Dependencies -join ',')|Should -BeExactly $Dependencies
        ($selection.Images -join ',')|Should -BeExactly $Images
        $selection.HasCoreEvidence|Should -Be $Evidence
        $selection.Suite|Should -BeExactly $Suite
        $selection.ConfigurationSHA256|Should -BeExactly $configuration.SHA256
    }

    It 'enables declared mutation controls only for the selected suite, runtime identifier and major' -ForEach @(
        @{Suite='Git';Rid='win-x64';Major=11;Value='1'}
        @{Suite='All';Rid='win-x64';Major=11;Value='1'}
        @{Suite='Git';Rid='win-arm64';Major=11;Value='0'}
        @{Suite='Git';Rid='win-x64';Major=10;Value='0'}
        @{Suite='Core';Rid='win-x64';Major=11;Value='0'}
    ) {
        $selection=Resolve-QuietCiCompanions $configuration -Suite $Suite -RuntimeIdentifier $Rid -RuntimeMajor $Major
        @($selection.Environment.Keys)|Should -Be @('QUIETCLI_GIT_PUSH_MUTATION')
        $selection.Environment['QUIETCLI_GIT_PUSH_MUTATION']|Should -BeExactly $Value
    }

    It 'rejects an unknown suite' -ForEach @(@{Suite='Nope'},@{Suite=''},@{Suite='Gi'}) {
        {Resolve-QuietCiCompanions $configuration -Suite $Suite}|Should -Throw -ExpectedMessage ('CiCompanionSuiteUnknown: '+$Suite)
    }

    It 'selects every suite when no suite is given' {
        $selection=Resolve-QuietCiCompanions $configuration
        ($selection.Selected -join ',')|Should -BeExactly 'Core,Git,Vagrant'
        $selection.Suite|Should -BeExactly 'All'
    }

    It 'rejects a companion that no suite tests' {
        $extra=& $read ($valid.Replace("  Git:`n    requires: [Core]`n    image: overlay","  Git:`n    requires: [Core]`n    image: overlay`n  Extra:`n    requires: [Core]`n    image: none"))
        $message=try{$null=Resolve-QuietCiCompanions $extra -Suite Extra;'<no error>'}catch{$_.Exception.Message}
        $message|Should -BeExactly 'CiCompanionSuiteUnknown: Extra'
    }

    It 'selects the suites of a companion by their group, whatever their names' {
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','CiFixtures.psm1')) -Force -DisableNameChecking -ErrorAction Stop
        $renamed=0
        foreach($candidate in 1..40){
            $catalogue=(New-QuietCiCatalogue ([Random]::new($candidate))).Configuration
            foreach($name in $catalogue.Companions.Keys){
                $expected=@($catalogue.Suites.Keys|Where-Object {$catalogue.Suites[$_].Group -ceq $name})
                ((Resolve-QuietCiCompanions $catalogue -Suite $name).Selected -join ',')|Should -BeExactly ($expected -join ',') -Because "companion $name of seed $candidate"
                if($expected -cnotcontains $name){$renamed++}
            }
        }
        $renamed|Should -BeGreaterThan 0 -Because 'some suites are named apart from their companion'
    }

    It 'rejects a selection whose images do not start at the base' {
        $broken=& $read ($valid.Replace("  Git:`n    requires: [Core]`n    image: overlay","  Git:`n    requires: [Orphan, Core]`n    image: overlay`n  Orphan:`n    requires: []`n    image: overlay"))
        {Resolve-QuietCiCompanions $broken -Suite Git}|Should -Throw -ExpectedMessage 'CiCompanionOverlayBaseDependencyMissing'
    }

    It 'rejects a selection that does not reach the base' {
        $broken=& $read ($valid.Replace("  Git:`n    requires: [Core]`n    image: overlay","  Git:`n    requires: []`n    image: overlay"))
        {Resolve-QuietCiCompanions $broken -Suite Git}|Should -Throw -ExpectedMessage 'CiCompanionBaseDependencyMissing'
    }
}

Describe 'Get-QuietCiSuiteImagePlan' {
    BeforeAll {
        $repository=Read-QuietCiCompanions -WorkspaceRoot $workspace
        $planOf={param([string]$Suite,[string]$Rid)Get-QuietCiSuiteImagePlan -WorkspaceRoot $workspace -Selection (Resolve-QuietCiCompanions $repository -Suite $Suite -RuntimeIdentifier $Rid -RuntimeMajor 11) -RuntimeIdentifier $Rid}
        $rids=@('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')
        $plans=@{}
        foreach($rid in $rids){foreach($suite in @('Core','Git')){$plans["$suite|$rid"]=& $planOf $suite $rid}}
    }

    It 'composes the <Rid> base plan without building and deterministically' -ForEach @(
        @{Rid='linux-x64'};@{Rid='linux-arm64'};@{Rid='linux-musl-x64'};@{Rid='linux-musl-arm64'}
    ) {
        $core=$plans["Core|$Rid"]
        $core.Rid|Should -BeExactly $Rid
        $core.Fingerprint|Should -Match '\A[0-9a-f]{64}\z'
        $core.PSObject.Properties.Name|Should -Not -Contain 'ParentReference'
        (& $planOf Core $Rid|ConvertTo-Json -Depth 8)|Should -BeExactly ($core|ConvertTo-Json -Depth 8)
    }

    It 'stacks the <Rid> Git overlay on exactly the base plan of the same identifier' -ForEach @(
        @{Rid='linux-x64'};@{Rid='linux-arm64'};@{Rid='linux-musl-x64'};@{Rid='linux-musl-arm64'}
    ) {
        $core=$plans["Core|$Rid"];$git=$plans["Git|$Rid"]
        $git.Rid|Should -BeExactly $Rid
        ($git.Core|ConvertTo-Json -Depth 8)|Should -BeExactly ($core|ConvertTo-Json -Depth 8)
        $git.ParentReference|Should -Not -BeNullOrEmpty
        $git.Fingerprint|Should -Match '\A[0-9a-f]{64}\z'
        $git.Fingerprint|Should -Not -Be $core.Fingerprint
        $git.RegistryPath|Should -BeLike '*-git'
        $git.RegistryPath|Should -Not -Be $core.RegistryPath
    }

    It 'gives every layer and identifier its own registry identity' {
        @($plans.Values|ForEach-Object {$_.RegistryPath+'@'+$_.Fingerprint}|Sort-Object -Unique).Count|Should -Be $plans.Count
        @($plans.Values.RegistryPath|Sort-Object -Unique).Count|Should -Be $plans.Count
    }

    It 'shares the base fingerprint across architectures of one platform only' {
        $plans['Core|linux-x64'].Fingerprint|Should -BeExactly $plans['Core|linux-arm64'].Fingerprint
        $plans['Core|linux-musl-x64'].Fingerprint|Should -BeExactly $plans['Core|linux-musl-arm64'].Fingerprint
        $plans['Core|linux-x64'].Fingerprint|Should -Not -Be $plans['Core|linux-musl-x64'].Fingerprint
        $plans['Git|linux-x64'].Fingerprint|Should -Not -Be $plans['Git|linux-arm64'].Fingerprint -Because 'an overlay fingerprint covers its parent reference'
    }

    It 'plans a suite without an image as the bare base' {
        $vagrant=Resolve-QuietCiCompanions $repository -Suite Vagrant -RuntimeIdentifier linux-x64 -RuntimeMajor 11
        if(@($vagrant.Images).Count -ne 1){Set-ItResult -Skipped -Because 'Vagrant now ships an image';return}
        (Get-QuietCiSuiteImagePlan -WorkspaceRoot $workspace -Selection $vagrant -RuntimeIdentifier linux-x64|ConvertTo-Json -Depth 8)|Should -BeExactly ($plans['Core|linux-x64']|ConvertTo-Json -Depth 8)
    }
}

Describe 'Invoke-QuietCiSuiteImage guards' {
    It 'rejects <Name> before touching any image' -ForEach @(
        @{Name='registry resolution without the cache';Arguments=@{ResolveOnly=$true};Error='CiImageRegistryResolutionRequiresCache'}
        @{Name='a probe without the cache';Arguments=@{ProbeOnly=$true};Error='CiImageRegistryResolutionRequiresCache'}
        @{Name='a publishing probe';Arguments=@{ProbeOnly=$true;RegistryCache=$true;PublishCache=$true};Error='CiImageProbeCannotPublish'}
    ) {
        {Invoke-QuietCiSuiteImage -WorkspaceRoot $TestDrive -Selection $null -RuntimeIdentifier linux-x64 @Arguments -Confirm:$false}|Should -Throw -ExpectedMessage $Error
    }

    It 'does nothing under -WhatIf and clears the registry token afterwards' {
        $env:QUIETCLI_REGISTRY_TOKEN='secret'
        try{
            Invoke-QuietCiSuiteImage -WorkspaceRoot $TestDrive -Selection $null -RuntimeIdentifier linux-x64 -WhatIf|Should -BeNullOrEmpty
            $env:QUIETCLI_REGISTRY_TOKEN|Should -BeExactly 'secret' -Because '-WhatIf returns before taking the credential'
        }finally{$env:QUIETCLI_REGISTRY_TOKEN=$null}
    }
}

Describe 'Invoke-QuietCiSuiteImages' {
    BeforeAll {
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','CiFixtures.psm1')) -Force -DisableNameChecking -ErrorAction Stop
        $identityOf={param([string]$Chain,[string]$Rid)
            $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Chain))).ToLowerInvariant()
            'ghcr.io/fixture/'+$Chain.Replace('>','-').ToLowerInvariant()+'/'+$Rid+'@'+$fingerprint
        }
    }

    BeforeEach {
        $script:calls=[Collections.Generic.List[object]]::new()
        $script:hits=@{}
        Mock -ModuleName CiCompanions Get-QuietCiSuiteImagePlan {
            $chain=@($Selection.Images) -join '>'
            [pscustomobject]@{
                RegistryPath=('ghcr.io/fixture/'+$chain.Replace('>','-').ToLowerInvariant()+'/'+$RuntimeIdentifier)
                Fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($chain))).ToLowerInvariant()
            }
        }
        Mock -ModuleName CiCompanions Invoke-QuietCiSuiteImage {
            $chain=@($Selection.Images) -join '>'
            $script:calls.Add([pscustomobject]@{Chain=$chain;Confirmed=!($PesterBoundParameters.ContainsKey('Confirm') -and !$PesterBoundParameters['Confirm']);Rid=$RuntimeIdentifier;Runtime=$ContainerRuntime;RegistryCache=[bool]$RegistryCache;PublishCache=[bool]$PublishCache;ResolveOnly=[bool]$ResolveOnly;ProbeOnly=[bool]$ProbeOnly;PreparedLayers=$PreparedLayers})
            [pscustomobject]@{CacheHit=[bool]$script:hits[$chain]}
        }
    }

    It 'prepares each distinct chain once, shortest first, and aggregates independently of the suite order' {
        $null=Invoke-QuietProperty -Name 'suite-image-chains' -Seed $seed -Count 60 -Generator {param($random)
            $catalogue=New-QuietCiCatalogue $random
            $names=@($catalogue.Configuration.Suites.Keys)
            $picked=[object[]](Get-QuietRandomSubset $random $names 0.6)
            if(!$picked.Count){$picked=@(Get-QuietRandomItem $random $names)}
            $requested=[string[]](@($picked)+@(if($random.Next(0,2)){Get-QuietRandomItem $random $picked}))
            [pscustomobject]@{Configuration=$catalogue.Configuration;Suites=$requested;Shuffled=[string[]](Get-QuietShuffle $random $requested);HitSeed=$random.Next()}
        } -Property {param($case)
            $expected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($name in $case.Suites){[void]$expected.Add((@((Resolve-QuietCiCompanions $case.Configuration -Suite $name).Images) -join '>'))}
            $hitRandom=[Random]::new($case.HitSeed)
            $script:hits=@{};foreach($chain in $expected){$script:hits[$chain]=($hitRandom.Next(0,2) -eq 1)}
            $script:calls.Clear()
            $left=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $case.Configuration -Suite $case.Suites -RuntimeIdentifier linux-x64 -Confirm:$false
            $order=[string[]]@($script:calls|ForEach-Object Chain)
            if($order.Count -ne $expected.Count -or @($order|Sort-Object -Unique -CaseSensitive).Count -ne $order.Count){throw 'each distinct chain once'}
            foreach($chain in $order){
                if(!$expected.Contains($chain)){throw "unexpected chain $chain"}
                if($chain.Split('>')[0] -cne $case.Configuration.Base){throw "base first in $chain"}
            }
            for($index=1;$index -lt $order.Count;$index++){if($order[$index].Split('>').Count -lt $order[$index-1].Split('>').Count){throw 'shortest chain first'}}
            for($index=0;$index -lt $order.Count;$index++){for($later=$index+1;$later -lt $order.Count;$later++){
                if($order[$index].StartsWith($order[$later]+'>',[StringComparison]::Ordinal)){throw 'a parent chain runs after its extension'}
            }}
            $script:calls.Clear()
            $right=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $case.Configuration -Suite $case.Shuffled -RuntimeIdentifier linux-x64 -Confirm:$false
            if((@($script:calls|ForEach-Object Chain) -join '|') -cne ($order -join '|')){throw 'the chain order depends on the suite order'}
            if($left.Fingerprint -cne $right.Fingerprint -or $left.Fingerprint -cnotmatch '\A[0-9a-f]{64}\z'){throw 'fingerprint'}
            if((@($left.Chains|ForEach-Object Chain) -join '|') -cne ($order -join '|')){throw 'chains are reported in execution order'}
            $left.CacheHit -eq (@($order|Where-Object {!$script:hits[$_]}).Count -eq 0)
        }
    }

    It 'aggregates the sorted RegistryPath@Fingerprint identities of every chain' {
        $configuration=(New-QuietCiCatalogue ([Random]::new(3))).Configuration
        $result=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Suites.Keys) -RuntimeIdentifier linux-musl-x64 -Confirm:$false
        $identities=[string[]]@($script:calls|ForEach-Object {& $identityOf $_.Chain 'linux-musl-x64'}|Sort-Object -CaseSensitive)
        $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($identities -join "`n")))).ToLowerInvariant()
        $result.Fingerprint|Should -BeExactly $expected
        $result.RuntimeIdentifier|Should -BeExactly 'linux-musl-x64'
        ($result.Suites -join ',')|Should -BeExactly (@($configuration.Suites.Keys) -join ',')
        (@($result.Chains|ForEach-Object Identity)|Sort-Object -CaseSensitive) -join ','|Should -BeExactly ($identities -join ',')
        foreach($chain in $result.Chains){(@($chain.Images) -join '>')|Should -BeExactly $chain.Chain}
    }

    It 'forwards the identifier, runtime and cache switches to every chain' -ForEach @(
        @{Switches=@{RegistryCache=$true;PublishCache=$true;ResolveOnly=$true}}
        @{Switches=@{RegistryCache=$true;ProbeOnly=$true}}
        @{Switches=@{}}
    ) {
        $configuration=(New-QuietCiCatalogue ([Random]::new(4))).Configuration
        $null=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Suites.Keys) -RuntimeIdentifier linux-arm64 -ContainerRuntime docker @Switches -Confirm:$false
        $script:calls.Count|Should -BeGreaterThan 0
        foreach($call in $script:calls){
            $call.Rid|Should -BeExactly 'linux-arm64'
            $call.Runtime|Should -BeExactly 'docker'
            $call.Confirmed|Should -BeFalse -Because 'the aggregate already passed ShouldProcess'
            $call.PreparedLayers|Should -BeOfType ([hashtable])
            [object]::ReferenceEquals($call.PreparedLayers,$script:calls[0].PreparedLayers)|Should -BeTrue
            foreach($name in 'RegistryCache','PublishCache','ResolveOnly','ProbeOnly'){$call.$name|Should -Be ([bool]$Switches[$name]) -Because $name}
        }
    }

    It 'hands the registry credential to every chain and clears it afterwards, even on failure' -ForEach @(
        @{Failing=$false}
        @{Failing=$true}
    ) {
        $configuration=$null
        foreach($candidate in 10..80){
            $catalogue=(New-QuietCiCatalogue ([Random]::new($candidate))).Configuration
            $distinct=@($catalogue.Suites.Keys|ForEach-Object {@((Resolve-QuietCiCompanions $catalogue -Suite $_).Images) -join '>'}|Sort-Object -Unique -CaseSensitive)
            if($distinct.Count -ge 2){$configuration=$catalogue;break}
        }
        $configuration|Should -Not -BeNullOrEmpty -Because 'a catalogue with two distinct chains exists among the seeds'
        $script:tokens=[Collections.Generic.List[string]]::new()
        $script:failing=$Failing
        # The real chain clears the credential in its finally block; the double reproduces that.
        Mock -ModuleName CiCompanions Invoke-QuietCiSuiteImage {
            $script:tokens.Add([string]$env:QUIETCLI_REGISTRY_TOKEN)
            $env:QUIETCLI_REGISTRY_TOKEN=$null
            if($script:failing -and $script:tokens.Count -eq 2){throw 'chain failed'}
            [pscustomobject]@{CacheHit=$true}
        }
        $saved=$env:QUIETCLI_REGISTRY_TOKEN
        try{
            $env:QUIETCLI_REGISTRY_TOKEN='fixture-token'
            $run={$null=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Suites.Keys) -RuntimeIdentifier linux-x64 -Confirm:$false}
            if($Failing){$run|Should -Throw -ExpectedMessage 'chain failed'}else{& $run}
            $script:tokens.Count|Should -BeGreaterOrEqual 2
            foreach($token in $script:tokens){$token|Should -BeExactly 'fixture-token'}
            $env:QUIETCLI_REGISTRY_TOKEN|Should -BeNullOrEmpty
        }finally{$env:QUIETCLI_REGISTRY_TOKEN=$saved}
    }

    It 'clears the registry credential even when a chain leaves it set' {
        Mock -ModuleName CiCompanions Invoke-QuietCiSuiteImage {[pscustomobject]@{CacheHit=$true}}
        $configuration=(New-QuietCiCatalogue ([Random]::new(5))).Configuration
        $saved=$env:QUIETCLI_REGISTRY_TOKEN
        try{
            $env:QUIETCLI_REGISTRY_TOKEN='fixture-token'
            $null=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Base) -RuntimeIdentifier linux-x64 -Confirm:$false
            $env:QUIETCLI_REGISTRY_TOKEN|Should -BeNullOrEmpty
        }finally{$env:QUIETCLI_REGISTRY_TOKEN=$saved}
    }

    It 'reports a miss when a chain returns no receipt' {
        Mock -ModuleName CiCompanions Invoke-QuietCiSuiteImage {}
        $configuration=(New-QuietCiCatalogue ([Random]::new(5))).Configuration
        $result=Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Base) -RuntimeIdentifier linux-x64 -Confirm:$false
        $result.CacheHit|Should -BeFalse
        @($result.Chains).Count|Should -Be 1
        $result.Chains[0].CacheHit|Should -BeFalse
    }

    It 'reports a hit only when every chain hits' {
        $configuration=(New-QuietCiCatalogue ([Random]::new(6))).Configuration
        $script:hits=@{}
        foreach($name in $configuration.Suites.Keys){$script:hits[(@((Resolve-QuietCiCompanions $configuration -Suite $name).Images) -join '>')]=$true}
        (Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Suites.Keys) -RuntimeIdentifier linux-x64 -Confirm:$false).CacheHit|Should -BeTrue
    }

    It 'rejects an empty suite list' {
        $configuration=(New-QuietCiCatalogue ([Random]::new(7))).Configuration
        {Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @() -RuntimeIdentifier linux-x64 -Confirm:$false}|Should -Throw -ExpectedMessage 'CiSuiteImagesEmpty'
        $script:calls.Count|Should -Be 0
    }

    It 'resolves every suite before preparing any image' {
        $configuration=(New-QuietCiCatalogue ([Random]::new(8))).Configuration
        {Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Base,'Nope') -RuntimeIdentifier linux-x64 -Confirm:$false}|Should -Throw -ExpectedMessage 'CiCompanionSuiteUnknown: Nope'
        $script:calls.Count|Should -Be 0
    }

    It 'prepares nothing under -WhatIf' {
        $configuration=(New-QuietCiCatalogue ([Random]::new(9))).Configuration
        Invoke-QuietCiSuiteImages -WorkspaceRoot $TestDrive -Configuration $configuration -Suite @($configuration.Suites.Keys) -RuntimeIdentifier linux-x64 -WhatIf|Should -BeNullOrEmpty
        $script:calls.Count|Should -Be 0
        Should -Invoke -ModuleName CiCompanions Get-QuietCiSuiteImagePlan -Times 0 -Exactly
    }
}

Describe 'Assert-QuietCiCompanionImages' {
    BeforeAll {
        $product='src/Box/src/FrenchExDev2.QuietCli.Box.PoSh'
        $newCase={param([string]$Image,[bool]$WithContract,[string[]]$Files=@())
            $root=[IO.Path]::Combine($TestDrive,'ws-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root,$product))
            if($WithContract){$null=New-QuietTestFile ([IO.Path]::Combine($root,$product,'ci','Get-CiImageArguments.ps1')) "param()`n"}
            foreach($relative in $Files){$null=New-QuietTestFile ([IO.Path]::Combine($root,$relative)) "FROM scratch`n"}
            $companions=[ordered]@{
                Core=[pscustomobject]@{Name='Core';requires=@();Image='base'}
                Box=[pscustomobject]@{Name='Box';requires=@('Core');Image=$Image}
            }
            [pscustomobject]@{Root=$root;Configuration=[pscustomobject]@{Companions=$companions;Base='Core'}}
        }
    }

    It '<Image> with contract=<Contract> and <Label> gives <Expected>' -ForEach @(
        foreach($image in 'overlay','none'){foreach($contract in $true,$false){foreach($file in @(
            @{Label='no container file';Path=''}
            @{Label='a product Containerfile';Path='src/Box/src/FrenchExDev2.QuietCli.Box.PoSh/.github/containers/box.Containerfile'}
            @{Label='a product Dockerfile';Path='src/Box/src/FrenchExDev2.QuietCli.Box.PoSh/Dockerfile'}
            @{Label='a test fixture Dockerfile';Path='src/Box/test/FrenchExDev2.QuietCli.Box.Tests.PoSh/fixture/Dockerfile.box'}
        )){
            $productFile=$file.Path.StartsWith('src/Box/src/',[StringComparison]::Ordinal)
            $expected=if($image -ceq 'overlay' -and !$contract){'CiCompanionOverlayContractMissing: Box'}elseif($image -ceq 'none' -and ($contract -or $productFile)){'CiCompanionImageMustBeOverlay: Box'}else{'pass'}
            @{Image=$image;Contract=$contract;Label=$file.Label;FilePath=$file.Path;ProductFile=$productFile;Expected=$expected}
        }}}
    ) {
        $case=& $newCase $Image $Contract @(if($FilePath){$FilePath})
        if($Expected -cne 'pass'){
            {Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration}|Should -Throw -ExpectedMessage $Expected
            return
        }
        $rows=@(Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration)
        ($rows|ForEach-Object Companion) -join ','|Should -BeExactly 'Core,Box'
        $box=$rows[1]
        $box.Image|Should -BeExactly $Image
        $box.Contract|Should -Be $Contract
        ($box.ContainerFiles -join ',')|Should -BeExactly $(if($ProductFile){$FilePath}else{''}) -Because 'test fixtures are not CI images'
    }

    It 'recognizes <Name> as a container file: <Matched>' -ForEach @(
        @{Name='Dockerfile';Matched=$true};@{Name='Dockerfile.alpine';Matched=$true};@{Name='Containerfile';Matched=$true}
        @{Name='base.Dockerfile';Matched=$true};@{Name='box.containerfile';Matched=$true};@{Name='dockerfile';Matched=$true}
        @{Name='Dockerfiles';Matched=$false};@{Name='MyDockerfile';Matched=$false};@{Name='Dockerfile-old';Matched=$false};@{Name='Dockerfile_old';Matched=$false};@{Name='notes.md';Matched=$false}
    ) {
        $case=& $newCase none $false @("$product/assets/$Name")
        if($Matched){
            {Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration}|Should -Throw -ExpectedMessage 'CiCompanionImageMustBeOverlay: Box'
        }else{
            @(Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration)[1].ContainerFiles.Count|Should -Be 0
        }
    }

    It 'never rejects the base, whatever it ships' {
        $case=& $newCase none $false
        $null=New-QuietTestFile ([IO.Path]::Combine($case.Root,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1')) "param()`n"
        $null=New-QuietTestFile ([IO.Path]::Combine($case.Root,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/Dockerfile')) "FROM scratch`n"
        $core=@(Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration)[0]
        $core.Contract|Should -BeTrue
        ($core.ContainerFiles -join ',')|Should -BeExactly 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/Dockerfile'
    }

    It 'treats a companion without a product module as image-less' {
        $case=& $newCase none $false
        [IO.Directory]::Delete([IO.Path]::Combine($case.Root,$product))
        $box=@(Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration)[1]
        $box.Contract|Should -BeFalse
        $box.ContainerFiles.Count|Should -Be 0
        $case.Configuration.Companions['Box'].Image='overlay'
        {Assert-QuietCiCompanionImages -WorkspaceRoot $case.Root -Configuration $case.Configuration}|Should -Throw -ExpectedMessage 'CiCompanionOverlayContractMissing: Box'
    }

    It 'accepts the repository: every overlay ships its contract, every other companion ships no image' {
        $rows=@(Assert-QuietCiCompanionImages -WorkspaceRoot $workspace -Configuration (Read-QuietCiCompanions -WorkspaceRoot $workspace))
        $rows.Count|Should -BeGreaterThan 1
        foreach($row in $rows|Where-Object Image -CEQ 'overlay'){$row.Contract|Should -BeTrue -Because $row.Companion}
        foreach($row in $rows|Where-Object Image -CEQ 'none'){($row.Contract -or $row.ContainerFiles.Count)|Should -BeFalse -Because $row.Companion}
    }
}
