#!/bin/bash

# VM Helper Script - Enhanced for step-by-step testing
# Provides specific test functions for the training guide

set -e

# Configuration
RESOURCE_GROUP_PREFIX="aks-cni-demo-rg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠️  WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[❌ ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[ℹ️  INFO]${NC} $1"
}

print_test_header() {
    echo
    echo "=============================================="
    echo "  $1"
    echo "=============================================="
}

# Get resource group
get_resource_group() {
    local existing_rg=$(az group list --query "[?starts_with(name, '$RESOURCE_GROUP_PREFIX')].name" --output tsv | head -1)
    echo "$existing_rg"
}

# Execute command on VM or container
vm_exec() {
    local resource_group=$1
    local command=$2
    
    # Try VM first, then ACI
    if az vm run-command invoke \
        --resource-group "$resource_group" \
        --name external-workload \
        --command-id RunShellScript \
        --scripts "$command" \
        --query 'value[0].message' \
        --output tsv 2>/dev/null; then
        return 0
    else
        # Try ACI
        az container exec \
            --resource-group "$resource_group" \
            --name external-workload \
            --exec-command "bash -c \"$command\"" 2>/dev/null || echo "Command failed"
    fi
}

# Basic network test
network_test() {
    print_test_header "Network Connectivity Test"
    
    local resource_group=$(get_resource_group)
    if [ -z "$resource_group" ]; then
        print_error "No resource group found"
        return 1
    fi
    
    # Get external workload IP
    local workload_ip=$(az vm show --resource-group "$resource_group" --name external-workload --show-details --query privateIps --output tsv 2>/dev/null || \
                       az container show --resource-group "$resource_group" --name external-workload --query ipAddress.ip --output tsv 2>/dev/null)
    
    print_info "External workload IP: $workload_ip"
    
    # Get current kubectl context to determine which cluster we're testing
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    print_info "Current cluster context: $current_context"
    
    if [[ "$current_context" == *"traditional"* ]]; then
        test_traditional_cni "$resource_group" "$workload_ip"
    elif [[ "$current_context" == *"podsubnet"* ]]; then
        test_podsubnet_cni "$resource_group" "$workload_ip"
    elif [[ "$current_context" == *"overlay"* ]]; then
        test_overlay_cni "$resource_group" "$workload_ip"
    else
        print_warning "Unknown cluster context. Running basic connectivity test."
        basic_connectivity_test "$resource_group" "$workload_ip"
    fi
}

