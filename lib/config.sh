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

declare -A NODE_NAME=(
    [10.10.0.11]="redis-node-1"
    [10.10.0.12]="redis-node-2"
    [10.10.0.13]="redis-node-3"
    [10.10.0.14]="redis-node-4"
    [10.10.0.15]="redis-node-5"
    [10.10.0.16]="redis-node-6"
)

# Port-forwarded SSH: internal container IP -> host port (rootless Podman / Docker)
declare -A NODE_SSH_PORT=(
    [10.10.0.11]=2221
    [10.10.0.12]=2222
    [10.10.0.13]=2223
    [10.10.0.14]=2224
    [10.10.0.15]=2225
    [10.10.0.16]=2226
)

REDIS_PORT=6379
SSH_HOST="127.0.0.1"
REDIS_CLI_KEY="$HOME/.ssh-redis-tool/id_rsa"
MIN_ANSIBLE_VERSION="2.14.0"