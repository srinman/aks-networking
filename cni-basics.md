# AKS CNI Options Comparison Lab

## Lab Overview
This lab demonstrates the differences between three AKS networking configurations:
- **democluster**: Kubenet networking with Azure-managed route tables
- **aks-cni-overlay**: CNI Overlay without Cilium datapath
- **aks-cilium**: CNI Overlay with Cilium datapath

## Prerequisites
Ensure you have access to all three clusters:
```bash
# List available contexts
kubectl config get-contexts

# Expected contexts:
# - democluster (kubenet)
# - aks-cni-overlay (CNI overlay)
# - aks-cilium (CNI overlay + Cilium)
```

## Exercise 1: Cluster Context Switching and Basic Comparison

### Step 1: Kubenet Cluster Analysis (democluster)
```bash
# Switch to kubenet cluster
kubectl config use-context democluster

# Verify cluster type
kubectl get nodes -o wide
az aks show -n democluster -g <resource-group> --query "networkProfile"

# Deploy troubleshooting pod
kubectl apply -f rootpod.yaml
kubectl exec rootpod -it -- bash
```

### Step 2: CNI Overlay Cluster Analysis (aks-cni-overlay)
```bash
# Switch to CNI overlay cluster
kubectl config use-context aks-cni-overlay

# Verify cluster type
kubectl get nodes -o wide
az aks show -n aks-cni-overlay -g <resource-group> --query "networkProfile"

# Check for CNI overlay components
kubectl get configmap azure-ip-masq-agent-config-reconciled -n kube-system -o yaml
```

### Step 3: Cilium Cluster Analysis (aks-cilium)
```bash
# Switch to Cilium cluster
kubectl config use-context aks-cilium

# Verify cluster type and Cilium presence
kubectl get nodes -o wide
kubectl get pods -n kube-system | grep cilium
az aks show -n aks-cilium -g <resource-group> --query "networkProfile"
```

## Exercise 2: Network Policy Enforcement Comparison

### Kubenet Cluster (democluster)
```bash
kubectl config use-context democluster

# Check for network policy engines
kubectl get pods -n kube-system | grep -E "azure-npm|calico"
echo "Network policies require additional components like Azure NPM or Calico"

# Check kube-proxy presence
kubectl get pods -n kube-system | grep kube-proxy
kubectl get daemonset -n kube-system kube-proxy
```

### CNI Overlay without Cilium (aks-cni-overlay)
```bash
kubectl config use-context aks-cni-overlay

# Check for network policy engines
kubectl get pods -n kube-system | grep -E "azure-npm|calico|cilium"
echo "Network policies require additional components like Azure NPM or Calico"

# Check kube-proxy presence
kubectl get pods -n kube-system | grep kube-proxy
kubectl get daemonset -n kube-system kube-proxy
```

### Cilium Cluster (aks-cilium)
```bash
kubectl config use-context aks-cilium

# Check Cilium components
kubectl get pods -n kube-system | grep cilium
kubectl get daemonset -n kube-system cilium

# Check if kube-proxy is replaced by Cilium
kubectl get pods -n kube-system | grep kube-proxy
echo "Note: Cilium replaces kube-proxy functionality"

# Verify Cilium network policy enforcement
kubectl get ciliumnodes
```

## Exercise 3: Routing and Traffic Management Analysis

### Kubenet Routing Analysis
```bash
kubectl config use-context democluster

# Deploy rootpod and analyze routing
kubectl apply -f rootpod.yaml
kubectl exec rootpod -it -- bash

# Inside rootpod:
ip route
iptables -t nat -S | grep -E "KUBE-"
exit

# Check Azure route table (from Azure Portal or CLI)
az network route-table list --query "[?contains(name, 'democluster')]"
```

### CNI Overlay Routing Analysis
```bash
kubectl config use-context aks-cni-overlay

# Deploy netshoot for network analysis
kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# Inside netshoot:
ip route
ip addr show
# Note the simplified routing - only default via 169.254.1.1
exit

# Check that no custom route tables are needed
echo "CNI Overlay uses Azure networking fabric - no custom route tables"
```

### Cilium Routing Analysis  
```bash
kubectl config use-context aks-cilium

# Check Cilium routing
kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# Inside netshoot:
ip route
ip addr show
exit

# Use Cilium CLI if available
cilium status
cilium node list
```

## Exercise 4: Service and Load Balancing Comparison

### Deploy Test Service Across All Clusters
```bash
# Deploy to kubenet cluster
kubectl config use-context democluster
kubectl create deployment test-app --image=nginx --replicas=3
kubectl expose deployment test-app --port=80 --type=ClusterIP

# Deploy to CNI overlay cluster  
kubectl config use-context aks-cni-overlay
kubectl create deployment test-app --image=nginx --replicas=3
kubectl expose deployment test-app --port=80 --type=ClusterIP

# Deploy to Cilium cluster
kubectl config use-context aks-cilium
kubectl create deployment test-app --image=nginx --replicas=3
kubectl expose deployment test-app --port=80 --type=ClusterIP
```

