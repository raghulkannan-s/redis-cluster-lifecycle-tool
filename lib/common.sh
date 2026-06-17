SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
source "$SCRIPT_DIR/lib/config.sh"

version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

node_ssh() {
    local ip="$1"
    shift
    ssh -n -i "$REDIS_CLI_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "${NODE_SSH_PORT[$ip]}" \
        "root@${SSH_HOST}" "$@" 2>/dev/null
}

node_ssh_stdin() {
    local ip="$1"
    shift
    ssh -i "$REDIS_CLI_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "${NODE_SSH_PORT[$ip]}" \
        "root@${SSH_HOST}" "$@" 2>/dev/null
}

ensure_redis_binaries() {
    local version="$1"
    local bin_dir="$SCRIPT_DIR/binaries/$version"

    if [ ! -f "$bin_dir/redis-server" ]; then
        echo "Extracting Redis $version binaries locally..."
        mkdir -p "$bin_dir"
        local container_name="temp-redis-$version-$RANDOM"
        
        # Use whatever runtime is available (detect_runtime should have populated RUNTIME)
        local rt="${RUNTIME:-docker}"
        
        "$rt" create --name "$container_name" "redis:$version" >/dev/null
        "$rt" cp "$container_name:/usr/local/bin/redis-server" "$bin_dir/"
        "$rt" cp "$container_name:/usr/local/bin/redis-cli" "$bin_dir/"
        "$rt" cp "$container_name:/usr/local/bin/redis-benchmark" "$bin_dir/"
        "$rt" cp "$container_name:/usr/local/bin/redis-check-aof" "$bin_dir/"
        "$rt" cp "$container_name:/usr/local/bin/redis-check-rdb" "$bin_dir/"
        "$rt" rm "$container_name" >/dev/null
    fi
}