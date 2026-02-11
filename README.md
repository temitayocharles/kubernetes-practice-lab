# Kubernetes Practice Lab & Local Cluster Setup


## Start Here
- Read [START_HERE.md](START_HERE.md) for the chronological playbook.

A comprehensive hands-on Kubernetes learning environment with 12 guided practice phases, from basic deployments to advanced RBAC and network security. Includes an automated local cluster setup script for k3d.


## Documentation Index
- [QUICKSTART.md](QUICKSTART.md)

## 🎯 What's Inside

### 📚 Practice Lab (`k8s-practice/`)
**12 progressive phases** covering essential Kubernetes concepts with hands-on exercises:

1. **Basic Deployment & Service** (15 min) - Pods, Deployments, Services
2. **ConfigMaps & Secrets** (20 min) - Configuration management
3. **Service Debugging** (15 min) - Troubleshooting connectivity
4. **Rolling Updates & Rollbacks** (20 min) - Safe deployments
5. **Ingress & External Access** (25 min) - External routing
6. **Persistent Storage** (20 min) - PersistentVolumes & Claims
7. **Health Checks & Resources** (20 min) - Probes & resource limits
8. **Advanced Patterns** (30 min) - HPA, NetworkPolicy, Init/Sidecar
9. **Labels & Selectors Mastery** (45 min) - Traffic routing
10. **Service Types Deep Dive** (40 min) - ClusterIP, NodePort, LoadBalancer
11. **RBAC & Security** (60 min) - ServiceAccounts, Roles, ClusterRoles
12. **Network Security** (75 min) - Zero-trust, Pod Security Standards

**Total:** 6-7 hours for complete mastery

### 🛠️ Local Cluster Setup (`local-k8s.sh`)
Automated script to create a production-like local Kubernetes cluster with:
- k3d (Kubernetes in Docker)
- Metrics Server (with RBAC fix)
- Traefik Ingress Controller
- Local Path Provisioner for storage
- Priority Classes
- Optional ServiceLB (load balancer)

---

## 🚀 Quick Start

### Prerequisites
- Docker Desktop installed and running
- kubectl installed
- Basic command-line knowledge

### Option 1: Use the Practice Lab (Any Cluster)

```bash
# Clone the repository
git clone https://github.com/temitayocharles/kubernetes-practice-lab.git
cd kubernetes-practice-lab

# Start with Phase 1
cd k8s-practice
cat README.md  # Read the complete guide

# Follow the exercises
cd 01-basic
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

**Works with any Kubernetes cluster:**
- k3d, minikube, kind (local)
- GKE, EKS, AKS (cloud)
- Your existing cluster

### Option 2: Create Local Cluster + Practice

```bash
# Clone the repository
git clone https://github.com/temitayocharles/kubernetes-practice-lab.git
cd kubernetes-practice-lab

# Install local cluster (macOS/Linux)
./local-k8s.sh install

# Wait for cluster to be ready (~3-5 minutes)
kubectl get nodes
kubectl get pods -A

# Start practicing
cd k8s-practice
cat README.md
```

---

## 📋 Practice Lab Structure

```
k8s-practice/
├── README.md                    # Complete assignment guide (2000+ lines)
├── 01-basic/                    # Deployments & Services
│   ├── deployment.yaml
│   ├── service.yaml
│   └── README.md
├── 02-config/                   # ConfigMaps & Secrets
│   ├── config-resources.yaml
│   ├── deployment-with-config.yaml
│   └── ...
├── 03-services/                 # Service debugging exercises
├── 04-updates/                  # Rolling updates & rollbacks
├── 05-ingress/                  # Ingress configuration
├── 06-storage/                  # PersistentVolumes
├── 07-health-resources/         # Health checks & resource limits
├── 08-advanced/                 # HPA, NetworkPolicy, Init/Sidecar
├── 09-labels-mastery/           # Label-based routing (10 exercises)
├── 10-service-types/            # ClusterIP, NodePort, LoadBalancer
├── 11-rbac-security/            # RBAC deep dive (6 manifests)
└── 12-network-security/         # Zero-trust networking (6 manifests)
```

---

## 🎓 Learning Outcomes

By completing this lab, you will:

✅ Deploy and scale applications with Deployments  
✅ Externalize configuration with ConfigMaps and Secrets  
✅ Debug service connectivity issues  
✅ Perform safe rolling updates and rollbacks  
✅ Expose applications externally with Ingress  
✅ Manage persistent storage  
✅ Implement health checks and resource limits  
✅ Use HPA, NetworkPolicies, and advanced patterns  
✅ Master label-based traffic routing  
✅ Choose appropriate service types  
✅ **Implement RBAC for authentication and authorization**  
✅ **Design zero-trust network architectures**  
✅ **Apply Pod Security Standards for production**

---

## 🛠️ Local Cluster Setup Script

### Features

The `local-k8s.sh` script provides:

- **k3d cluster** with 2 nodes (1 server, 1 agent)
- **Metrics Server** (with RBAC fix for `kubectl top`)
- **Traefik Ingress** (HTTP/HTTPS routing)
- **Local Path Provisioner** (persistent storage)
- **Priority Classes** (cluster-critical, high-priority, low-priority)
- **Optional ServiceLB** (LoadBalancer support)

### Usage

```bash
# Install cluster
./local-k8s.sh install

