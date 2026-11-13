# CiImages.ps1

## Purpose and functions

Function library for native image plans, recipe rendering, verified GHCR lookup and Docker/Podman preparation. Callers load Common first; this file uses its process, resource and JSON helpers rather than importing the product engine.

| Functions | Responsibility |
| --- | --- |
| `Get-QuietCiFingerprint`, `Get-QuietCiImagePlan` | Hash declared inputs/rendered recipes and select Core's pinned native image. |
| `Get-QuietModuleContainerfile`, `Get-QuietCiModuleImagePlan` | Render declared overlays and bind parent fingerprints/references. |
| `Get-QuietCiRegistryDigest`, `Read-QuietCiRegistryDocument` | Negotiate image/index formats, follow one matching Linux platform and verify bounded JSON digests and image identity. |
| `Get-QuietCiVerifiedImage`, `Get-QuietCiLocalImageArchitecture` | Inspect actual local identity and architecture. |
| `Get-QuietCiBuildCacheOptions`, `Get-QuietCiBuildCommand` | Plan Docker-only intermediate caches and exact build arguments. |
| `ConvertTo-QuietCiRegistryDiagnostic` | Redact credentials and bound retained diagnostics. |
| `Invoke-QuietCiImageBuild` | Pull verified cache hits, build misses, optionally publish trusted cache entries, save receipts. |

Use the guarded [base](New-CiImage.md), [overlay](New-CiModuleImage.md) or [suite](New-CiSuiteImage.md) entry points for normal operations.

## Cache and parent boundaries

RegistryCache checks the final image before unused parents are prepared. CacheOnly never builds on a missing digest; the caller decides whether to prepare parents. Suite ProbeOnly verifies registry metadata without a daemon/pull; ResolveOnly can return an immutable reference without downloading layers. Image execution resolves/pulls that identity separately.

Registry requests accept OCI image indexes and Docker manifest lists as well as their single-image formats. BuildKit can publish an index containing the image and a separate attestation even for one target platform. Digest-only lookup returns that root digest. `IncludeConfiguration` follows exactly one Linux descriptor matching the requested architecture, including bounded nested indexes, and returns the original immutable root reference after verifying the selected configuration's architecture, OS, source and fingerprint. Attestations and unrelated platforms are not followed. Missing or ambiguous platform matches, invalid schema/types, repeated digests, excess nesting, altered bytes and unavailable referenced documents fail explicitly. Only a 401/403/404 at the initial token/tag lookup is a cache miss.

`Read-QuietCiRegistryDocument` bounds each document to 1 MiB, checks SHA-256 against the received bytes and parses strict UTF-8 JSON. The optional caller-owned `HttpClient` on `Get-QuietCiRegistryDigest` permits offline transport tests; the default private client retains its deadline and is disposed by the reader. Tests negotiate the real request headers against synthetic HTTP responses, rather than replacing registry resolution with a preselected digest.

Docker uses the active-context builder/containerd image store, `--load`, optional local import and `mode=max` export. Cache keys bind final fingerprint and RID with an earlier-recipe fallback. Successful exports rotate the owned scope; workflow save occurs after image preparation and before tests. Podman does not use this Docker-specific BuildKit path.

An overlay's ParentReference is a local tag bound to platform, architecture and parent fingerprint. The renderer declares it as the default CORE_IMAGE before inherited FROM stages. The builder verifies and tags that same parent; no floating or unrelated fallback is accepted.

## Dependencies and side effects

Requires Common's engine-independent native/JSON helpers, .NET HTTP APIs, module-owned image contracts and the selected container application/daemon for preparation. Container resolution follows explicit selection, checkout `.env`, then Podman-first discovery. PlanOnly entry points remain offline.

Preparation can pull/build/tag/push images and create recipe/image/cache/login receipts. PublishCache requires upstream `FrenchExDev2/QuietCli.PoSh`, `refs/heads/develop`, and push/workflow_dispatch; PRs cannot publish. Registry configuration/digest checks precede reuse. Trusted cache publication rejects non-native architecture. Local nonpublication preparation can use a backend's emulation capability; that does not establish native CI qualification.

Credentials are removed from child environments, held only as needed in the owner, supplied through BOM-free UTF-8 stdin and private temporary Docker configuration/Podman authfiles, then cleaned up. Login diagnostics record exit/duration/encoding and bounded redacted records; tokens, Basic credentials and authfile contents are excluded. PSGallery credentials are unrelated.

The shared GitHub cache action exports its Docker setup socket with `set-host: true`. `DOCKER_HOST` preserves daemon selection across the temporary `DOCKER_CONFIG` used for registry credentials, so publication can find the image built with the original configuration. Offline publication regressions exercise all four Linux RIDs with and without BuildKit caching, requiring the same daemon, exact tag, private credential directory and restoration after publication. They do not execute Docker or contact GHCR.

## Critical review and verdict

`scripts/CiImages.ps1:214` owns registry identity checks, `:286`/`:314` the cache/build policy and `:333` effectful preparation. The function library intentionally requires Common to be loaded by its entry-point caller. Adapter/recipe properties and targeted mutations cover cache-only misses, verified final reuse, parent defaults/provenance, argument vectors and credential handoff. Hosted GHCR/BuildKit transfers and ARM execution need actual runner evidence; local tests do not establish speedup. See [Linux images](../ci/linux-images.md).



<!-- script-contract:begin -->
## Execution contract

Purpose: Hashes an image plan's own input files and its rendered Containerfile text into one deterministic identity, optionally folding in a parent's own fingerprint.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
