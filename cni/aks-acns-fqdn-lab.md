# Azure AKS ACNS FQDN Filtering Lab Guide

## Overview

This lab demonstrates FQDN-based network policies using Azure CNI Powered by Cilium (ACNS) in Azure Kubernetes Service (AKS). You'll learn how to control egress traffic to specific public websites using domain names and understand the critical role of DNS inspection in FQDN filtering.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AKS Cluster with ACNS                       │
│                                                                 │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │   app1ns        │              │   app2ns        │          │
│  │                 │              │                 │          │
│  │ ┌─────────────┐ │              │ ┌─────────────┐ │          │
│  │ │   Pod A     │ │              │ │   Pod B     │ │          │
│  │ │ (GitHub)    │ │              │ │ (Google)    │ │          │
│  │ └─────────────┘ │              │ └─────────────┘ │          │
│  └─────────────────┘              └─────────────────┘          │
│           │                                   │                │
│           │ ✅ github.com                    │ ✅ google.com   │
│           │ ❌ google.com                     │ ❌ github.com   │
│           ▼                                 ▼                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Internet                             │   │
│  │                                                         │   │
│  │  ┌──────────────┐              ┌──────────────┐        │   │
│  │  │  github.com  │              │ google.com   │        │   │
│  │  │  api.github  │              │ *.google.com │        │   │
│  │  └──────────────┘              └──────────────┘        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Azure CLI installed and logged in
- kubectl installed
- Azure subscription with appropriate permissions
- Basic understanding of Kubernetes networking concepts

## Part 1: Create AKS Cluster with ACNS

### Step 1: Set Environment Variables

```bash
# Set variables
RESOURCE_GROUP="aksadv-acns-lab-rg"
LOCATION="eastus2"  # Changed from eastus due to VM size availability
CLUSTER_NAME="aksadv-acns-cluster"
STORAGE_ACCOUNT="srinmanapp1stgtst"

echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Cluster Name: $CLUSTER_NAME"
```

### Step 2: Create Resource Group

```bash
# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Verify creation
az group show --name $RESOURCE_GROUP --query "{Name:name, Location:location, State:properties.provisioningState}" --output table
```

**Expected Output:**
```
Name              Location    State
aksadv-acns-lab-rg   eastus2     Succeeded
```

### Step 2.5: Check Available VM Sizes (Optional)

```bash
# Check available VM sizes in your region
echo "Checking available VM sizes in $LOCATION..."
az vm list-skus --location $LOCATION --resource-type virtualMachines --query "[?starts_with(name, 'Standard_D2') || starts_with(name, 'Standard_B2')].{Name:name, Available:restrictions}" --output table

# If Standard_D2s_v3 is not available, you can use one of these alternatives:
# --node-vm-size Standard_D2s_v4  
# --node-vm-size Standard_D2s_v5
# --node-vm-size Standard_D2as_v4
```

### Step 3: Create AKS Cluster with ACNS

```bash
# Create AKS cluster with Azure CNI Powered by Cilium
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --enable-acns \
    --node-count 2 \
    --node-vm-size Standard_D2s_v3 \
    --generate-ssh-keys \
    --enable-managed-identity \
    --output table

echo "✅ AKS cluster creation initiated. This will take 10-15 minutes..."
```

**Key Parameters Explained:**
- `--network-plugin azure`: Uses Azure CNI
- `--network-plugin-mode overlay`: Uses overlay networking
- `--network-dataplane cilium`: Enables Cilium as the network dataplane
- `--enable-acns`: Enables advanced network functionalities (ACNS features)

**What `--enable-acns` Provides:**
- Enhanced FQDN filtering capabilities
- Advanced network observability features
- Additional security and monitoring capabilities
- Note: This flag may incur additional costs

**VM Size Notes:**
- Changed to `Standard_D2s_v3` for better availability across regions
- If this size is not available, try: `Standard_B2s`, `Standard_D2s_v4`, or `Standard_D2s_v5`

### Step 4: Get Cluster Credentials

```bash
# Get credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing

# Verify cluster access
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME                                STATUS   ROLES   AGE   VERSION   INTERNAL-IP   
aks-nodepool1-xxxxx-vmss000000     Ready    agent   5m    v1.28.x   10.224.0.4
aks-nodepool1-xxxxx-vmss000001     Ready    agent   5m    v1.28.x   10.224.0.35
```

