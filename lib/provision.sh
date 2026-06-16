cmd_provision() {
    local version="7.0.15"
    local masters=3
    local replicas_per_master=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            --masters) masters="$2"; shift 2 ;;
            --replicas-per-master) replicas_per_master="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ "$masters" -ne 3 ] || [ "$replicas_per_master" -ne 1 ]; then
        echo "NOTE: This tool is built for a fixed 6-node topology"
        echo "      (3 masters + 3 replicas, replicas-per-master=1)."
        echo "      Ignoring --masters/--replicas-per-master overrides."
        echo ""
    fi

    echo "Provisioning Redis $version on 6-node cluster..."
    log INFO "Provision started version=$version"
    echo ""

    # Idempotency check: if cluster is already healthy, skip re-provisioning
    local existing_state
    start_infra_if_needed
    existing_state=$(ssh -i "$REDIS_CLI_KEY" -o StrictHostKeyChecking=accept-new \
        "root@${NODE1_IP}" "redis-cli -p ${REDIS_PORT} cluster info 2>/dev/null" 2>/dev/null \
        | awk -F: '/cluster_state/ {print $2}' | tr -d '\r')

    if [ "$existing_state" = "ok" ]; then
        echo "Cluster already provisioned and healthy (cluster_state:ok)."
        echo "Skipping re-provisioning. Showing current topology:"
        print_topology
        log INFO "Provision skipped - cluster already healthy"
        return 0
    fi

    ansible-playbook "$ANSIBLE_DIR/playbooks/provision.yml" -e "redis_version=$version"
    log INFO "Provision completed successfully"

    print_topology
}
