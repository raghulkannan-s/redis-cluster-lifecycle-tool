#!/bin/bash
set -e

mkdir -p output

echo "Running setup..."
./redis-tool setup --force

echo "Running provision..."
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1 | tee output/provision_output.txt

echo "Running seed..."
./redis-tool data seed --keys 1000 | tee output/data_seed_output.txt

echo "Running status..."
./redis-tool status | tee output/status_output.txt

echo "Running upgrade..."
./redis-tool upgrade --target-version 7.2.6 --strategy rolling | tee output/upgrade_output.txt

echo "Running verify after upgrade..."
./redis-tool data verify --keys 1000

echo "Running full verification..."
./redis-tool verify --full | tee output/verify_output.txt

echo "ALL DONE!"