### Step 5: Verify Cilium Installation

```bash
# Check Cilium pods
kubectl get pods -n kube-system | grep cilium

# Check Cilium version
kubectl exec -n kube-system ds/cilium -- cilium-dbg version
```

**Expected Output:**
```
cilium-xxxxx        1/1     Running   0          5m
cilium-xxxxx        1/1     Running   0          5m
cilium-operator-xxx 1/1     Running   0          5m
```

## Part 2: Create Namespaces and Applications

### Step 6: Create Namespaces

```bash
# Create app1ns namespace (GitHub access only)
kubectl create namespace app1ns

# Create app2ns namespace (Google access only)
kubectl create namespace app2ns

# Verify namespaces
kubectl get namespaces | grep app
```

**Expected Output:**
```
app1ns    Active   30s
app2ns    Active   25s
```

### Step 7: Deploy Test Applications

```bash
# Deploy test pod in app1ns
```bash
# Deploy test pod in app1ns
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-app1
  namespace: app1ns
  labels:
    app: test-app1
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    env:
    - name: NAMESPACE
      value: "app1ns"
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-app2
  namespace: app2ns
  labels:
    app: test-app2
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    env:
    - name: NAMESPACE
      value: "app2ns"
EOF

# Wait for pods to be ready
kubectl wait --for=condition=ready pod/test-pod-app1 -n app1ns --timeout=300s
kubectl wait --for=condition=ready pod/test-pod-app2 -n app2ns --timeout=300s

# Verify pods
kubectl get pods -n app1ns
kubectl get pods -n app2ns
```

## Part 3: FQDN Network Policies - The Critical DNS Rules

### 🚨 Important Note: DNS Rules Are Essential

**Why `rules.dns` is Critical:**

FQDN filtering won't work without the `rules.dns` section. This section is essential because it allows Cilium to:

1. **Inspect DNS traffic** - Intercept and analyze DNS queries
2. **Extract resolved IPs** - Capture the IP addresses returned by DNS responses
3. **Populate FQDN cache** - Store domain-to-IP mappings for policy enforcement
4. **Enforce HTTP requests** - Use the cache to allow/deny subsequent HTTP requests

**DNS Inspection Flow:**
```
1. Pod makes DNS query (e.g., "www.bing.com")
2. Cilium inspects DNS query against rules.dns.matchPattern
3. DNS response returns IP (e.g., 13.107.42.14)
4. Cilium stores IP in FQDN cache
5. Pod makes HTTP request to 13.107.42.14
6. Cilium checks if IP exists in FQDN cache
7. If found → Allow, If not found → Deny
```

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg fqdn cache list
``` 

### Step 8: Create FQDN Policy for GitHub Access (app1ns)

```bash
# Create network policy allowing app1ns to access GitHub only
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-app1
  namespace: app1ns
spec:
  endpointSelector:
    matchLabels:
      app: test-app1
  egress:
  # Allow DNS to CoreDNS for name resolution
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": kube-system
        "k8s:k8s-app": kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*.github.com"
        - matchPattern: "github.com"
        - matchPattern: "${STORAGE_ACCOUNT}.privatelink.blob.core.windows.net"
        - matchPattern: "${STORAGE_ACCOUNT}.blob.core.windows.net"
  # Allow HTTPS access to GitHub domains
  - toFQDNs:
    - matchPattern: "*.github.com"
    - matchPattern: "github.com"
    - matchPattern: "${STORAGE_ACCOUNT}.privatelink.blob.core.windows.net"
    - matchPattern: "${STORAGE_ACCOUNT}.blob.core.windows.net"
EOF

echo "✅ Network policy created for app1ns (GitHub access only)"
```

### Step 9: Create FQDN Policy for Google Access (app2ns)

```bash
# Create network policy allowing app2ns to access Google only
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-google-app2
  namespace: app2ns
spec:
  endpointSelector:
    matchLabels:
      app: test-app2
  egress:
  # Allow DNS to CoreDNS for name resolution
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": kube-system
        "k8s:k8s-app": kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "google.com"
        - matchPattern: "*.google.com"
        - matchPattern: "www.google.com"
  # Allow HTTPS access to Google domains
  - toFQDNs:
    - matchPattern: "google.com"
  - toFQDNs:
    - matchPattern: "*.google.com"
  - toFQDNs:
    - matchPattern: "www.google.com"
EOF

echo "✅ Network policy created for app2ns (Google access only)"
```

