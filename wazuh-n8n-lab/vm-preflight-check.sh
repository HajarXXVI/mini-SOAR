#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Oracle Cloud ARM64 VM Pre-Flight Check"
echo "======================================"

# Check architecture
ARCH=$(uname -m)
echo "📋 Architecture: $ARCH"
if [ "$ARCH" != "aarch64" ]; then
    echo "❌ WARNING: This script is optimized for ARM64 (aarch64)"
    echo "   Current: $ARCH"
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "📋 OS: $NAME $VERSION"
fi

# Check memory
MEMORY=$(free -h | awk '/^Mem:/ {print $2}')
echo "📋 Memory: $MEMORY"

# Check disk space
DISK=$(df -h / | awk 'NR==2 {print $4}')
echo "📋 Available Disk: $DISK"

# Check if Docker is installed
if command -v docker &> /dev/null; then
    echo "✅ Docker is installed"
    docker --version
else
    echo "❌ Docker is NOT installed"
fi

# Check if Docker Compose is available
if docker compose version &> /dev/null; then
    echo "✅ Docker Compose is available"
    docker compose version
else
    echo "❌ Docker Compose is NOT available"
fi

# Check if ports are available
echo ""
echo "🔍 Port Availability Check:"
for port in 443 5678 9200 1514 1515 1516; do
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "❌ Port $port is already in use"
    else
        echo "✅ Port $port is available"
    fi
done

# Check kernel settings
echo ""
echo "🔍 Kernel Settings:"
MAX_MAP=$(sysctl vm.max_map_count 2>/dev/null | awk '{print $3}')
if [ "$MAX_MAP" = "262144" ]; then
    echo "✅ vm.max_map_count is correctly set to $MAX_MAP"
else
    echo "⚠️  vm.max_map_count is $MAX_MAP (should be 262144)"
    echo "   Run: sudo sysctl -w vm.max_map_count=262144"
fi

# Check firewall status
echo ""
echo "🔍 Firewall Status:"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    echo "UFW: $UFW_STATUS"
fi

if command -v firewall-cmd &> /dev/null; then
    FW_STATUS=$(firewall-cmd --state 2>/dev/null || echo "not running")
    echo "Firewalld: $FW_STATUS"
fi

# Check Oracle Cloud specific settings
echo ""
echo "🔍 Oracle Cloud Specific Checks:"

# Check if we're in Oracle Cloud
if dmesg | grep -qi "oracle" || dmidecode 2>/dev/null | grep -qi "oracle"; then
    echo "✅ Detected Oracle Cloud environment"
    
    # Check for Oracle's agent
    if systemctl is-active --quiet oracle-cloud-agent; then
        echo "✅ Oracle Cloud Agent is running"
    else
        echo "⚠️  Oracle Cloud Agent not detected"
    fi
else
    echo "ℹ️  Not in Oracle Cloud environment (or couldn't detect)"
fi

# Check swap space (important for ARM64)
echo ""
echo "🔍 Swap Space:"
SWAP=$(free -h | awk '/^Swap:/ {print $2}')
if [ "$SWAP" = "0B" ]; then
    echo "⚠️  No swap space detected (recommended for ARM64)"
    echo "   Consider adding swap: sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
else
    echo "✅ Swap space: $SWAP"
fi

# Internet connectivity test
echo ""
echo "🔍 Internet Connectivity:"
if curl -s --connect-timeout 5 https://github.com > /dev/null; then
    echo "✅ GitHub connectivity OK"
else
    echo "❌ Cannot reach GitHub (check firewall/proxy)"
fi

if curl -s --connect-timeout 5 https://registry-1.docker.io > /dev/null; then
    echo "✅ Docker Hub connectivity OK"
else
    echo "❌ Cannot reach Docker Hub (check firewall/proxy)"
fi

# Recommendations
echo ""
echo "💡 Recommendations:"
echo "1. Ensure Oracle Cloud Security List allows ports: 443, 5678, 9200"
echo "2. Configure Ubuntu firewall if needed"
echo "3. Consider adding swap space for better ARM64 performance"
echo "4. Use the ARM64-optimized installation script"

echo ""
echo "✅ Pre-flight check complete!"
