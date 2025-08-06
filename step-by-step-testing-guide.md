# Azure CNI Networking Demo - Step-by-Step Testing Guide

This guide provides detailed instructions for trainees to test Azure CNI networking options. Each section includes commands to run, expected outputs, and verification steps.

## Prerequisites Check

Before starting the demo, verify your environment is ready.

### Step 1: Check Azure CLI
```bash
az --version
```
**Expected Output:** Should show Azure CLI version (2.x.x or higher)
**Verification:** ✅ If you see version info, ❌ If command not found - install Azure CLI

### Step 2: Check kubectl
```bash
kubectl version --client
```
**Expected Output:** Should show kubectl client version
**Verification:** ✅ If you see version info, ❌ If command not found - install kubectl

### Step 3: Verify Azure Login
```bash
az account show
```
**Expected Output:** Should show your Azure subscription details
**Verification:** ✅ If you see subscription info, ❌ If error - run `az login`

---

## Lab Setup

### Step 4: Set Up Infrastructure
```bash
./setup-demo.sh infra
```
**Expected Output:** 
- Green [INFO] messages showing progress
- Resource group creation confirmation
- VNet and subnet creation confirmations
- External workload VM creation

**What to Look For:**
- ✅ "Prerequisites check passed!"
- ✅ "Creating resource group: aks-cni-demo-rg-XXXXXX"
- ✅ "Creating VNet: aks-demo-vnet"
- ✅ "External workload created with IP: 10.3.0.X"
- ❌ Any red [ERROR] messages

**If You See Errors:**
- VM creation failed: Script will try different VM sizes automatically
- If all VM sizes fail: Script will try Azure Container Instance as fallback
- Region capacity issues: Script uses westus2 which typically has capacity

### Step 5: Verify Infrastructure
```bash
# Check resource group
az group list --query "[?contains(name, 'aks-cni-demo-rg')].{Name:name, Location:location}" --output table

# Check VNet and subnets
az network vnet subnet list --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --vnet-name aks-demo-vnet --output table
```

**Expected Output:**
- Resource group with timestamp in name
- Four subnets: aks-nodes (10.1.0.0/16), aks-pods (10.2.0.0/16), external-workload (10.3.0.0/24), default

**Verification:** ✅ All subnets exist with correct address spaces

---

## Traditional Azure CNI Testing

### Step 6: Create Traditional CNI Cluster
```bash
./setup-demo.sh traditional
```
**Expected Output:**
- Cluster creation progress (takes 5-10 minutes)
- Pod deployment confirmation
- "Netshoot deployment completed for aks-cni-traditional"

**What to Look For:**
- ✅ "AKS cluster aks-cni-traditional created successfully!"
- ✅ "Netshoot deployment completed"
- ❌ Any timeout or failure messages

### Step 7: Examine Node and Pod IPs
```bash
# Get current cluster context
kubectl config current-context

# Check nodes and their IPs
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME                              STATUS   ROLES   AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE
aks-nodepool1-xxxxx-vmss000000    Ready    agent   5m    v1.x.x    10.1.0.4      <none>       Ubuntu 22.04
aks-nodepool1-xxxxx-vmss000001    Ready    agent   5m    v1.x.x    10.1.0.33     <none>       Ubuntu 22.04
```

**Key Points to Understand:**
- ✅ Node IPs are from node subnet (10.1.x.x)
- ✅ Each node has a unique IP from the 10.1.0.0/16 range

### Step 8: Check Pod IPs
```bash
# Check pod IPs and locations
kubectl get pods -o wide
```

**Expected Output:**
```
NAME                                   READY   STATUS    IP          NODE
netshoot-traditional-xxxxx-xxxxx       1/1     Running   10.1.0.49   aks-nodepool1-xxxxx-vmss000000
netshoot-traditional-xxxxx-xxxxx       1/1     Running   10.1.0.10   aks-nodepool1-xxxxx-vmss000001
```

**Key Points to Understand:**
- ✅ **IMPORTANT:** In Traditional CNI, pods get IPs from the SAME subnet as nodes (10.1.x.x)
- ✅ Each pod has a unique IP from the node subnet
- ✅ This is why Traditional CNI uses many IP addresses

### Step 9: Test External Connectivity (Pod to Outside)
```bash
# Test from first pod
kubectl exec -it $(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[0].metadata.name}') -- curl -s https://httpbin.org/ip
```

