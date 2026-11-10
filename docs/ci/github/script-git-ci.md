# git-ci.yml

<!-- workflow-source-sha256: 076824DC219AB3EE845D574384AFBEDF7A116214AD25F0CFB4A85E5C42366F3C -->

## Purpose

Path-filtered Git consumer qualification through the shared CI implementation.

## Triggers

PRs and develop pushes matching Git/Git.Tests, this workflow, `Quietly.slnx`, `Directory.Build.props` or `Directory.Packages.props`. No direct manual trigger. The shared build compiles the solution once and prepares manifest-declared portable distributions without recompilation before targeted RID publications.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push"]
    job_git["git"]
    event --> job_git
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| git | reuses ./.github/workflows/ci.yml |  | default success condition |  |

<!-- workflow-generated:end -->

## Scripts and effects

The git job reuses ci.yml with suite=Git and packages:write. Consumer images are derived from verified Core images; the common CI owns build/test execution and publication restrictions.

## Validation and limits

This filter does not run on every Core-only change. Release publication requests All so the delivered source also validates consumers; a skipped development workflow is not release evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
