#!/bin/bash

# Azure CNI Networking Demo - Quick Setup Script
# This script sets up the environment for demonstrating Azure CNI options

set -e

# Configuration
RESOURCE_GROUP_PREFIX="aks-cni-demo-rg"
LOCATION="westus2"  # Changed from eastus due to capacity issues
VNET_NAME="aks-demo-vnet"
NODE_SUBNET_NAME="aks-nodes"
POD_SUBNET_NAME="aks-pods"

# Function to get or create resource group
get_resource_group() {
    # Try to find existing resource group first
    local existing_rg=$(az group list --query "[?starts_with(name, '$RESOURCE_GROUP_PREFIX')].name" --output tsv | head -1)
    
    if [ ! -z "$existing_rg" ]; then
        echo "$existing_rg"
    else
        # Generate new resource group name with timestamp
        echo "${RESOURCE_GROUP_PREFIX}-$(date +%m%d%H%M)"
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Please install Azure CLI."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login'"
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Check available VM sizes in the region
check_vm_availability() {
    print_status "Checking available VM sizes in region: $LOCATION"
    
    local available_sizes=$(az vm list-sizes --location $LOCATION --query "[?starts_with(name, 'Standard_B') || starts_with(name, 'Standard_D2s')].name" --output tsv | head -10)
    
    if [ -z "$available_sizes" ]; then
        print_warning "Could not retrieve available VM sizes"
    else
        print_status "Available small VM sizes in $LOCATION:"
        echo "$available_sizes" | while read size; do
            echo "  - $size"
        done
    fi
}

# Create base infrastructure
setup_infrastructure() {
    print_status "Setting up base infrastructure..."
    
    # Get or generate resource group name
    RESOURCE_GROUP=$(get_resource_group)
    
    # Create resource group
    print_status "Creating resource group: $RESOURCE_GROUP"
    az group create --name $RESOURCE_GROUP --location $LOCATION --output table
    
    # Create VNet with node subnet
    print_status "Creating VNet: $VNET_NAME"
    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefixes 10.0.0.0/8 \
        --subnet-name $NODE_SUBNET_NAME \
        --subnet-prefix 10.1.0.0/16 \
        --output table
    
    # Create pod subnet
    print_status "Creating pod subnet: $POD_SUBNET_NAME"
    az network vnet subnet create \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $POD_SUBNET_NAME \
        --address-prefix 10.2.0.0/16 \
        --output table
    
    # Create external workload subnet
    print_status "Creating external workload subnet"
    az network vnet subnet create \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name external-workload \
        --address-prefix 10.3.0.0/24 \
        --output table
}

# Create external workload (VM)
setup_external_workload() {
    print_status "Creating external workload (Azure VM)..."
    
    # Create cloud-init script for network tools
    cat > /tmp/cloud-init.txt << 'EOF'
#cloud-config
package_update: true
packages:
  - curl
  - wget
  - netcat-openbsd
  - traceroute
  - dnsutils
  - tcpdump
  - nmap
  - jq
  - iperf3
  - net-tools
  - iputils-ping
runcmd:
  - echo "Network tools installed successfully" > /tmp/setup-complete.log
  - systemctl enable ssh
  - systemctl start ssh
EOF

    # Try different VM sizes in order of preference (smallest to largest)
    VM_SIZES=("Standard_B1ls" "Standard_B2als_v2" "Standard_B2as_v2" "Standard_B2ats_v2" "Standard_D2s_v3" "Standard_D2s_v5")
    
    local vm_created=false
    
    for size in "${VM_SIZES[@]}"; do
        print_status "Attempting to create VM with size: $size"
        
        if az vm create \
            --resource-group $RESOURCE_GROUP \
            --name external-workload \
            --image Ubuntu2204 \
            --size $size \
            --admin-username azureuser \
            --generate-ssh-keys \
            --vnet-name $VNET_NAME \
            --subnet external-workload \
            --nsg "" \
            --public-ip-address "" \
            --custom-data /tmp/cloud-init.txt \
            --output table 2>/dev/null; then
            
            print_status "VM created successfully with size: $size"
            vm_created=true
            break
        else
            print_warning "Failed to create VM with size $size, trying next size..."
        fi
    done
    
    if [ "$vm_created" = false ]; then
        print_warning "Failed to create VM with any of the attempted sizes. Trying Azure Container Instance as fallback..."
        
        # Fallback to ACI with Ubuntu
        if az container create \
            --resource-group $RESOURCE_GROUP \
            --name external-workload \
            --image ubuntu:22.04 \
            --os-type Linux \
            --cpu 1 \
            --memory 1 \
            --vnet $VNET_NAME \
            --subnet external-workload \
            --restart-policy Never \
            --command-line "bash -c 'apt-get update && apt-get install -y curl wget netcat-openbsd traceroute dnsutils jq iputils-ping net-tools && sleep 3600'" \
            --output table; then
            
            print_status "Created Azure Container Instance as external workload"
            vm_created=true
        else
            print_error "Failed to create both VM and ACI"
            rm -f /tmp/cloud-init.txt
            return 1
        fi
    fi
    
    # Clean up temp file
    rm -f /tmp/cloud-init.txt
    
    if [ "$vm_created" = true ]; then
        # Get workload IP (try VM first, then ACI)
        WORKLOAD_IP=$(az vm show --resource-group $RESOURCE_GROUP --name external-workload --show-details --query privateIps --output tsv 2>/dev/null || \
                      az container show --resource-group $RESOURCE_GROUP --name external-workload --query ipAddress.ip --output tsv 2>/dev/null)
        
        print_status "External workload created with IP: $WORKLOAD_IP"
        
        # Wait for initialization to complete
        print_status "Waiting for workload initialization to complete..."
        sleep 60
        
        # Test connectivity
        print_status "Testing workload accessibility..."
        if az vm run-command invoke \
            --resource-group $RESOURCE_GROUP \
            --name external-workload \
            --command-id RunShellScript \
            --scripts "echo 'Workload is ready'" \
            --output none 2>/dev/null || \
           az container exec \
            --resource-group $RESOURCE_GROUP \
            --name external-workload \
            --exec-command "echo 'Workload is ready'" 2>/dev/null; then
            print_status "External workload is ready and accessible"
        else
            print_warning "Workload may still be initializing. You can check status later."
        fi
    fi
}

# Create a specific AKS cluster
create_aks_cluster() {
    local cluster_name=$1
    local network_mode=$2
    
    # Get existing resource group
    RESOURCE_GROUP=$(get_resource_group)
    
    if [ -z "$RESOURCE_GROUP" ] || ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Resource group not found. Please run './setup-demo.sh infra' first to create the infrastructure."
        exit 1
    fi
    
    print_status "Using resource group: $RESOURCE_GROUP"
    print_status "Creating AKS cluster: $cluster_name with mode: $network_mode"
    
    # Get subnet IDs
    NODE_SUBNET_ID=$(az network vnet subnet show \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $NODE_SUBNET_NAME \
        --query id -o tsv)
    
    case $network_mode in
        "traditional")
            az aks create \
                --resource-group $RESOURCE_GROUP \
                --name $cluster_name \
                --network-plugin azure \
                --vnet-subnet-id $NODE_SUBNET_ID \
                --service-cidr 192.168.0.0/16 \
                --dns-service-ip 192.168.0.10 \
                --node-count 2 \
                --generate-ssh-keys \
                --output table
            ;;
        "podsubnet")
            POD_SUBNET_ID=$(az network vnet subnet show \
                --resource-group $RESOURCE_GROUP \
                --vnet-name $VNET_NAME \
                --name $POD_SUBNET_NAME \
                --query id -o tsv)
            
            az aks create \
                --resource-group $RESOURCE_GROUP \
                --name $cluster_name \
                --network-plugin azure \
                --vnet-subnet-id $NODE_SUBNET_ID \
                --pod-subnet-id $POD_SUBNET_ID \
                --service-cidr 192.168.0.0/16 \
                --dns-service-ip 192.168.0.10 \
                --node-count 2 \
                --generate-ssh-keys \
                --output table
            ;;
        "overlay")
            az aks create \
                --resource-group $RESOURCE_GROUP \
                --name $cluster_name \
                --network-plugin azure \
                --network-plugin-mode overlay \
                --vnet-subnet-id $NODE_SUBNET_ID \
                --service-cidr 192.168.0.0/16 \
                --dns-service-ip 192.168.0.10 \
                --pod-cidr 192.169.0.0/16 \
                --node-count 2 \
                --generate-ssh-keys \
                --output table
            ;;
        *)
            print_error "Unknown network mode: $network_mode"
            exit 1
            ;;
    esac
    
    print_status "AKS cluster $cluster_name created successfully!"
}

