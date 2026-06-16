
cmd_rollback() {

    local target_version=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --target-version)
                target_version="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [ -z "$target_version" ]; then
        echo "Usage: $0 rollback --target-version <version>"
        exit 1
    fi

    echo ""
    echo "===================================="
    echo "ROLLBACK STARTED"
    echo "===================================="
    echo ""

    log INFO "Rollback started (target_version=$target_version)"

    cmd_upgrade \
        --target-version "$target_version" \
        --strategy rolling

    rc=$?

    if [ "$rc" -eq 0 ]; then
        echo ""
        echo "ROLLBACK COMPLETE"
        log INFO "Rollback completed"
    else
        echo ""
        echo "ROLLBACK FAILED"
        log ERROR "Rollback failed"
    fi

    return "$rc"
}