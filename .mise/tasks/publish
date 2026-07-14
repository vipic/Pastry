#!/usr/bin/env bash
set -euo pipefail

VERSION=""
if [[ "$#" -gt 0 && "$1" != --* ]]; then
    VERSION="$1"
    shift
else
    echo "Publishing the next version calculated from Conventional Commits"
    exec ./release.sh --auto-version --publish "$@"
fi

echo "Publishing version: $VERSION"
exec ./release.sh "$VERSION" --publish "$@"