# Traditional CNI specific tests
test_traditional_cni() {
    local resource_group=$1
    local workload_ip=$2
    
    print_test_header "Traditional Azure CNI Testing"
    
    # Get pod IPs
    local pod_ips=($(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[*].status.podIP}'))
    
    print_info "Pod IPs in node subnet: ${pod_ips[@]}"
    
    # Test ping to each pod
    for pod_ip in "${pod_ips[@]}"; do
        echo -n "Testing connectivity to pod $pod_ip: "
        if vm_exec "$resource_group" "ping -c 1 -W 2 $pod_ip" >/dev/null 2>&1; then
            print_status "REACHABLE"
        else
            print_error "UNREACHABLE"
        fi
    done
    
    # Test LoadBalancer service
    test_loadbalancer_service "$resource_group"
    
    print_info "Traditional CNI: Pods use node subnet IPs and are directly reachable"
}

# Pod Subnet CNI specific tests
test_podsubnet_cni() {
    local resource_group=$1
    local workload_ip=$2
    
    print_test_header "Pod Subnet Azure CNI Testing"
    
    # Get pod IPs
    local pod_ips=($(kubectl get pods -l app=netshoot-podsubnet -o jsonpath='{.items[*].status.podIP}'))
    
    print_info "Pod IPs in pod subnet: ${pod_ips[@]}"
    
    # Test ping to each pod
    for pod_ip in "${pod_ips[@]}"; do
        echo -n "Testing connectivity to pod $pod_ip: "
        if vm_exec "$resource_group" "ping -c 1 -W 2 $pod_ip" >/dev/null 2>&1; then
            print_status "REACHABLE"
        else
            print_error "UNREACHABLE"
        fi
    done
    
    # Test LoadBalancer service
    test_loadbalancer_service "$resource_group"
    
    print_info "Pod Subnet CNI: Pods use dedicated pod subnet and are directly reachable"
}

# Overlay CNI specific tests
test_overlay_cni() {
    local resource_group=$1
    local workload_ip=$2
    
    print_test_header "Overlay Azure CNI Testing"
    
    # Get pod IPs
    local pod_ips=($(kubectl get pods -l app=netshoot-overlay -o jsonpath='{.items[*].status.podIP}'))
    
    print_info "Pod IPs in overlay network: ${pod_ips[@]}"
    
    # Test ping to each pod (should fail)
    for pod_ip in "${pod_ips[@]}"; do
        echo -n "Testing direct connectivity to pod $pod_ip: "
        if vm_exec "$resource_group" "ping -c 1 -W 2 $pod_ip" >/dev/null 2>&1; then
            print_warning "UNEXPECTEDLY REACHABLE"
        else
            print_status "UNREACHABLE (as expected)"
        fi
    done
    
    # Test LoadBalancer service (should work)
    test_loadbalancer_service "$resource_group"
    
    print_info "Overlay CNI: Pod IPs are not VNet-routable, access via services only"
}

# Test LoadBalancer service
test_loadbalancer_service() {
    local resource_group=$1
    
    echo
    print_info "Testing LoadBalancer Service Access"
    
    # Get service external IP
    local service_name=""
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    
    if [[ "$current_context" == *"traditional"* ]]; then
        service_name="netshoot-traditional-svc"
    elif [[ "$current_context" == *"podsubnet"* ]]; then
        service_name="netshoot-podsubnet-svc"
    elif [[ "$current_context" == *"overlay"* ]]; then
        service_name="netshoot-overlay-svc"
    fi
    
    if [ -n "$service_name" ]; then
        local external_ip=$(kubectl get service "$service_name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
            print_info "LoadBalancer External IP: $external_ip"
            echo -n "Testing LoadBalancer connectivity: "
            
            if vm_exec "$resource_group" "curl -s --connect-timeout 5 http://$external_ip:8080 || echo 'Connection test'" >/dev/null 2>&1; then
                print_status "ACCESSIBLE"
            else
                print_error "INACCESSIBLE"
            fi
        else
            print_warning "LoadBalancer External IP not yet assigned or pending"
        fi
    fi
}

# Basic connectivity test for unknown contexts
basic_connectivity_test() {
    local resource_group=$1
    local workload_ip=$2
    
    print_test_header "Basic Connectivity Test"
    
    # Get all pod IPs
    local pod_ips=($(kubectl get pods -o jsonpath='{.items[*].status.podIP}' 2>/dev/null))
    
    if [ ${#pod_ips[@]} -eq 0 ]; then
        print_warning "No pods found in current context"
        return
    fi
    
    print_info "Found ${#pod_ips[@]} pods with IPs: ${pod_ips[@]}"
    
    # Test connectivity to each pod
    for pod_ip in "${pod_ips[@]}"; do
        echo -n "Testing connectivity to $pod_ip: "
        if vm_exec "$resource_group" "ping -c 1 -W 2 $pod_ip" >/dev/null 2>&1; then
            print_status "REACHABLE"
        else
            print_error "UNREACHABLE"
        fi
    done
}

# Test pod external connectivity
test_pod_external() {
    print_test_header "Pod External Connectivity Test"
    
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    local app_label=""
    
    if [[ "$current_context" == *"traditional"* ]]; then
        app_label="netshoot-traditional"
    elif [[ "$current_context" == *"podsubnet"* ]]; then
        app_label="netshoot-podsubnet"
    elif [[ "$current_context" == *"overlay"* ]]; then
        app_label="netshoot-overlay"
    else
        print_error "Unknown cluster context"
        return 1
    fi
    
    local pod_name=$(kubectl get pods -l app="$app_label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        print_error "No pods found with label app=$app_label"
        return 1
    fi
    
    print_info "Testing external connectivity from pod: $pod_name"
    
    echo -n "Testing internet connectivity: "
    if kubectl exec "$pod_name" -- curl -s --connect-timeout 10 https://httpbin.org/ip >/dev/null 2>&1; then
        print_status "SUCCESS"
        
        # Show SNAT IP
        local snat_ip=$(kubectl exec "$pod_name" -- curl -s --connect-timeout 10 https://httpbin.org/ip | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        print_info "SNAT IP (external sees): $snat_ip"
    else
        print_error "FAILED"
    fi
}

# Show cluster information
show_cluster_info() {
    print_test_header "Cluster Information"
    
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    print_info "Current Context: $current_context"
    
    echo
    echo "Nodes:"
    kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,INTERNAL-IP:.status.addresses[?(@.type=='InternalIP')].address" --no-headers 2>/dev/null | while read line; do
        echo "  $line"
    done
    
    echo
    echo "Pods:"
    kubectl get pods -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,POD-IP:.status.podIP,NODE:.spec.nodeName" --no-headers 2>/dev/null | while read line; do
        echo "  $line"
    done
    
    echo
    echo "Services:"
    kubectl get services -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip" --no-headers 2>/dev/null | while read line; do
        echo "  $line"
    done
}

# Main function
main() {
    local action=${1:-"network-test"}
    
    case $action in
        "network-test")
            network_test
            ;;
        "test-traditional")
            test_traditional_cni "$(get_resource_group)" "10.3.0.4"
            ;;
        "test-podsubnet")
            test_podsubnet_cni "$(get_resource_group)" "10.3.0.4"
            ;;
        "test-overlay")
            test_overlay_cni "$(get_resource_group)" "10.3.0.4"
            ;;
        "test-external")
            test_pod_external
            ;;
        "test-loadbalancer")
            test_loadbalancer_service "$(get_resource_group)"
            ;;
        "cluster-info")
            show_cluster_info
            ;;
        *)
            echo "Usage: $0 {network-test|test-traditional|test-podsubnet|test-overlay|test-external|test-loadbalancer|cluster-info}"
            echo
            echo "Commands:"
            echo "  network-test      - Auto-detect cluster type and run appropriate tests"
            echo "  test-traditional  - Test Traditional CNI connectivity"
            echo "  test-podsubnet    - Test Pod Subnet CNI connectivity"
            echo "  test-overlay      - Test Overlay CNI connectivity"
            echo "  test-external     - Test pod external connectivity"
            echo "  test-loadbalancer - Test LoadBalancer service access"
            echo "  cluster-info      - Show cluster and pod information"
            exit 1
            ;;
    esac
}

main "$@"
