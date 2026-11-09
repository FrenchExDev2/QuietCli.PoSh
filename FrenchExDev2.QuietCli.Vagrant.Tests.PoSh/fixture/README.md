# Vagrant fixture (CI and manual verification)

Shared, committed `Vagrantfile` + `Dockerfile.vagrant` used by both the `Vagrant` CI suite (deterministic
line-parsing/fuzz tests do not need it; the `-UI` manual verification step does) and by anyone verifying this
module by hand. It is not a disposable file recreated ad hoc -- edit it in place and keep it in sync with the
module's own tests and docs.

## Provider choice: Docker

The default provider is Vagrant's own built-in [`docker`
provider](https://developer.hashicorp.com/vagrant/docs/providers/docker/basics)
([configuration reference](https://developer.hashicorp.com/vagrant/docs/providers/docker/configuration)).
It needs no VirtualBox/libvirt and no nested virtualization -- the two things that block most hosted CI
runners -- because it never boots a host VM; it builds and runs an ordinary container image. This is why it
works directly on a Linux CI runner that already has Docker installed (for example GitHub Actions'
`ubuntu-latest`).

Two machines are defined, `web` and `db`, each built from the same minimal Alpine SSH image
(`Dockerfile.vagrant`). `has_ssh = true` is required: Vagrant's `shell` provisioner talks to the target over
SSH even under the `docker` provider (community-confirmed behavior, not just an incidental default) -- without
it the provisioner silently no-ops instead of failing loudly. The image's `authorized_keys` is fetched at
*build* time from HashiCorp's own canonical source
(`https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub`) rather than retyped by hand, so a
transcription mistake can never silently break SSH authentication.

## Isolated real-provider smoke

From the monorepo root:

```powershell
./FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/Invoke-ProviderSmoke.ps1
```

This explicit check requires existing Vagrant 2.4.9 and a working Docker-compatible client/engine.
It opens the shared visible monitor, copies this fixture into a private temporary directory, uses
an isolated Vagrant home and supplies a unique `QUIETCLI_VAGRANT_PREFIX`. Shared folders are disabled,
and `force_host_vm = false` prevents creating a Vagrant host VM. SSH boot waits are bounded to 60 seconds.
The image unlocks its test account while disabling password authentication and root login; the
well-known public test key remains the SSH authentication mechanism.

The smoke checks `up --no-provision`, explicit provisioning of both machines, ordered listener events,
shell output sentinels, generated/boundary/malformed fixture prefixes and an isolated prefix-guard mutant.
It destroys only its copied Vagrant environment and independently verifies container absence. Base-image
and build caches may remain. It never installs host tools, plugins or provider configuration.

## Podman: observed local compatibility, broader coverage partial

The repository treats Podman compatibility separately from Vagrant's documented Docker provider.
A Windows Docker client connected to the existing Podman 6.1.4 service passed the plugin-free smoke
with Vagrant 2.4.9. This is one observed combination, not general cross-provider qualification.
Two community options exist:

1. **Plugin-free**: point `DOCKER_HOST` at Podman's own Docker-compatible socket and let Vagrant's native
   `docker` provider talk to it unmodified (recent community write-up, not HashiCorp-confirmed:
   <https://oneuptime.com/blog/post/2026-03-18-use-podman-with-vagrant/view>). Also needs `podman-docker` on
   `PATH`, since Vagrant shells out to a `docker` binary by name.

   ```bash
   systemctl --user enable --now podman.socket
   export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"
   export VAGRANT_DEFAULT_PROVIDER=docker
   vagrant up --machine-readable
   ```

   When this is active, the Vagrant module's `-UI` header and `Get-QuietVagrantProviderLabel` both report
   `Mode: docker via podman`.

2. **Community `podman` gem** (<https://rubygems.org/gems/podman>, v1.0.3; source
   <https://github.com/reiserfs/vagrant-podman>) -- rewrites the `docker` provider to fix `network inspect`
   output differences between Docker and Podman. Low-traffic repository (0 stars/forks), no maintenance
   guarantee. `vagrant plugin install podman`. This path is **not** detected by
   `Get-QuietVagrantProviderLabel`, which still reports plain `docker` under this gem.

## `ProvisionerStarted` is an inference, not a guaranteed field

HashiCorp's own documented `--machine-readable` type list (`box-name`, `box-provider`, `cli-command`,
`error-exit`, `provider-name`, `ssh-config`, `state`, `state-human-long`, `state-human-short`) does not include
any dedicated "provisioner started" type -- the module's `ProvisionerStarted` detection is a regex match over
the generic `ui`/`info` channel, not a read of a structured, guaranteed field. That official list does not even
mention the `ui` type itself (which comes from a different source, a HashiCorp GitHub PR, not the reference
page), so the two sources are more likely both incomplete than contradictory -- which is exactly why nothing in
this module treats `ui`/its subtypes as a closed set (`ConvertFrom-QuietVagrantMachineReadableLine` never
throws on an unknown type). This fixture is precisely what lets that inference be checked against a real
transcript; running it is not by itself proof the inference is correct everywhere (`Qualification = 'Partial'`
stays set in both the module manifest and its handler registrations until this is checked more broadly).

## Observed and remaining provider scope

The [9 November execution audit](../../docs/audits/2026-11-09-provider-ui-qualification.md) records
successful SSH handshakes and shell provisioners for `web` and `db` through the local Windows/Podman
combination. Its real machine-readable `ui,info` messages include the display prefix:
`timestamp,web,ui,info,==> web: Running provisioner: shell...`. The module recognizes that prefix only
when it matches the event envelope's machine. Structured `action,provision,start/end` events are also
retained; they do not themselves identify the named provisioner.

Documentation alone cannot settle these -- they are tracked as open qualification gaps, not assumptions:

- Other Vagrant versions, real Docker daemons and additional providers beyond the recorded combination.
- That `vagrant up` on a GitHub Actions `ubuntu-latest` runner triggers no host VM at all (strongly implied by
  Vagrant's own docs, not verified here).
- The community Podman plugin and Linux-side socket/service setup above; neither was installed by this smoke.

## CI prerequisite

The automated `Vagrant` suite uses the shared .NET process fixture, so it needs neither Vagrant nor
a container engine. It never installs prerequisites. Real provider/UI verification is a separate manual
run requiring Vagrant and a usable Docker-compatible client, prepared explicitly through the
[module workstation selector](../../README-development-workstation.md#select-git-and-vagrant-independently).
