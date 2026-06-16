
validate_version() {

    local version="$1"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: Invalid version format: $version"
        echo "Expected format: X.Y.Z (example: 7.2.6)"
        return 1
    fi

    return 0
}


validate_upgrade_request() {

    local target_version="$1"

    validate_version "$target_version" || return 1

    echo "Checking current cluster versions..."

    local versions
    versions=$(get_cluster_versions) || return 1

    local needs_upgrade=0

    while read -r current_version; do

        [ -z "$current_version" ] && continue

        if version_lt "$target_version" "$current_version"; then

            echo
            echo "ERROR: Downgrade detected"
            echo "Current version : $current_version"
            echo "Target version  : $target_version"
            echo
            echo "Downgrades are not supported."
            return 1
        fi

        if version_gt "$target_version" "$current_version"; then
            needs_upgrade=1
        fi

    done <<< "$versions"

    if [ "$needs_upgrade" -eq 0 ]; then

        echo
        echo "All nodes already running Redis $target_version"
        echo "Nothing to do."
        return 2
    fi

    return 0
}

validate_download_url() {

    local version="$1"

    local url="https://download.redis.io/releases/redis-${version}.tar.gz"

    if ! curl -fsI "$url" >/dev/null 2>&1; then

        echo "ERROR: Redis version does not exist: $version"
        echo "URL checked: $url"
        return 1
    fi

    return 0
}


check_prereqs() {
    local missing=0

    if command -v podman >/dev/null 2>&1; then
        RUNTIME="podman"
        VER=$(podman --version | awk '{print $3}')
        echo "✓ Podman $VER found"

    elif command -v docker >/dev/null 2>&1; then

        if docker compose version >/dev/null 2>&1; then
            RUNTIME="docker"
            VER=$(docker --version | awk '{print $3}' | tr -d ',')
            echo "✓ Docker $VER found"
        else
            echo "✗ Docker Compose plugin not found"
            missing=1
        fi

    else
        echo "✗ Container runtime not found"
        missing=1
    fi

    if command -v ansible-playbook >/dev/null 2>&1; then
        AV=$(ansible-playbook --version | head -1 | grep -oP '\d+\.\d+\.\d+')
        echo "✓ Ansible $AV found"
    else
        echo "✗ Ansible not found"
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        exit 1
    fi

    echo "Proceeding..."
    echo ""
}



# Run the per-node upgrade playbook against one host
upgrade_one_node() {
    local node_name="$1"
    local target_version="$2"
    ansible-playbook "$ANSIBLE_DIR/playbooks/upgrade_node.yml" \
        -e "redis_version=${target_version}" \
        --limit "${node_name}"
}


