#!/bin/sh
# Objectif : Telecharger (avec cache Podman) le code source Git verrouille et le compiler dans /opt/git.
# URL and digest are supplied by FrenchExDev2.QuietCli.Git.PoSh/ci/Get-CiImageArguments.ps1 from the reviewed lock.
set -eu
# Retries absorb a transient CDN edge failure (e.g. GitHub releases returning 503); the SHA check right
# after the download still rejects anything a retry brought back corrupted or substituted.
fetch='curl --fail --silent --show-error --location --proto =https --tlsv1.2 --retry 5 --retry-all-errors --retry-delay 3'
cache_dir=/var/cache/ci-tools
mkdir -p /opt/git /tmp/git-source "$cache_dir"

# Fetches $2 into $3, trusting a cache entry keyed by the URL's basename only when its digest ($4,
# checked with the $1 sha256sum tool) still matches the locked value; otherwise downloads fresh and
# repopulates the cache. The cache lives in a Podman build-cache mount: it speeds up a repeated local
# build but is never committed to an image layer and is never trusted without this check.
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

fetch_cached sha256 "$GIT_URL" /tmp/git.tar.gz "$GIT_SHA256"
tar -xzf /tmp/git.tar.gz --strip-components=1 -C /tmp/git-source
# This is the quick companion-suite baseline, not the exhaustive helper/Rust qualification image.
make -C /tmp/git-source -s --no-print-directory -j2 prefix=/opt/git NO_RUST=YesPlease NO_TCLTK=YesPlease NO_GETTEXT=YesPlease NO_INSTALL_HARDLINKS=YesPlease NO_REGEX=NeedsStartEnd 'CFLAGS=-std=gnu11 -O2' all install
mkdir -p /opt/git/share/licenses/git
cp /tmp/git-source/COPYING /opt/git/share/licenses/git/COPYING
printf '%s\n' "Source: $GIT_URL" "SHA256: $GIT_SHA256" > /opt/git/share/licenses/git/SOURCE.txt
rm -rf /tmp/git.tar.gz /tmp/git-source
