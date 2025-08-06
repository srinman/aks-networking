# Azure CNI Network Traffic Scenarios

This document provides specific scenarios for testing network traffic patterns across different Azure CNI configurations.

## Scenario 1: Web Application with Database

### Setup

```bash
# Apply this to each cluster to test realistic workload patterns
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 80
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
        listen 80;
        location / {
            return 200 'Web Server Pod IP: $POD_IP\nNode: $NODE_NAME\nTimestamp: $time_iso8601\n';
            add_header Content-Type text/plain;
        }
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-svc
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: db
        image: nicolaka/netshoot
        command: ["sh", "-c", "while true; do echo 'DB Response from '$POD_IP' at '$(date) | nc -l -p 5432; done"]
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
---
apiVersion: v1
kind: Service
metadata:
  name: database-svc
spec:
  selector:
    app: database
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
```

### Test Inter-Pod Communication

```bash
# Test communication between web app and database
WEB_POD=$(kubectl get pods -l app=web-app -o jsonpath='{.items[0].metadata.name}')

kubectl exec $WEB_POD -- sh -c '
    echo "Testing database connectivity from web app pod:"
    echo "Pod IP: $POD_IP"
    echo "Database service test:"
    nc -zv database-svc 5432
    echo "Direct database connection test:"
    echo "GET /data" | nc database-svc 5432
'
```

## Scenario 2: Network Policy Testing

### Apply Network Policies

```bash
# Allow only web app to access database
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-isolation
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web-app
    ports:
    - protocol: TCP
      port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-app-egress
spec:
  podSelector:
    matchLabels:
      app: web-app
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  - to: []
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
EOF
```

### Test Network Policy Effects

```bash
# Test that web app can still reach database
WEB_POD=$(kubectl get pods -l app=web-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $WEB_POD -- nc -zv database-svc 5432

# Test that netshoot pods cannot reach database (should fail)
NETSHOOT_POD=$(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ ! -z "$NETSHOOT_POD" ]; then
    kubectl exec $NETSHOOT_POD -- timeout 5 nc -zv database-svc 5432 || echo "Connection blocked by network policy (expected)"
fi
```

## Scenario 3: Load Balancer Deep Dive

### Multiple Load Balancer Types

```bash
# Create different load balancer configurations
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: web-app-internal-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "aks-nodes"
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-nodeport
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
EOF
```

### Test Load Balancer Behavior

```bash
# Test external load balancer
EXTERNAL_LB=$(kubectl get service web-app-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Testing External LoadBalancer ($EXTERNAL_LB):"
curl -s http://$EXTERNAL_LB

# Test internal load balancer from VM
INTERNAL_LB=$(kubectl get service web-app-internal-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Testing Internal LoadBalancer ($INTERNAL_LB) from VM:"
az vm run-command invoke --resource-group aks-cni-demo-rg --name external-workload --command-id RunShellScript --scripts "curl -s http://$INTERNAL_LB" --output tsv --query 'value[0].message'

# Test NodePort from VM
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "Testing NodePort ($NODE_IP:30080) from VM:"
az vm run-command invoke --resource-group aks-cni-demo-rg --name external-workload --command-id RunShellScript --scripts "curl -s http://$NODE_IP:30080" --output tsv --query 'value[0].message'
```

## Scenario 4: Cross-CNI Communication Test

### Deploy Echo Server

```bash
# Deploy a simple echo server for testing
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo
        image: nicolaka/netshoot
        command: 
        - sh
        - -c
        - |
          while true; do
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nEcho Server Response\nPod IP: \$POD_IP\nNode: \$NODE_NAME\nTimestamp: \$(date)\nHeaders: \$HTTP_HEADERS" | nc -l -p 8080
          done
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server-svc
spec:
  selector:
    app: echo-server
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
EOF
```

### Performance Testing

