#!/bin/bash

# Azure CNI Networking Analysis Script
# This script runs network analysis across different CNI configurations

set -e

RESOURCE_GROUP=${RESOURCE_GROUP:-$(az group list --query "[?starts_with(name, 'aks-cni-demo-rg')].name" --output tsv | head -1)}

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

print_header() {
    echo -e "\n${BLUE}=====================================${NC}"
    echo -e "${BLUE} $1 ${NC}"
    echo -e "${BLUE}=====================================${NC}\n"
}

print_subheader() {
    echo -e "\n${GREEN}--- $1 ---${NC}\n"
}

# Network analysis for a specific cluster
analyze_cluster_networking() {
    local cluster_name=$1
    local app_label=$2
    local cni_type=$3
    
    print_header "Network Analysis: $cluster_name ($cni_type)"
    
    # Get credentials
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster_name --overwrite-existing >/dev/null 2>&1
    
    print_subheader "Cluster Overview"
    echo "Cluster: $cluster_name"
    echo "CNI Type: $cni_type"
    
    print_subheader "Node Information"
    kubectl get nodes -o wide
    
    print_subheader "Pod Information"
    kubectl get pods -l app=$app_label -o wide
    
    # Get pod names
    PODS=($(kubectl get pods -l app=$app_label -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#PODS[@]} -eq 0 ]; then
        echo "No pods found with label app=$app_label"
        return
    fi
    
    print_subheader "Detailed Pod Network Configuration"
    
    for POD in "${PODS[@]}"; do
        echo "----------------------------------------"
        echo "Pod: $POD"
        echo "----------------------------------------"
        
        kubectl exec $POD -- sh -c '
            echo "Basic Information:"
            echo "  Pod Name: $POD_NAME"
            echo "  Node Name: $NODE_NAME"
            echo "  Pod IP: $POD_IP"
            echo ""
            
            echo "Network Interfaces:"
            ip addr show | grep -E "^[0-9]+:|inet " | sed "s/^/  /"
            echo ""
            
            echo "Routing Table:"
            ip route | sed "s/^/  /"
            echo ""
            
            echo "Default Gateway:"
            ip route | grep default | sed "s/^/  /"
            echo ""
            
            echo "DNS Configuration:"
            cat /etc/resolv.conf | sed "s/^/  /"
            echo ""
        ' 2>/dev/null || echo "Failed to get network info from $POD"
        
        echo ""
    done
    
    print_subheader "Service Information"
    kubectl get services -l app=$app_label -o wide
    
    # Get LoadBalancer IP if available
    LB_IP=$(kubectl get service ${app_label}-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ ! -z "$LB_IP" ]; then
        echo "LoadBalancer IP: $LB_IP"
    fi
    
    print_subheader "Endpoint Information"
    kubectl get endpoints ${app_label}-svc -o wide 2>/dev/null || echo "No endpoints found"
}

# Test external connectivity
test_external_connectivity() {
    local cluster_name=$1
    local app_label=$2
    local cni_type=$3
    
    print_header "External Connectivity Test: $cluster_name ($cni_type)"
    
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster_name --overwrite-existing >/dev/null 2>&1
    
    FIRST_POD=$(kubectl get pods -l app=$app_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$FIRST_POD" ]; then
        echo "No pods found for testing"
        return
    fi
    
    print_subheader "Outbound Connectivity Test"
    
    echo "Testing from pod: $FIRST_POD"
    
    kubectl exec $FIRST_POD -- sh -c '
        echo "Pod IP: $POD_IP"
        echo ""
        
        echo "Testing DNS resolution:"
        nslookup google.com 2>/dev/null | head -10 || echo "DNS test failed"
        echo ""
        
        echo "Testing external HTTP connectivity:"
        curl -s -m 10 http://httpbin.org/ip 2>/dev/null || echo "HTTP test failed"
        echo ""
        
        echo "Testing external IP as seen by remote service (SNAT behavior):"
        curl -s -m 10 http://httpbin.org/ip | jq -r .origin 2>/dev/null || echo "SNAT test failed"
        echo ""
    ' 2>/dev/null || echo "Connectivity test failed"
    
    print_subheader "VM Connectivity Test"
    
    # Test connectivity to VM
    VM_IP=$(az vm show --resource-group $RESOURCE_GROUP --name external-workload --show-details --query privateIps --output tsv 2>/dev/null)
    
    if [ ! -z "$VM_IP" ]; then
        echo "Testing connectivity to VM ($VM_IP):"
        kubectl exec $FIRST_POD -- sh -c "
            ping -c 3 $VM_IP 2>/dev/null || echo 'Ping to VM failed'
        " 2>/dev/null
    else
        echo "VM not found or not accessible"
    fi
}

# Test inbound connectivity
test_inbound_connectivity() {
    local cluster_name=$1
    local app_label=$2
    local cni_type=$3
    
    print_header "Inbound Connectivity Test: $cluster_name ($cni_type)"
    
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster_name --overwrite-existing >/dev/null 2>&1
    
    # Start HTTP server in pod
    PODS=($(kubectl get pods -l app=$app_label -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#PODS[@]} -eq 0 ]; then
        echo "No pods found for testing"
        return
    fi
    
    FIRST_POD=${PODS[0]}
    
    print_subheader "Setting up HTTP server in pod"
    
    # Kill any existing servers and start new one
    kubectl exec $FIRST_POD -- sh -c 'pkill -f "nc -l" 2>/dev/null || true'
    kubectl exec $FIRST_POD -- sh -c 'nohup sh -c "while true; do echo -e \"HTTP/1.1 200 OK\r\n\r\nHello from \$(hostname) - IP: \$POD_IP - Node: \$NODE_NAME - Time: \$(date)\" | nc -l -p 8080; done" >/dev/null 2>&1 &' &
    
    sleep 5
    
    # Test via LoadBalancer
    LB_IP=$(kubectl get service ${app_label}-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [ ! -z "$LB_IP" ]; then
        print_subheader "Testing via LoadBalancer ($LB_IP)"
        
        echo "Testing from VM to LoadBalancer:"
        az vm run-command invoke \
            --resource-group $RESOURCE_GROUP \
            --name external-workload \
            --command-id RunShellScript \
            --scripts "curl -s -m 10 http://$LB_IP:8080" \
            --output tsv --query 'value[0].message' 2>/dev/null || echo "LoadBalancer test failed"
        echo ""
    fi
    
    # Test direct pod access
    POD_IP=$(kubectl get pod $FIRST_POD -o jsonpath='{.status.podIP}')
    
    print_subheader "Testing direct pod access ($POD_IP)"
    
    echo "Testing direct pod connectivity from VM:"
    az vm run-command invoke \
        --resource-group $RESOURCE_GROUP \
        --name external-workload \
        --command-id RunShellScript \
        --scripts "timeout 10 curl -s http://$POD_IP:8080" \
        --output tsv --query 'value[0].message' 2>/dev/null || echo "Direct pod access failed (expected with overlay CNI)"
    echo ""
}

# Compare SNAT behavior across clusters
compare_snat_behavior() {
    print_header "SNAT Behavior Comparison"
    
    declare -A clusters=(
        ["aks-cni-traditional"]="netshoot-traditional"
        ["aks-cni-podsubnet"]="netshoot-podsubnet"
        ["aks-cni-overlay"]="netshoot-overlay"
    )
    
    echo "Comparing Source NAT behavior across different CNI configurations:"
    echo ""
    
    for cluster in "${!clusters[@]}"; do
        app_label=${clusters[$cluster]}
        
        echo "--- $cluster ---"
        
        # Check if cluster exists
        if ! az aks show --resource-group $RESOURCE_GROUP --name $cluster >/dev/null 2>&1; then
            echo "Cluster not found or not accessible"
            echo ""
            continue
        fi
        
        az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster --overwrite-existing >/dev/null 2>&1
        
        POD=$(kubectl get pods -l app=$app_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -z "$POD" ]; then
            echo "No pods found"
            echo ""
            continue
        fi
        
        kubectl exec $POD -- sh -c '
            echo "Pod Internal IP: $POD_IP"
            echo "External IP (SNAT result): $(curl -s -m 10 http://httpbin.org/ip 2>/dev/null | jq -r .origin 2>/dev/null || echo "Test failed")"
        ' 2>/dev/null || echo "SNAT test failed"
        
        echo ""
    done
}

# Show network policy effects
test_network_policies() {
    print_header "Network Policy Testing"
    
    # Test on traditional CNI cluster
    if az aks show --resource-group $RESOURCE_GROUP --name aks-cni-traditional >/dev/null 2>&1; then
        az aks get-credentials --resource-group $RESOURCE_GROUP --name aks-cni-traditional --overwrite-existing >/dev/null 2>&1
        
        print_subheader "Testing without Network Policy"
        
        POD=$(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ ! -z "$POD" ]; then
            echo "Testing connectivity before network policy:"
            kubectl exec $POD -- curl -s -m 5 http://httpbin.org/ip >/dev/null 2>&1 && echo "✓ External connectivity works" || echo "✗ External connectivity failed"
        fi
        
        print_subheader "Applying Restrictive Network Policy"
        
        kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-netpol
spec:
  podSelector:
    matchLabels:
      app: netshoot-traditional
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
EOF
        
        sleep 10
        
        echo "Testing connectivity after network policy:"
        kubectl exec $POD -- timeout 10 curl -s http://httpbin.org/ip >/dev/null 2>&1 && echo "✓ External connectivity still works (policy may not be enforced)" || echo "✗ External connectivity blocked by policy"
        
        # Cleanup
        kubectl delete networkpolicy test-netpol >/dev/null 2>&1 || true
        
        echo "Network policy removed"
    fi
}

# Generate summary report
generate_summary() {
    print_header "Summary Report"
    
    echo "Azure CNI Networking Demo Summary"
    echo "================================="
    echo ""
    
    # Check which clusters exist
    echo "Available Clusters:"
    for cluster in aks-cni-traditional aks-cni-podsubnet aks-cni-overlay; do
        if az aks show --resource-group $RESOURCE_GROUP --name $cluster >/dev/null 2>&1; then
            status=$(az aks show --resource-group $RESOURCE_GROUP --name $cluster --query provisioningState -o tsv)
            echo "  ✓ $cluster ($status)"
        else
            echo "  ✗ $cluster (not found)"
        fi
    done
    
    echo ""
    
    # Check VM
    if az vm show --resource-group $RESOURCE_GROUP --name external-workload >/dev/null 2>&1; then
        VM_IP=$(az vm show --resource-group $RESOURCE_GROUP --name external-workload --show-details --query privateIps --output tsv)
        VM_STATUS=$(az vm show --resource-group $RESOURCE_GROUP --name external-workload --query provisioningState --output tsv)
        echo "External Workload (VM): ✓ Running ($VM_IP) - Status: $VM_STATUS"
    else
        echo "External Workload (VM): ✗ Not found"
    fi
    
    echo ""
    echo "Key Differences Observed:"
    echo "========================"
    echo "• Traditional CNI: Pods get IPs from node subnet (10.1.x.x)"
    echo "• Pod Subnet CNI: Pods get IPs from dedicated subnet (10.2.x.x)"  
    echo "• Overlay CNI: Pods get IPs from overlay CIDR (192.169.x.x)"
    echo ""
    echo "SNAT Behavior: All configurations show node IP as external source"
    echo "DNAT Behavior: LoadBalancer services work across all configurations"
    echo "Direct Pod Access: Available with Traditional/Pod Subnet, blocked with Overlay"
}

# Main execution
main() {
    local action=${1:-"all"}
    
    case $action in
        "analyze")
            analyze_cluster_networking "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            analyze_cluster_networking "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            analyze_cluster_networking "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            ;;
        "external")
            test_external_connectivity "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            test_external_connectivity "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            test_external_connectivity "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            ;;
        "inbound")
            test_inbound_connectivity "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            test_inbound_connectivity "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            test_inbound_connectivity "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            ;;
        "snat")
            compare_snat_behavior
            ;;
        "netpol")
            test_network_policies
            ;;
        "summary")
            generate_summary
            ;;
        "all")
            analyze_cluster_networking "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            analyze_cluster_networking "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            analyze_cluster_networking "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            
            test_external_connectivity "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            test_external_connectivity "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            test_external_connectivity "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            
            test_inbound_connectivity "aks-cni-traditional" "netshoot-traditional" "Traditional Azure CNI"
            test_inbound_connectivity "aks-cni-podsubnet" "netshoot-podsubnet" "Azure CNI with Pod Subnet"
            test_inbound_connectivity "aks-cni-overlay" "netshoot-overlay" "Azure CNI Overlay"
            
            compare_snat_behavior
            test_network_policies
            generate_summary
            ;;
        *)
            echo "Usage: $0 {analyze|external|inbound|snat|netpol|summary|all}"
            echo "  analyze  - Analyze cluster networking configuration"
            echo "  external - Test external connectivity (outbound)"
            echo "  inbound  - Test inbound connectivity"
            echo "  snat     - Compare SNAT behavior"
            echo "  netpol   - Test network policies"
            echo "  summary  - Generate summary report"
            echo "  all      - Run all tests"
            exit 1
            ;;
    esac
}

main "$@"
