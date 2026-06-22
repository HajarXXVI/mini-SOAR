#!/usr/bin/env bash
set -euo pipefail

# ARM64-specific Wazuh installation script for Oracle Cloud
# Tested on Ubuntu ARM64 (aarch64) with Ampere CPUs

echo "🔧 ARM64 Wazuh Installation for Oracle Cloud"
echo "============================================"

# Verify ARM64 architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "❌ ERROR: This script is designed for ARM64 (aarch64) architecture."
    echo "   Current architecture: $ARCH"
    exit 1
fi

echo "✅ Verified ARM64 architecture: $ARCH"

# Install dependencies for ARM64
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates gnupg lsb-release

# Install Docker with ARM64 support
echo "🐳 Installing Docker for ARM64..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository for ARM64
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    echo "✅ Docker already installed"
fi

# Add user to docker group
sudo usermod -aG docker $USER
echo "✅ Added user to docker group"

# Configure kernel settings for ARM64
echo "⚙️  Configuring kernel settings for ARM64..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
sudo sysctl --system

# Create shared network
echo "🌐 Creating Docker network..."
if ! docker network ls | grep -q "soc-net"; then
    docker network create soc-net
    echo "✅ Created soc-net network"
else
    echo "✅ soc-net network already exists"
fi

# Get ARM64-compatible Wazuh (v4.14.5 has full ARM64 support)
echo "📦 Cloning Wazuh Docker repository (ARM64 compatible)..."
if [ ! -d "wazuh-docker" ]; then
    git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.5
else
    echo "✅ Wazuh repository already exists"
fi

cd wazuh-docker/single-node

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker compose down -v 2>/dev/null || true

# Generate certificates with ARM64-compatible generator
echo "🔐 Generating SSL certificates for ARM64..."
if [ -d "./config/wazuh_indexer_ssl_certs" ]; then
    rm -rf ./config/wazuh_indexer_ssl_certs
fi

# Use the updated certificate generator that supports ARM64
docker compose -f generate-indexer-certs.yml run --rm generator

# Update configuration files for ARM64
echo "⚙️  Updating configuration for ARM64..."
curl -sL https://raw.githubusercontent.com/wazuh/wazuh-docker/v4.14.5/single-node/config/wazuh_cluster/wazuh_manager.conf > ./config/wazuh_cluster/wazuh_manager.conf

# Pull ARM64-compatible images
echo "📥 Pulling ARM64-compatible Docker images..."
docker compose pull

# Start Wazuh stack
echo "🚀 Starting Wazuh stack on ARM64..."
docker compose up -d

# Wait for services to be ready (longer for ARM64)
echo "⏳ Waiting for Wazuh services to initialize (ARM64 requires more time)..."
sleep 60

# Check service status
echo "🔍 Checking service status..."
docker compose ps

# Connect to shared network
echo "🌐 Connecting services to shared network..."
for s in wazuh.manager wazuh.indexer wazuh.dashboard; do
    container_name="single-node-$s-1"
    if docker network inspect soc-net | grep -q "$container_name"; then
        echo "✅ $container_name already connected to soc-net"
    else
        echo "🔗 Connecting $container_name to soc-net..."
        docker network connect soc-net "$container_name"
    fi
done

# Deploy n8n with ARM64 support
echo "🔄 Deploying n8n with ARM64 support..."
cd ../../n8n-docker

# Update n8n docker-compose for ARM64 if needed
cat > docker-compose.yml << 'EOF'
version: "3.9"
services:
  n8n:
    image: n8nio/n8n:latest
    platform: linux/arm64
    restart: always
    ports:
      - "5678:5678"
    environment:
      - GENERIC_TIMEZONE=UTC
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - soc-net

volumes:
  n8n_data:

networks:
  soc-net:
    external: true
EOF

# Start n8n
docker compose up -d

# Final verification
echo "🎉 ARM64 Wazuh + n8n deployment complete!"
echo ""
echo "📋 Access Information:"
echo "   Wazuh Dashboard: https://localhost:443"
echo "   Default credentials: admin/SecretPassword"
echo "   n8n Interface:  http://localhost:5678"
echo ""
echo "🔧 Troubleshooting Commands:"
echo "   Check logs: docker compose -f wazuh-docker/single-node/docker-compose.yml logs -f"
echo "   Check status: docker compose -f wazuh-docker/single-node/docker-compose.yml ps"
echo ""
echo "⚠️  Note: ARM64 may require 2-3 minutes for full initialization"
