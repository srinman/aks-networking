# Azure CNI Models Overview and Architecture Diagrams

## Azure CNI Models Summary

Based on the Microsoft documentation, there are **4 main Azure CNI models**:

1. **Azure CNI Overlay** (Recommended for most scenarios)
2. **Azure CNI Pod Subnet - Dynamic IP Allocation** (Recommended for flat networking)
3. **Azure CNI Pod Subnet - Static Block Allocation** (Preview - for large scale)
4. **Azure CNI Node Subnet (Legacy)** - Previously called "Azure CNI"

## Key Question: Is Azure CNI Legacy the same as CNI Pod Subnet Static?

**No, Azure CNI Legacy (Node Subnet) is NOT the same as CNI Pod Subnet Static.**

- **Azure CNI Node Subnet (Legacy)**: Pods get IPs from the **same subnet as nodes**
- **Azure CNI Pod Subnet Static**: Pods get IPs from a **separate dedicated pod subnet** with CIDR blocks allocated to nodes

## Architecture Diagrams

### 1. Azure CNI Overlay (Recommended)

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Virtual Network                    │
│                     10.0.0.0/16                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Node Subnet                             │  │
│  │             10.0.1.0/24                             │  │
│  │                                                     │  │
│  │  ┌─────────────────┐    ┌─────────────────┐       │  │
│  │  │   Node 1        │    │   Node 2        │       │  │
│  │  │  10.0.1.4       │    │  10.0.1.5       │       │  │
│  │  │                 │    │                 │       │  │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │       │  │
│  │  │  │   Pod 1   │  │    │  │   Pod 3   │  │       │  │
│  │  │  │192.168.1.1│  │    │  │192.168.2.1│  │       │  │
│  │  │  └───────────┘  │    │  └───────────┘  │       │  │
│  │  │                 │    │                 │       │  │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │       │  │
│  │  │  │   Pod 2   │  │    │  │   Pod 4   │  │       │  │
│  │  │  │192.168.1.2│  │    │  │192.168.2.2│  │       │  │
│  │  │  └───────────┘  │    │  └───────────┘  │       │  │
│  │  └─────────────────┘    └─────────────────┘       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

Pod IP Source: Private CIDR separate from VNet (192.168.0.0/16)
Traffic: Pod traffic is SNAT'd to Node IP for external communication
Scalability: Maximum cluster scale supported
IP Conservation: Excellent - pods use separate logical CIDR
```

### 2. Azure CNI Pod Subnet - Dynamic IP Allocation

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Virtual Network                    │
│                     10.0.0.0/16                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Node Subnet                             │  │
│  │             10.0.1.0/24                             │  │
│  │                                                     │  │
│  │  ┌─────────────────┐    ┌─────────────────┐       │  │
│  │  │   Node 1        │    │   Node 2        │       │  │
│  │  │  10.0.1.4       │    │  10.0.1.5       │       │  │
│  │  └─────────────────┘    └─────────────────┘       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Pod Subnet                              │  │
│  │             10.0.2.0/24                             │  │
│  │                                                     │  │
│  │     ┌───────────┐       ┌───────────┐             │  │
│  │     │   Pod 1   │       │   Pod 3   │             │  │
│  │     │ 10.0.2.10 │       │ 10.0.2.30 │             │  │
│  │     └───────────┘       └───────────┘             │  │
│  │           │                   │                    │  │
│  │     ┌───────────┐       ┌───────────┐             │  │
│  │     │   Pod 2   │       │   Pod 4   │             │  │
│  │     │ 10.0.2.20 │       │ 10.0.2.40 │             │  │
│  │     └───────────┘       └───────────┘             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

Pod IP Source: Dedicated Pod Subnet (dynamically allocated in batches of 16)
Traffic: Direct VNet connectivity - no NAT required
Scalability: Node and pod subnets scale independently
IP Conservation: Good - IPs allocated dynamically as needed
```