**Expected Output:**
```json
{
  "origin": "4.149.161.80"
}
```

**Key Points to Understand:**
- ✅ The "origin" IP is the SNAT (Source NAT) IP - the public IP that external services see
- ✅ This is NOT the pod's private IP (10.1.x.x)
- ✅ Azure automatically translates the pod's private IP to this public IP

### Step 10: Verify SNAT Behavior
```bash
# Check from both pods to see if they share the same SNAT IP
echo "=== Pod 1 External IP ==="
kubectl exec -it $(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[0].metadata.name}') -- curl -s https://httpbin.org/ip

echo "=== Pod 2 External IP ==="
kubectl exec -it $(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[1].metadata.name}') -- curl -s https://httpbin.org/ip
```

**Expected Output:**
Both pods should show the same external IP (SNAT IP)

**Key Points to Understand:**
- ✅ Both pods share the same outbound public IP
- ✅ This is Azure's SNAT behavior for AKS clusters
- ✅ Multiple pods can share the same SNAT IP with different source ports

### Step 11: Test External-to-Pod Connectivity
```bash
# Get LoadBalancer service external IP
kubectl get service netshoot-traditional-svc
```

**Expected Output:**
```
NAME                      TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
netshoot-traditional-svc  LoadBalancer   192.168.x.x    172.179.130.77   8080:xxxxx/TCP
```

Wait for EXTERNAL-IP to show (may take 2-3 minutes). If it shows `<pending>`, wait and check again.

### Step 12: Test from External Workload to Pod
```bash
# Use the enhanced helper script to test connectivity
# This script automatically detects the current cluster context and pod IPs
./vm-helper-enhanced.sh network-test
```

**Expected Output:**
```
==============================================
  Network Connectivity Test
==============================================
[ℹ️  INFO] External workload IP: 10.3.0.4
[ℹ️  INFO] Current cluster context: aks-cni-traditional
==============================================
  Traditional Azure CNI Testing
==============================================
[ℹ️  INFO] Pod IPs in node subnet: 10.1.0.49 10.1.0.10
Testing connectivity to pod 10.1.0.49: [✅ SUCCESS] REACHABLE
Testing connectivity to pod 10.1.0.10: [✅ SUCCESS] REACHABLE
```

**How It Works:**
- ✅ Script automatically detects current kubectl context (`aks-cni-traditional`)
- ✅ Script queries Kubernetes API to get pod IPs: `kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[*].status.podIP}'`
- ✅ Script tests connectivity from external workload VM to each discovered pod IP

**Key Points to Understand:**
- ✅ External workload (10.3.0.4) can ping pod IPs directly (10.1.x.x)
- ✅ This works because pods have real VNet IPs in Traditional CNI
- ✅ The script automatically discovers which pod IPs to test based on the cluster type

### Step 13: Analyze Network Paths
```bash
# Run comprehensive network analysis
./analyze-networking.sh traditional
```

**Expected Output:**
```
=== Traditional Azure CNI Analysis ===
Node Subnet: 10.1.0.0/16
Pod IPs: Same as node subnet
SNAT IP: 4.149.161.80
External Connectivity: Direct VNet routing
LoadBalancer: 172.179.130.77
```

**Key Points to Understand:**
- ✅ Pods use node subnet IPs - this is the defining characteristic of Traditional CNI
- ✅ Direct VNet routing means no additional NAT for pod-to-pod or external-to-pod within VNet
- ✅ Only outbound internet traffic gets SNAT translation

---

## Pod Subnet CNI Testing

### Step 14: Create Pod Subnet CNI Cluster
```bash
./setup-demo.sh podsubnet
```

**Expected Output:**
Similar to traditional, but for "aks-cni-podsubnet" cluster

### Step 15: Switch to Pod Subnet Cluster
```bash
# Get credentials for pod subnet cluster
az aks get-credentials --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --name aks-cni-podsubnet --overwrite-existing

# Verify context
kubectl config current-context
```

**Expected Output:**
Should show "aks-cni-podsubnet" context

### Step 16: Compare Node and Pod IPs
```bash
# Check nodes
echo "=== NODES ==="
kubectl get nodes -o wide

# Check pods
echo "=== PODS ==="
kubectl get pods -o wide
```

