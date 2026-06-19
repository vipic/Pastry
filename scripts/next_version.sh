#!/bin/bash
# Calculate the next SemVer version from Conventional Commit messages.
set -e
set -o pipefail

LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION="${LATEST_TAG#v}"

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Unsupported latest tag version: $LATEST_TAG" >&2
    exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

if git rev-parse "$LATEST_TAG" >/dev/null 2>&1; then
    RANGE="${LATEST_TAG}..HEAD"
else
    RANGE="HEAD"
fi

COMMITS=$(git log "$RANGE" --pretty=format:%B --no-merges 2>/dev/null || true)

if [[ -z "$(printf "%s" "$COMMITS" | tr -d '[:space:]')" ]]; then
    echo "$CURRENT_VERSION"
    exit 0
fi

BUMP="none"

if printf "%s\n" "$COMMITS" | grep -Eq '(^[a-zA-Z]+(\([^)]+\))?!:|^BREAKING CHANGE:|^BREAKING-CHANGE:)'; then
    BUMP="major"
elif printf "%s\n" "$COMMITS" | grep -Eq '^feat(\([^)]+\))?:'; then
    BUMP="minor"
elif printf "%s\n" "$COMMITS" | grep -Eq '^(fix|perf)(\([^)]+\))?:'; then
    BUMP="patch"
else
    BUMP="${VERSION_BUMP_FALLBACK:-patch}"
fi

case "$BUMP" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    none)
        ;;
    *)
        echo "Unsupported bump type: $BUMP" >&2
        exit 1
        ;;
esac

echo "$MAJOR.$MINOR.$PATCH"