cmd_upgrade() {
    local target_version=""
    local strategy="rolling"


    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target-version) target_version="$2"; shift 2 ;;
            --strategy) strategy="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$target_version" ]; then
        echo "ERROR: --target-version is required"
        exit 1
    fi

    log INFO "Upgrade started target_version=$target_version"

    echo "===================================="
    echo " Rolling Upgrade: -> v${target_version} (strategy: ${strategy})"
    echo "===================================="
    echo ""

    # --- 1. Pre-flight checks ---------------------------------------------
    echo "[Pre-flight] Checking cluster health..."

    state=$(get_cluster_state)

    if [ "$state" != "ok" ]; then
        echo "ABORT: cluster_state is '$state', expected 'ok'"
        exit 1
    fi

    echo "  cluster_state: ok"


    echo "[Pre-flight] Checking all nodes reachable..."

    for ip in "${ALL_IPS[@]}"; do

        if ! ssh -n \
            -i "$REDIS_CLI_KEY" \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=5 \
            "root@${ip}" \
            "redis-cli -p ${REDIS_PORT} ping" 2>/dev/null |
            grep -q PONG; then

            echo "ABORT: $ip unreachable"
            exit 1
        fi

    done

    echo "  all nodes reachable"


    echo "[Pre-flight] Validating target version..."

    validate_upgrade_request "$target_version"
    rc=$?

    if [ "$rc" -eq 2 ]; then
        exit 0
    elif [ "$rc" -ne 0 ]; then
        exit 1
    fi

    echo "[Pre-flight] Verifying Redis release exists..."

    if ! curl -fsI \
        "https://download.redis.io/releases/redis-${target_version}.tar.gz" \
        >/dev/null 2>&1; then

        echo "ERROR: Redis version '$target_version' does not exist"
        exit 1
    fi

    echo "  target version validated"


    echo "[Pre-flight] Running data verification..."

    cmd_data_verify --keys 1000

    echo ""

    # --- 2. Upgrade replicas first ------------------------------------------
    echo "===================================="
    echo " Step 1: Upgrading replicas"
    echo "===================================="
    local progress=0
    for ip in "${REPLICA_IPS[@]}"; do
        progress=$((progress+1))
        local name="${NODE_NAME[$ip]}"
        echo ""
        echo "--- Upgrading replica $ip ($name) ---"

        if ! upgrade_one_node "$name" "$target_version"; then
            echo "FAILED at step: upgrading replica $ip ($name)"
            exit 1
        fi

        if ! wait_for_cluster_ok; then
            echo "FAILED: cluster did not return to cluster_state:ok after upgrading $ip"
            exit 1
        fi

        echo "[${progress}/6] Upgraded replica ${ip} — cluster: ok"
    done

    # --- 3. Upgrade masters (one at a time, with failover) -------------------
    echo ""
    echo "===================================="
    echo " Step 2: Upgrading masters (with failover)"
    echo "===================================="
    for ip in "${MASTER_IPS[@]}"; do
        progress=$((progress+1))
        local name="${NODE_NAME[$ip]}"
        echo ""
        echo "--- Upgrading master $ip ($name) ---"

        # Find this master's replica (already upgraded in step 1)
        local replica_ip
        replica_ip=$(get_replica_for_master "$ip")
        if [ -z "$replica_ip" ]; then
            echo "FAILED: could not find replica for master $ip"
            exit 1
        fi
        echo "  Replica for $ip is $replica_ip — triggering CLUSTER FAILOVER on it"

        # Trigger failover on the replica - it becomes the new master
        if ! ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${replica_ip}" "redis-cli -p ${REDIS_PORT} cluster failover" 2>/dev/null; then
            echo "FAILED at step: CLUSTER FAILOVER on $replica_ip (replica of master $ip)"
            exit 1
        fi

        # Wait for failover to complete: old master ($ip) should now show as a slave
        local failover_done=0
        for attempt in $(seq 1 20); do
            sleep 2
            local role
            role=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
                "root@${ip}" "redis-cli -p ${REDIS_PORT} role" 2>/dev/null | head -1)
            if [[ "$role" == "slave" || "$role" == "replica" ]]; then
                failover_done=1
                break
            fi
        done

        if [ "$failover_done" -ne 1 ]; then
            echo "FAILED at step: failover did not complete - $ip is still master after waiting"
            exit 1
        fi
        echo "  Failover complete: $ip is now a replica, $replica_ip is the new master"

        # Old master ($ip) is now a replica - upgrade it
        if ! upgrade_one_node "$name" "$target_version"; then
            echo "FAILED at step: upgrading old master $ip (now replica)"
            exit 1
        fi

        if ! wait_for_cluster_ok; then
            echo "FAILED: cluster did not return to cluster_state:ok after upgrading $ip"
            exit 1
        fi

        echo "[${progress}/6] Upgraded master ${ip} (failover -> ${replica_ip}, then upgraded) — cluster: ok"
    done

    # --- 4. Post-upgrade verification -----------------------------------------
    echo ""
    echo "===================================="
    echo " Step 3: Post-upgrade verification"
    echo "===================================="

    echo ""
    echo "[Post-upgrade] Data verify..."
    cmd_data_verify --keys 1000

    echo ""
    echo "[Post-upgrade] Status..."
    cmd_status

    echo ""
    echo "UPGRADE COMPLETE — all nodes on v${target_version}, data integrity verified"
    log INFO "Upgrade completed target_version=$target_version"
}