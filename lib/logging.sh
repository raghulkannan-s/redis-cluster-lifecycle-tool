LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/operations.log"


log() {
    mkdir -p "$LOG_DIR"

    local level="$1"
    shift

    printf '[%s] [%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$level" \
        "$*" >> "$LOG_FILE"
}
