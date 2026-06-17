
detect_runtime() {
    if command -v docker >/dev/null 2>&1; then
        RUNTIME="docker"
        return 0
    fi

    if command -v podman >/dev/null 2>&1; then
        RUNTIME="podman"
        return 0
    fi

    RUNTIME=""
    return 1
}

check_runtime_prereqs() {
    local missing=0

    if detect_runtime; then
        if [ "$RUNTIME" = "docker" ]; then
            VER=$(docker --version | awk '{print $3}')
            echo "✓ Docker $VER found"
        else
            VER=$(podman --version | awk '{print $3}')
            echo "✓ Podman $VER found"
        fi
    else
        echo "✗ Container runtime not found (Docker or Podman)"
        echo "Install Docker: https://docs.docker.com/engine/install/"
        echo "Install Podman: https://podman.io/docs/installation"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "Please install the missing dependencies and retry."
        exit 1
    fi

    echo "Proceeding..."
    echo ""
}

check_prereqs() {
    local missing=0

    if detect_runtime; then
        if [ "$RUNTIME" = "docker" ]; then
            VER=$(docker --version | awk '{print $3}')
            echo "✓ Docker $VER found"
        else
            VER=$(podman --version | awk '{print $3}')
            echo "✓ Podman $VER found"
        fi
    else
        echo "✗ Container runtime not found (Docker or Podman)"
        echo "Install Docker: https://docs.docker.com/engine/install/"
        echo "Install Podman: https://podman.io/docs/installation"
        missing=1
    fi

    if command -v ansible-playbook >/dev/null 2>&1; then
        AV=$(ansible-playbook --version 2>/dev/null | head -1 | sed -E 's/.* ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
        if [ -n "$AV" ] && version_ge "$AV" "$MIN_ANSIBLE_VERSION"; then
            echo "✓ Ansible $AV found"
        else
            echo "✗ Ansible ${AV:-unknown} found (requires ${MIN_ANSIBLE_VERSION}+)"
            echo "  Install: pip install 'ansible>=2.14' (or use your OS package manager)"
            missing=1
        fi
    else
        echo "✗ Ansible not found"
        echo "Install: pip install ansible (or use your OS package manager)"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "Please install the missing dependencies and retry."
        exit 1
    fi

    echo "Proceeding..."
    echo ""
}

setup_ssh_keys() {
    local project_key_dir="$SCRIPT_DIR/infra/keys"
    local project_private="$project_key_dir/id_rsa"
    local project_public="$project_key_dir/id_rsa.pub"

    local user_key_dir="$HOME/.ssh-redis-tool"
    local user_private="$user_key_dir/id_rsa"
    local user_public="$user_key_dir/id_rsa.pub"

    mkdir -p "$project_key_dir"
    mkdir -p "$user_key_dir"

    if [ ! -f "$project_private" ]; then
        echo "Generating SSH key pair..."
        ssh-keygen \
            -t rsa \
            -b 4096 \
            -f "$project_private" \
            -N "" >/dev/null
    fi

    if [ ! -f "$user_private" ]; then
        cp "$project_private" "$user_private"
    fi

    if [ ! -f "$user_public" ]; then
        cp "$project_public" "$user_public"
    fi

    chmod 600 "$user_private"
}

select_runtime() {
    detect_runtime && echo "$RUNTIME" || echo ""
}

count_running_nodes() {
    local runtime="${1:-${RUNTIME:-docker}}"
    local running=0

    for node in \
        redis-node-1 \
        redis-node-2 \
        redis-node-3 \
        redis-node-4 \
        redis-node-5 \
        redis-node-6
    do
        if $runtime ps --format '{{.Names}}' 2>/dev/null | grep -q "^${node}$"; then
            running=$((running + 1))
        fi
    done

    echo "$running"
}

is_infra_running() {
    [ "$(count_running_nodes)" -eq 6 ]
}

require_infra_running() {
    detect_runtime || true

    local running
    running=$(count_running_nodes)

    if [ "$running" -ne 6 ]; then
        echo "ERROR: Infrastructure is not running ($running/6 containers up)."
        echo ""
        echo "Start the containers first:"
        echo "  ./redis-tool setup"
        echo ""
        echo "To rebuild from scratch:"
        echo "  ./redis-tool setup --force"
        exit 1
    fi
}

start_infra() {
    echo "Preparing infrastructure..."

    setup_ssh_keys

    cd "$SCRIPT_DIR/infra"

    if [ "${RUNTIME:-}" = "podman" ]; then
        echo "Using Podman"

        echo "Cleaning previous infrastructure..."
        podman-compose down >/dev/null 2>&1 || true

        echo "Removing old networks..."
        podman network prune -f >/dev/null 2>&1 || true

        echo "Starting infrastructure..."

        # Pre-create the network so we can patch the CNI config version before containers start
        podman network create infra_redis-net --subnet 172.25.0.0/24 >/dev/null 2>&1 || true
        # Patch the CNI config to avoid firewall plugin version incompatibility
        for cni_conf in ~/.config/cni/net.d/*infra_redis-net.conflist /etc/cni/net.d/*infra_redis-net.conflist; do
            if [ -f "$cni_conf" ]; then
                sed -i 's/"cniVersion": "1.0.0"/"cniVersion": "0.4.0"/g' "$cni_conf"
            fi
        done

        if ! podman-compose up -d --build; then
            echo "Retrying after cleanup..."
            podman-compose down >/dev/null 2>&1 || true
            podman network prune -f >/dev/null 2>&1 || true
            podman network create infra_redis-net --subnet 172.25.0.0/24 >/dev/null 2>&1 || true
            for cni_conf in ~/.config/cni/net.d/*infra_redis-net.conflist /etc/cni/net.d/*infra_redis-net.conflist; do
                if [ -f "$cni_conf" ]; then
                    sed -i 's/"cniVersion": "1.0.0"/"cniVersion": "0.4.0"/g' "$cni_conf"
                fi
            done
            podman-compose up -d --build
        fi

    elif [ "${RUNTIME:-}" = "docker" ]; then
        echo "Using Docker"

        echo "Cleaning previous infrastructure..."
        docker-compose down >/dev/null 2>&1 || true

        echo "Removing old networks..."
        docker network prune -f >/dev/null 2>&1 || true

        echo "Starting infrastructure..."
        docker-compose up -d --build

    else
        echo "ERROR: No runtime selected"
        exit 1
    fi

    cd - >/dev/null

    wait_for_ssh
}

start_infra_if_needed() {
    if is_infra_running; then
        echo "Infrastructure already running."
        return 0
    fi

    start_infra
}