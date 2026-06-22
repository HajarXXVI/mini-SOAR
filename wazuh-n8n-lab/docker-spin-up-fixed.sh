#!/usr/bin/env bash
set -euo pipefail
sudo apt install git

# 0) Check and create the shared network if it doesn't exist
if ! sudo docker network ls | grep -q "soc-net"; then
    echo "Creating soc-net network..."
    sudo docker network create soc-net
else
    echo "soc-net network already exists"
fi

# 1) Kernel setting required by OpenSearch
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
sudo sysctl --system

# 2) Get Wazuh (single-node) at latest stable version
if [ ! -d "wazuh-docker" ]; then
    git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.5
fi
cd wazuh-docker/single-node

# 3) Clean up any existing containers and volumes
docker compose down -v 2>/dev/null || true

# 4) Generate fresh Indexer certs
if [ -d "./config/wazuh_indexer_ssl_certs" ]; then
    rm -rf ./config/wazuh_indexer_ssl_certs
fi
docker compose -f generate-indexer-certs.yml run --rm generator

# 5) Update configuration files for v4.14.5
curl -sL https://raw.githubusercontent.com/wazuh/wazuh-docker/v4.14.5/single-node/config/wazuh_cluster/wazuh_manager.conf > ./config/wazuh_cluster/wazuh_manager.conf

# 6) Bring up Wazuh stack
docker compose up -d

# 7) Wait for services to be ready
echo "Waiting for Wazuh services to be ready..."
sleep 30

# 8) Verify services are running
docker compose ps

# 9) Ensure Wazuh services are connected to the shared network
for s in wazuh.manager wazuh.indexer wazuh.dashboard; do
    container_name="single-node-$s-1"
    if ! docker network inspect soc-net | grep -q "$container_name"; then
        echo "Connecting $container_name to soc-net..."
        docker network connect soc-net "$container_name"
    else
        echo "$container_name already connected to soc-net"
    fi
done

# 10) Spin up n8n if not already running
cd ../../n8n-docker
if ! docker ps -a | grep -q "n8n"; then
    docker compose up -d
else
    echo "n8n container already exists"
fi

echo "Setup complete! Access Wazuh Dashboard at: https://localhost:443"
echo "Access n8n at: http://localhost:5678"
