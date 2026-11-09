#!/bin/sh
# Objectif : Télécharger (avec cache Podman) les archives verrouillées du banc CI, sans compilation.
# All URLs and digests are supplied by scripts/CiImages.ps1 from the reviewed lock.
set -eu
# Retries absorb a transient CDN edge failure (e.g. GitHub releases returning 503); the SHA check right
# after each download still rejects anything a retry brought back corrupted or substituted.
fetch='curl --fail --silent --show-error --location --proto =https --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 3'
cache_dir=/var/cache/ci-tools
mkdir -p /opt/dotnet "$cache_dir"

# Fetches $2 into $3, trusting a cache entry keyed by the URL's basename (distinct per architecture
# for SDK_URL/POWERSHELL_URL) only when its digest ($4, checked with the $1 sha256sum/sha512sum tool)
# still matches the locked value; otherwise downloads fresh and repopulates the cache. The cache lives
# in a Podman build-cache mount: it speeds up a repeated local build but is never committed to an
# image layer and is never trusted without this check.
fetch_cached() {
    algo=$1; url=$2; dest=$3; digest=$4
    cached="$cache_dir/$(basename "$url")"
    if [ -f "$cached" ] && printf '%s  %s\n' "$digest" "$cached" | "${algo}sum" -c - >/dev/null 2>&1; then
        echo "cache hit: $(basename "$url")" >&2
        cp "$cached" "$dest"
    else
        echo "cache miss: $(basename "$url") -- downloading $url" >&2
        $fetch --output "$dest" "$url"
        printf '%s  %s\n' "$digest" "$dest" | "${algo}sum" -c -
        cp "$dest" "$cached"
    fi
}

fetch_cached sha512 "$SDK_URL" /tmp/sdk.tar.gz "$SDK_SHA512"
tar -xzf /tmp/sdk.tar.gz -C /opt/dotnet
if [ -n "${POWERSHELL_URL:-}" ]; then
    mkdir -p /opt/powershell
    fetch_cached sha256 "$POWERSHELL_URL" /tmp/powershell.tar.gz "$POWERSHELL_SHA256"
    tar -xzf /tmp/powershell.tar.gz -C /opt/powershell
    chmod 755 /opt/powershell/pwsh
fi
rm -rf /tmp/sdk.tar.gz /tmp/powershell.tar.gz
