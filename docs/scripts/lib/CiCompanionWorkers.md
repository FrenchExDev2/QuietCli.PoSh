# CiCompanionWorkers.psm1

<!-- script-source:begin -->
Source file: [`lib/CiCompanionWorkers.psm1`](../../../scripts/lib/CiCompanionWorkers.psm1)
<!-- script-source:end -->

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

Each child is the only writer in its own directory. The parent never opens active
workers' mutable status.json files. It reads the independently published terminal
core-cases/<case>/case-result.json receipts once and caches their Passed/Failed states.
Isolated-case receipts are written after the case process exits. In-process Pester
cases publish their own receipts as each test finishes. When
the suite process exits, its final summary replaces its partial contribution to the
aggregate. Heartbeats continue between completions. A terminal worker failure publishes
the results observed so far before the supervisor reports the failure.

The supervisor reads terminal summary.json only after observing the worker exit.
Its existing exit-code/state/suite-count gates remain mandatory. Malformed, duplicate
or invalid case receipts remain explicit errors; completed-case progress is not a
qualification waiver. The parent writes only its own aggregate, never a child report.

CompanionReports.Tests.ps1 checks 32 Unicode receipts, repeated polls without recounting,
four malformed/duplicate cases and three targeted mutants. The real two-worker fixture
holds both mutable status files exclusively locked while publishing terminal case
receipts, then waits for the parent to observe both before publishing final summaries.
The old active-status reader fails this Windows reproducer; aggregation requires no
new report protocol or changes to the shared JSON writer and visible monitor.

The Core prerequisite is checked before creating child directories. Each actual child exit code and saved terminal summary must succeed. Reports are returned in declaration order. Real-process regressions require both sibling start markers, distinct PIDs, preserved RID/TTY arguments, rejection of failed/partial Core, failed child rejection and no-effect preview.

Parallelism is within one matrix target, not separate GitHub jobs or agents. This preserves one build and one image download per target. A shared runner remains unsuitable for controlled concurrent performance comparisons; Core's samples finish before companion fan-out.

## Verdict

Suitable for shared-image companion validation. Hosted Linux and ARM64 qualification remains the responsibility of the complete CI matrix.

<!-- script-contract:begin -->
## Execution contract

Purpose: Counts each published terminal case receipt once without opening mutable worker status files.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
