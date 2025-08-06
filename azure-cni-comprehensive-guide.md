# Azure CNI Networking Demo - Comprehensive Guide

This consolidated guide combines the essential information about Azure CNI networking options in AKS. It provides architecture overview, visual references, and practical implementation steps.

## Lab Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              Azure Region (westus2)                                │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                    Resource Group: aks-cni-demo-rg-XXXX                    │   │
│  │                                                                             │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                VNet: aks-demo-vnet (10.0.0.0/8)                    │   │   │
│  │  │                                                                     │   │   │
│  │  │  ┌─────────────────────┐  ┌─────────────────────┐                   │   │   │
│  │  │  │   Node Subnet       │  │   Pod Subnet        │                   │   │   │
│  │  │  │   aks-nodes         │  │   aks-pods          │                   │   │   │
│  │  │  │   10.1.0.0/16       │  │   10.2.0.0/16       │                   │   │   │
│  │  │  │                     │  │                     │                   │   │   │
│  │  │  │  ┌─────┐ ┌─────┐    │  │  (Used by Pod       │                   │   │   │
│  │  │  │  │Node1│ │Node2│    │  │   Subnet CNI only)  │                   │   │   │
│  │  │  │  │10.1.│ │10.1.│    │  │                     │                   │   │   │
│  │  │  │  │0.4  │ │0.33 │    │  │                     │                   │   │   │
│  │  │  │  └─────┘ └─────┘    │  │                     │                   │   │   │
│  │  │  └─────────────────────┘  └─────────────────────┘                   │   │   │
│  │  │                                                                     │   │   │
│  │  │  ┌─────────────────────┐                                            │   │   │
│  │  │  │ External Workload   │                                            │   │   │
│  │  │  │ Subnet              │                                            │   │   │
│  │  │  │ external-workload   │                                            │   │   │
│  │  │  │ 10.3.0.0/24         │                                            │   │   │
│  │  │  │                     │                                            │   │   │
│  │  │  │  ┌─────────────┐    │                                            │   │   │
│  │  │  │  │External VM  │    │                                            │   │   │
│  │  │  │  │10.3.0.4     │    │                                            │   │   │
│  │  │  │  │(Test Client)│    │                                            │   │   │
│  │  │  │  └─────────────┘    │                                            │   │   │
│  │  │  └─────────────────────┘                                            │   │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │   │
└─────────────────────────────────────────────────────────────────────────────────────┘

                                    ┌─────────────────┐
                                    │   Internet      │
                                    │                 │
                                    │ ┌─────────────┐ │
                                    │ │httpbin.org  │ │
                                    │ │(Test Target)│ │
                                    │ └─────────────┘ │
                                    └─────────────────┘
                                            ▲
                                            │ SNAT: 4.149.161.80
                                            │ (Shared by all pods)
                                            │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            Three AKS Clusters (Created Separately)                 │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Three Azure CNI Options Explained

### 1. Traditional Azure CNI Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                Traditional CNI: aks-cni-traditional            │
│                                                                 │
│  Node Subnet (10.1.0.0/16)                                     │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │  Node 1         │              │  Node 2         │          │
│  │  IP: 10.1.0.4   │              │  IP: 10.1.0.33  │          │
│  │                 │              │                 │          │
│  │ ┌─────────────┐ │              │ ┌─────────────┐ │          │
│  │ │   Pod A     │ │              │ │   Pod B     │ │          │
│  │ │ 10.1.0.49   │ │              │ │ 10.1.0.10   │ │          │
│  │ │(netshoot)   │ │              │ │(netshoot)   │ │          │
│  │ └─────────────┘ │              │ └─────────────┘ │          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                 │
│  LoadBalancer Service: 172.179.130.77:8080                     │
│  External IP ──────────────────────────────► Pods             │
└─────────────────────────────────────────────────────────────────┘

