cmd_data_seed() {
    local keys=1000

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keys) keys="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    echo "Seeding $keys keys into the cluster..."
    log INFO "Data seed started keys=$keys"
    echo ""

    local inserted=0
    local failed=0

    for ((i=1; i<=keys; i++)); do
        local key
        key=$(printf "key:%04d" "$i")

        local value
        value=$(echo -n "$key" | sha256sum | awk '{print $1}')

        if ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${NODE1_IP}" "redis-cli -c -p ${REDIS_PORT} SET $key $value" 2>/dev/null \
            | grep -q "OK"; then
            inserted=$((inserted+1))
        else
            failed=$((failed+1))
        fi
    done

    echo "Insertion complete."
    echo "  Total keys requested: $keys"
    echo "  Successfully inserted: $inserted"
    echo "  Failed: $failed"
    echo ""

    echo "Distribution across masters:"
    for ip in 10.55.0.11 10.55.0.12 10.55.0.13; do
        local count
        count=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} DBSIZE" 2>/dev/null | tr -d '\r')
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
    
    log INFO "Data verification started keys=$keys"

    echo "Verifying $keys keys..."
    echo ""

    local missing=0
    local mismatched=0
    local ok=0

    for ((i=1; i<=keys; i++)); do
        local key
        key=$(printf "key:%04d" "$i")

        local expected
        expected=$(echo -n "$key" | sha256sum | awk '{print $1}')

        local actual
        actual=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${NODE1_IP}" "redis-cli -c -p ${REDIS_PORT} GET $key" 2>/dev/null | tr -d '\r')

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
    echo ""
}
