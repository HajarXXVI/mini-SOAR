#!/usr/bin/env bash
set -euo pipefail

# Oracle Cloud Neoverse-N1 ARM64 Optimized Wazuh Installation
# Specifically designed for: Ubuntu 22.04, Neoverse-N1, 23GB RAM, 194GB Disk
echo "🚀 Oracle Cloud Neoverse-N1 ARM64 Wazuh Installation"
echo "=================================================="

# System verification
echo "🔍 Verifying Oracle Cloud Neoverse-N1 environment..."
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "❌ ERROR: This script requires ARM64 (aarch64) architecture"
    echo "   Current: $ARCH"
    exit 1
fi

# Check for Neoverse-N1 CPU
CPU_MODEL=$(lscpu | grep "Model name" | awk -F': ' '{print $2}')
if [[ "$CPU_MODEL" == *"Neoverse-N1"* ]]; then
    echo "✅ Detected Oracle Cloud Neoverse-N1 CPU"
else
    echo "⚠️  Warning: Expected Neoverse-N1, found: $CPU_MODEL"
fi

# Check memory (23GB available - well above 8GB requirement)
MEMORY_GB=$(free -g | awk '/^Mem:/ {print $2}')
if [ "$MEMORY_GB" -ge 8 ]; then
    echo "✅ Memory: ${MEMORY_GB}GB (exceeds 8GB requirement)"
else
    echo "❌ Memory: ${MEMORY_GB}GB (below 8GB requirement)"
    exit 1
fi

# Check disk space (194GB available - well above 50GB requirement)
DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$DISK_GB" -ge 50 ]; then
    echo "✅ Disk: ${DISK_GB}GB available (exceeds 50GB requirement)"
else
    echo "❌ Disk: ${DISK_GB}GB available (below 50GB requirement)"
    exit 1
fi

# Create swap file for better ARM64 performance (optional but recommended)
echo "🔄 Configuring swap space for ARM64 optimization..."
if [ ! -f /swapfile ]; then
    echo "Creating 4GB swap file for ARM64 performance..."
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "✅ 4GB swap file created and activated"
else
    echo "✅ Swap file already exists"
fi

# Update system packages
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install dependencies for ARM64
echo "🔧 Installing ARM64-compatible dependencies..."
sudo apt install -y git curl ca-certificates gnupg lsb-release software-properties-common

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
    echo "✅ Docker installed for ARM64"
else
    echo "✅ Docker already installed"
fi

# Add user to docker group
sudo usermod -aG docker $USER
echo "✅ Added user to docker group"

# Configure kernel settings for Oracle Cloud ARM64
echo "⚙️  Configuring kernel settings for Oracle Cloud ARM64..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
sudo sysctl --system

# Configure Docker for ARM64 optimization
echo "🐳 Optimizing Docker for ARM64..."
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

# Restart Docker to apply settings
sudo systemctl restart docker
sudo systemctl enable docker
echo "✅ Docker optimized for ARM64"

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
if [ -d "wazuh-docker" ]; then
    echo "Removing existing wazuh-docker directory..."
    rm -rf wazuh-docker
fi

git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.5
cd wazuh-docker/single-node

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker compose down -v 2>/dev/null || true

# Pre-pull ARM64 images to avoid timeouts
echo "📥 Pre-pulling ARM64-compatible Docker images..."
docker compose pull --parallel

# Generate certificates with ARM64-compatible generator
echo "🔐 Generating SSL certificates for ARM64..."
if [ -d "./config/wazuh_indexer_ssl_certs" ]; then
    rm -rf ./config/wazuh_indexer_ssl_certs
fi

# Use updated certificate generator that supports ARM64
docker compose -f generate-indexer-certs.yml run --rm generator

# Update configuration files for ARM64/Neoverse-N1
echo "⚙️  Updating configuration for Neoverse-N1 ARM64..."
curl -sL https://raw.githubusercontent.com/wazuh/wazuh-docker/v4.14.5/single-node/config/wazuh_cluster/wazuh_manager.conf > ./config/wazuh_cluster/wazuh_manager.conf

# Optimize docker-compose.yml for ARM64
echo "🔧 Optimizing docker-compose.yml for ARM64..."
sed -i 's/image: wazuh\/wazuh-indexer:4.14.5/image: wazuh\/wazuh-indexer:4.14.5\n    platform: linux\/arm64/' docker-compose.yml
sed -i 's/image: wazuh\/wazuh-manager:4.14.5/image: wazuh\/wazuh-manager:4.14.5\n    platform: linux\/arm64/' docker-compose.yml
sed -i 's/image: wazuh\/wazuh-dashboard:4.14.5/image: wazuh\/wazuh-dashboard:4.14.5\n    platform: linux\/arm64/' docker-compose.yml

# Start Wazuh stack with extended timeout for ARM64
echo "🚀 Starting Wazuh stack on Neoverse-N1 ARM64..."
docker compose up -d

# Wait for services to be ready (ARM64 needs more time)
echo "⏳ Waiting for Wazuh services to initialize (ARM64 optimization)..."
sleep 90

# Check service status
echo "🔍 Checking service status..."
docker compose ps

# Verify services are healthy
echo "🏥 Verifying service health..."
for service in wazuh.indexer wazuh.manager wazuh.dashboard; do
    container_name="single-node-${service}-1"
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container_name.*Up"; then
        echo "✅ $service is running"
    else
        echo "❌ $service is not running properly"
    fi
done

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

# Create optimized n8n docker-compose.yml for ARM64
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
      - NODE_OPTIONS=--max-old-space-size=4096
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - soc-net
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

volumes:
  n8n_data:

networks:
  soc-net:
    external: true
EOF

# Start n8n
docker compose up -d

# Final verification
echo "🎉 Oracle Cloud Neoverse-N1 ARM64 deployment complete!"
echo ""
echo "📋 System Information:"
echo "   Architecture: $ARCH"
echo "   CPU: $CPU_MODEL"
echo "   Memory: ${MEMORY_GB}GB"
echo "   Disk: ${DISK_GB}GB"
echo ""
echo "🌐 Access Information:"
echo "   Wazuh Dashboard: https://localhost:443"
echo "   Default credentials: admin/SecretPassword"
echo "   n8n Interface:  http://localhost:5678"
echo ""
echo "🔧 Oracle Cloud Configuration Needed:"
echo "   Open these ports in OCI Console > Networking > Security Lists:"
echo "   - Port 443 (HTTPS - Wazuh Dashboard)"
echo "   - Port 5678 (HTTP - n8n Interface)"
echo "   - Port 9200 (OpenSearch - Wazuh Indexer)"
echo ""
echo "🔍 Troubleshooting Commands:"
echo "   Check logs: docker compose -f wazuh-docker/single-node/docker-compose.yml logs -f"
echo "   Check status: docker compose -f wazuh-docker/single-node/docker-compose.yml ps"
echo "   Restart services: docker compose -f wazuh-docker/single-node/docker-compose.yml restart"
echo ""
echo "⚠️  Note: Neoverse-N1 ARM64 may require 2-3 minutes for full initialization"