### Step 10: Verify Policies Are Applied

```bash
# Check applied policies
kubectl get ciliumnetworkpolicies -A

# Get policy details
kubectl describe ciliumnetworkpolicy allow-github-app1 -n app1ns
kubectl describe ciliumnetworkpolicy allow-google-app2 -n app2ns
```

## Part 4: Testing FQDN Filtering

### Step 11: Test Website Access

```bash
echo "🧪 Testing Website Access..."

# Test from app1ns (should access GitHub only)
echo "=== Testing from app1ns (GitHub access only) ==="
echo "✅ Testing GitHub access (should SUCCEED):"
kubectl exec -n app1ns test-pod-app1 -- wget https://github.com
kubectl exec -n app1ns test-pod-app1 -- wget https://api.github.com
kubectl exec -n app1ns test-pod-app1 -- wget https://${STORAGE_ACCOUNT}.blob.core.windows.net



echo "❌ Testing Google access (should FAIL):"
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://www.google.com

echo ""
echo "=== Testing from app2ns (Google access only) ==="
echo "✅ Testing Google access (should SUCCEED):"
kubectl exec -n app2ns test-pod-app2 -- curl -I --connect-timeout 10 --max-time 15 https://www.google.com
kubectl exec -n app2ns test-pod-app2 -- curl -I --connect-timeout 10 --max-time 15 https://google.com

echo "❌ Testing GitHub access (should FAIL):"
kubectl exec -n app2ns test-pod-app2 -- curl -I --connect-timeout 10 --max-time 15 https://github.com
```

**Expected Results:**
- **app1ns**: GitHub access succeeds ✅, Google access fails ❌
- **app2ns**: Google access succeeds ✅, GitHub access fails ❌

### Step 12: Test Additional Blocked Sites

```bash
echo "🧪 Testing Additional Blocked Sites..."

# Test other popular sites (should all be blocked)
echo "=== Testing blocked sites from app1ns ==="
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://www.microsoft.com
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://www.facebook.com

echo "=== Testing blocked sites from app2ns ==="
kubectl exec -n app2ns test-pod-app2 -- curl -I --connect-timeout 10 --max-time 15 https://www.microsoft.com
kubectl exec -n app2ns test-pod-app2 -- curl -I --connect-timeout 10 --max-time 15 https://www.facebook.com
```

**Expected Results:**
- All non-allowed sites should fail/timeout ❌

### Step 13: Examine Cilium FQDN Cache

```bash
echo "🔍 Examining Cilium FQDN Cache..."

# Get Cilium pod names
CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}')

# Check FQDN cache on first Cilium pod
CILIUM_POD=$(echo $CILIUM_PODS | cut -d' ' -f1)
echo "Checking FQDN cache on pod: $CILIUM_POD"

kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg fqdn cache list
```

**Expected Output:**
You should see cached entries for domains that were successfully resolved through DNS inspection.

## Part 5: Advanced Testing and Troubleshooting

### Step 14: Demonstrate DNS Rules Importance

```bash
# Create a policy WITHOUT DNS rules (incorrect policy)
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: incorrect-policy-no-dns
  namespace: app1ns
spec:
  endpointSelector:
    matchLabels:
      app: test-app1
  egress:
  - toFQDNs:
    - matchPattern: "httpbin.org"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      - port: "80"
        protocol: TCP
    # ❌ MISSING: rules.dns section
EOF

echo "❌ Created INCORRECT policy without DNS rules"

# Test the incorrect policy (should fail due to missing DNS rules)
echo "Testing incorrect policy (should FAIL):"
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://httpbin.org

# Clean up the incorrect policy
kubectl delete ciliumnetworkpolicy incorrect-policy-no-dns -n app1ns
```

### Step 15: Monitor Network Policies