### Analyze Service Implementation Differences

#### Kubenet Cluster Analysis
```bash
kubectl config use-context democluster
kubectl exec rootpod -it -- bash

# Inside rootpod - analyze kube-proxy iptables rules:
iptables -t nat -S | grep -E "KUBE-SVC"
iptables -t nat -S | grep test-app
iptables -t nat -L KUBE-SERVICES

# Check service endpoints
iptables -t nat -S | grep -E "KUBE-SEP"
exit
```

#### CNI Overlay Cluster Analysis  
```bash
kubectl config use-context aks-cni-overlay
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# Inside debug pod - analyze kube-proxy iptables rules:
iptables -t nat -S | grep -E "KUBE-SVC"
iptables -t nat -S | grep test-app
exit
```

#### Cilium Cluster Analysis
```bash
kubectl config use-context aks-cilium

# Check Cilium service implementation
kubectl get services
cilium service list

# Verify eBPF service implementation (no iptables rules)
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# Inside debug pod:
iptables -t nat -S | grep -E "KUBE-SVC" || echo "No kube-proxy iptables rules - Cilium uses eBPF"
exit

# Check Cilium service details
cilium service get --service-name test-app
```

## Exercise 5: Network Security Groups (NSG) Role

### Understanding NSG Implementation Across Clusters
```bash
# Check NSG configuration for each cluster subnet
az network nsg list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location}"

# For each cluster, examine the subnet NSG rules
# Kubenet cluster
az network vnet subnet show --vnet-name <kubenet-vnet> --name <kubenet-subnet> --resource-group <rg> --query "networkSecurityGroup"

# CNI Overlay cluster  
az network vnet subnet show --vnet-name <overlay-vnet> --name <overlay-subnet> --resource-group <rg> --query "networkSecurityGroup"

# Cilium cluster
az network vnet subnet show --vnet-name <cilium-vnet> --name <cilium-subnet> --resource-group <rg> --query "networkSecurityGroup"
```

### NSG Rules Analysis
```bash
# Examine NSG rules for AKS traffic
az network nsg rule list --nsg-name <nsg-name> --resource-group <rg> --query "[].{Name:name, Priority:priority, Direction:direction, Access:access, Protocol:protocol, SourceAddressPrefix:sourceAddressPrefix, DestinationAddressPrefix:destinationAddressPrefix, DestinationPortRange:destinationPortRange}"
```

## Exercise 6: Network Policy Enforcement Demonstration

### Deploy Network Policy Test Application
```bash
# Deploy to all clusters
for context in democluster aks-cni-overlay aks-cilium; do
  kubectl config use-context $context
  kubectl create namespace netpol-test
  kubectl run frontend --image=nginx --namespace=netpol-test --labels="app=frontend"
  kubectl run backend --image=nginx --namespace=netpol-test --labels="app=backend"
  kubectl expose pod frontend --port=80 --namespace=netpol-test
  kubectl expose pod backend --port=80 --namespace=netpol-test
done
```

### Apply Network Policy and Test Enforcement

#### Kubenet Cluster (requires additional components)
```bash
kubectl config use-context democluster

# Apply network policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

# Test policy enforcement
kubectl exec frontend -n netpol-test -- curl --connect-timeout 5 backend.netpol-test.svc.cluster.local || echo "Policy enforcement depends on Azure NPM/Calico installation"
```

#### CNI Overlay Cluster (requires additional components)
```bash
kubectl config use-context aks-cni-overlay

# Apply same network policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

# Test policy enforcement
kubectl exec frontend -n netpol-test -- curl --connect-timeout 5 backend.netpol-test.svc.cluster.local || echo "Policy enforcement depends on Azure NPM/Calico installation"
```

#### Cilium Cluster (native enforcement)
```bash
kubectl config use-context aks-cilium

# Apply same network policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

# Test policy enforcement
kubectl exec frontend -n netpol-test -- curl --connect-timeout 5 backend.netpol-test.svc.cluster.local || echo "Traffic blocked by Cilium network policy"

# Check Cilium policy enforcement
cilium policy get
```

## Exercise 7: Advanced Cilium Features Demonstration

### Cilium CLI Commands
```bash
kubectl config use-context aks-cilium

# Check Cilium status
cilium status

# List Cilium nodes
cilium node list

# Check connectivity
cilium connectivity test --test-namespace cilium-test

# Monitor network traffic
cilium monitor

# Check service mesh readiness
cilium config view | grep -i mesh
```

### eBPF vs iptables Comparison
```bash
# In Cilium cluster - no kube-proxy iptables rules
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium bpf lb list

# Compare with kubenet/overlay clusters that use iptables
kubectl config use-context democluster
kubectl exec rootpod -- iptables -t nat -L KUBE-SERVICES | wc -l
```

