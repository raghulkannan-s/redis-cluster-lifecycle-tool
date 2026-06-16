SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ANSIBLE_DIR="$SCRIPT_DIR/ansible"

REDIS_CLI_KEY="$HOME/.ssh-redis-tool/id_rsa"

REDIS_PORT=6379

NODE1_IP="10.55.0.11"

ALL_IPS=(
    10.55.0.11
    10.55.0.12
    10.55.0.13
    10.55.0.14
    10.55.0.15
    10.55.0.16
)