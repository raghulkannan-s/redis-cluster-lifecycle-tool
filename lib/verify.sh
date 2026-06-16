cmd_status() {
    local cluster_info
    cluster_info=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
        "root@${NODE1_IP}" "redis-cli -p ${REDIS_PORT} cluster info" 2>/dev/null)

    local state
    state=$(echo "$cluster_info" | awk -F: '/cluster_state/ {print $2}' | tr -d '\r')

    echo "Cluster State: $state"
    echo ""

    local nodes
    nodes=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
        "root@${NODE1_IP}" "redis-cli -p ${REDIS_PORT} cluster nodes" 2>/dev/null)

    echo "MASTERS"
    while read -r line; do
        ip_port=$(echo "$line" | awk '{print $2}' | cut -d@ -f1)
        ip=$(echo "$ip_port" | cut -d: -f1)

        slots=$(echo "$line" | awk '{ for(i=9;i<=NF;i++) printf "%s ", $i }' | xargs)

        ver=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} info server" 2>/dev/null \
            | awk -F: '/redis_version/ {print $2}' | tr -d '\r')

        keycount=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} DBSIZE" 2>/dev/null | tr -d '\r')

        mem=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} info memory" 2>/dev/null \
            | awk -F: '/used_memory_human/ {print $2}' | tr -d '\r')

        echo "  $ip_port [master] v$ver slots: $slots keys: $keycount mem: $mem"
    done < <(echo "$nodes" | grep -E 'master')

    echo ""
    echo "REPLICAS"
    while read -r line; do
        ip_port=$(echo "$line" | awk '{print $2}' | cut -d@ -f1)
        ip=$(echo "$ip_port" | cut -d: -f1)
        master_id=$(echo "$line" | awk '{print $4}')

        master_ip=$(echo "$nodes" | awk -v id="$master_id" '$1 == id {print $2}' | cut -d@ -f1)

        ver=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} info server" 2>/dev/null \
            | awk -F: '/redis_version/ {print $2}' | tr -d '\r')

        mem=$(ssh -n -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "redis-cli -p ${REDIS_PORT} info memory" 2>/dev/null \
            | awk -F: '/used_memory_human/ {print $2}' | tr -d '\r')

        echo "  $ip_port [replica] v$ver replicating: $master_ip mem: $mem"
    done < <(echo "$nodes" | grep -E 'slave')

    echo ""
}


cmd_verify_full() {
    log INFO "Full verification started"
    echo "===================================="
    echo " FULL CLUSTER VERIFICATION"
    echo "===================================="
    echo ""

    local overall_fail=0

    # -------------------------------------------------------
    # 1. DATA INTEGRITY
    # -------------------------------------------------------
    echo "[1/5] Data Integrity"

    local verify_output
    verify_output=$(cmd_data_verify --keys 1000)

    if echo "$verify_output" | grep -q "PASS"; then
        echo "  PASS"
    else
        echo "  FAIL"
        overall_fail=1
    fi

    echo ""

    # -------------------------------------------------------
    # 2. VERSION CONSISTENCY
    # -------------------------------------------------------
    echo "[2/5] Version Consistency"

    declare -A version_map=()

    for ip in "${ALL_IPS[@]}"; do
        version_map["$ip"]="$(get_redis_version "$ip")"
    done

    expected_version="${version_map[${ALL_IPS[0]}]}"

    version_fail=0

    for ip in "${ALL_IPS[@]}"; do
        if [ "${version_map[$ip]}" != "$expected_version" ]; then
            version_fail=1
            echo "  MISMATCH: $ip -> ${version_map[$ip]}"
        fi
    done

    if [ "$version_fail" -eq 0 ]; then
        echo "  PASS - all nodes running Redis $expected_version"
    else
        echo "  FAIL"
        overall_fail=1
    fi

    echo ""

    # -------------------------------------------------------
    # 3. TOPOLOGY HEALTH
    # -------------------------------------------------------
    echo "[3/5] Topology Health"

    topology_fail=0

    cluster_info=$(ssh -n -i "$REDIS_CLI_KEY" \
        -o StrictHostKeyChecking=accept-new \
        "root@${NODE1_IP}" \
        "redis-cli -p ${REDIS_PORT} cluster info" 2>/dev/null)

    slots_assigned=$(echo "$cluster_info" |
        awk -F: '/cluster_slots_assigned/ {print $2}' |
        tr -d '\r')

    if [ "$slots_assigned" != "16384" ]; then
        echo "  FAIL - only $slots_assigned slots assigned"
        topology_fail=1
    fi

    cluster_nodes=$(get_cluster_nodes)

    master_count=$(echo "$cluster_nodes" |
        grep master |
        grep -v fail |
        wc -l)

    replica_count=$(echo "$cluster_nodes" |
        grep -E 'slave|replica' |
        grep -v fail |
        wc -l)

    echo "  Masters : $master_count"
    echo "  Replicas: $replica_count"

    while read -r line; do

        master_id=$(echo "$line" | awk '{print $1}')
        master_ip=$(echo "$line" | awk '{print $2}' | cut -d@ -f1)

        replica_exists=$(echo "$cluster_nodes" |
            awk -v mid="$master_id" '$4 == mid {print $0}')

        if [ -z "$replica_exists" ]; then
            echo "  FAIL - master $master_ip has no replica"
            topology_fail=1
        fi

    done < <(echo "$cluster_nodes" | grep master)

    if [ "$topology_fail" -eq 0 ]; then
        echo "  PASS - all 16384 slots covered and all masters have replicas"
    else
        overall_fail=1
    fi

    echo ""

    # -------------------------------------------------------
    # 4. CLUSTER STATE
    # -------------------------------------------------------
    echo "[4/5] Cluster State"

    state=$(get_cluster_state)

    if [ "$state" = "ok" ]; then
        echo "  PASS - cluster_state:ok"
    else
        echo "  FAIL - cluster_state:$state"
        overall_fail=1
    fi

    echo ""

    # -------------------------------------------------------
    # 5. REPLICATION HEALTH
    # -------------------------------------------------------
    echo "[5/5] Replication Health"

    replication_fail=0

    for ip in "${ALL_IPS[@]}"; do

        role=$(ssh -n -i "$REDIS_CLI_KEY" \
            -o StrictHostKeyChecking=accept-new \
            "root@${ip}" \
            "redis-cli -p ${REDIS_PORT} info replication" 2>/dev/null |
            awk -F: '/role/ {print $2}' |
            tr -d '\r')

        if [[ "$role" == "slave" || "$role" == "replica" ]]; then

            link_status=$(ssh -n -i "$REDIS_CLI_KEY" \
                -o StrictHostKeyChecking=accept-new \
                "root@${ip}" \
                "redis-cli -p ${REDIS_PORT} info replication" 2>/dev/null |
                awk -F: '/master_link_status/ {print $2}' |
                tr -d '\r')

            if [ "$link_status" != "up" ]; then
                echo "  FAIL - replica $ip master_link_status:$link_status"
                replication_fail=1
            fi
        fi
    done

    if [ "$replication_fail" -eq 0 ]; then
        echo "  PASS - all replicas linked to masters"
    else
        overall_fail=1
    fi

    echo ""
    echo "===================================="

    if [ "$overall_fail" -eq 0 ]; then
        echo " OVERALL RESULT: PASS"
        echo "===================================="
        log INFO "Full verification passed"
        return 0
    else
        echo " OVERALL RESULT: FAIL"
        echo "===================================="
        log ERROR "Full verification failed"
        return 1
    fi
}