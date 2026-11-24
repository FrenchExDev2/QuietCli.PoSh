## Additional CI validation

Edit the description and use `[x]` for yes or `[ ]` for no. A dash means the effect has no option for that target.

<!-- quietcli-ci:begin -->

| Effect | Core | Git | Vagrant | Scripts |
| --- | --- | --- | --- | --- |
| [Mutation testing](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#companion-mutation) | `[ ]` <!-- ci:run-profile-mutation-core --> | `[ ]` <!-- ci:run-profile-mutation-git --> | `[ ]` <!-- ci:run-profile-mutation-vagrant --> | `[ ]` <!-- ci:script-mutation --> |
| [Performance](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#companion-performance) | `[ ]` <!-- ci:performance-core --> | `[ ]` <!-- ci:performance-git --> | `[ ]` <!-- ci:performance-vagrant --> | — |
| [Profiling](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#companion-profiling) | `[ ]` <!-- ci:profiling-core --> | `[ ]` <!-- ci:profiling-git --> | `[ ]` <!-- ci:profiling-vagrant --> | — |
| [Refresh mutation cache](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#refresh-the-script-mutation-cache) | — | — | — | `[ ]` <!-- ci:script-mutation-no-input-cache --> |
| [ReadyToRun comparison](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#readytorun-performance) | `[ ]` <!-- ci:readytorun --> | — | — | — |
| [PowerShell Preview](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#powershell-preview) | `[ ]` <!-- ci:preview --> | — | — | — |

- [ ] Run mutation workers sequentially for all targets [Details](https://github.com/FrenchExDev2/QuietCli.PoSh/blob/develop/docs/README-pull-request-ci.md#sequential-mutation-workers) <!-- ci:mutation-serial -->
<!-- quietcli-ci:end -->