```bash
# Create more sophisticated SaaS filtering
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: advanced-saas-filtering
  namespace: app1ns
spec:
  endpointSelector:
    matchLabels:
      app: test-app1
  egress:
  # Allow specific Microsoft services
  - toFQDNs:
    - matchPattern: "*.office.com"
    - matchPattern: "*.microsoft.com"
    - matchPattern: "*.azure.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
    rules:
      dns:
      - matchPattern: "*.office.com"
      - matchPattern: "*.microsoft.com"
      - matchPattern: "*.azure.com"
  
  # Allow specific AWS services
  - toFQDNs:
    - matchPattern: "*.amazonaws.com"
    - matchPattern: "s3.amazonaws.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
    rules:
      dns:
      - matchPattern: "*.amazonaws.com"
      - matchPattern: "s3.amazonaws.com"
  
  # Block social media (by not including them)
  # - Facebook, Twitter, Instagram, etc. will be blocked by default
  
  # Allow container registries
  - toFQDNs:
    - matchPattern: "*.docker.io"
    - matchPattern: "registry-1.docker.io"
    - matchPattern: "*.azurecr.io"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
    rules:
      dns:
      - matchPattern: "*.docker.io"
      - matchPattern: "registry-1.docker.io"
      - matchPattern: "*.azurecr.io"
EOF

echo "✅ Advanced SaaS filtering policy applied"
```

### Step 21: Test Advanced Filtering

```bash
echo "🧪 Testing Advanced SaaS Filtering..."

# Test allowed services
echo "=== Testing ALLOWED services ==="
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://www.microsoft.com
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://portal.azure.com

# Test blocked services (these should fail)
echo "=== Testing BLOCKED services ==="
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://www.facebook.com
kubectl exec -n app1ns test-pod-app1 -- curl -I --connect-timeout 10 --max-time 15 https://twitter.com
```

## Part 7: Monitoring and Troubleshooting

### Step 22: Monitor Network Policies

```bash
# Check policy status
kubectl get ciliumnetworkpolicies -A -o wide

# View policy details
kubectl describe ciliumnetworkpolicy allow-github-app1 -n app1ns
kubectl describe ciliumnetworkpolicy allow-google-app2 -n app2ns

# Check Cilium agent logs for policy violations
kubectl logs -n kube-system -l k8s-app=cilium --tail=50 | grep -i "denied\|drop\|fqdn"
```

### Step 16: Debug FQDN Issues

```bash
# Check DNS resolution in pods
kubectl exec -n app1ns test-pod-app1 -- nslookup github.com
kubectl exec -n app2ns test-pod-app2 -- nslookup google.com

# Check Cilium connectivity
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg connectivity test

# View FQDN policy status
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg policy get | grep -A 10 -B 10 fqdn
```

## Part 6: Cleanup

### Step 17: Clean Up Resources

### Common Issues and Solutions

#### Issue 1: VM Size Not Available
**Error**: `The VM size of Standard_DS2_v2 is not allowed in your subscription in location 'eastus'`

**Solution**: Try different VM sizes or regions:
```bash
# Check available VM sizes
az vm list-skus --location eastus2 --resource-type virtualMachines --query "[?starts_with(name, 'Standard_D2') || starts_with(name, 'Standard_B2')].name" --output table

# Alternative VM sizes to try:
# Standard_D2s_v3, Standard_D2s_v4, Standard_D2s_v5, Standard_B2s, Standard_D2as_v4
```

### Common Issues and Solutions

#### Issue 1: VM Size Not Available
**Error**: `The VM size of Standard_DS2_v2 is not allowed in your subscription in location 'eastus'`

**Solution**: Try different VM sizes or regions:
```bash
# Check available VM sizes
az vm list-skus --location eastus2 --resource-type virtualMachines --query "[?starts_with(name, 'Standard_D2') || starts_with(name, 'Standard_B2')].name" --output table

# Alternative VM sizes to try:
# Standard_D2s_v3, Standard_D2s_v4, Standard_D2s_v5, Standard_B2s, Standard_D2as_v4
```

#### Issue 2: FQDN Policies Not Working
**Problem**: FQDN policies not enforcing as expected

**Solution**: Verify DNS rules are included:
```bash
# Check if DNS rules are properly configured in your policies
kubectl describe ciliumnetworkpolicy allow-github-app1 -n app1ns | grep -A 5 "dns:"

# Verify Cilium is running
kubectl get pods -n kube-system | grep cilium
```

#### Issue 3: DNS Resolution Failures
**Problem**: Pods cannot resolve domain names

**Solution**: Ensure DNS access is allowed:
```bash
# Test DNS resolution
kubectl exec -n app1ns test-pod-app1 -- nslookup github.com

# Check CoreDNS is accessible
kubectl get svc -n kube-system | grep dns
```

## Part 7: Understanding DNS Rules Deep Dive

### 📚 DNS Rules Explained

