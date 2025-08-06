#!/bin/bash

# VM Helper Script for Azure CNI Demo
# This script provides convenient functions for interacting with the external workload VM

set -e

RESOURCE_GROUP=${RESOURCE_GROUP:-$(az group list --query "[?starts_with(name, 'aks-cni-demo-rg')].name" --output tsv | head -1)}
VM_NAME="external-workload"

if [ -z "$RESOURCE_GROUP" ]; then
    echo "No resource group found matching 'aks-cni-demo-rg*'. Please set RESOURCE_GROUP environment variable."
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Execute command on VM
vm_exec() {
    local command="$1"
    local description="${2:-Running command on VM}"
    
    print_status "$description"
    az vm run-command invoke \
        --resource-group $RESOURCE_GROUP \
        --name $VM_NAME \
        --command-id RunShellScript \
        --scripts "$command" \
        --output tsv \
        --query 'value[0].message' 2>/dev/null || echo "Command failed"
}

# Get VM status and info
vm_status() {
    print_status "VM Status Information"
    
    if ! az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME >/dev/null 2>&1; then
        print_error "VM not found"
        return 1
    fi
    
    local vm_state=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query provisioningState --output tsv)
    local vm_ip=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --query privateIps --output tsv)
    local vm_size=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query hardwareProfile.vmSize --output tsv)
    
    echo "VM Name: $VM_NAME"
    echo "State: $vm_state"
    echo "Private IP: $vm_ip"
    echo "Size: $vm_size"
    echo "Resource Group: $RESOURCE_GROUP"
}

# Test network connectivity from VM
vm_network_test() {
    local target_ip="$1"
    local target_port="${2:-80}"
    local description="${3:-Network connectivity test}"
    
    print_status "$description"
    
    vm_exec "
        echo 'Testing connectivity to $target_ip:$target_port'
        echo '--- Ping Test ---'
        ping -c 3 $target_ip 2>/dev/null || echo 'Ping failed'
        echo '--- Port Test ---'
        nc -zv $target_ip $target_port 2>&1 || echo 'Port test failed'
        echo '--- HTTP Test (if port 80/443/8080) ---'
        if echo '$target_port' | grep -E '^(80|443|8080)$' >/dev/null; then
            curl -s -m 10 http://$target_ip:$target_port || echo 'HTTP test failed'
        fi
    " "Testing connectivity to $target_ip:$target_port"
}

# Install additional tools on VM
vm_install_tools() {
    print_status "Installing additional network tools on VM"
    
    vm_exec "
        sudo apt-get update -y
        sudo apt-get install -y iperf3 nmap tcpdump wireshark-common hping3 mtr-tiny
        echo 'Additional tools installed successfully'
    " "Installing additional network tools"
}

# Get comprehensive network info from VM
vm_network_info() {
    print_status "Getting comprehensive network information from VM"
    
    vm_exec "
        echo '=== Network Interfaces ==='
        ip addr show
        echo ''
        echo '=== Routing Table ==='
        ip route show
        echo ''
        echo '=== ARP Table ==='
        arp -a
        echo ''
        echo '=== DNS Configuration ==='
        cat /etc/resolv.conf
        echo ''
        echo '=== Active Connections ==='
        ss -tuln
        echo ''
        echo '=== Network Statistics ==='
        cat /proc/net/dev
    " "Getting network information"
}

# Test HTTP connectivity with detailed output
vm_http_test() {
    local url="$1"
    local description="${2:-HTTP connectivity test}"
    
    vm_exec "
        echo 'Testing HTTP connectivity to: $url'
        echo '--- Basic curl test ---'
        curl -s -w 'HTTP Code: %{http_code}\nTotal Time: %{time_total}s\nConnect Time: %{time_connect}s\nRemote IP: %{remote_ip}\n' '$url' || echo 'HTTP test failed'
        echo ''
        echo '--- Headers test ---'
        curl -s -I '$url' || echo 'Headers test failed'
    " "$description"
}

# Trace route to target
vm_traceroute() {
    local target="$1"
    local description="${2:-Traceroute test}"
    
    vm_exec "
        echo 'Traceroute to: $target'
        traceroute -n $target 2>/dev/null || echo 'Traceroute failed'
    " "$description"
}

# Performance test with iperf3
vm_iperf_test() {
    local server_ip="$1"
    local port="${2:-5201}"
    local duration="${3:-10}"
    
    vm_exec "
        echo 'iPerf3 performance test to $server_ip:$port for ${duration}s'
        iperf3 -c $server_ip -p $port -t $duration 2>/dev/null || echo 'iPerf3 test failed (server may not be running)'
    " "Performance test with iPerf3"
}

# Start simple HTTP server on VM
vm_start_server() {
    local port="${1:-8080}"
    
    vm_exec "
        # Kill any existing server
        pkill -f 'python3.*http.server' 2>/dev/null || true
        
        # Start new server in background
        nohup python3 -m http.server $port > /tmp/http-server.log 2>&1 &
        echo 'HTTP server started on port $port'
        echo 'Server PID:' \$(pgrep -f 'python3.*http.server')
    " "Starting HTTP server on port $port"
}

# Stop HTTP server on VM
vm_stop_server() {
    vm_exec "
        pkill -f 'python3.*http.server' && echo 'HTTP server stopped' || echo 'No HTTP server running'
    " "Stopping HTTP server"
}

# DNS lookup test
vm_dns_test() {
    local hostname="$1"
    local description="${2:-DNS lookup test}"
    
    vm_exec "
        echo 'DNS lookup for: $hostname'
        echo '--- nslookup ---'
        nslookup $hostname
        echo '--- dig ---'
        dig $hostname +short
    " "$description"
}

# Main function
main() {
    local action="$1"
    shift
    
    case $action in
        "status")
            vm_status
            ;;
        "exec")
            vm_exec "$1" "$2"
            ;;
        "network-test")
            vm_network_test "$1" "$2" "$3"
            ;;
        "network-info")
            vm_network_info
            ;;
        "http-test")
            vm_http_test "$1" "$2"
            ;;
        "traceroute")
            vm_traceroute "$1" "$2"
            ;;
        "iperf")
            vm_iperf_test "$1" "$2" "$3"
            ;;
        "start-server")
            vm_start_server "$1"
            ;;
        "stop-server")
            vm_stop_server
            ;;
        "dns-test")
            vm_dns_test "$1" "$2"
            ;;
        "install-tools")
            vm_install_tools
            ;;
        *)
            echo "Usage: $0 {status|exec|network-test|network-info|http-test|traceroute|iperf|start-server|stop-server|dns-test|install-tools}"
            echo ""
            echo "Examples:"
            echo "  $0 status                              # Get VM status"
            echo "  $0 network-info                        # Get comprehensive network info"
            echo "  $0 network-test 10.1.0.4 80           # Test connectivity to IP:port"
            echo "  $0 http-test http://example.com        # Test HTTP connectivity"
            echo "  $0 traceroute 8.8.8.8                 # Traceroute to target"
            echo "  $0 dns-test google.com                 # DNS lookup test"
            echo "  $0 start-server 8080                   # Start HTTP server on port"
            echo "  $0 exec 'ls -la' 'List files'         # Execute custom command"
            exit 1
            ;;
    esac
}

main "$@"