Key: Pods share the same subnet as nodes (10.1.x.x)
```

**Characteristics:**
- Pods get IPs from the same subnet as nodes (10.1.x.x)
- External workloads can directly communicate with pods
- Highest IP consumption (1 VNet IP per pod)
- Best performance (no NAT overhead)
- Used when direct pod access is needed and IP space is abundant

### 2. Pod Subnet Azure CNI Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                Pod Subnet CNI: aks-cni-podsubnet               │
│                                                                 │
│  Node Subnet (10.1.0.0/16)        Pod Subnet (10.2.0.0/16)    │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │  Node 1         │              │ ┌─────────────┐ │          │
│  │  IP: 10.1.0.4   │              │ │   Pod A     │ │          │
│  │                 │              │ │ 10.2.0.15   │ │          │
│  └─────────────────┘              │ │(netshoot)   │ │          │
│                                   │ └─────────────┘ │          │
│  ┌─────────────────┐              │                 │          │
│  │  Node 2         │              │ ┌─────────────┐ │          │
│  │  IP: 10.1.0.33  │              │ │   Pod B     │ │          │
│  │                 │              │ │ 10.2.0.23   │ │          │
│  └─────────────────┘              │ │(netshoot)   │ │          │
│                                   │ └─────────────┘ │          │
│                                   └─────────────────┘          │
│                                                                 │
│  LoadBalancer Service: 172.180.45.123:8080                     │
│  External IP ──────────────────────────────► Pods             │
└─────────────────────────────────────────────────────────────────┘

Key: Pods use dedicated pod subnet (10.2.x.x), separate from nodes
```

**Characteristics:**
- Nodes use node subnet (10.1.x.x)
- Pods use separate pod subnet (10.2.x.x)
- External workloads can directly communicate with pods
- Medium IP consumption (dedicated subnet for pods)
- Good performance (no NAT overhead)
- Used when IP separation is needed but direct pod access is still required

### 3. Overlay Azure CNI Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                Overlay CNI: aks-cni-overlay                    │
│                                                                 │
│  Node Subnet (10.1.0.0/16)        Overlay Network             │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │  Node 1         │              │ ┌─────────────┐ │          │
│  │  IP: 10.1.0.4   │  ┌─────────► │ │   Pod A     │ │          │
│  │                 │  │ NAT       │ │192.169.0.15 │ │          │
│  └─────────────────┘  │           │ │(netshoot)   │ │          │
│                       │           │ └─────────────┘ │          │
│  ┌─────────────────┐  │           │                 │          │
│  │  Node 2         │  │           │ ┌─────────────┐ │          │
│  │  IP: 10.1.0.33  │  └─────────► │ │   Pod B     │ │          │
│  │                 │              │ │192.169.0.23 │ │          │
│  └─────────────────┘              │ │(netshoot)   │ │          │
│                                   │ └─────────────┘ │          │
│                                   └─────────────────┘          │
│                                                                 │
│  LoadBalancer Service: 172.181.67.89:8080                      │
│  External IP ──────────────────────────────► Pods             │
└─────────────────────────────────────────────────────────────────┘

Key: Pods use overlay IPs (192.169.x.x), NOT routable from VNet
```

**Characteristics:**
- Nodes use node subnet (10.1.x.x)
- Pods use overlay network IPs (192.169.x.x)
- External workloads CANNOT directly communicate with pods
- Lowest IP consumption (overlay IPs don't count against VNet)
- Good performance (minimal overlay overhead)
- Used when IP space is limited and service-based access is sufficient

## Network Flow Patterns

### Outbound Traffic (Pod → Internet)
```
All CNI Types: Same SNAT Behavior

┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Pod      │    │    Node     │    │Azure SNAT   │    │  Internet   │
│             │────│             │────│             │────│             │
│ 10.1.x.x    │    │ 10.1.x.x    │    │4.149.161.80 │    │httpbin.org  │
│ 10.2.x.x    │    │             │    │(Shared)     │    │             │
│192.169.x.x  │    │             │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘

Result: All pods share the same external IP (4.149.161.80)
```

### Inbound Traffic (External → Pod)

#### Traditional & Pod Subnet CNI: Direct Access
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│External VM  │    │   VNet      │    │    Pod      │
│             │────│  Routing    │────│             │
│ 10.3.0.4    │    │             │    │ 10.1.x.x or │
│             │    │             │    │ 10.2.x.x    │
└─────────────┘    └─────────────┘    └─────────────┘

Result: ✅ Direct connectivity works
```

#### Overlay CNI: Service-Only Access
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│External VM  │    │LoadBalancer │    │    Node     │    │    Pod      │
│             │────│   Service   │────│             │────│             │
│ 10.3.0.4    │    │172.x.x.x    │    │ 10.1.x.x    │    │192.169.x.x  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘

