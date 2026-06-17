# Network and cluster topology (must match infra/compose.yml and ansible/inventory/hosts.ini)
NETWORK_SUBNET="172.25.0.0/24"
NODE1_IP="172.25.0.11"

ALL_IPS=(
    172.25.0.11
    172.25.0.12
    172.25.0.13
    172.25.0.14
    172.25.0.15
    172.25.0.16
)

MASTER_IPS=(
    172.25.0.11
    172.25.0.12
    172.25.0.13
)

REPLICA_IPS=(
    172.25.0.14
    172.25.0.15
    172.25.0.16
)

get_node_name() {
    case "$1" in
        172.25.0.11) echo "redis-node-1" ;;
        172.25.0.12) echo "redis-node-2" ;;
        172.25.0.13) echo "redis-node-3" ;;
        172.25.0.14) echo "redis-node-4" ;;
        172.25.0.15) echo "redis-node-5" ;;
        172.25.0.16) echo "redis-node-6" ;;
    esac
}

get_ssh_port() {
    case "$1" in
        172.25.0.11) echo "2221" ;;
        172.25.0.12) echo "2222" ;;
        172.25.0.13) echo "2223" ;;
        172.25.0.14) echo "2224" ;;
        172.25.0.15) echo "2225" ;;
        172.25.0.16) echo "2226" ;;
    esac
}

REDIS_PORT=6379
SSH_HOST="127.0.0.1"
REDIS_CLI_KEY="$HOME/.ssh-redis-tool/id_rsa"
MIN_ANSIBLE_VERSION="2.14.0"