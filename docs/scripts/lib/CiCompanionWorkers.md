# CiCompanionWorkers.psm1

`WorkerBudget` is the shared budget for concurrent suite workers. The caller still limits simultaneous suites with MaxConcurrency. Internal slots are the integer quotient of the budget by the admitted suite-slot count, with a minimum of one; no extra slot is invented. For All with a budget of four and two suites, Git and Vagrant each receive two, then apply their own case policy/cap. Omitting WorkerBudget preserves one internal slot per admitted suite. Budgets one/two therefore keep inner concurrency at one. Core qualification still precedes all companion admissions, and individual case children remain single-slot. The owned optimization regression verifies both legacy one-slot isolation and the four-slot/two-suite distribution.

## Purpose

Runs selected companion test suites concurrently only after a successful complete Core result. Git and Vagrant use separate PowerShell processes inside the same already prepared runner or Linux container, sharing its immutable toolchain image and compiled checkout.

## Usage

`Invoke-TestWorker.ps1 -Suite All` invokes `Invoke-QuietCiCompanionWorkers` after accepting Core's integration evidence. At most two companions execute simultaneously, bounded further by `MaxConcurrency`. Each child receives its share of the explicit WorkerBudget (one internal slot by default) and its own report directory, measurement database and test configuration. Single-suite runs retain their existing execution path.

## Dependencies

`scripts/Ci.Process.ps1` owns asynchronous native startup. The exact current `PSHOME` executable and its normal profile are retained. The default child entry point is `Invoke-TestWorker.ps1`; `WorkerPath` allows explicit owned process fixtures in the test companion.

## Side effects

Creates `companions/<Suite>` reports and starts owned processes with inherited output streams. It never rebuilds, downloads an image, redirects business output, publishes or installs anything. `-WhatIf` returns before directories or processes. Failures and per-process deadlines terminate remaining owned child trees; no child failure qualifies the parent.

## Findings

The Core prerequisite is checked before creating child directories. Each actual child exit code and saved terminal summary must succeed. Reports are returned in declaration order. Real-process regressions require both sibling start markers, distinct PIDs, preserved RID/TTY arguments, rejection of failed/partial Core, failed child rejection and no-effect preview.

Parallelism is within one matrix target, not separate GitHub jobs or agents. This preserves one build and one image download per target. A shared runner remains unsuitable for controlled concurrent performance comparisons; Core's samples finish before companion fan-out.

## Verdict

Suitable for shared-image companion validation. Hosted Linux and ARM64 qualification remains the responsibility of the complete CI matrix.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs companion suites in bounded isolated processes after the caller has accepted Core.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
