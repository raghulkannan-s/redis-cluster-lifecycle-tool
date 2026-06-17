version_lt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

version_gt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" != "$2" ]
}

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
    local allow_downgrade="${2:-false}"

    validate_version "$target_version" || return 1

    echo "Checking current cluster versions..."

    local versions
    versions=$(get_cluster_versions) || return 1

    local needs_upgrade=0

    while read -r current_version; do

        [ -z "$current_version" ] && continue

        if [ "$allow_downgrade" != "true" ] && version_lt "$target_version" "$current_version"; then

            echo
            echo "ERROR: Downgrade detected"
            echo "Current version : $current_version"
            echo "Target version  : $target_version"
            echo
            echo "Downgrades are not supported. Use rollback command instead."
            return 1
        fi

        if [ "$current_version" != "$target_version" ]; then
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


# Run the per-node upgrade playbook against one host
upgrade_one_node() {
    local node_name="$1"
    local target_version="$2"

    ensure_redis_binaries "$target_version"

    ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" ansible-playbook "$ANSIBLE_DIR/playbooks/upgrade_node.yml" \
        -e "redis_version=${target_version}" \
        --limit "${node_name}"
}


cmd_upgrade() {
    local target_version=""
    local strategy="rolling"
    local allow_downgrade="false"


    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target-version) target_version="$2"; shift 2 ;;
            --strategy) strategy="$2"; shift 2 ;;
            --allow-downgrade) allow_downgrade="true"; shift ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ "$strategy" != "rolling" ]; then

        echo "ERROR: unsupported strategy '$strategy'"
        echo "Supported: rolling"

        exit 1

    fi

    if [ -z "$target_version" ]; then
        echo "ERROR: --target-version is required"
        exit 1
    fi

    require_infra_running

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

        if ! node_ssh "$ip" "redis-cli -p ${REDIS_PORT} ping" 2>/dev/null |
            grep -q PONG; then

            echo "ABORT: $ip unreachable"
            exit 1
        fi

    done

    echo "  all nodes reachable"


    echo "[Pre-flight] Validating target version..."

    # Capture exit code without set -e killing the script
    rc=0
    validate_upgrade_request "$target_version" "$allow_downgrade" || rc=$?

    if [ "$rc" -eq 2 ]; then
        exit 0
    elif [ "$rc" -ne 0 ]; then
        exit 1
    fi

    echo "[Pre-flight] Verifying Redis release exists..."

    validate_download_url "$target_version" || exit 1

    echo "  target version validated"


    echo "[Pre-flight] Running data verification..."

    if ! cmd_data_verify --keys 1000; then

        echo "ABORT: pre-upgrade data verification failed"
        exit 1

    fi

    echo ""

    # --- 2. Upgrade replicas first ------------------------------------------
    # Dynamically discover current replicas from cluster state
    echo "===================================="
    echo " Step 1: Upgrading replicas"
    echo "===================================="

    local current_replica_ips
    current_replica_ips=$(get_cluster_nodes | awk '$3 ~ /slave|replica/ && $3 !~ /fail/' | awk '{print $2}' | cut -d: -f1 | cut -d@ -f1)

    local current_master_ips
    current_master_ips=$(get_cluster_nodes | awk '$3 ~ /master/ && $3 !~ /fail/' | awk '{print $2}' | cut -d: -f1 | cut -d@ -f1)

    local progress=0
    local total_nodes
    total_nodes=$(echo "$current_replica_ips" "$current_master_ips" | wc -w)

    for ip in $current_replica_ips; do
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

        echo "[${progress}/${total_nodes}] Upgraded replica ${ip} — cluster: ok"
    done

    # --- 3. Upgrade masters (one at a time, with failover) -------------------
    echo ""
    echo "===================================="
    echo " Step 2: Upgrading masters (with failover)"
    echo "===================================="
    for ip in $current_master_ips; do
        progress=$((progress+1))
        local name="${NODE_NAME[$ip]}"
        echo ""
        echo "--- Upgrading master $ip ($name) ---"

        ensure_redis_binaries "$target_version"

        # Find this master's replica (already upgraded in step 1)
        local replica_ip
        replica_ip=$(get_replica_for_master "$ip")
        if [ -z "$replica_ip" ]; then
            echo "FAILED: could not find replica for master $ip"
            exit 1
        fi
        echo "  Replica for $ip is $replica_ip — triggering CLUSTER FAILOVER on it"

        # Trigger failover on the replica - it becomes the new master
        if ! node_ssh "${replica_ip}" "redis-cli -p ${REDIS_PORT} cluster failover" 2>/dev/null; then
            echo "FAILED at step: CLUSTER FAILOVER on $replica_ip (replica of master $ip)"
            exit 1
        fi

        # Wait for failover to complete: old master ($ip) should now show as a slave
        local failover_done=0
        for attempt in $(seq 1 20); do
            sleep 2
            local role
            role=$(node_ssh "${ip}" "redis-cli -p ${REDIS_PORT} role" 2>/dev/null | head -1 | tr -d '\r')
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

        echo "[${progress}/${total_nodes}] Upgraded master ${ip} (failover -> ${replica_ip}, then upgraded) — cluster: ok"
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