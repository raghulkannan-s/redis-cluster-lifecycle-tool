# Network and cluster topology (must match infra/compose.yml and ansible/inventory/hosts.ini)
NETWORK_SUBNET="10.10.0.0/24"
NODE1_IP="10.10.0.11"

ALL_IPS=(
    10.10.0.11
    10.10.0.12
    10.10.0.13
    10.10.0.14
    10.10.0.15
    10.10.0.16
)

MASTER_IPS=(
    10.10.0.11
    10.10.0.12
    10.10.0.13
)

REPLICA_IPS=(
    10.10.0.14
    10.10.0.15
    10.10.0.16
)

get_node_name() {
    case "$1" in
        10.10.0.11) echo "redis-node-1" ;;
        10.10.0.12) echo "redis-node-2" ;;
        10.10.0.13) echo "redis-node-3" ;;
        10.10.0.14) echo "redis-node-4" ;;
        10.10.0.15) echo "redis-node-5" ;;
        10.10.0.16) echo "redis-node-6" ;;
    esac
}

get_ssh_port() {
    case "$1" in
        10.10.0.11) echo "2221" ;;
        10.10.0.12) echo "2222" ;;
        10.10.0.13) echo "2223" ;;
        10.10.0.14) echo "2224" ;;
        10.10.0.15) echo "2225" ;;
        10.10.0.16) echo "2226" ;;
    esac
}

REDIS_PORT=6379
SSH_HOST="127.0.0.1"
REDIS_CLI_KEY="$HOME/.ssh-redis-tool/id_rsa"
MIN_ANSIBLE_VERSION="2.14.0"