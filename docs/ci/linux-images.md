# Images Linux de la CI

Aucune machine ARM locale n’est nécessaire. GitHub exécute x64 sur `ubuntu-latest` et ARM64 sur `ubuntu-24.04-arm`. Chaque runner construit et exécute ses conteneurs de même architecture, sans QEMU. Les deux recettes multiétapes sont `.github/containers/Dockerfile.ci.debian` et `Dockerfile.ci.alpine`.

## Premier run et cache GHCR

1. `New-CiImage.ps1` calcule une empreinte SHA-256 des recettes, de leur script commun, des scripts d’image, de `global.json` et des verrouillages SDK/Git.
2. Il cherche cette empreinte dans `ghcr.io/frenchexdev2/quietcli2-ci-{debian|alpine}-{x64|arm64}`.
3. Si elle existe et est accessible, il résout le tag vers un digest, télécharge ce digest puis vérifie architecture, origine et empreinte déclarées dans les labels.
4. Sinon, il construit nativement une nouvelle image. Sur un push ou déclenchement manuel du dépôt d’origine sur `main`, il la publie dans GHCR avec le tag de l’empreinte. Un changement d’entrée donne un nouveau tag ; les anciennes images ne sont ni écrasées intentionnellement ni supprimées automatiquement.
5. Les suites sont exécutées dans un conteneur privé sans réseau, par ID d’image local vérifié. Les rapports conservent l’ID réel, le digest du registre et l’identité hôte/invité/moteur.

Un changement uniquement dans un handler ne reconstruit pas l’image. Une pull request réutilise un cache accessible ou construit localement ; elle ne publie pas dans le cache de confiance de `main`. Les erreurs réseau/serveur du registre restent des erreurs, sans répétition automatique. Un cache absent ou inaccessible peut être construit à nouveau.

## Outils et étapes

L’étape `tools` télécharge le SDK .NET exact et vérifie son SHA-512. Elle compile Git 2.56.0 depuis l’archive SHA-256 verrouillée. Les compilateurs et sources Git ne passent pas dans l’étape finale. Le SDK reste dans l’image finale car les suites vérifient les outils et assemblages de tests.

Debian utilise les archives officielles PowerShell 7.6.7 x64/ARM64, vérifiées en SHA-256. Alpine utilise son paquet signé `powershell=7.6.9-r0`, disponible pour x86_64 et aarch64, avec sa dépendance .NET 10. Le SDK/runtime .NET 11 épinglé est ajouté à côté pour le moteur séparé. Une recette ne remplace jamais silencieusement PowerShell ARM64 par un exécutable x64.

Les bases Debian/Alpine sont verrouillées par digest d’index multiarchitecture dans les recettes et `build/ci-images.lock.json`. Les dépendances apt/apk transitives sont résolues depuis leurs dépôts signés pendant une construction : l’ensemble n’est pas présenté comme une reconstruction bit à bit reproductible. Une version de paquet retirée fait échouer le build et nécessite une mise à jour examinée du verrouillage.

Ce banc rapide utilise Git sans Rust et sans interface Tcl/Tk. Il ne remplace pas la qualification exhaustive des helpers, variantes et versions Git ; l’ancien `Containerfile.debian` reste dédié à cette préparation distincte.

## Autorisations et confidentialité

Le job d’images utilise uniquement son `GITHUB_TOKEN` éphémère, avec `contents: read` et `packages: write`. Il est absent des runs de pull requests. Les jobs Linux de tests possèdent seulement `packages: read` et attendent les jobs d’images sur `main`. Une concurrence par RID évite deux publications simultanées depuis les workflows Core et Git. Le login Podman reçoit le jeton par stdin dans un fichier d’authentification privé temporaire supprimé en sortie. Aucun jeton n’entre dans les arguments de build, le contexte Docker, les couches ou les rapports. La clé PSGallery est indépendante.

GHCR crée initialement les packages privés et les relie au dépôt via le jeton du workflow et le label OCI `org.opencontainers.image.source`. Les jobs du dépôt peuvent réutiliser ce cache. Pour autoriser les pulls anonymes, passer ces quatre packages en visibilité publique dans les paramètres GitHub Packages. Une PR de fork qui ne peut pas lire un cache privé construit son image ; elle reste testable sans accès en écriture au registre.

Les reçus se trouvent dans `artifacts/ci-images/*/image.json`. Les anciennes variables `QUIETCLI_*_IMAGE` ne sont plus requises. La publication PSGallery reste manuelle et attend la réussite des six jobs Windows/Linux ; publier une image de banc ne publie aucun module.

Références : [runners ARM64 GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [authentification et visibilité GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [paquet Alpine ARM64](https://pkgs.alpinelinux.org/package/v3.24/community/aarch64/powershell).

## Native PTY compiler

The final Debian image includes gcc and libc6-dev; the final Alpine image includes gcc and musl-dev. The pty-mutation matrix compiles and runs its baseline and all 23 targeted mutants inside these same native x64/ARM64 images without guest network access. Invoke-ContainerCi.ps1 -Suite Mutation retains reports and rejects a mismatched runtime identifier. Dockerfile changes alter the content fingerprint, so old images without the compiler are not accepted as the new image plan.

Native qualification also requires all 35 baseline assertions (including process properties) and 20,000 coverage-guided decoder executions under ASan/UBSan. CI images contain GCC, G++, Clang and compiler-rt (Debian: libclang-rt-dev; Alpine: compiler-rt). The ordinary CI process runner has no product-engine dependency. A successful native matrix is required before the .NET matrix starts and before any Gallery publication can be authorized.

Native mutation containers have a 1 GiB cgroup memory limit. On musl the fuzzer requires that external limit before disabling its defective internal RSS-monitor thread; ASan, UBSan and LeakSanitizer remain enabled. The delivery guard requires at least 20,000 executed fuzz inputs, all process properties and all 23 targeted mutants. Runtime-leak reproducers are retained for the separate future libFuzzer patch.
