# Instructor Validation Checklist

## Pre-Training Setup Verification

### Infrastructure Check
- [ ] Resource group created with timestamp suffix
- [ ] VNet created with 4 subnets:
  - [ ] aks-nodes (10.1.0.0/16)
  - [ ] aks-pods (10.2.0.0/16) 
  - [ ] external-workload (10.3.0.0/24)
  - [ ] default subnet
- [ ] External workload VM/container deployed successfully
- [ ] External workload has IP in 10.3.0.x range

### Traditional CNI Cluster Validation
- [ ] Cluster name: aks-cni-traditional
- [ ] Node IPs: 10.1.x.x range
- [ ] Pod IPs: 10.1.x.x range (same as nodes)
- [ ] 2 nodes in Ready state
- [ ] 2 netshoot pods in Running state
- [ ] LoadBalancer service has external IP assigned

### Pod Subnet CNI Cluster Validation
- [ ] Cluster name: aks-cni-podsubnet
- [ ] Node IPs: 10.1.x.x range (same as traditional)
- [ ] Pod IPs: 10.2.x.x range (different from nodes)
- [ ] 2 nodes in Ready state
- [ ] 2 netshoot pods in Running state
- [ ] LoadBalancer service has external IP assigned

### Overlay CNI Cluster Validation
- [ ] Cluster name: aks-cni-overlay
- [ ] Node IPs: 10.1.x.x range (same as others)
- [ ] Pod IPs: 192.169.x.x range (overlay network)
- [ ] 2 nodes in Ready state
- [ ] 2 netshoot pods in Running state
- [ ] LoadBalancer service has external IP assigned

## Connectivity Testing Validation

### Traditional CNI Connectivity
- [ ] External workload can ping pod IPs directly
- [ ] Pods can reach internet (curl httpbin.org/ip works)
- [ ] External workload can reach LoadBalancer service
- [ ] Same SNAT IP returned from all pods

### Pod Subnet CNI Connectivity
- [ ] External workload can ping pod IPs directly
- [ ] Pods can reach internet (curl httpbin.org/ip works)
- [ ] External workload can reach LoadBalancer service
- [ ] Same SNAT IP as traditional CNI

### Overlay CNI Connectivity
- [ ] External workload CANNOT ping pod IPs directly (expected)
- [ ] Pods can reach internet (curl httpbin.org/ip works)
- [ ] External workload can reach LoadBalancer service
- [ ] Same SNAT IP as other CNI types

## Common Issues and Solutions

### Infrastructure Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| VM creation fails | Region capacity | Script automatically tries different sizes |
| Resource group exists | Previous run | Script uses existing or creates new with timestamp |
| Network errors | Subnet conflicts | Verify VNet address spaces don't overlap |

### Cluster Creation Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| Cluster creation timeout | Resource limits | Try in different region or time |
| Pod subnet creation fails | Subnet already associated | Use new resource group |
| Overlay CNI fails | Region support | Verify region supports overlay CNI |

### Connectivity Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| Pod pending state | Image pull issues | Check node capacity and network |
| LoadBalancer pending | Service allocation | Wait 5-10 minutes or check quotas |
| External workload unreachable | VM not ready | Wait for cloud-init completion |

## Training Execution Checklist

### Before Class
- [ ] Run complete setup: `./setup-demo.sh all`
- [ ] Verify all connectivity tests pass
- [ ] Test each helper script function
- [ ] Confirm LoadBalancer IPs are assigned
- [ ] Have backup resource group ready

### During Class - Per Section
- [ ] Trainees see expected output formats
- [ ] Success/error indicators are clear
- [ ] IP ranges match documentation
- [ ] Connectivity results match expectations
- [ ] Trainees understand why overlay fails direct access

### After Each CNI Demo
- [ ] Verify trainees understand IP allocation differences
- [ ] Confirm connectivity pattern understanding
- [ ] Check comprehension of SNAT behavior
- [ ] Ensure LoadBalancer access patterns are clear

## Troubleshooting Commands for Instructors

### Quick Status Check
```bash
# Check all resource groups
az group list --query "[?contains(name, 'aks-cni-demo-rg')].{Name:name, Location:location}" --output table

# Check cluster status
az aks list --resource-group <rg-name> --query "[].{Name:name, Status:provisioningState, Version:kubernetesVersion}" --output table

# Check external workload
az vm show --resource-group <rg-name> --name external-workload --show-details --query "{Name:name, PowerState:powerState, PrivateIP:privateIps}" --output table
```

### Network Validation
```bash
# Test all connectivity patterns
./vm-helper-enhanced.sh network-test

# Quick cluster info
./vm-helper-enhanced.sh cluster-info

# Test external connectivity
./vm-helper-enhanced.sh test-external
```

### Reset Specific Cluster
```bash
# Delete and recreate specific cluster
az aks delete --resource-group <rg-name> --name aks-cni-<type> --yes --no-wait
./setup-demo.sh <type>
```

## Expected Timing

| Phase | Duration | Notes |
|-------|----------|-------|
| Infrastructure setup | 10-15 min | Including VM provisioning |
| Traditional CNI | 8-12 min | Cluster creation + testing |
| Pod Subnet CNI | 8-12 min | Cluster creation + testing |
| Overlay CNI | 8-12 min | Cluster creation + testing |
| Comparison/Analysis | 10-15 min | Understanding differences |
| Q&A and Cleanup | 5-10 min | Questions and cleanup |
| **Total** | **50-75 min** | Full demonstration |

## Success Metrics
- [ ] All trainees can differentiate CNI IP allocation patterns
- [ ] Trainees understand direct vs service-based connectivity
- [ ] SNAT behavior is clearly demonstrated
- [ ] Overlay limitations are understood
- [ ] Practical use cases for each CNI type are clear
- [ ] Trainees can run tests independently

## Backup Plans
- [ ] Secondary region (eastus2) configured if westus2 fails
- [ ] Alternative VM sizes configured in script
- [ ] Container Instance fallback available
- [ ] Pre-created screenshots for demo if live fails
