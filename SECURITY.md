# Security Policy

Thank you for helping keep **FrenchExDev2.QuietCli.PoSh** (QuietCli v2) and its provider modules secure. This document explains which versions are supported, how to report a vulnerability privately, and what you can expect from us.

## Supported Versions

QuietCli v2 is under active development. Security fixes are applied to the latest released version only.

| Version                         | Supported          |
| ------------------------------- | ------------------ |
| 2.x (latest release)            | :white_check_mark: |
| 2.x (older pre-releases)        | :x:                |
| 1.x (FrenchExDev.QuietCli.PoSh) | :x:                |

If you are running an older version, please upgrade before reporting an issue, as it may already be fixed.

## Scope

This policy covers:

- The core `FrenchExDev2.QuietCli.PoSh` PowerShell module.
- Official provider modules of the QuietCli ecosystem (for example `QuietCli.Git.PoSh`) maintained in this repository.
- Native components (C# and C) shipped with these modules.
- The PowerShell installer that downloads and installs QuietCli modules.

Examples of issues we are particularly interested in:

- **Command / argument injection**: untrusted input reaching a wrapped binary, `Invoke-Expression`, or a shell in an unintended way.
- **Output handling flaws**: bounded output (`-AsJson`, `-AsYaml`, `-AsObject`) leaking data it should have filtered, or parsing that can be abused (e.g. deserialization issues).
- **Secret exposure**: tokens, passwords, environment variables or credentials printed, logged, cached or returned in bounded output.
- **Installer and supply-chain issues**: downloading modules over insecure channels, missing integrity / signature checks, path hijacking, or installing modules that were not requested.
- **Privilege or path issues**: unsafe temporary files, DLL / binary search-order hijacking, writing outside expected directories.
- **Memory-safety bugs** in native (C) components.

Out of scope:

- Vulnerabilities in third-party binaries wrapped by QuietCli (e.g. `git`, `podman`, `dotnet`). Please report those to their upstream projects.
- Vulnerabilities in third-party dependencies, unless QuietCli uses them in a way that makes them exploitable.
- Issues that require an attacker to already have administrator rights or full control of the user's session or PowerShell profile.
- Denial of service caused by intentionally huge inputs on a local machine, without a broader security impact.
- Missing best-practice hardening without a demonstrable exploit.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, report them privately through **GitHub Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Fill in the advisory form.

Please include as much of the following as possible:

- The affected module(s) and version(s) (`Get-Module FrenchExDev2.QuietCli.PoSh -ListAvailable`).
- Your environment: OS, PowerShell version (`$PSVersionTable`), and .NET version if relevant.
- The type of issue (e.g. command injection, secret leak, installer integrity).
- Step-by-step instructions to reproduce the issue.
- A proof of concept or exploit code, if available.
- The impact you believe the issue has and how an attacker could use it.
- Any suggested fix or mitigation.

Reports in English or French are welcome.

## What to Expect

| Step                                   | Target time                     |
| -------------------------------------- | ------------------------------- |
| Acknowledgement of your report         | within 3 business days          |
| Initial assessment and severity rating | within 10 business days         |
| Status updates                         | at least every 14 days          |
| Fix for critical / high severity       | as soon as possible, aim 30 days |
| Fix for medium / low severity          | next planned release            |

We assess severity using [CVSS v3.1](https://www.first.org/cvss/calculator/3.1). If we decide the report is not a vulnerability, or is out of scope, we will explain why.

## Disclosure Policy

We follow **coordinated disclosure**:

1. We confirm the issue and determine the affected versions.
2. We prepare a fix and, where possible, share it with you for verification.
3. We release the fixed version and publish a **GitHub Security Advisory**, requesting a **CVE** when appropriate.
4. The advisory credits you, unless you prefer to remain anonymous.

We ask that you give us **90 days** from your initial report before any public disclosure, or until a fix is released, whichever comes first. If the issue is being actively exploited, we may shorten this timeline and will coordinate with you.

## Safe Harbor

We consider security research carried out in good faith and in line with this policy to be authorized. We will not pursue legal action against researchers who:

- Make a good-faith effort to avoid privacy violations, data destruction, and service disruption.
- Only test against their own installations and data.
- Do not exploit the issue beyond what is necessary to demonstrate it.
- Report the issue privately and give us reasonable time to fix it before disclosure.

## Security Best Practices for Users

- Install QuietCli and its providers only from official sources, and install only the provider modules you need.
- Keep QuietCli, PowerShell, and the wrapped binaries up to date.
- Prefer running with `pwsh -NoProfile` and importing modules explicitly in automated or AI-driven contexts.
- Never pass secrets as plain command-line arguments; use environment variables or a secret store, and review bounded output before sharing it.
- Review scripts generated by AI tools before running them, especially when they wrap binaries with user-supplied arguments.
- Use a restrictive PowerShell execution policy (e.g. `RemoteSigned` or `AllSigned`) where possible.

## Security Tooling

This project aims to use automated tooling such as Dependabot, CodeQL / code scanning, PSScriptAnalyzer, and secret scanning to catch issues early. Findings from these tools are triaged like any other report.

## Acknowledgements

We are grateful to everyone who responsibly discloses vulnerabilities. Researchers who report valid issues will be credited in the corresponding Security Advisory and release notes, if they wish.
