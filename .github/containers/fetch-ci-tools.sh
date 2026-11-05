#!/bin/sh
# Objectif : Télécharger les archives verrouillées et compiler uniquement les outils du banc CI.
# All URLs and digests are supplied by scripts/CiImages.ps1 from the reviewed lock.
set -eu
mkdir -p /opt/dotnet /opt/git /tmp/git-source
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --output /tmp/sdk.tar.gz "$SDK_URL"
printf '%s  /tmp/sdk.tar.gz\n' "$SDK_SHA512" | sha512sum -c -
tar -xzf /tmp/sdk.tar.gz -C /opt/dotnet
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --output /tmp/git.tar.gz "$GIT_URL"
printf '%s  /tmp/git.tar.gz\n' "$GIT_SHA256" | sha256sum -c -
tar -xzf /tmp/git.tar.gz --strip-components=1 -C /tmp/git-source
# This is the quick companion-suite baseline, not the exhaustive helper/Rust qualification image.
make -C /tmp/git-source -s --no-print-directory -j2 prefix=/opt/git NO_RUST=YesPlease NO_TCLTK=YesPlease NO_GETTEXT=YesPlease NO_INSTALL_HARDLINKS=YesPlease NO_REGEX=NeedsStartEnd 'CFLAGS=-std=gnu11 -O2' all install
mkdir -p /opt/git/share/licenses/git
cp /tmp/git-source/COPYING /opt/git/share/licenses/git/COPYING
printf '%s\n' "Source: $GIT_URL" "SHA256: $GIT_SHA256" > /opt/git/share/licenses/git/SOURCE.txt
if [ -n "${POWERSHELL_URL:-}" ]; then
    mkdir -p /opt/powershell
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --output /tmp/powershell.tar.gz "$POWERSHELL_URL"
    printf '%s  /tmp/powershell.tar.gz\n' "$POWERSHELL_SHA256" | sha256sum -c -
    tar -xzf /tmp/powershell.tar.gz -C /opt/powershell
    chmod 755 /opt/powershell/pwsh
fi
rm -rf /tmp/sdk.tar.gz /tmp/git.tar.gz /tmp/git-source /tmp/powershell.tar.gz