The `rules.dns` section in FQDN policies is **MANDATORY** for proper FQDN filtering. Here's why:

#### ✅ Correct Policy Structure:
```yaml
egress:
- toFQDNs:
  - matchPattern: "github.com"
  toPorts:
  - ports:
    - port: "443"
      protocol: TCP
  rules:
    dns:
    - matchPattern: "github.com"  # ← THIS IS ESSENTIAL
```

#### ❌ Incorrect Policy Structure:
```yaml
egress:
- toFQDNs:
  - matchPattern: "github.com"
  toPorts:
  - ports:
    - port: "443"
      protocol: TCP
  # ❌ MISSING: rules.dns section
```

#### DNS Inspection Flow (Correct Policy):
1. **DNS Request**: Pod executes `curl github.com`
2. **DNS Query**: Triggers DNS lookup to CoreDNS
3. **Cilium Inspection**: Cilium inspects DNS query against `rules.dns.matchPattern`
4. **DNS Response**: Returns IP address (e.g., 140.82.112.3)
5. **Cache Population**: Cilium stores IP in FQDN cache
6. **HTTP Request**: Pod makes HTTP request to 140.82.112.3
7. **Cache Check**: Cilium finds IP in FQDN cache
8. **Result**: Request is **ALLOWED** ✅

#### DNS Inspection Flow (Incorrect Policy):
1. **DNS Request**: Pod executes `curl github.com`
2. **DNS Query**: Triggers DNS lookup to CoreDNS
3. **No Inspection**: Cilium doesn't inspect DNS traffic (no `rules.dns`)
4. **DNS Response**: Returns IP address (e.g., 140.82.112.3)
5. **No Cache**: IP is NOT stored in FQDN cache
6. **HTTP Request**: Pod makes HTTP request to 140.82.112.3
7. **Cache Miss**: Cilium doesn't find IP in FQDN cache
8. **Result**: Request is **DENIED** ❌

## Part 8: Cleanup

```bash
echo "🧹 Cleaning up resources..."

# Delete test pods
kubectl delete pod test-pod-app1 -n app1ns
kubectl delete pod test-pod-app2 -n app2ns

# Delete namespaces (this also deletes network policies)
kubectl delete namespace app1ns
kubectl delete namespace app2ns

# Delete AKS cluster
az aks delete --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --yes --no-wait

# Delete entire resource group (optional - removes everything)
read -p "Delete entire resource group? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    az group delete --name $RESOURCE_GROUP --yes --no-wait
    echo "✅ Resource group deletion initiated"
else
    echo "ℹ️ Resource group preserved"
fi
```

## Summary and Key Takeaways

### 🎯 Critical Learning Points

1. **DNS Rules Are Mandatory**: FQDN filtering requires `rules.dns` section for DNS inspection
2. **DNS-to-IP Mapping**: Cilium must cache DNS resolutions to enforce FQDN policies
3. **Default Deny**: Traffic not explicitly allowed by FQDN policies is denied
4. **Namespace Isolation**: Different namespaces can have different access policies
5. **Public Website Control**: Fine-grained control over external website access

### 🔍 DNS Rules Importance Summary

| Component | With DNS Rules | Without DNS Rules |
|-----------|-----------------|-------------------|
| **DNS Inspection** | ✅ Enabled | ❌ Disabled |
| **FQDN Cache** | ✅ Populated | ❌ Empty |
| **HTTP Requests** | ✅ Allowed if cached | ❌ Denied (not in cache) |
| **Policy Effectiveness** | ✅ Works as expected | ❌ Fails silently |

### 🛡️ Security Best Practices

1. **Always include `rules.dns`** matching your `toFQDNs` patterns
2. **Use specific patterns** instead of wildcards when possible
3. **Test policies thoroughly** before production deployment
4. **Monitor FQDN cache** to verify expected behavior
5. **Implement default deny** posture for enhanced security

### 🌐 Lab Demonstration Summary

This simplified lab demonstrated:
- **app1ns**: Access to GitHub.com only ✅
- **app2ns**: Access to Google.com only ✅
- **All other sites**: Blocked by default ❌

The lab shows how FQDN-based network policies can provide granular control over internet access, enabling organizations to implement least-privilege networking for their applications.

This lab demonstrates the essential concepts of FQDN-based network policies in AKS with ACNS, focusing on practical implementation and the critical importance of proper DNS rule configuration.
