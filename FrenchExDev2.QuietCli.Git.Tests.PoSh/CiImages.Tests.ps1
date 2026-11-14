function Get-QuietGitCiImageCases {
    <#
    .SYNOPSIS
    Verifies the Git module's own CI image plan composes its own fingerprint with Core's already-verified
    fingerprint, and that Core never reads anything the module owns.
    .PARAMETER WorkspaceRoot
    QuietCli2 monorepo root.
    #>
    param([string]$WorkspaceRoot)
    $cases=[ordered]@{}
    $cases['Git module CI image plan derives from its own files and from Core, never the reverse']={
        & {
            param($root)
            Import-Module (Join-Path $root 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
            $contractPath='FrenchExDev2.QuietCli.Git.PoSh/ci/Get-CiImageArguments.ps1'
            $core=Get-QuietCiImagePlan $root linux-x64
            $moduleInputs=& (Join-Path $root $contractPath) -WorkspaceRoot $root -Platform $core.Platform
            if(!$moduleInputs.Arguments.GIT_URL.StartsWith('https://codeload.github.com/git/git/')){throw 'Git module build argument missing upstream source'}
            if($moduleInputs.InputPaths -contains 'build/ci-images.lock.json'){throw 'Git module inputs leaked a Core-owned path'}
            $moduleInputPaths=@($moduleInputs.InputPaths)+@($contractPath)
            $plan=Get-QuietCiModuleImagePlan $root linux-x64 Git $moduleInputs.Containerfile $moduleInputs.Arguments $moduleInputPaths
            if($plan.RegistryPath -cne 'frenchexdev2/quietcli2-ci-debian-x64-git'){throw 'Module registry path does not carry the module suffix'}
            if($plan.Fingerprint -cnotmatch '^[a-f0-9]{64}$'){throw 'Module cache identity missing'}
            if(!$plan.ContainerfileText.Contains('ARG CORE_IMAGE') -or !$plan.ContainerfileText.Contains('FROM ${CORE_IMAGE} AS tools')){throw 'Rendered Containerfile missing Core skeleton'}
            if($plan.ContainerfileText.Contains('FROM docker.io')){throw 'Module Containerfile must never name a floating base image directly'}

            $copy=Join-Path $root ('artifacts/git-ci-image-contract/'+[guid]::NewGuid().ToString('N'))
            $files=@('global.json','build/ci-images.lock.json','scripts/lib/CiImages.psm1','scripts/New-CiImage.ps1','FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1','FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/ci-image.lock.json','FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/UpstreamSources.json',$contractPath,'FrenchExDev2.QuietCli.Git.PoSh/.github/containers/fetch-git-tools.sh')
            $files+=@(Get-ChildItem (Join-Path $root '.github/containers') -File -Force|ForEach-Object {'.github/containers/'+$_.Name})
            # Preserve the imported library graph as well as the image entry point.
            $files+=@(Get-ChildItem ([IO.Path]::Combine($root,'scripts/lib')) -File -Filter *.psm1 | ForEach-Object {'scripts/lib/'+$_.Name})
            $files=@($files | Select-Object -Unique)
            foreach($file in $files){$destination=Join-Path $copy $file;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination));Copy-Item -LiteralPath (Join-Path $root $file) -Destination $destination}

            & {
                param($copy,$contractPath)
                Import-Module (Join-Path $copy 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
                $before=Get-QuietCiImagePlan $copy linux-x64
                $beforeModuleInputs=& (Join-Path $copy $contractPath) -WorkspaceRoot $copy -Platform $before.Platform
                $beforeModulePlan=Get-QuietCiModuleImagePlan $copy linux-x64 Git $beforeModuleInputs.Containerfile $beforeModuleInputs.Arguments (@($beforeModuleInputs.InputPaths)+@($contractPath))

                [IO.File]::AppendAllText((Join-Path $copy 'FrenchExDev2.QuietCli.Git.PoSh/.github/containers/fetch-git-tools.sh'),"`n# synthetic module recipe change`n",[Text.UTF8Encoding]::new($false))
                $afterModuleInputs=& (Join-Path $copy $contractPath) -WorkspaceRoot $copy -Platform $before.Platform
                $afterModulePlan=Get-QuietCiModuleImagePlan $copy linux-x64 Git $afterModuleInputs.Containerfile $afterModuleInputs.Arguments (@($afterModuleInputs.InputPaths)+@($contractPath))
                if($beforeModulePlan.Fingerprint -ceq $afterModulePlan.Fingerprint){throw 'Changed module recipe reused the old module cache'}
                $coreUnaffected=Get-QuietCiImagePlan $copy linux-x64
                if($before.Fingerprint -cne $coreUnaffected.Fingerprint){throw 'A module-owned file change leaked into the Core fingerprint'}

                $mutatedFragment=$afterModuleInputs.Containerfile.PSObject.Copy()
                $mutatedFragment.Stages=@($mutatedFragment.Stages|ForEach-Object {$_.PSObject.Copy()})
                $mutatedFragment.Stages[0].Packages=$mutatedFragment.Stages[0].Packages+' jq'
                $mutatedModulePlan=Get-QuietCiModuleImagePlan $copy linux-x64 Git $mutatedFragment $afterModuleInputs.Arguments (@($afterModuleInputs.InputPaths)+@($contractPath))
                if($afterModulePlan.Fingerprint -ceq $mutatedModulePlan.Fingerprint){throw 'A declared-fragment-only change (no file touched) reused the old module cache'}
                if(!$mutatedModulePlan.ContainerfileText.Contains(' jq')){throw 'Rendered Containerfile did not reflect the mutated fragment'}

                [IO.File]::AppendAllText((Join-Path $copy $contractPath),"`n# synthetic module contract script change`n",[Text.UTF8Encoding]::new($false))
                $contractChangedModuleInputs=& (Join-Path $copy $contractPath) -WorkspaceRoot $copy -Platform $before.Platform
                $contractChangedModulePlan=Get-QuietCiModuleImagePlan $copy linux-x64 Git $contractChangedModuleInputs.Containerfile $contractChangedModuleInputs.Arguments (@($contractChangedModuleInputs.InputPaths)+@($contractPath))
                if($afterModulePlan.Fingerprint -ceq $contractChangedModulePlan.Fingerprint){throw 'A change to the module contract script itself reused the old module cache'}

                [IO.File]::AppendAllText((Join-Path $copy '.github/containers/fetch-ci-tools.sh'),"`n# synthetic core recipe change`n",[Text.UTF8Encoding]::new($false))
                $coreAfter=Get-QuietCiImagePlan $copy linux-x64
                $moduleInputsAfterCoreChange=& (Join-Path $copy $contractPath) -WorkspaceRoot $copy -Platform $coreAfter.Platform
                $modulePlanAfterCoreChange=Get-QuietCiModuleImagePlan $copy linux-x64 Git $moduleInputsAfterCoreChange.Containerfile $moduleInputsAfterCoreChange.Arguments (@($moduleInputsAfterCoreChange.InputPaths)+@($contractPath))
                if($afterModulePlan.Fingerprint -ceq $modulePlanAfterCoreChange.Fingerprint){throw 'Module cache ignored a Core fingerprint change'}
            } $copy $contractPath
        } $WorkspaceRoot
    }
    $cases
}
