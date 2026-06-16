

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

    cp "$project_private" "$user_private"
    cp "$project_public" "$user_public"

    chmod 600 "$user_private"
}

select_runtime() {

    if command -v docker >/dev/null 2>&1; then
        if docker ps >/dev/null 2>&1; then
            echo "docker"
            return
        fi
    fi

    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return
    fi

    echo ""
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

        if ! podman-compose up -d --build; then

            echo "Retrying after cleanup..."

            podman-compose down >/dev/null 2>&1 || true
            podman network prune -f >/dev/null 2>&1 || true

            podman-compose up -d --build
        fi

    elif [ "${RUNTIME:-}" = "docker" ]; then

        echo "Using Docker"

        echo "Cleaning previous infrastructure..."
        docker compose down >/dev/null 2>&1 || true

        echo "Removing old networks..."
        docker network prune -f >/dev/null 2>&1 || true

        echo "Starting infrastructure..."

        docker compose up -d --build

    else

        echo "ERROR: No runtime selected"
        exit 1

    fi

    cd - >/dev/null
}

start_infra_if_needed() {

    local runtime="${RUNTIME:-podman}"

    if $runtime ps --format '{{.Names}}' 2>/dev/null | grep -q redis-node-1; then
        echo "Infrastructure already running."
        return 0
    fi

    start_infra
}
