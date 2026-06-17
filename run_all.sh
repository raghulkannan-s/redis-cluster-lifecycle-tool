#!/bin/bash
set -e
set -o pipefail

mkdir -p output

echo "Running setup..."
./redis-tool setup --force

echo "Running provision..."
./redis-tool provision --version 7.0.15 --masters 3 --replicas-per-master 1

echo "Running seed..."
./redis-tool data seed --keys 1000

echo "Running status..."
./redis-tool status

echo "Running upgrade..."
./redis-tool upgrade --target-version 7.2.6 --strategy rolling

echo "Running verify after upgrade..."
./redis-tool data verify --keys 1000

echo "Running full verification..."
./redis-tool verify --full

echo "ALL DONE!"

echo ""
echo "Output Directory Contents:"
if command -v tree >/dev/null 2>&1; then
    tree output/
else
    ls -lh output/
fi
