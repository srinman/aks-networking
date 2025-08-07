
> ⚠️ **Warning:** The Kubenet CNI model is deprecated in Azure Kubernetes Service (AKS) and will be retired on March 31, 2028. New deployments should use Azure CNI instead. For details, see the official Azure documentation:
> - [Kubenet networking configuration](https://learn.microsoft.com/en-us/azure/aks/configure-kubenet) (includes deprecation notice)
> - [AKS networking concepts](https://learn.microsoft.com/en-us/azure/aks/concepts-network)
> - [Configure Azure CNI networking](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)

# AKS Networking Lab

This repository provides a hands-on lab for learning and testing Azure Kubernetes Service (AKS) networking options, including Traditional Azure CNI, Pod Subnet CNI, and Overlay CNI. The lab is designed for trainees, engineers, and architects who want to understand AKS networking behaviors, IP allocation, connectivity, and troubleshooting in real-world scenarios.

## Lab Overview

You will deploy multiple AKS clusters with different networking models, set up supporting infrastructure, and run comprehensive connectivity tests. The lab covers:
- Architecture and IP allocation patterns
- Outbound and inbound connectivity flows
- SNAT/DNAT behavior
- Troubleshooting and best practices

## Learning Path

1. Review AKS networking concepts and architecture
2. Deploy infrastructure and clusters using provided scripts
3. Test and compare networking behaviors across CNI types
4. Analyze connectivity, SNAT/DNAT, and security implications
5. Clean up resources

## Prerequisites

- Azure subscription with sufficient permissions
- Azure CLI installed
- kubectl installed
- Bash shell (Linux/macOS or WSL on Windows)
- Basic understanding of Kubernetes and networking

## Repository Structure

```
├── azure-cni-comprehensive-guide.md   # Consolidated reference for all CNI types
├── step-by-step-testing-guide.md      # Detailed step-by-step instructions for the lab
├── network-scenarios.md               # Additional networking scenarios and examples
├── instructor-checklist.md            # Checklist and tips for lab instructors
├── analyze-networking.sh              # Script for network analysis
├── setup-demo.sh                      # Main setup/cleanup script
├── vm-helper-enhanced.sh              # Helper script for external workload testing
├── vm-helper.sh                       # Basic VM helper script
```

## Documentation Index

- [Azure CNI Comprehensive Guide](azure-cni-comprehensive-guide.md)
- [Step-by-Step Testing Guide](step-by-step-testing-guide.md)
- [Network Scenarios](network-scenarios.md)
- [Instructor Checklist](instructor-checklist.md)

## Getting Started

1. **Clone the repository:**
   ```bash
   git clone <repo-url>
   cd aks-networking
   ```
2. **Review prerequisites and install required tools.**
3. **Run the setup script to provision infrastructure:**
   ```bash
   ./setup-demo.sh all
   ```
4. **Follow the [Step-by-Step Testing Guide](step-by-step-testing-guide.md) for hands-on exercises.**
5. **Use the [Azure CNI Comprehensive Guide](azure-cni-comprehensive-guide.md) for reference and comparison.**
6. **Clean up resources when finished:**
   ```bash
   ./setup-demo.sh cleanup
   ```

---

For questions or troubleshooting, refer to the guides above or contact the lab instructor.
