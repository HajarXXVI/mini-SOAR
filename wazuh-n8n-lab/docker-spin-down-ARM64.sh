#!/usr/bin/env bash
set -euo pipefail

echo "🛑 ARM64 Wazuh + n8n Shutdown Script"
echo "===================================="

# Stop Wazuh stack
if [ -d "wazuh-docker/single-node" ]; then
    echo "🔄 Stopping Wazuh stack..."
    cd wazuh-docker/single-node
    docker compose down -v 2>/dev/null || true
    echo "✅ Wazuh stack stopped"
    cd ../../
else
    echo "⚠️  Wazuh directory not found"
fi

# Stop n8n
if [ -d "n8n-docker" ]; then
    echo "🔄 Stopping n8n..."
    cd n8n-docker
    docker compose down 2>/dev/null || true
    echo "✅ n8n stopped"
    cd ..
else
    echo "⚠️  n8n directory not found"
fi

# Clean up containers
echo "🧹 Cleaning up any remaining containers..."
docker container prune -f 2>/dev/null || true

# Clean up networks (except default ones)
echo "🌐 Cleaning up custom networks..."
docker network prune -f 2>/dev/null || true

echo "✅ ARM64 shutdown complete!"
