wait_for_ssh() {
    local retries="${1:-30}"
    local delay="${2:-2}"

    echo "Waiting for SSH to become available on all nodes..."

    for ip in "${ALL_IPS[@]}"; do
        local port="${NODE_SSH_PORT[$ip]}"
        local n=0
        while [ "$n" -lt "$retries" ]; do
            if ssh -n -i "$REDIS_CLI_KEY" \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=3 \
                -o BatchMode=yes \
                -p "$port" \
                "root@${SSH_HOST}" "true" 2>/dev/null; then
                break
            fi
            n=$((n+1))
            sleep "$delay"
        done

        if [ "$n" -ge "$retries" ]; then
            echo "ERROR: SSH not available on ${NODE_NAME[$ip]} (port $port) after $((retries * delay))s"
            return 1
        fi
    done

    echo "  All nodes reachable via SSH."
}