## Troubleshooting Commands Reference
## Troubleshooting Commands Reference

### General Cluster Analysis
```bash
# Switch between clusters
kubectl config use-context <cluster-name>

# Check cluster networking configuration
az aks show -n <cluster-name> -g <resource-group> --query "networkProfile"

# Check node configuration
kubectl get nodes -o wide
kubectl describe node <node-name>
```

### Network Policy Debugging
```bash
# Check network policy engines
kubectl get pods -n kube-system | grep -E "azure-npm|calico|cilium"

# List network policies
kubectl get networkpolicy --all-namespaces

# Check Cilium policies (Cilium clusters only)
cilium policy get
```

### Service and Load Balancing Analysis
```bash
# Deploy rootpod for deep network analysis
kubectl apply -f rootpod.yaml 
kubectl exec rootpod -it -- bash  

# Inside rootpod - analyze kube-proxy rules:
iptables -t nat -S | grep -E "KUBE-"
iptables -t nat -S | grep <service-ip>
iptables -t nat -S KUBE-SVC-<service-chain>
iptables -t nat -S KUBE-SEP-<endpoint-chain>

# Check service endpoints
kubectl get endpoints
kubectl get endpointslices
```

### Cilium-Specific Commands
```bash
# Check Cilium status and configuration
cilium status
cilium config view

# List Cilium services (replaces kube-proxy)
cilium service list
cilium service get --service-name <service-name>

# Monitor network traffic
cilium monitor

# Check eBPF programs
cilium bpf lb list
cilium bpf ct list global

# Connectivity testing
cilium connectivity test
```

### Route Table Analysis
```bash
# Kubenet clusters - check Azure route tables
az network route-table list --query "[?contains(name, '<cluster-name>')]"
az network route-table route list --resource-group <rg> --route-table-name <rt-name>

# CNI Overlay - minimal routing (handled by Azure fabric)
kubectl exec <pod> -- ip route
# Should show: default via 169.254.1.1 dev eth0
```

### NSG Analysis Commands
```bash
# List NSGs associated with cluster subnets
az network vnet subnet show --vnet-name <vnet> --name <subnet> --resource-group <rg> --query "networkSecurityGroup"

# Examine NSG rules
az network nsg rule list --nsg-name <nsg-name> --resource-group <rg> --output table

# Check NSG flow logs (if enabled)
az network watcher flow-log list --resource-group <rg>
```

## Key Learning Points

### Kubenet vs CNI Overlay vs Cilium Comparison

| Feature | Kubenet | CNI Overlay | CNI Overlay + Cilium |
|---------|---------|-------------|---------------------|
| **Pod IP Source** | Node subnet | Overlay network | Overlay network |
| **Routing** | Azure route tables | Azure fabric (169.254.1.1) | Azure fabric + eBPF |
| **Network Policies** | Requires Azure NPM/Calico | Requires Azure NPM/Calico | Native Cilium enforcement |
| **Service Implementation** | kube-proxy + iptables | kube-proxy + iptables | Cilium eBPF (no kube-proxy) |
| **Performance** | Good | Good | Excellent (eBPF) |
| **Observability** | Standard K8s tools | Standard K8s tools | Advanced (Cilium/Hubble) |
| **Security** | Basic + additional tools | Basic + additional tools | Advanced (L3-L7 policies) |

### NSG Role Explanation

**Network Security Groups (NSGs) operate at the subnet level and provide:**
- **Layer 4 traffic filtering** (source/destination IP, ports, protocols)
- **Azure-native security** independent of Kubernetes networking
- **Defense in depth** alongside Kubernetes network policies
- **Protection for node-to-node communication**
- **Integration with Azure Firewall and other Azure services**

**NSG Rules for AKS typically include:**
- Allow inbound traffic to API server (443)
- Allow outbound traffic for container registry access (443)
- Allow inter-node communication (various ports)
- Allow load balancer health probes
- Custom rules for application requirements

### Cilium Advantages

**Cilium replaces traditional kube-proxy with eBPF programs that:**
- **Eliminate iptables overhead** - no complex rule chains
- **Provide native network policy enforcement** - no additional components needed
- **Enable advanced L7 filtering** - HTTP/gRPC/Kafka protocol awareness
- **Offer superior observability** - network flow monitoring with Hubble
- **Support service mesh features** - without sidecar proxies
- **Scale better** - O(1) lookup vs O(n) iptables traversal

## Cleanup Commands
```bash
# Clean up test resources from all clusters
for context in democluster aks-cni-overlay aks-cilium; do
  kubectl config use-context $context
  kubectl delete namespace netpol-test --ignore-not-found
  kubectl delete deployment test-app --ignore-not-found
  kubectl delete service test-app --ignore-not-found
  kubectl delete pod rootpod --ignore-not-found
  kubectl delete pod netshoot --ignore-not-found
done
```