### 3. Azure CNI Pod Subnet - Static Block Allocation (Preview)

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Virtual Network                    │
│                     10.0.0.0/16                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Node Subnet                             │  │
│  │             10.0.1.0/24                             │  │
│  │                                                     │  │
│  │  ┌─────────────────┐    ┌─────────────────┐       │  │
│  │  │   Node 1        │    │   Node 2        │       │  │
│  │  │  10.0.1.4       │    │  10.0.1.5       │       │  │
│  │  └─────────────────┘    └─────────────────┘       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Pod Subnet                              │  │
│  │             10.0.2.0/24                             │  │
│  │                                                     │  │
│  │  ┌─────────────────────────────────────────────────┐ │  │
│  │  │ Node 1 CIDR Block: 10.0.2.0/28 (16 IPs)       │ │  │
│  │  │ ┌─────────┐ ┌─────────┐ ┌─────────┐           │ │  │
│  │  │ │  Pod 1  │ │  Pod 2  │ │ Pod N.. │           │ │  │
│  │  │ │10.0.2.1 │ │10.0.2.2 │ │10.0.2.15│           │ │  │
│  │  │ └─────────┘ └─────────┘ └─────────┘           │ │  │
│  │  └─────────────────────────────────────────────────┘ │  │
│  │                                                     │  │
│  │  ┌─────────────────────────────────────────────────┐ │  │
│  │  │ Node 2 CIDR Block: 10.0.2.16/28 (16 IPs)      │ │  │
│  │  │ ┌─────────┐ ┌─────────┐ ┌─────────┐           │ │  │
│  │  │ │  Pod 3  │ │  Pod 4  │ │ Pod N.. │           │ │  │
│  │  │ │10.0.2.17│ │10.0.2.18│ │10.0.2.31│           │ │  │
│  │  │ └─────────┘ └─────────┘ └─────────┘           │ │  │
│  │  └─────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

Pod IP Source: Dedicated Pod Subnet (pre-allocated CIDR blocks per node)
Traffic: Direct VNet connectivity - no NAT required
Scalability: Supports up to 1 million pods per cluster
IP Conservation: Optimized with /28 CIDR blocks (16 IPs per node)
Block Allocation: Each node gets /28 blocks based on max-pods configuration
```

### 4. Azure CNI Node Subnet (Legacy)

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Virtual Network                    │
│                     10.0.0.0/16                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │            Node & Pod Subnet (Same)                  │  │
│  │             10.0.1.0/24                             │  │
│  │                                                     │  │
│  │  ┌─────────────────┐    ┌─────────────────┐       │  │
│  │  │   Node 1        │    │   Node 2        │       │  │
│  │  │  10.0.1.4       │    │  10.0.1.5       │       │  │
│  │  │                 │    │                 │       │  │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │       │  │
│  │  │  │   Pod 1   │  │    │  │   Pod 3   │  │       │  │
│  │  │  │ 10.0.1.10 │  │    │  │ 10.0.1.30 │  │       │  │
│  │  │  └───────────┘  │    │  └───────────┘  │       │  │
│  │  │                 │    │                 │       │  │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │       │  │
│  │  │  │   Pod 2   │  │    │  │   Pod 4   │  │       │  │
│  │  │  │ 10.0.1.20 │  │    │  │ 10.0.1.40 │  │       │  │
│  │  │  └───────────┘  │    │  └───────────┘  │       │  │
│  │  └─────────────────┘    └─────────────────┘       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

Pod IP Source: Same subnet as nodes (shared address space)
Traffic: Direct VNet connectivity - no NAT required
Scalability: Limited by subnet size and IP exhaustion
IP Conservation: Poor - inefficient use of VNet IPs
Legacy: Not recommended for new deployments
```

## Key Differences Summary

