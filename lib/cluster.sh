find_alive_node() {

    for ip in "${ALL_IPS[@]}"; do

        if node_ssh "$ip" "redis-cli -p ${REDIS_PORT} ping" 2>/dev/null | grep -q PONG; then
            echo "$ip"
            return 0
        fi

    done

    return 1
}

get_cluster_state() {
    local ip="${1:-$NODE1_IP}"
    node_ssh "${ip}" "redis-cli -p ${REDIS_PORT} cluster info" 2>/dev/null \
        | awk -F: '/cluster_state/ {print $2}' | tr -d '\r' || true
}

get_redis_version() {
    local ip="$1"
    node_ssh "${ip}" "redis-cli -p ${REDIS_PORT} info server" 2>/dev/null \
        | awk -F: '/redis_version/ {print $2}' | tr -d '\r' || true
}

get_cluster_nodes() {

    local alive

    alive=$(find_alive_node) || return 1

    node_ssh "$alive" \
        "redis-cli -p ${REDIS_PORT} cluster nodes" \
        2>/dev/null || true

}

get_node_id() {
    local ip="$1"
    get_cluster_nodes | awk -v ip="${ip}:${REDIS_PORT}" '$2 ~ ip"@" {print $1}'
}

get_replica_for_master() {
    local master_ip="$1"
    local master_id
    master_id=$(get_node_id "$master_ip")
    get_cluster_nodes | awk -v mid="$master_id" '$4 == mid {print $2}' | cut -d: -f1 | cut -d@ -f1
}

wait_for_cluster_ok() {
    local retries="${1:-20}"
    local delay="${2:-3}"
    local n=0
    while [ "$n" -lt "$retries" ]; do
        local state
        state=$(get_cluster_state)
        if [ "$state" = "ok" ]; then
            return 0
        fi
        n=$((n+1))
        sleep "$delay"
    done
    return 1
}

print_topology() {
    echo ""
    echo "===================================="
    echo " Redis Cluster Topology"
    echo "===================================="

    local cluster_info
    local alive

        alive=$(find_alive_node) || {
            echo "No reachable Redis node found"
            return 1
        }

        cluster_info=$(node_ssh "$alive" \
        "redis-cli -p ${REDIS_PORT} cluster info" 2>/dev/null)

    local state
    state=$(echo "$cluster_info" | awk -F: '/cluster_state/ {print $2}' | tr -d '\r')

    echo "Cluster State: $state"
    echo ""

    local nodes
    nodes=$(node_ssh "$alive" \
        "redis-cli -p ${REDIS_PORT} cluster nodes" 2>/dev/null)

    echo "MASTERS"

    while read -r line; do
        ip_port=$(echo "$line" | awk '{print $2}' | cut -d@ -f1)

        slots=$(echo "$line" | awk '
            {
                for(i=9;i<=NF;i++)
                    printf "%s ", $i
            }
        ' | xargs)

        ver=$(get_redis_version "$(echo "$ip_port" | cut -d: -f1)")

        echo "  $ip_port [master] v$ver slots: $slots"
    done < <(echo "$nodes" | awk '$3 ~ /master/')

    echo ""
    echo "REPLICAS"

    while read -r line; do
        ip_port=$(echo "$line" | awk '{print $2}' | cut -d@ -f1)

        master_id=$(echo "$line" | awk '{print $4}')

        master_ip=$(echo "$nodes" |
            awk -v id="$master_id" '$1 == id {print $2}' |
            cut -d@ -f1)

        ver=$(get_redis_version "$(echo "$ip_port" | cut -d: -f1)")

        echo "  $ip_port [replica] v$ver replicating: $master_ip"
    done < <(echo "$nodes" | awk '$3 ~ /slave|replica/')

    echo ""
}

get_cluster_versions() {

    for ip in "${ALL_IPS[@]}"; do
        get_redis_version "$ip"
    done
}