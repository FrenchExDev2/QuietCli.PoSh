# .NET provisioning and SDK pins

The complete user guide is [README-dotnet-and-global-dot-json.md](../README-dotnet-and-global-dot-json.md).

```powershell
./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -WhatIf
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -Confirm
./scripts/Update-DotNetGlobalJson.ps1 -Version $setup.Version -DotNetPath $setup.DotNetPath -SdkDirectory $setup.SdkDirectory -Confirm
```

SDKs are installed portably under this checkout's .dotnet/version. The SDK already includes
applicable runtimes. SHA-512 is verified before extraction and successful inventories
are required before promotion. Image pulls, SDK pin updates and session activation are
explicit options. Runtime resolution reuses Common.ps1's invocation/dotenv/discovery policy.

Only exact selected global.json files are changed; the default is this checkout's root pin.
Unrelated JSON values and existing rollForward survive. Backups preserve original bytes;
replacement is atomic per file, not across a batch. Formatting/comments may be normalized.
A complete existing version is reused; an incomplete one is not implicitly repaired/deleted.

See [installer](scripts/Install-DotNet.md), [pin updater](scripts/Update-DotNetGlobalJson.md),
[provisioning library](scripts/lib/DotNetProvisioning.md) and [focused test runner](scripts/Invoke-DotNetTests.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
