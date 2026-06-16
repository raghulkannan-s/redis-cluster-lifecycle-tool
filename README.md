# Redis Cluster Lifecycle Tool

A CLI tool built with Bash and Ansible to provision, manage, verify, and perform zero-downtime rolling upgrades of a Redis Cluster.

## Overview

The project manages a 6-node Redis Cluster:

* 3 Master nodes
* 3 Replica nodes
* SSH-based management through Ansible
* Containerized infrastructure using Podman or Docker

The host machine acts as the Ansible control node and all cluster operations are executed through the `redis-tool` CLI.

## Infrastructure Setup

Start the infrastructure:

```bash
cd infra

# Docker
docker compose up -d
```

Verify the containers are running:


```bash
docker ps
```

## Commands

### Provision Redis Cluster

```bash
./redis-tool provision --version 7.0.15
```

Installs Redis, configures cluster mode, starts Redis on all nodes, and forms a 3-master / 3-replica cluster.

### Seed Test Data

```bash
./redis-tool data seed --keys 1000
```

Generates 1000 deterministic key-value pairs and inserts them into the cluster.

### Verify Data Integrity

```bash
./redis-tool data verify
```

Reads all keys back and verifies their values.

### View Cluster Status

```bash
./redis-tool status
```

Displays:

* Cluster state
* Node roles
* Redis versions
* Slot allocation
* Key counts
* Memory usage
* Replication relationships

### Rolling Upgrade

```bash
./redis-tool upgrade --target-version 7.2.6 --strategy rolling
```

Performs a zero-downtime rolling upgrade.

Upgrade process:

1. Run pre-flight checks
2. Upgrade replicas one at a time
3. Fail over each master to its upgraded replica
4. Upgrade the old master
5. Verify cluster health after every step
6. Run post-upgrade validation

### Full Verification

```bash
./redis-tool verify --full
```

Checks:

* Data integrity
* Version consistency
* Cluster topology
* Cluster state
* Replication health

## Idempotency

* Running `provision` on an already healthy cluster does not recreate it.
* Running `upgrade` when all nodes are already on the target version exits cleanly.

## Assumptions

* Fixed 6-node topology
* 3 masters and 3 replicas
* One replica per master
* Static container IP addresses
* SSH key authentication
* 
## Known Limitations

* No scale-out support
* No scale-in support
* Rollback support is experimental and not fully validated across Redis versions
  
## Output Files

Generate submission artifacts:

```bash
mkdir -p output

./redis-tool provision > output/provision_output.txt
./redis-tool data seed --keys 1000 > output/data_seed_output.txt
./redis-tool status > output/status_output.txt
./redis-tool upgrade --target-version 7.2.6 --strategy rolling > output/upgrade_output.txt
./redis-tool verify --full > output/verify_output.txt
```

Additional Features

- Idempotent provisioning
- Idempotent upgrades
- Structured operation logging
- Full cluster verification
