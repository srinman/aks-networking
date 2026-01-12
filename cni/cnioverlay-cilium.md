# AKS CNI Overlay vs Cilium: Traffic Routing and Network Analysis

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Environment Setup](#environment-setup)
- [CNI Overlay Analysis](#cni-overlay-analysis)
- [Cilium CNI Analysis](#cilium-cni-analysis)
- [Traffic Flow Comparison](#traffic-flow-comparison)
- [Service Mesh Capabilities](#service-mesh-capabilities)
- [Performance Analysis](#performance-analysis)
- [Troubleshooting Commands](#troubleshooting-commands)

## Architecture Overview

### CNI Overlay Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Azure CNI Overlay                        │
├─────────────────────────────────────────────────────────────┤
│  Pod-to-Pod Communication                                   │
│                                                             │
│  ┌─────────┐              ┌─────────┐              ┌──────┐ │
│  │  Pod A  │ ──────────── │  Node   │ ──────────── │Pod B │ │
│  │10.244.x │              │ Bridge  │              │10.244│ │
│  └─────────┘              └─────────┘              └──────┘ │
│       │                       │                       │     │
│       └───────── Host Network (10.240.x.x) ──────────┘      │
│                                                             │
│  Role: IPAM (IP Address Management Only)                    │
│  - Assigns Pod IPs from overlay subnet                      │
│                       │
│  - Basic routing via kernel bridge                         │
└─────────────────────────────────────────────────────────────┘
```

### Cilium CNI Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Cilium CNI with eBPF                     │
├─────────────────────────────────────────────────────────────┤
│  Advanced Traffic Management & Security                     │
│                                                             │
│  ┌─────────┐    eBPF     ┌─────────┐    eBPF     ┌──────────┐│
│  │  Pod A  │ ────────── │ Cilium  │ ────────── │  Pod B   ││
│  │10.244.x │            │ Agent   │            │ 10.244.y ││
│  └─────────┘            └─────────┘            └──────────┘│
│       │                     │                       │      │
│       │                     │                       │      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              eBPF Data Plane                            ││
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐   ││
│  │  │Endpoint │ │Service  │ │Network  │ │ Security    │   ││
│  │  │ Map     │ │ Map     │ │Policy   │ │ Policy      │   ││
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────────┘   ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  Role: Full CNI + Advanced Features                        │
│  - IPAM + Traffic routing via eBPF                         │
│  - Service load balancing                                   │
│  - Network security policies                               │
│  - Observability and metrics                               │
└─────────────────────────────────────────────────────────────┘
```

## Environment Setup

### Prerequisites
- Two AKS clusters (one with CNI Overlay, one with Cilium)
- Azure CLI with AKS preview extension
- kubectl configured for both clusters
- Administrative access to cluster nodes

### Cluster Creation Commands

#### 1. Create CNI Overlay Cluster
```bash
# Create resource group
az group create --name cni-comparison-rg --location westus3

# Create CNI Overlay cluster
az aks create \
    --resource-group cni-comparison-rg \
    --name aks-cni-overlay \
    --location westus3 \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --pod-cidr 10.244.0.0/16 \
    --node-count 2 \
    --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group cni-comparison-rg --name aks-cni-overlay
```

#### 2. Create Cilium CNI Cluster
```bash
# Create Cilium-enabled cluster
az aks create \
    --resource-group cni-comparison-rg \
    --name aks-cilium \
    --location eastus2 \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --pod-cidr 10.245.0.0/16 \
    --node-count 2 \
    --generate-ssh-keys

# Optionally, create kubenet cluster for comparison

 az aks create \
    --resource-group cni-comparison-rg \
    --name aks-kubenet \
    --location westus3 \
    --network-plugin kubenet \
    --pod-cidr 10.244.0.0/16 \
    --node-count 2 \
    --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group cni-comparison-rg --name aks-cilium
```

## CNI Overlay Analysis

### Switch to CNI Overlay Cluster Context
```bash
# Set context to CNI Overlay cluster
kubectl config use-context aks-cni-overlay

# Verify cluster and networking
kubectl get nodes -o wide
kubectl get pods -n kube-system | grep azure-cni
```

### Deploy Test Applications
```bash
# Create test namespace
kubectl create namespace cni-test

# Deploy sample applications
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-frontend
  namespace: cni-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-backend
  namespace: cni-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: httpd:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: cni-test
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

### Analyze CNI Overlay Traffic Routing

#### 1. Pod Network Information
```bash
# Get pod details with IP addresses and node placement
kubectl get pods -n cni-test -o wide

# Store pod IPs for analysis
FRONTEND_POD=$(kubectl get pods -n cni-test -l app=frontend -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD=$(kubectl get pods -n cni-test -l app=backend -o jsonpath='{.items[0].metadata.name}')
FRONTEND_IP=$(kubectl get pods -n cni-test -l app=frontend -o jsonpath='{.items[0].status.podIP}')
BACKEND_IP=$(kubectl get pods -n cni-test -l app=backend -o jsonpath='{.items[0].status.podIP}')

echo "Frontend Pod: $FRONTEND_POD on IP: $FRONTEND_IP"
echo "Backend Pod: $BACKEND_POD on IP: $BACKEND_IP"
```

#### 2. Node Network Configuration
```bash
# Get node information
kubectl get nodes -o wide

# Access node to examine network configuration
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Examining node: $NODE_NAME"

# Check node network interfaces (requires node access)
kubectl debug node/$NODE_NAME -it --image=mcr.microsoft.com/cbl-mariner/base/core:2.0 -- chroot /host
```

#### 3. Route Table Analysis on Node
```bash
# Inside the debug pod on the node, examine routing
ip route show

# Check VXLAN interfaces
ip link show type vxlan

# Examine bridge configuration
brctl show

# Check iptables rules for pod traffic
iptables -t nat -L -n

# Exit the debug session
exit
```

#### 4. Pod-to-Pod Communication Analysis
```bash
# Test connectivity and trace route
kubectl exec -n cni-test $FRONTEND_POD -- ping -c 3 $BACKEND_IP

# Examine network namespace in pod
kubectl exec -n cni-test $FRONTEND_POD -- ip route show
kubectl exec -n cni-test $FRONTEND_POD -- ip addr show

# Test service connectivity
kubectl exec -n cni-test $FRONTEND_POD -- curl backend-service.cni-test.svc.cluster.local
```

#### 5. CNI Overlay Route Analysis
```bash
# Deploy network analysis tool
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: network-analyzer
  namespace: cni-test
spec:
  selector:
    matchLabels:
      name: network-analyzer
  template:
    metadata:
      labels:
        name: network-analyzer
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: analyzer
        image: nicolaka/netshoot
        command: ["/bin/bash"]
        args: ["-c", "while true; do sleep 30; done"]
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /
      tolerations:
      - operator: Exists
EOF

# Wait for deployment
kubectl rollout status daemonset/network-analyzer -n cni-test

# Get analyzer pod on specific node
ANALYZER_POD=$(kubectl get pods -n cni-test -l name=network-analyzer -o jsonpath='{.items[0].metadata.name}')

# Examine VXLAN traffic
kubectl exec -n cni-test $ANALYZER_POD -- tcpdump -i any -n host $FRONTEND_IP
```

## Cilium CNI Analysis

### Switch to Cilium Cluster Context
```bash
# Set context to Cilium cluster
kubectl config use-context aks-cilium

# Verify Cilium installation
kubectl get pods -n kube-system | grep cilium
kubectl get nodes -o wide
```

### Deploy Test Applications on Cilium Cluster
```bash
# Create test namespace
kubectl create namespace cilium-test

# Deploy the same applications
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-frontend
  namespace: cilium-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-backend
  namespace: cilium-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: httpd:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: cilium-test
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

### Cilium Network Analysis

#### 1. Install Cilium CLI Tools
```bash
# Download and install cilium CLI (if not already available)
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

#### 2. Cilium Status and Configuration
```bash
# Check Cilium status
cilium status

# Get detailed Cilium configuration
cilium config view

# Check Cilium endpoints
cilium endpoint list
```

#### 3. eBPF Map Analysis
```bash
# Get Cilium agent pod
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

# Access Cilium agent for debugging
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg endpoint list

# Check eBPF maps for service load balancing
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg service list

# Examine specific service mapping
BACKEND_SVC_IP=$(kubectl get svc -n cilium-test backend-service -o jsonpath='{.spec.clusterIP}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg service get $BACKEND_SVC_IP:80

# View eBPF program statistics
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg bpf lb list

# Check endpoint connectivity map
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg endpoint get $(kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg endpoint list | grep cilium-test | head -1 | awk '{print $1}')
```

#### 4. Traffic Flow Analysis with Cilium
```bash
# Get pod information
FRONTEND_POD_CILIUM=$(kubectl get pods -n cilium-test -l app=frontend -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD_CILIUM=$(kubectl get pods -n cilium-test -l app=backend -o jsonpath='{.items[0].metadata.name}')

# Monitor Cilium traffic with eBPF
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg monitor --type trace

# In another terminal, generate traffic
kubectl exec -n cilium-test $FRONTEND_POD_CILIUM -- curl backend-service.cilium-test.svc.cluster.local
```

#### 5. Service Load Balancing Deep Dive
```bash
# Examine Cilium's service load balancing
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg bpf lb maglev list

# Check backend endpoint distribution
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg service list --output json | jq '.[] | select(.frontend."port" == 80)'

# Monitor service connections
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg bpf ct list global | grep $BACKEND_SVC_IP
```

## Traffic Flow Comparison

### Key Differences Summary

| Aspect | CNI Overlay | Cilium CNI |
|--------|-------------|------------|
| **IPAM Role** | Primary function - assigns IPs only | Enhanced IPAM with policy enforcement |
| **Traffic Routing** | Kernel bridge + VXLAN tunneling | eBPF programs in kernel space |
| **Load Balancing** | kube-proxy (iptables/IPVS) | Native eBPF load balancing |
| **Policy Enforcement** | Basic Kubernetes NetworkPolicies | Advanced L3/L4/L7 policies |
| **Observability** | Limited to standard tools | Built-in flow monitoring |
| **Performance** | Standard kernel networking | Optimized eBPF dataplane |

### Performance Test Comparison
```bash
# Deploy performance testing tools
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: perf-test-client
  namespace: cni-test
spec:
  containers:
  - name: client
    image: nicolaka/netshoot
    command: ["/bin/bash"]
    args: ["-c", "while true; do sleep 30; done"]
---
apiVersion: v1
kind: Pod
metadata:
  name: perf-test-client
  namespace: cilium-test
spec:
  containers:
  - name: client
    image: nicolaka/netshoot
    command: ["/bin/bash"]
    args: ["-c", "while true; do sleep 30; done"]
EOF

# Test CNI Overlay performance
kubectl config use-context aks-cni-overlay
kubectl exec -n cni-test perf-test-client -- iperf3 -c backend-service.cni-test.svc.cluster.local -p 80 -t 10

# Test Cilium performance  
kubectl config use-context aks-cilium
kubectl exec -n cilium-test perf-test-client -- iperf3 -c backend-service.cilium-test.svc.cluster.local -p 80 -t 10
```

## Service Mesh Capabilities

### Cilium Service Mesh Features
```bash
# Enable Cilium service mesh features (if available)
kubectl config use-context aks-cilium

# Check for Envoy integration
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg config | grep -i envoy

# Enable L7 policy (example)
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-policy
  namespace: cilium-test
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  egress:
  - toEndpoints:
    - matchLabels:
        app: backend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api.*"
EOF

# Monitor L7 traffic
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg monitor --type l7
```

## Troubleshooting Commands

### CNI Overlay Troubleshooting
```bash
# Check Azure CNI logs
kubectl logs -n kube-system -l k8s-app=azure-cni-networkmonitor

# Verify pod connectivity
kubectl exec -n cni-test $FRONTEND_POD -- nslookup backend-service.cni-test.svc.cluster.local

# Check bridge configuration on nodes
kubectl debug node/$NODE_NAME -it --image=nicolaka/netshoot -- chroot /host brctl show
```

### Cilium Troubleshooting
```bash
# Comprehensive Cilium status
cilium status --verbose

# Check connectivity between endpoints
cilium connectivity test

# Debug specific endpoint
ENDPOINT_ID=$(kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg endpoint list | grep frontend | head -1 | awk '{print $1}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg endpoint get $ENDPOINT_ID

# Check BPF program loading
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg bpf prog list

# Monitor dropped packets
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg monitor --type drop
```

### Network Policy Testing
```bash
# Test network policies on both clusters
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: cni-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: cilium-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Test connectivity after policy application
kubectl config use-context aks-cni-overlay
kubectl exec -n cni-test $FRONTEND_POD -- curl --connect-timeout 5 backend-service.cni-test.svc.cluster.local

kubectl config use-context aks-cilium  
kubectl exec -n cilium-test $FRONTEND_POD_CILIUM -- curl --connect-timeout 5 backend-service.cilium-test.svc.cluster.local
```

## Advanced Cilium Features

### Flow Monitoring and Observability
```bash
# Install Hubble (Cilium's observability platform)
cilium hubble enable

# Check Hubble status
cilium hubble ui

# Monitor real-time flows
kubectl exec -n kube-system $CILIUM_POD -- hubble observe --follow

# Filter flows by service
kubectl exec -n kube-system $CILIUM_POD -- hubble observe --service backend-service
```

### Load Balancing Algorithm Comparison
```bash
# Check current load balancing configuration
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg config | grep -i maglev

# Test different load balancing modes and observe distribution
for i in {1..10}; do
  kubectl exec -n cilium-test $FRONTEND_POD_CILIUM -- curl -s backend-service.cilium-test.svc.cluster.local | grep "backend"
done
```

## Conclusion

### Key Takeaways

1. **CNI Overlay Role**: Limited to IPAM - assigns pod IP addresses and creates basic VXLAN overlay networks
2. **Cilium Enhancement**: Provides full CNI functionality plus advanced features via eBPF
3. **Performance**: Cilium's eBPF dataplane can offer better performance than traditional iptables-based solutions
4. **Observability**: Cilium provides superior traffic visibility and monitoring capabilities
5. **Security**: Enhanced network policy enforcement and L7 policy support with Cilium

### Best Practices

- Use CNI Overlay for simple networking requirements where you only need basic pod-to-pod connectivity
- Choose Cilium when you need advanced networking features, better observability, or enhanced security policies
- Monitor both solutions using their respective tools to understand traffic patterns
- Implement network policies gradually and test connectivity after each change
- Leverage Cilium's eBPF capabilities for performance-critical applications

### Cleanup
```bash
# Clean up test resources
kubectl delete namespace cni-test cilium-test --ignore-not-found=true

# Delete clusters if no longer needed
az aks delete --resource-group cni-comparison-rg --name aks-cni-overlay --yes --no-wait
az aks delete --resource-group cni-comparison-rg --name aks-cilium --yes --no-wait
az group delete --name cni-comparison-rg --yes --no-wait
```