```bash
# Simple performance test using wget/curl
ECHO_LB=$(kubectl get service echo-server-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test from external source (VM)
VM_IP=$(az vm show --resource-group aks-cni-demo-rg --name external-workload --show-details --query privateIps --output tsv)
echo "Testing from VM ($VM_IP) to AKS:"

az vm run-command invoke --resource-group aks-cni-demo-rg --name external-workload --command-id RunShellScript --scripts "
for i in {1..10}; do
  time curl -s http://$ECHO_LB:8080 > /dev/null
done" --output tsv --query 'value[0].message'

# Test from pod within cluster
NETSHOOT_POD=$(kubectl get pods -l app=netshoot-traditional -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ ! -z "$NETSHOOT_POD" ]; then
    kubectl exec $NETSHOOT_POD -- sh -c "
    for i in {1..10}; do
      time curl -s http://echo-server-svc:8080 > /dev/null
    done"
fi
```

## Scenario 5: DNS Resolution Testing

### Test DNS Resolution Patterns

```bash
# Test DNS resolution from different pods
test_dns_resolution() {
    local pod_name=$1
    
    kubectl exec $pod_name -- sh -c '
        echo "=== DNS Resolution Test from $POD_NAME ==="
        echo "Testing cluster internal DNS:"
        nslookup kubernetes.default.svc.cluster.local
        echo ""
        
        echo "Testing service DNS:"
        nslookup web-app-svc.default.svc.cluster.local
        echo ""
        
        echo "Testing external DNS:"
        nslookup google.com
        echo ""
        
        echo "DNS Configuration:"
        cat /etc/resolv.conf
        echo ""
    '
}

# Test DNS from each cluster type
for cluster in aks-cni-traditional aks-cni-podsubnet aks-cni-overlay; do
    if az aks show --resource-group aks-cni-demo-rg --name $cluster >/dev/null 2>&1; then
        echo "=== DNS Testing for $cluster ==="
        az aks get-credentials --resource-group aks-cni-demo-rg --name $cluster --overwrite-existing
        
        POD=$(kubectl get pods -l app=web-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ ! -z "$POD" ]; then
            test_dns_resolution $POD
        fi
    fi
done
```

## Scenario 6: Network Troubleshooting Tools

### Deploy Network Troubleshooting Pod

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-debug
  labels:
    app: network-debug
spec:
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
    securityContext:
      capabilities:
        add: ["NET_ADMIN", "NET_RAW"]
    env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
EOF
```

### Network Diagnostic Commands

```bash
# Comprehensive network diagnostics
kubectl exec network-debug -- sh -c '
    echo "=== Network Interface Details ==="
    ip addr show
    echo ""
    
    echo "=== Routing Table ==="
    ip route show
    echo ""
    
    echo "=== ARP Table ==="
    arp -a
    echo ""
    
    echo "=== Network Statistics ==="
    netstat -i
    echo ""
    
    echo "=== Active Connections ==="
    netstat -tunlp
    echo ""
    
    echo "=== DNS Test ==="
    dig @8.8.8.8 google.com
    echo ""
    
    echo "=== Connectivity Test ==="
    ping -c 3 8.8.8.8
    echo ""
    
    echo "=== Traceroute Test ==="
    traceroute -n 8.8.8.8
'
```

### Packet Capture (if supported)

```bash
# Simple packet capture using tcpdump
kubectl exec network-debug -- timeout 30 tcpdump -i any -n -c 100 -w /tmp/capture.pcap
kubectl cp network-debug:/tmp/capture.pcap ./network-capture.pcap
```

## Cleanup Commands

```bash
# Clean up all test resources
kubectl delete deployment web-app database echo-server
kubectl delete service web-app-svc web-app-internal-lb web-app-nodeport database-svc echo-server-svc
kubectl delete configmap nginx-config
kubectl delete networkpolicy database-isolation web-app-egress
kubectl delete pod network-debug
```

This scenarios document provides realistic testing patterns that demonstrate the networking differences between Azure CNI configurations.
