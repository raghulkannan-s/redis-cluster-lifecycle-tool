cmd_setup() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    echo "Setting up container infrastructure..."
    log INFO "Setup started force=$force"
    echo ""

    if [ "$force" = true ]; then
        start_infra
    else
        start_infra_if_needed
    fi

    echo ""
    print_infra_summary
    log INFO "Setup completed"
}

print_infra_summary() {
    echo "===================================="
    echo " Infrastructure Ready"
    echo "===================================="
    echo "Runtime : ${RUNTIME:-unknown}"
    echo "Network : ${NETWORK_SUBNET}"
    echo ""
    echo "Nodes (SSH via port-forward):"
    for ip in "${ALL_IPS[@]}"; do
        local name=$(get_node_name "$ip")
        local port=$(get_ssh_port "$ip")
        echo "  $name  container=${ip}  ssh=${SSH_HOST}:$port"
    done
    echo ""
    echo "Next step:"
    echo "  ./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1"
    echo ""
}