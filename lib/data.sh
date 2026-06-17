cmd_data_seed() {
    local keys=1000

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keys) keys="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_infra_running

    echo "Seeding $keys keys into the cluster..."
    log INFO "Data seed started keys=$keys"
    echo ""

    # Build a bash script with all SET commands to run in a single SSH session
    local batch_script=""
    for ((i=1; i<=keys; i++)); do
        local key
        key=$(printf "key:%04d" "$i")
        local value
        value=$(echo -n "$key" | sha256sum | awk '{print $1}')
        batch_script+="redis-cli -c -p ${REDIS_PORT} SET ${key} ${value}"$'\n'
    done

    local result
    result=$(echo "$batch_script" | node_ssh_stdin "${NODE1_IP}" "bash" 2>/dev/null || true)

    local inserted
    inserted=$(echo "$result" | grep -c "OK" || true)
    local failed=$((keys - inserted))

    echo "Insertion complete."
    echo "  Total keys requested: $keys"
    echo "  Successfully inserted: $inserted"
    echo "  Failed: $failed"
    echo ""

    echo "Distribution across masters:"
    local current_masters
    current_masters=$(get_cluster_nodes | awk '$3 ~ /master/ {print $2}' | cut -d: -f1 | cut -d@ -f1)
    for ip in $current_masters; do
        local count
        count=$(node_ssh "${ip}" "redis-cli -p ${REDIS_PORT} DBSIZE" 2>/dev/null | tr -d '\r' || true)
        echo "  ${ip}:${REDIS_PORT} -> $count keys"
    done
    echo ""
    log INFO "Data seed completed inserted=$inserted failed=$failed"
}

cmd_data_verify() {
    local keys=1000

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keys) keys="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_infra_running

    log INFO "Data verification started keys=$keys"

    echo "Verifying $keys keys..."
    echo ""

    # Build a bash script to GET all keys in a single SSH session
    # Output format: KEY:<key> VALUE:<value>
    local batch_script=""
    for ((i=1; i<=keys; i++)); do
        local key
        key=$(printf "key:%04d" "$i")
        batch_script+="echo \"KEY:${key}:\$(redis-cli -c -p ${REDIS_PORT} GET ${key})\""$'\n'
    done

    local result
    result=$(echo "$batch_script" | node_ssh_stdin "${NODE1_IP}" "bash" 2>/dev/null || true)

    local missing=0
    local mismatched=0
    local ok=0

    for ((i=1; i<=keys; i++)); do
        local key
        key=$(printf "key:%04d" "$i")

        local expected
        expected=$(echo -n "$key" | sha256sum | awk '{print $1}')

        local actual
        actual=$(echo "$result" | grep "^KEY:${key}:" | sed "s/^KEY:${key}://" | tr -d '\r')

        if [ -z "$actual" ]; then
            missing=$((missing+1))
        elif [ "$actual" != "$expected" ]; then
            mismatched=$((mismatched+1))
        else
            ok=$((ok+1))
        fi
    done

    echo ""
    if [ "$missing" -eq 0 ] && [ "$mismatched" -eq 0 ]; then
        echo "PASS — $ok/$keys keys verified"
        log INFO "Data verification passed"
        return 0
    else
        echo "FAIL — $missing keys missing, $mismatched values mismatched"
        log ERROR "Data verification failed missing=$missing mismatched=$mismatched"
        return 1
    fi
}
