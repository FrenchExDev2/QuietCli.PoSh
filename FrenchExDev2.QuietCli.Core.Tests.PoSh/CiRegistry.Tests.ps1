function Test-QuietCiRegistryProtocol {
    <#
    .SYNOPSIS
    Exercises real HTTP request/response processing for image indexes without a network or registry.
    .PARAMETER WorkspaceRoot
    Checkout providing the registry reader.
    .PARAMETER RunDirectory
    Owned protocol evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
    if(!('QuietCiRegistryFixture.Handler' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
namespace QuietCiRegistryFixture {
    /// <summary>Returns owned HTTP fixtures without opening sockets or reading credentials.</summary>
    public sealed class Handler : HttpMessageHandler {
        public Dictionary<string, byte[]> Bodies = new Dictionary<string, byte[]>();
        public Dictionary<string, int> Status = new Dictionary<string, int>();
        public Dictionary<string, string> Digests = new Dictionary<string, string>();
        public List<string> Requests = new List<string>();
        /// <summary>Records a metadata request and applies the fixture's content-negotiation policy.</summary>
        /// <param name="request">HTTP metadata request produced by the real registry reader.</param>
        /// <param name="cancellation">Client cancellation token; fixture responses complete synchronously.</param>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation) {
            string path = request.RequestUri.AbsolutePath;
            Requests.Add(path);
            int status = Status.ContainsKey(path) ? Status[path] : Bodies.ContainsKey(path) ? 200 : 404;
            if (path.Contains("/manifests/") && !request.Headers.Accept.ToString().Contains("application/vnd.oci.image.index.v1+json")) status = 404;
            var response = new HttpResponseMessage((HttpStatusCode)status);
            response.Content = new ByteArrayContent(Bodies.ContainsKey(path) ? Bodies[path] : Encoding.UTF8.GetBytes("{}"));
            if (Digests.ContainsKey(path)) response.Headers.TryAddWithoutValidation("Docker-Content-Digest", Digests[path]);
            return Task.FromResult(response);
        }
    }
}
'@
    }
    $seed=20261113;$random=[Random]::new($seed)
    $indexTypes=@('application/vnd.oci.image.index.v1+json','application/vnd.docker.distribution.manifest.list.v2+json')
    $leafTypes=@('application/vnd.oci.image.manifest.v1+json','application/vnd.docker.distribution.manifest.v2+json')
    $plan=[pscustomobject]@{RegistryPath='fixture/toolchain';Fingerprint=('a'*64);Architecture='x64';Source='https://github.com/FrenchExDev2/QuietCli.PoSh'}
    $encode={param($value) [Text.Encoding]::UTF8.GetBytes(($value|ConvertTo-Json -Depth 20 -Compress))}
    $hash={param([byte[]]$bytes) 'sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()}
    $makeFixture={
        param($kind,$architecture)
        $handler=[QuietCiRegistryFixture.Handler]::new()
        $handler.Bodies['/token']=[Text.Encoding]::UTF8.GetBytes('{"token":"synthetic-registry-bearer"}')
        $configBytes=& $encode @{architecture=$architecture;os='linux';config=@{Labels=@{'org.frenchexdev.quietcli2.inputs'=$plan.Fingerprint;'org.opencontainers.image.source'=$plan.Source}}}
        $configDigest=& $hash $configBytes
        $leafType=$leafTypes[$random.Next(2)]
        $leafBytes=& $encode @{schemaVersion=2;mediaType=$leafType;config=@{digest=$configDigest;size=$configBytes.Length;mediaType='application/vnd.oci.image.config.v1+json'};layers=@()}
        $leafDigest=& $hash $leafBytes
        $handler.Bodies['/v2/fixture/toolchain/blobs/'+$configDigest]=$configBytes
        $handler.Bodies['/v2/fixture/toolchain/manifests/'+$leafDigest]=$leafBytes
        $rootBytes=if($kind -eq 'leaf'){$leafBytes}else{
            $descriptors=@(
                @{mediaType=$leafType;digest=$leafDigest;size=$leafBytes.Length;platform=@{os='linux';architecture=$architecture}},
                @{mediaType=$leafType;digest=('sha256:'+('b'*64));size=123;platform=@{os='unknown';architecture='unknown'};annotations=@{'vnd.docker.reference.type'='attestation-manifest'}},
                @{mediaType=$leafType;digest=('sha256:'+('c'*64));size=123;platform=@{os='windows';architecture=$architecture}}
            )|Sort-Object {$random.Next()}
            $indexType=if($kind -eq 'nested'){$indexTypes[0]}else{$kind}
            & $encode @{schemaVersion=2;mediaType=$indexType;manifests=@($descriptors)}
        }
        if($kind -eq 'nested'){
            $innerDigest=& $hash $rootBytes
            $handler.Bodies['/v2/fixture/toolchain/manifests/'+$innerDigest]=$rootBytes
            $rootBytes=& $encode @{schemaVersion=2;mediaType=$indexTypes[0];manifests=@(@{mediaType=$indexTypes[0];digest=$innerDigest;size=$rootBytes.Length;platform=@{os='linux';architecture=$architecture}})}
        }
        $rootDigest=& $hash $rootBytes
        $rootPath='/v2/fixture/toolchain/manifests/'+$plan.Fingerprint
        $handler.Bodies[$rootPath]=$rootBytes;$handler.Digests[$rootPath]=$rootDigest
        [pscustomobject]@{Handler=$handler;Client=[Net.Http.HttpClient]::new($handler);RootPath=$rootPath;RootDigest=$rootDigest;LeafDigest=$leafDigest;ConfigDigest=$configDigest}
    }
    $assertValid={
        param($resolver,$kind,$architecture,$include)
        $plan.Architecture=if($architecture -eq 'amd64'){'x64'}else{'arm64'}
        $fixture=& $makeFixture $kind $architecture
        try{
            $result=& $resolver -Plan $plan -Actor fixture -Token '' -IncludeConfiguration:$include -HttpClient $fixture.Client
            if($include){
                if($result.Digest -cne $fixture.RootDigest -or $result.Reference -cne ('ghcr.io/fixture/toolchain@'+$fixture.RootDigest) -or $result.Architecture -cne $architecture -or $result.Fingerprint -cne $plan.Fingerprint){throw 'RegistryResolvedIdentityChanged'}
                $expected=if($kind -eq 'leaf'){3}elseif($kind -eq 'nested'){5}else{4}
                if($fixture.Handler.Requests.Count -ne $expected){throw 'RegistryRequestedUnrelatedManifest'}
            }elseif($result -cne $fixture.RootDigest -or $fixture.Handler.Requests.Count -ne 2){throw 'RegistryIndexDigestUnavailable'}
        }finally{$fixture.Client.Dispose()}
    }
    $resolver=(Get-Command Get-QuietCiRegistryDigest).ScriptBlock
    $properties=0
    foreach($iteration in 1..8){foreach($kind in @('leaf','nested')+$indexTypes){foreach($arch in @('amd64','arm64')){foreach($include in @($false,$true)){
        & $assertValid $resolver $kind $arch $include;$properties++
    }}}}
    $assertRejected={
        param($damage)
        $plan.Architecture='x64';$fixture=& $makeFixture $indexTypes[0] 'amd64'
        try{
            switch($damage){
                'root bytes' {$fixture.Handler.Bodies[$fixture.RootPath]+=[byte]32}
                'config bytes' {$fixture.Handler.Bodies['/v2/fixture/toolchain/blobs/'+$fixture.ConfigDigest]+=[byte]32}
                'missing platform' {$plan.Architecture='arm64'}
                'missing child' {$fixture.Handler.Status['/v2/fixture/toolchain/manifests/'+$fixture.LeafDigest]=404}
                'missing config' {$fixture.Handler.Status['/v2/fixture/toolchain/blobs/'+$fixture.ConfigDigest]=404}
                'server error' {$fixture.Handler.Status[$fixture.RootPath]=500}
                'invalid digest' {$fixture.Handler.Digests[$fixture.RootPath]='sha256:invalid'}
                'malformed JSON' {$fixture.Handler.Bodies[$fixture.RootPath]=[Text.Encoding]::UTF8.GetBytes('{');$fixture.Handler.Digests[$fixture.RootPath]=& $hash $fixture.Handler.Bodies[$fixture.RootPath]}
                'ambiguous platform' {
                    $index=[Text.Encoding]::UTF8.GetString($fixture.Handler.Bodies[$fixture.RootPath])|ConvertFrom-Json -AsHashtable
                    $index.manifests+=@($index.manifests|Where-Object {$_.platform.os -eq 'linux'})
                    $fixture.Handler.Bodies[$fixture.RootPath]=& $encode $index;$fixture.Handler.Digests[$fixture.RootPath]=& $hash $fixture.Handler.Bodies[$fixture.RootPath]
                }
                {$_ -in @('schema version','descriptor digest','unsupported type','missing manifests')} {
                    $index=[Text.Encoding]::UTF8.GetString($fixture.Handler.Bodies[$fixture.RootPath])|ConvertFrom-Json -AsHashtable
                    switch($damage){
                        'schema version' {$index.schemaVersion=1}
                        'descriptor digest' {foreach($entry in $index.manifests){$entry.digest='sha256:invalid'}}
                        'unsupported type' {$index.mediaType='application/unknown'}
                        'missing manifests' {$index.manifests=@()}
                    }
                    $fixture.Handler.Bodies[$fixture.RootPath]=& $encode $index;$fixture.Handler.Digests[$fixture.RootPath]=& $hash $fixture.Handler.Bodies[$fixture.RootPath]
                }
            }
            $rejected=$false
            try{$null=& $resolver -Plan $plan -Actor fixture -Token '' -IncludeConfiguration -HttpClient $fixture.Client}catch{$rejected=$true}
            if(!$rejected){throw ('RegistryMalformedInputAccepted: '+$damage)}
        }finally{$fixture.Client.Dispose()}
    }
    $damages=@('root bytes','config bytes','missing platform','missing child','missing config','server error','invalid digest','malformed JSON','ambiguous platform','schema version','descriptor digest','unsupported type','missing manifests')
    foreach($damage in $damages){& $assertRejected $damage}
    foreach($status in @(401,403,404)){
        $fixture=& $makeFixture $indexTypes[0] 'amd64'
        try{
            $fixture.Handler.Status[$fixture.RootPath]=$status
            if($null -ne (& $resolver -Plan $plan -Actor fixture -Token '' -HttpClient $fixture.Client)){throw 'RegistryCacheMissChanged'}
        }finally{$fixture.Client.Dispose()}
    }
    $source=$resolver.ToString()
    $oldAccept="'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'"
    $mutations=@(
        @{From=$oldAccept;To="'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'";Arch='amd64'},
        @{From="`$arch=if(`$Plan.Architecture -eq 'x64'){'amd64'}else{'arm64'}";To="`$arch='amd64'";Arch='arm64'},
        @{From='Digest=$digest;Reference=';To='Digest=$selectedDigest;Reference=';Arch='amd64'}
    )
    $killed=0
    foreach($mutation in $mutations){
        if(!$source.Contains($mutation.From)){throw 'RegistryProtocolMutationAnchorMissing'}
        $mutant=[scriptblock]::Create($source.Replace($mutation.From,$mutation.To))
        $detected=$false
        try{& $assertValid $mutant $indexTypes[0] $mutation.Arch $true}catch{$detected=$true}
        if(!$detected){throw 'RegistryProtocolMutantSurvived'}
        $killed++
    }
    $reader=(Get-Command Read-QuietCiRegistryDocument).ScriptBlock
    $readerSource=$reader.ToString();$anchor='-cne $Digest'
    if(!$readerSource.Contains($anchor)){throw 'RegistryDigestMutationAnchorMissing'}
    try{
        # Mutate the reader in the resolver's owning module, not the calling test scope.
        & $reader.Module {param($body) Set-Item Function:script:Read-QuietCiRegistryDocument $body} ([scriptblock]::Create($readerSource.Replace($anchor,'-cne $Digest -and $false')))
        $detected=$false
        try{& $assertRejected 'config bytes'}catch{$detected=$_.Exception.Message -ceq 'RegistryMalformedInputAccepted: config bytes'}
        if(!$detected){throw 'RegistryDigestMutantSurvived'}
        $killed++
    }finally{& $reader.Module {param($body) Set-Item Function:script:Read-QuietCiRegistryDocument $body} $reader}
    Write-WorkspaceJson (Join-Path $RunDirectory 'ci-registry-protocol.json') @{Seed=$seed;ValidProperties=$properties;MalformedCases=$damages.Count;CacheMissStatuses=3;MutantsKilled=$killed;RealNetwork=$false;ImageLayersDownloaded=$false}
}