Direct Access:
┌─────────────┐                                         ┌─────────────┐
│External VM  │ ╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳ │    Pod      │
│ 10.3.0.4    │                BLOCKED                  │192.169.x.x  │
└─────────────┘                                         └─────────────┘

Result: ❌ Direct connectivity fails (expected)
       ✅ LoadBalancer service works
```

## Comparison Summary

| Feature | Traditional CNI | Pod Subnet CNI | Overlay CNI |
|---------|----------------|----------------|-------------|
| **Pod IP Assignment** | From node subnet | From dedicated pod subnet | From overlay CIDR |
| **Node IPs** | 10.1.x.x | 10.1.x.x | 10.1.x.x |
| **Pod IPs** | 10.1.x.x | 10.2.x.x | 192.169.x.x |
| **External Connectivity** | Direct routing | Direct routing | NAT required |
| **External → Pod Direct** | ✅ Works | ✅ Works | ❌ Blocked |
| **Pod → Internet** | ✅ Works | ✅ Works | ✅ Works |
| **External → LoadBalancer** | ✅ Works | ✅ Works | ✅ Works |
| **SNAT Behavior** | Same for all | Same for all | Same for all |
| **IP Address Efficiency** | Low (1:1 VNet IP per pod) | Medium | High |
| **Performance** | Best | Good | Good |
| **Scale Limitations** | VNet IP exhaustion | Pod subnet size | None |
| **Network Policies** | Supported | Supported | Supported |

## Quick Start Commands

```bash
# 1. Setup everything
./setup-demo.sh all

# 2. Test traditional CNI
az aks get-credentials --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --name aks-cni-traditional --overwrite-existing
./vm-helper-enhanced.sh network-test

# 3. Test pod subnet CNI  
az aks get-credentials --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --name aks-cni-podsubnet --overwrite-existing
./vm-helper-enhanced.sh network-test

# 4. Test overlay CNI
az aks get-credentials --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --name aks-cni-overlay --overwrite-existing  
./vm-helper-enhanced.sh network-test

# 5. Cleanup
./setup-demo.sh cleanup
```

## Key Commands During Demo

```bash
# Always check where you are
kubectl config current-context

# See the IP allocation pattern  
kubectl get nodes -o wide
kubectl get pods -o wide

# Test external connectivity
kubectl exec -it $(kubectl get pods -o name | head -1) -- curl -s https://httpbin.org/ip

# Test from external VM
./vm-helper-enhanced.sh network-test
```

## Learning Checkpoints

### After Traditional CNI
- Pods share node subnet (10.1.x.x)
- External VM can ping pod IPs directly
- Understand high IP usage impact

### After Pod Subnet CNI  
- Pods use separate subnet (10.2.x.x)
- External VM can still ping pod IPs directly
- Understand subnet separation benefits

### After Overlay CNI
- Pods use overlay IPs (192.169.x.x)  
- External VM CANNOT ping pod IPs directly
- LoadBalancer still works for external access
- Understand when to use overlay vs traditional

### Overall Understanding
- All pods share same SNAT IP for outbound traffic
- LoadBalancer services work with all CNI types
- Choose CNI based on IP availability and access needs

## Troubleshooting Quick Fixes

| Problem | Quick Fix |
|---------|-----------|
| VM creation fails | Script tries multiple sizes automatically |
| Pods stuck pending | Check `kubectl describe pod <name>` |
| LoadBalancer pending | Wait 5-10 minutes or check quotas |
| Wrong cluster context | Use `az aks get-credentials` command |
| Network test fails | Check pod status with `kubectl get pods` |

**Remember**: Overlay CNI direct access failures are EXPECTED! This is by design.

## When to Use Each Option

1. **Azure CNI Traditional**: When you need maximum performance and full VNet integration
   - Best for scenarios requiring direct pod access from other VNet resources
   - Use when IP address space is abundant

2. **Azure CNI Pod Subnet**: When you want VNet integration but better IP management
   - Good for scenarios requiring direct pod access with separate security policies
   - Use when IP address space is adequate but needs to be managed efficiently

3. **Azure CNI Overlay**: When you need maximum scalability and efficient IP usage
   - Best for large clusters or environments with limited IP address space
   - Use when direct pod access from VNet is not required

## Cleanup

```bash
./setup-demo.sh cleanup
```

This guide consolidates all the information you need to understand and demonstrate Azure CNI networking options in AKS. For detailed step-by-step testing procedures, refer to the `step-by-step-testing-guide.md`.