# Check cluster status
./local-k8s.sh status

# Stop cluster (saves state)
./local-k8s.sh stop

# Start cluster (restores state)
./local-k8s.sh start

# Delete cluster
./local-k8s.sh uninstall

# Enable ServiceLB (LoadBalancer)
./local-k8s.sh enable-servicelb

# Get cluster info
./local-k8s.sh info
```

### Verified Working Features

✅ Metrics Server (`kubectl top nodes` works!)  
✅ Ingress Controller (Traefik)  
✅ Persistent Storage (local-path)  
✅ Priority Classes (cluster-critical)  
✅ ServiceLB (optional LoadBalancer)

---

## 🔐 Security Features

### Phase 11: RBAC & Security
- ServiceAccounts for pod identity
- Roles and ClusterRoles (namespace vs cluster-wide)
- RoleBindings and ClusterRoleBindings
- Debugging 403 Forbidden errors
- Real-world scenarios (developer, deployer, admin roles)
- **Fixes metrics-server RBAC issue** (hands-on learning!)

### Phase 12: Network Security
- Default deny all NetworkPolicies (zero-trust foundation)
- Three-tier application security (Frontend → API → Database)
- Namespace-based isolation
- Metadata server blocking (AWS/GCP/Azure security)
- Pod Security Standards (restricted profile)
- Security best practices comparison (insecure vs secure)

---

## 📚 Documentation

- **[Practice Lab Guide](k8s-practice/README.md)** - Complete assignment with all 12 phases
- **[Phase 11: RBAC](k8s-practice/11-rbac-security/README.md)** - RBAC deep dive
- **[Phase 12: Network Security](k8s-practice/12-network-security/README.md)** - Zero-trust networking
- **[Quick Start Guide](QUICKSTART.md)** - Get started in 5 minutes

---

## 🐛 Troubleshooting

### Metrics Server Not Working
```bash
# Check metrics-server pod
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# If 403 Forbidden errors, apply RBAC fix:
kubectl apply -f k8s-practice/11-rbac-security/04-metrics-server-rbac-fix.yaml
kubectl rollout restart deployment metrics-server -n kube-system
```

### NetworkPolicy Not Working
```bash
# Check if CNI supports NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|canal'

# k3d uses Flannel (no NetworkPolicy support)
# Install Calico for NetworkPolicy support:
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

### Cluster Won't Start
```bash
# Check Docker is running
docker ps

# Check k3d cluster status
k3d cluster list

# Delete and recreate if needed
./local-k8s.sh uninstall
./local-k8s.sh install
```

---

## 🤝 Contributing

Contributions welcome! Please feel free to:
- Report bugs or issues
- Suggest improvements to practice exercises
- Add new phases or scenarios
- Fix typos or clarify documentation

---

## 📄 License

MIT License - Feel free to use this for learning, teaching, or workshops!

---

## 🙏 Acknowledgments

Created as a comprehensive Kubernetes learning resource combining:
- Official Kubernetes documentation best practices
- Real-world production patterns
- Hands-on guided exercises
- Security-focused approach (RBAC, NetworkPolicies, Pod Security Standards)

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/temitayocharles/kubernetes-practice-lab/issues)
- **Author:** Temitayo Charles [@temitayocharles](https://github.com/temitayocharles)

---

**Start your Kubernetes mastery journey today!** 🚀