# Deploy netshoot pods
deploy_netshoot() {
    local cluster_name=$1
    local app_label=$2
    
    # Get existing resource group
    RESOURCE_GROUP=$(get_resource_group)
    
    print_status "Deploying netshoot pods to $cluster_name..."
    
    # Get credentials
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster_name --overwrite-existing
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $app_label
  labels:
    demo: $cluster_name
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $app_label
  template:
    metadata:
      labels:
        app: $app_label
    spec:
      containers:
      - name: netshoot
        image: nicolaka/netshoot
        command: ["sleep", "3600"]
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${app_label}-svc
spec:
  selector:
    app: $app_label
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
EOF
    
    print_status "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=$app_label --timeout=300s
    
    print_status "Netshoot deployment completed for $cluster_name"
}

# Main execution
main() {
    local action=${1:-"all"}
    
    case $action in
        "prereq")
            check_prerequisites
            ;;
        "check-vm")
            check_prerequisites
            check_vm_availability
            ;;
        "infra")
            check_prerequisites
            setup_infrastructure
            setup_external_workload
            ;;
        "traditional")
            create_aks_cluster "aks-cni-traditional" "traditional"
            deploy_netshoot "aks-cni-traditional" "netshoot-traditional"
            ;;
        "podsubnet")
            create_aks_cluster "aks-cni-podsubnet" "podsubnet"
            deploy_netshoot "aks-cni-podsubnet" "netshoot-podsubnet"
            ;;
        "overlay")
            create_aks_cluster "aks-cni-overlay" "overlay"
            deploy_netshoot "aks-cni-overlay" "netshoot-overlay"
            ;;
        "all")
            # Get or create resource group for the all command
            RESOURCE_GROUP=$(get_resource_group)
            
            check_prerequisites
            setup_infrastructure
            setup_external_workload
            
            create_aks_cluster "aks-cni-traditional" "traditional"
            deploy_netshoot "aks-cni-traditional" "netshoot-traditional"
            
            create_aks_cluster "aks-cni-podsubnet" "podsubnet"  
            deploy_netshoot "aks-cni-podsubnet" "netshoot-podsubnet"
            
            create_aks_cluster "aks-cni-overlay" "overlay"
            deploy_netshoot "aks-cni-overlay" "netshoot-overlay"
            
            print_status "All clusters and workloads deployed successfully!"
            print_status "You can now follow the demo guide to test networking scenarios."
            ;;
        "cleanup")
            # Get existing resource group for cleanup
            RESOURCE_GROUP=$(get_resource_group)
            
            if [ -z "$RESOURCE_GROUP" ] || ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
                print_error "No resource group found matching '$RESOURCE_GROUP_PREFIX*'"
                exit 1
            fi
            
            print_warning "This will delete all resources in resource group: $RESOURCE_GROUP"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Cleaning up resources..."
                
                # Optional: Delete individual resources first for faster cleanup
                print_status "Deleting AKS clusters..."
                az aks delete --resource-group $RESOURCE_GROUP --name aks-cni-traditional --yes --no-wait 2>/dev/null || true
                az aks delete --resource-group $RESOURCE_GROUP --name aks-cni-podsubnet --yes --no-wait 2>/dev/null || true
                az aks delete --resource-group $RESOURCE_GROUP --name aks-cni-overlay --yes --no-wait 2>/dev/null || true
                
                print_status "Deleting external workload VM..."
                az vm delete --resource-group $RESOURCE_GROUP --name external-workload --yes --no-wait 2>/dev/null || true
                
                print_status "Deleting entire resource group..."
                az group delete --name $RESOURCE_GROUP --yes --no-wait
                print_status "Cleanup initiated. Resources will be deleted in the background."
            else
                print_status "Cleanup cancelled."
            fi
            ;;
        *)
            echo "Usage: $0 {prereq|check-vm|infra|traditional|podsubnet|overlay|all|cleanup}"
            echo "  prereq     - Check prerequisites"
            echo "  check-vm   - Check available VM sizes in region"
            echo "  infra      - Setup base infrastructure only"
            echo "  traditional- Create traditional Azure CNI cluster"
            echo "  podsubnet  - Create Azure CNI with pod subnet cluster"
            echo "  overlay    - Create Azure CNI overlay cluster"
            echo "  all        - Setup everything"
            echo "  cleanup    - Delete all resources"
            exit 1
            ;;
    esac
}

main "$@"
