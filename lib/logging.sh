LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/operations.log"

log() {

    mkdir -p "$LOG_DIR"

    local level="$1"
    shift

    local msg="$*"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    msg="${msg//\"/\\\"}"

    printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
        "$timestamp" \
        "$level" \
        "$msg" >> "$LOG_FILE"
}