| Feature | CNI Overlay | Pod Subnet Dynamic | Pod Subnet Static | Node Subnet (Legacy) |
|---------|-------------|-------------------|------------------|---------------------|
| **Pod IP Source** | Separate logical CIDR | Dedicated pod subnet | Dedicated pod subnet | Same as node subnet |
| **IP Allocation** | Private overlay network | Dynamic batches of 16 | Static CIDR blocks | Pre-allocated per node |
| **IPAM Provider** | Azure CNI Plugin | Azure IPAM | Azure IPAM | Azure IPAM |
| **VNet IP Usage** | Excellent conservation | Good utilization | Optimized blocks | Poor - wasteful |
| **Direct External Access** | No (SNAT'd) | Yes | Yes | Yes |
| **Max Scale** | Maximum supported | High | Up to 1M pods | Limited |
| **Routing** | Overlay routing | VNet routing | VNet routing | VNet routing |
| **Use Case** | General purpose | Direct pod access needed | Large scale clusters | Legacy only |

## Recommendations

1. **Azure CNI Overlay**: Best for most scenarios - excellent IP conservation and maximum scalability
2. **Azure CNI Pod Subnet Dynamic**: When you need direct external pod access with good IP utilization
3. **Azure CNI Pod Subnet Static**: For large-scale clusters (Preview feature)
4. **Azure CNI Node Subnet**: Avoid for new deployments - legacy option only

## Pod IP Allocation Mechanisms

### CNI Overlay
- Pods get IPs from a private, logically separate CIDR (e.g., 192.168.0.0/16)
- Traffic is SNAT'd to node IP for external communication
- No VNet IP consumption for pods

### Pod Subnet Dynamic
- IPs allocated in batches of 16 from dedicated pod subnet
- Nodes request additional batches when <8 IPs remain
- Direct VNet connectivity for pods

### Pod Subnet Static
- Each node receives /28 CIDR blocks (16 IPs) from pod subnet
- CIDR blocks pre-allocated based on max-pods configuration
- Optimal formula: max_pods = (N * 16) - 1

### Node Subnet (Legacy)
- Pods and nodes share the same subnet address space
- Each pod gets a VNet IP address directly
- Leads to IP exhaustion in large clusters

## IPAM (IP Address Management) Roles

Understanding who manages IP addresses in each CNI model is crucial for troubleshooting and planning:

### Azure CNI Overlay
- **IPAM Provider**: Azure CNI Plugin (built-in)
- **Responsibility**: 
  - Manages overlay network CIDR ranges (e.g., 192.168.0.0/16)
  - Assigns pod IPs from overlay address space
  - Handles IP allocation and deallocation within overlay network
  - No interaction with Azure VNet IPAM for pod IPs
- **IP Source**: Kubernetes node-local IP pool from overlay CIDR
- **Azure Integration**: Only node IPs are managed by Azure VNet IPAM

### Azure CNI Pod Subnet - Dynamic Allocation
- **IPAM Provider**: Azure IPAM (Azure platform service)
- **Responsibility**:
  - Manages IP allocation from dedicated pod subnet
  - Allocates IPs in batches of 16 to nodes
  - Tracks IP usage across the pod subnet
  - Handles IP reclamation when pods terminate
- **IP Source**: Azure VNet pod subnet managed by Azure IPAM
- **Batch Management**: Nodes request additional IP batches when <8 IPs remain
- **Azure Integration**: Full integration with Azure VNet IP management

### Azure CNI Pod Subnet - Static Block Allocation
- **IPAM Provider**: Azure IPAM (Azure platform service)
- **Responsibility**:
  - Pre-allocates /28 CIDR blocks (16 IPs) to nodes
  - Manages block assignment based on max-pods configuration
  - Tracks block usage and availability
  - Handles block deallocation when nodes are removed
- **IP Source**: Azure VNet pod subnet with pre-allocated CIDR blocks
- **Block Management**: Static allocation of CIDR blocks per node lifetime
- **Azure Integration**: Full integration with Azure VNet IP management and routing

### Azure CNI Node Subnet (Legacy)
- **IPAM Provider**: Azure IPAM (Azure platform service)
- **Responsibility**:
  - Pre-allocates individual VNet IPs to nodes for pod use
  - Manages IP allocation from shared node/pod subnet
  - Tracks IP usage across the entire subnet
  - Handles IP reclamation when pods terminate
- **IP Source**: Azure VNet node subnet (shared with nodes)
- **Pre-allocation**: IPs are reserved in advance based on max-pods setting
- **Azure Integration**: Full integration but inefficient IP utilization

## IPAM Comparison Summary

| CNI Model | IPAM Provider | IP Management Scope | Efficiency | Azure Integration |
|-----------|---------------|-------------------|------------|------------------|
| **CNI Overlay** | Azure CNI Plugin | Overlay network only | Excellent | Minimal (nodes only) |
| **Pod Subnet Dynamic** | Azure IPAM | Pod subnet batches | Good | Full VNet integration |
| **Pod Subnet Static** | Azure IPAM | Pod subnet blocks | Optimized | Full VNet integration |
| **Node Subnet Legacy** | Azure IPAM | Shared subnet | Poor | Full but inefficient |

### Key IPAM Considerations:

1. **CNI Overlay**: 
   - Simplest IPAM - no Azure VNet IP consumption for pods
   - Built-in CNI plugin handles all pod IP management
   - Best for IP address conservation

2. **Pod Subnet Models**: 
   - Azure IPAM provides enterprise-grade IP management
   - Full visibility and control through Azure networking tools
   - Better for scenarios requiring direct pod connectivity

3. **Legacy Node Subnet**: 
   - Azure IPAM manages everything but inefficiently
   - High risk of IP exhaustion in large deployments
   - Not recommended for new implementations