**Expected Output:**
```
=== NODES ===
NAME                              INTERNAL-IP   
aks-nodepool1-xxxxx-vmss000000    10.1.0.4     (node subnet)
aks-nodepool1-xxxxx-vmss000001    10.1.0.33    (node subnet)

=== PODS ===
NAME                                IP          
netshoot-podsubnet-xxxxx-xxxxx      10.2.0.15   (pod subnet!)
netshoot-podsubnet-xxxxx-xxxxx      10.2.0.23   (pod subnet!)
```

**Key Points to Understand:**
- ✅ **IMPORTANT:** Nodes still use node subnet (10.1.x.x)
- ✅ **IMPORTANT:** Pods now use pod subnet (10.2.x.x) - this is the key difference!
- ✅ This separation allows better IP management and security policies

### Step 17: Test Pod Subnet External Connectivity
```bash
# Test external connectivity (should work the same)
kubectl exec -it $(kubectl get pods -l app=netshoot-podsubnet -o jsonpath='{.items[0].metadata.name}') -- curl -s https://httpbin.org/ip
```

**Expected Output:**
Same SNAT IP as traditional CNI (pods still share the cluster's outbound IP)

**Key Points to Understand:**
- ✅ Pod subnet CNI still uses the same SNAT behavior
- ✅ The difference is in internal IP allocation, not external connectivity

### Step 18: Test External-to-Pod with Pod Subnet
```bash
# Test connectivity from external workload (script auto-detects pod subnet cluster)
./vm-helper-enhanced.sh network-test
```

**Expected Output:**
```
==============================================
  Network Connectivity Test
==============================================
[ℹ️  INFO] External workload IP: 10.3.0.4
[ℹ️  INFO] Current cluster context: aks-cni-podsubnet
==============================================
  Pod Subnet Azure CNI Testing
==============================================
[ℹ️  INFO] Pod IPs in pod subnet: 10.2.0.15 10.2.0.23
Testing connectivity to pod 10.2.0.15: [✅ SUCCESS] REACHABLE
Testing connectivity to pod 10.2.0.23: [✅ SUCCESS] REACHABLE
```

**Key Points to Understand:**
- ✅ External workload can still reach pods directly
- ✅ Pod subnet IPs (10.2.x.x) are routable within the VNet
- ✅ No additional NAT required for VNet-internal communication

---

## Overlay CNI Testing

### Step 19: Create Overlay CNI Cluster
```bash
./setup-demo.sh overlay
```

**Expected Output:**
Similar creation process for "aks-cni-overlay" cluster

### Step 20: Switch to Overlay Cluster
```bash
# Get credentials for overlay cluster
az aks get-credentials --resource-group $(az group list --query "[?contains(name, 'aks-cni-demo-rg')].name" --output tsv) --name aks-cni-overlay --overwrite-existing

# Verify context
kubectl config current-context
```

### Step 21: Examine Overlay Networking
```bash
# Check nodes and pods
echo "=== NODES ==="
kubectl get nodes -o wide

echo "=== PODS ==="
kubectl get pods -o wide
```

**Expected Output:**
```
=== NODES ===
NAME                              INTERNAL-IP   
aks-nodepool1-xxxxx-vmss000000    10.1.0.4     (node subnet)
aks-nodepool1-xxxxx-vmss000001    10.1.0.33    (node subnet)

=== PODS ===
NAME                                IP            
netshoot-overlay-xxxxx-xxxxx        192.169.0.15  (overlay network!)
netshoot-overlay-xxxxx-xxxxx        192.169.0.23  (overlay network!)
```

**Key Points to Understand:**
- ✅ **IMPORTANT:** Nodes still use node subnet (10.1.x.x)
- ✅ **IMPORTANT:** Pods use overlay network (192.169.x.x) - completely different range!
- ✅ These are not routable VNet IPs - they exist only within the cluster

### Step 22: Test Overlay External Connectivity
```bash
# Test external connectivity
kubectl exec -it $(kubectl get pods -l app=netshoot-overlay -o jsonpath='{.items[0].metadata.name}') -- curl -s https://httpbin.org/ip
```

**Expected Output:**
Same SNAT IP as other clusters

**Key Points to Understand:**
- ✅ Overlay pods still reach internet through the same SNAT mechanism
- ✅ Overlay IPs are translated to node IPs, then to public SNAT IP

### Step 23: Test External-to-Overlay Limitations
```bash
# Test direct connectivity to overlay IPs (this should FAIL)
./vm-helper-enhanced.sh network-test
```

**Expected Output:**
```
==============================================
  Network Connectivity Test
==============================================
[ℹ️  INFO] External workload IP: 10.3.0.4
[ℹ️  INFO] Current cluster context: aks-cni-overlay
==============================================
  Overlay Azure CNI Testing
==============================================
[ℹ️  INFO] Pod IPs in overlay network: 192.169.0.15 192.169.0.23
Testing connectivity to pod 192.169.0.15: [❌ ERROR] UNREACHABLE
Testing connectivity to pod 192.169.0.23: [❌ ERROR] UNREACHABLE
[⚠️  WARNING] Overlay IPs are not routable from external networks
```

**Key Points to Understand:**
- ❌ **IMPORTANT:** External workload CANNOT reach overlay IPs directly
- ✅ This is expected! Overlay IPs are not routable from outside the cluster
- ✅ This demonstrates the key limitation of overlay networking

### Step 24: Test LoadBalancer Access to Overlay Pods
```bash
# Get LoadBalancer service IP
kubectl get service netshoot-overlay-svc

# Test LoadBalancer connectivity using enhanced script
./vm-helper-enhanced.sh test-loadbalancer
```

**Expected Output:**
LoadBalancer should work normally - external connectivity is maintained through the service

**Key Points to Understand:**
- ✅ LoadBalancer services work with overlay CNI
- ✅ Services provide the translation layer from external to overlay IPs
- ✅ This is how external traffic reaches overlay pods

---

## Comprehensive Comparison

### Step 25: Run Full Network Analysis
```bash
./analyze-networking.sh compare
```

**Expected Output:**
```
=== CNI Comparison Summary ===

Traditional CNI:
- Node IPs: 10.1.x.x (node subnet)
- Pod IPs: 10.1.x.x (same as nodes)
- External access: Direct IP connectivity
- SNAT IP: 4.149.161.80

Pod Subnet CNI:
- Node IPs: 10.1.x.x (node subnet)  
- Pod IPs: 10.2.x.x (dedicated pod subnet)
- External access: Direct IP connectivity
- SNAT IP: 4.149.161.80

Overlay CNI:
- Node IPs: 10.1.x.x (node subnet)
- Pod IPs: 192.169.x.x (overlay network)
- External access: Through LoadBalancer only
- SNAT IP: 4.149.161.80
```

### Step 26: Understand the Trade-offs

**IP Address Usage:**
- Traditional CNI: Highest (pods consume VNet IPs)
- Pod Subnet CNI: Medium (pods use dedicated subnet)
- Overlay CNI: Lowest (pods use overlay IPs)

**External Connectivity:**
- Traditional CNI: Direct pod access ✅
- Pod Subnet CNI: Direct pod access ✅
- Overlay CNI: Service-based access only ❌

**Security:**
- Traditional CNI: Pod IPs exposed in VNet
- Pod Subnet CNI: Pod subnet can have separate NSG rules
- Overlay CNI: Pod IPs hidden from VNet

**Performance:**
- Traditional CNI: Best (no additional NAT)
- Pod Subnet CNI: Good (no additional NAT)
- Overlay CNI: Good (minimal overhead for overlay)

---

## Cleanup

### Step 27: Clean Up Resources
```bash
./setup-demo.sh cleanup
```

**Follow the prompts and confirm deletion when ready.**

---

## Summary of Key Learning Points

### 1. IP Allocation Patterns
- **Traditional:** Pods share node subnet
- **Pod Subnet:** Pods get dedicated subnet  
- **Overlay:** Pods get non-routable overlay IPs

### 2. External Connectivity
- **Outbound (Pod → Internet):** All CNI types use SNAT
- **Inbound (External → Pod):** Traditional and Pod Subnet allow direct access; Overlay requires services

### 3. Use Case Recommendations
- **Traditional CNI:** When you have plenty of IP space and need direct pod access
- **Pod Subnet CNI:** When you want IP separation but still need direct access
- **Overlay CNI:** When IP space is limited and service-based access is sufficient

### 4. Troubleshooting Tips
- Always check pod IPs with `kubectl get pods -o wide`
- Use `kubectl exec` to test connectivity from inside pods
- Remember that overlay IPs are not VNet-routable
- LoadBalancer services work with all CNI types

This completes the comprehensive Azure CNI networking demonstration!
