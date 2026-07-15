#!/usr/bin/env bash
# Single source of truth for repository shell syntax checks.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts=(
    deploy.sh
    release.sh
    scripts/bench.sh
    scripts/check_shell.sh
    scripts/populate_clipboard.sh
    scripts/smoke.sh
    scripts/check_coverage.sh
    scripts/check_design_tokens.sh
    scripts/diagnostics.sh
    scripts/lib/command_log.sh
    scripts/next_version.sh
    .mise/tasks/release
    .mise/tasks/release-auto
    .mise/tasks/publish
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

echo "Shell syntax checks passed (${#scripts[@]} files)."
