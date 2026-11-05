# Integrated hosting and prerelease validation - 5 November 2026

Core and Git declare 0.2.0-preview. Both actual x64 host runs completed on a frozen source copy because a separate PTY task was editing the live checkout. This is local scenario evidence, not full remote release qualification. No public package was published.

- stable: PowerShell 7.6.7; .NET 10.0.13; target .NETCoreApp,Version=v10.0; 72 passed, 0 failed; mode InProcess.
  - 8 MiB fixture, InProcess: median 937.4 ms over 3 samples.
  - 8 MiB fixture, Process: median 1514.0 ms over 3 samples.
  - Frozen source SHA-256: 6DAF248333F10F6A7849025832BF5AFCC94A77C6646052488E90A52E83195A96.
- preview: PowerShell 7.7.0-preview.5; .NET 11.0.0-rc.1.26425.128; target .NETCoreApp,Version=v11.0; 72 passed, 0 failed; mode InProcess.
  - 8 MiB fixture, InProcess: median 747.2 ms over 3 samples.
  - 8 MiB fixture, Process: median 3358.3 ms over 3 samples.
  - Frozen source SHA-256: 6DAF248333F10F6A7849025832BF5AFCC94A77C6646052488E90A52E83195A96.

The hosting samples include producer startup, back-pressure, drainage, metadata and callback dispatch. They are not pure IPC latency measurements. The compiled framing samples and their exact counts are retained in each summary under Suites[].Performance. Direct read metadata and bytes use no JSON or pipe exchange; other control requests retain metadata JSON.

The reusable Windows CI matrix contains stable/.NET 10 and preview/.NET 11 integrated hosts on x64 and ARM64, plus both stable isolated-host architecture checks. All six entries contribute to the mandatory Windows qualification result. ARM64 and remote workflow execution were not performed in this local validation.

Gallery tests verify suffix preservation, rejection of stripped/wrong versions, both packaged imports outside sources, exact Git-to-Core NuGet dependency [0.2.0-preview], ValidateOnly and WhatIf. The PowerShell manifest dependency remains numeric 0.2.0. Prepared package hashes:
- FrenchExDev2.QuietCli.Core.PoSh.0.2.0-preview.nupkg: 51B038058ACA737A6BC084AFEBB08860A6127884582591DA64C9D8303BA4686B
- FrenchExDev2.QuietCli.Git.PoSh.0.2.0-preview.nupkg: FDD5C0C4A417CC9084AD9B10D86F9530D162B3232550F58AFF4A283AB804D807

Durable local artifacts: artifacts/tests/integrated-matrix-20261105 and artifacts/gallery-preview-20261105. Full frozen run trees and the read-only monitor scripts remain at C:\Users\serard\AppData\Local\Temp\quietcli-integrated-matrix-cb628f1f. The JSON summaries retain host versions, engine identities, test results and build/source fingerprints. The live PTY task was left running independently; its later source changes are outside this frozen evidence.
