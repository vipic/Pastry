#!/bin/bash
# Shared local command/stage logging for Pastry developer workflows.
# Logs stay under .local/logs/ and are never uploaded automatically.

COMMAND_LOG_INITIALIZED=false
COMMAND_LOG_FINISHED=false
COMMAND_LOG_CURRENT_STAGE=""
COMMAND_LOG_CURRENT_STAGE_STARTED_MS=0
COMMAND_LOG_STARTED_MS=0
COMMAND_LOG_SUMMARY_FILE=""

command_log_now_ms() {
    if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
    else
        # 最小 macOS 环境缺少高精度解释器时仍可记录到秒，不阻断构建/发布。
        echo $(( $(date '+%s') * 1000 ))
    fi
}

command_log_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

command_log_quote_command() {
    local quoted=""
    local arg
    for arg in "$@"; do
        printf -v arg '%q' "$arg"
        quoted="${quoted}${quoted:+ }${arg}"
    done
    printf '%s' "$quoted"
}

command_log_value() {
    local value="$1"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//\"/\'}"
    printf '"%s"' "$value"
}

command_log_write() {
    local level="$1"
    local event="$2"
    shift 2
    $COMMAND_LOG_INITIALIZED || return 0
    printf '%s level=%s workflow=%s run_id=%s event=%s %s\n' \
        "$(command_log_timestamp)" "$level" "$COMMAND_LOG_WORKFLOW" \
        "$COMMAND_LOG_RUN_ID" "$event" "$*" >> "$COMMAND_LOG_FILE"
}

command_log_init() {
    local workflow="$1"
    local version="${2:-unknown}"
    local project_dir="${PROJECT_DIR:-$(pwd)}"
    local root="${COMMAND_LOG_ROOT:-$project_dir/.local/logs}"
    local workflow_dir="$root/$workflow"
    local timestamp
    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

    mkdir -p "$workflow_dir"
    COMMAND_LOG_WORKFLOW="$workflow"
    COMMAND_LOG_RUN_ID="${timestamp}-$$"
    COMMAND_LOG_FILE="$workflow_dir/${COMMAND_LOG_RUN_ID}.log"
    COMMAND_LOG_SUMMARY_FILE="$workflow_dir/.${COMMAND_LOG_RUN_ID}.summary"
    COMMAND_LOG_STARTED_MS="$(command_log_now_ms)"
    COMMAND_LOG_INITIALIZED=true
    : > "$COMMAND_LOG_FILE"
    : > "$COMMAND_LOG_SUMMARY_FILE"
    ln -sfn "$(basename "$COMMAND_LOG_FILE")" "$workflow_dir/latest.log"

    command_log_write INFO workflow.start "version=$(command_log_value "$version") cwd=$(command_log_value "$project_dir")"
    echo "📝 本地命令日志: $COMMAND_LOG_FILE"
}

command_log_finish_stage() {
    local status="${1:-0}"
    [[ -n "$COMMAND_LOG_CURRENT_STAGE" ]] || return 0
    local now duration
    now="$(command_log_now_ms)"
    duration=$((now - COMMAND_LOG_CURRENT_STAGE_STARTED_MS))
    command_log_write INFO stage.finish \
        "label=$(command_log_value "$COMMAND_LOG_CURRENT_STAGE") duration_ms=$duration exit_code=$status"
    printf '%s|%s|%s\n' "$COMMAND_LOG_CURRENT_STAGE" "$duration" "$status" >> "$COMMAND_LOG_SUMMARY_FILE"
    COMMAND_LOG_CURRENT_STAGE=""
    COMMAND_LOG_CURRENT_STAGE_STARTED_MS=0
}

command_log_stage() {
    local label="$1"
    command_log_finish_stage 0
    COMMAND_LOG_CURRENT_STAGE="$label"
    COMMAND_LOG_CURRENT_STAGE_STARTED_MS="$(command_log_now_ms)"
    command_log_write INFO stage.start "label=$(command_log_value "$label")"
}

command_log_run() {
    local label="$1"
    shift
    local started duration status had_errexit command
    started="$(command_log_now_ms)"
    command="$(command_log_quote_command "$@")"
    command_log_write INFO command.start "label=$(command_log_value "$label") command=$(command_log_value "$command")"

    had_errexit=false
    [[ $- == *e* ]] && had_errexit=true
    set +e
    "$@" 2>&1 | tee -a "$COMMAND_LOG_FILE"
    status=${PIPESTATUS[0]}
    $had_errexit && set -e

    duration=$(( $(command_log_now_ms) - started ))
    command_log_write "$([[ $status -eq 0 ]] && echo INFO || echo "${COMMAND_LOG_FAILURE_LEVEL:-ERROR}")" command.finish \
        "label=$(command_log_value "$label") duration_ms=$duration exit_code=$status"
    return "$status"
}

command_log_run_tail() {
    local label="$1"
    local line_count="$2"
    shift 2
    local started duration status had_errexit command output_file
    started="$(command_log_now_ms)"
    command="$(command_log_quote_command "$@")"
    output_file="${COMMAND_LOG_FILE}.command.$$"
    command_log_write INFO command.start "label=$(command_log_value "$label") command=$(command_log_value "$command")"

    had_errexit=false
    [[ $- == *e* ]] && had_errexit=true
    set +e
    "$@" > "$output_file" 2>&1
    status=$?
    $had_errexit && set -e

    {
        printf '%s\n' "--- command output: $label ---"
        sed -n '1,$p' "$output_file"
        printf '%s\n' "--- end command output: $label ---"
    } >> "$COMMAND_LOG_FILE"
    tail -n "$line_count" "$output_file"
    rm -f "$output_file"

    duration=$(( $(command_log_now_ms) - started ))
    command_log_write "$([[ $status -eq 0 ]] && echo INFO || echo "${COMMAND_LOG_FAILURE_LEVEL:-ERROR}")" command.finish \
        "label=$(command_log_value "$label") duration_ms=$duration exit_code=$status"
    return "$status"
}

command_log_artifact() {
    local label="$1"
    local path="$2"
    local size=0
    [[ -f "$path" ]] && size="$(stat -f%z "$path" 2>/dev/null || echo 0)"
    command_log_write INFO artifact "label=$(command_log_value "$label") path=$(command_log_value "$path") size_bytes=$size"
}

command_log_finish() {
    local status="${1:-0}"
    $COMMAND_LOG_INITIALIZED || return 0
    $COMMAND_LOG_FINISHED && return 0
    COMMAND_LOG_FINISHED=true
    command_log_finish_stage "$status"

    local total_ms
    total_ms=$(( $(command_log_now_ms) - COMMAND_LOG_STARTED_MS ))
    command_log_write "$([[ $status -eq 0 ]] && echo INFO || echo ERROR)" workflow.finish \
        "duration_ms=$total_ms exit_code=$status"

    echo ""
    echo "═══ 命令耗时汇总 ═══"
    while IFS='|' read -r label duration stage_status; do
        [[ -n "$label" ]] || continue
        printf '  %-32s %8.2fs  exit=%s\n' "$label" "$(awk "BEGIN { print $duration / 1000 }")" "$stage_status"
    done < "$COMMAND_LOG_SUMMARY_FILE"
    printf '  %-32s %8.2fs\n' "总计" "$(awk "BEGIN { print $total_ms / 1000 }")"
    echo "  日志: $COMMAND_LOG_FILE"
    rm -f "$COMMAND_LOG_SUMMARY_FILE"
}
