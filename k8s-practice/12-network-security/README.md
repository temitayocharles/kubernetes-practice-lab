# PHASE 12: Network Policies & Security Hardening (75 minutes)

## 🎯 Learning Objectives

After completing this phase, you will:
- **Master NetworkPolicies** for zero-trust networking
- **Implement three-tier application security** (Frontend → API → Database)
- **Apply Pod Security Standards** (restricted profile)
- **Block metadata server access** (AWS/GCP/Azure security)
- **Follow security best practices** for production workloads

---

## 🔥 Why Network Security Matters

**Without NetworkPolicies:**
- Any pod can talk to ANY other pod
- Database accessible from any workload
- No defense-in-depth
- Single compromise = full cluster access

**With NetworkPolicies:**
- Explicit allow-list (zero-trust)
- Frontend can't directly access database
- Isolation between tiers
- Defense-in-depth architecture

---

## 📋 Prerequisites

```bash
# Ensure cluster is running
kubectl cluster-info

# If your cluster is stopped, start it first
# Example commands for different cluster types:
# k3d cluster start <cluster-name>
# minikube start
# kind start cluster

# Verify you can create NetworkPolicies
kubectl auth can-i create networkpolicies

# Create clean namespace for testing
kubectl create namespace netpol-test
kubectl config set-context --current --namespace=netpol-test

# Verify namespace created
kubectl get namespace netpol-test
```

---

## 🛡️ Zero-Trust Networking Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Zero-Trust Network Architecture                 │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. DEFAULT DENY ALL (ingress + egress)                     │
│     ↓                                                         │
│  2. EXPLICIT ALLOW rules                                     │
│     - Frontend → API (allowed)                               │
│     - API → Database (allowed)                               │
│     - Frontend → Database (DENIED - no rule exists)          │
│     ↓                                                         │
│  3. DEFENSE IN DEPTH                                         │
│     - Network layer (NetworkPolicy)                          │
│     - RBAC layer (ServiceAccount permissions)                │
│     - Pod security (securityContext)                         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Step 1: Default Deny All (10 minutes)

### Understanding Default Deny

**Without default deny:**
```
[Pod A] ──✅ can talk to──→ [Pod B]
[Pod A] ──✅ can talk to──→ [Database]
[Pod A] ──✅ can talk to──→ [Internet]
```

**With default deny:**
```
[Pod A] ──❌ blocked by──→ [Pod B]
[Pod A] ──❌ blocked by──→ [Database]
[Pod A] ──❌ blocked by──→ [Internet]
```

### Exercise 1.1: Apply Default Deny

```bash
cd 12-network-security

# First, deploy test apps WITHOUT network policies
kubectl apply -f 02-three-tier-app.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s
kubectl wait --for=condition=ready pod -l app=api --timeout=60s
kubectl wait --for=condition=ready pod -l app=database --timeout=60s

# Test: Frontend CAN reach API (no restrictions yet)
kubectl exec -it deployment/frontend -- curl -s -m 5 http://api-service:8080
# Output: API Response ✅

# Test: Frontend CAN reach database (insecure!)
kubectl exec -it deployment/frontend -- nc -zv database-service 5432
# Output: database-service (10.x.x.x:5432) open ⚠️

# Now apply default deny all
kubectl apply -f 01-default-deny-all.yaml

# Check NetworkPolicies
kubectl get networkpolicy

# Test: Frontend CANNOT reach API (blocked!)
kubectl exec -it deployment/frontend -- curl -s -m 5 http://api-service:8080
# Timeout after 5 seconds ❌

# Test: Frontend CANNOT reach database (blocked!)
kubectl exec -it deployment/frontend -- nc -zv -w 5 database-service 5432
# Timeout ❌
```

### 🧠 What Just Happened?

**Two NetworkPolicies created:**

1. **default-deny-all-ingress**: Blocks ALL incoming traffic to pods
   ```yaml
   spec:
     podSelector: {}  # Applies to ALL pods
     policyTypes:
     - Ingress
     # No ingress rules = deny all
   ```

2. **default-deny-all-egress**: Blocks ALL outgoing traffic from pods
   ```yaml
   spec:
     podSelector: {}  # Applies to ALL pods
     policyTypes:
     - Egress
     # No egress rules = deny all
   ```

**Result:** All traffic blocked by default. Now we selectively allow traffic.

---

## 📝 Step 2: Three-Tier Application Security (15 minutes)

### Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Frontend   │────▶│     API      │────▶│   Database   │
│  (nginx)     │     │ (http-echo)  │     │  (postgres)  │
└──────────────┘     └──────────────┘     └──────────────┘
     tier: web          tier: backend         tier: data

✅ Allowed:
- External → Frontend (port 80)
- Frontend → API (port 8080)
- API → Database (port 5432)

❌ Denied:
- Frontend → Database (no direct access)
- External → API (not public-facing)
- External → Database (not public-facing)
```

### Exercise 2.1: Apply Tier-Based Policies

```bash
# Apply NetworkPolicies for three-tier architecture
kubectl apply -f 03-tier-network-policies.yaml

# Check all NetworkPolicies
kubectl get networkpolicy

# You should see:
# - default-deny-all-ingress (blocks everything)
# - default-deny-all-egress (blocks everything)
# - allow-frontend-to-api (explicit allow)
# - allow-api-to-database (explicit allow)
# - allow-external-to-frontend (explicit allow)
# - frontend-egress-to-api (explicit egress allow)
# - api-egress-to-database (explicit egress allow)
```

### Exercise 2.2: Test Three-Tier Security

```bash
# Test 1: Frontend CAN reach API ✅
kubectl exec -it deployment/frontend -- curl -s -m 5 http://api-service:8080
# Output: API Response ✅

# Test 2: API CAN reach database ✅
kubectl exec -it deployment/api -- nc -zv -w 5 database-service 5432
# Output: database-service (10.x.x.x:5432) open ✅

# Test 3: Frontend CANNOT reach database ❌ (security win!)
kubectl exec -it deployment/frontend -- nc -zv -w 5 database-service 5432
# Timeout - blocked by network policy ✅

# Test 4: Can we bypass by using IP instead of DNS? ❌
DB_IP=$(kubectl get svc database-service -o jsonpath='{.spec.clusterIP}')
kubectl exec -it deployment/frontend -- nc -zv -w 5 $DB_IP 5432
# Still blocked! NetworkPolicy works at IP level ✅
```

### 🧠 Key Takeaways

1. **NetworkPolicies are additive** - multiple policies combine (OR logic)
2. **podSelector + namespaceSelector** - control source of traffic
3. **Ingress vs Egress** - both needed for complete control:
   - **Ingress**: Controls WHO can connect TO this pod
   - **Egress**: Controls WHERE this pod can connect TO
4. **DNS must be explicitly allowed** - egress policies need port 53 UDP exception

---

## 📝 Step 3: Advanced Network Policies (15 minutes)

### Exercise 3.1: Namespace-Based Isolation

```bash
# Create trusted namespace
kubectl create namespace trusted-namespace
kubectl label namespace trusted-namespace name=trusted-namespace

# Deploy app with high security label
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: high-security-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: high-security-app
      security: high
  template:
    metadata:
      labels:
        app: high-security-app
        security: high
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF

# Apply namespace isolation policy
kubectl apply -f 04-advanced-policies.yaml

# Test: Pod from default namespace CANNOT access ❌
kubectl run test-pod --image=busybox --rm -it -- wget -T 5 -O- http://high-security-app
# Timeout ❌

# Test: Pod from trusted-namespace CAN access ✅
kubectl run test-pod --image=busybox --rm -it -n trusted-namespace -- wget -T 5 -O- http://high-security-app.default
# Would work if namespace has correct label ✅
```

### Exercise 3.2: Block Metadata Server Access

**Why this matters:**
- AWS EC2 metadata: `http://169.254.169.254/latest/meta-data/`
- Contains IAM credentials, instance info
- Compromised pod = credentials leak

```bash
# Apply metadata server blocking policy
kubectl apply -f 04-advanced-policies.yaml

# Check the policy
kubectl describe networkpolicy deny-metadata-server

# Test: Cannot access metadata server
kubectl exec -it deployment/frontend -- curl -m 5 http://169.254.169.254/latest/meta-data/
# Timeout ✅ (blocked by network policy)
```

### Exercise 3.3: IP CIDR-Based Policies

```bash
# Apply policy allowing only specific external IPs
kubectl apply -f 04-advanced-policies.yaml

# Check policy
kubectl describe networkpolicy allow-egress-to-specific-ips

# Use case: Only allow egress to known third-party APIs
# Example: 203.0.113.0/24 (documentation IP range)
```

---

## 📝 Step 4: Pod Security Standards (15 minutes)

### Three Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| **Privileged** | Unrestricted | System components (CNI, storage drivers) |
| **Baseline** | Minimal restrictions | Standard workloads |
| **Restricted** | Hardened security | Production applications |

### Exercise 4.1: Restricted Profile

```bash
# Apply secure namespace with restricted profile
kubectl apply -f 05-pod-security-standards.yaml

# Check namespace labels
kubectl get namespace secure-namespace -o yaml | grep pod-security

# Deploy secure app (follows restricted profile)
# Already applied in previous step

# Verify pods running
kubectl get pods -n secure-namespace

# Try to deploy INSECURE pod (will fail)
kubectl apply -n secure-namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: insecure-pod
spec:
  containers:
  - name: app
    image: nginx
    securityContext:
      privileged: true  # ❌ Violates restricted profile
EOF

# Error: violates PodSecurity "restricted:latest"
# Forbidden: securityContext.privileged ✅
```

### 🧠 Restricted Profile Requirements

```yaml
securityContext:
  runAsNonRoot: true              # ✅ Never run as root
  runAsUser: 1000                 # ✅ Non-root UID
  allowPrivilegeEscalation: false # ✅ No privilege escalation
  readOnlyRootFilesystem: true    # ✅ Immutable filesystem
  capabilities:
    drop:
    - ALL                         # ✅ Drop all Linux capabilities
  seccompProfile:
    type: RuntimeDefault          # ✅ Enable seccomp filtering
```

---

## 📝 Step 5: Security Best Practices Comparison (10 minutes)

### Exercise 5.1: Insecure vs Secure Deployment

```bash
# Apply both deployments
kubectl apply -f 06-security-best-practices.yaml

# Check insecure deployment
kubectl get deployment insecure-app -o yaml | grep -A 5 securityContext

# Problems:
# - privileged: true (full host access)
# - runAsUser: 0 (running as root)
# - image: nginx:latest (mutable tag)
# - No resource limits
# - Hardcoded secrets

# Check secure deployment
kubectl get deployment secure-app-best-practice -o yaml | grep -A 10 securityContext

# Best practices:
# ✅ runAsNonRoot: true
# ✅ allowPrivilegeEscalation: false
# ✅ readOnlyRootFilesystem: true
# ✅ capabilities: drop: [ALL]
# ✅ seccompProfile: RuntimeDefault
# ✅ Resource limits defined
# ✅ Secrets from SecretKeyRef
```

### Security Checklist Comparison

| Security Aspect | ❌ Insecure | ✅ Secure |
|----------------|------------|-----------|
| **User** | root (UID 0) | Non-root (UID 1000) |
| **Privileged** | true | false |
| **Root filesystem** | Read-write | Read-only |
| **Capabilities** | All | None (drop ALL) |
| **Image tag** | :latest | :1.25.3-alpine |
| **Resource limits** | None | Defined |
| **Secrets** | Hardcoded | SecretKeyRef |
| **ServiceAccount** | default | Custom SA |
| **Health checks** | None | Liveness + Readiness |

---

## 📝 Step 6: Complete Security Stack (10 minutes)

### Layered Security Approach

```
┌─────────────────────────────────────────────────────────────┐
│                    Defense in Depth                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Layer 1: NetworkPolicy (network segmentation)              │
│           - Default deny all                                 │
│           - Explicit allow rules                             │
│           - Block metadata server                            │
│                                                               │
│  Layer 2: RBAC (identity & authorization)                   │
│           - Custom ServiceAccounts                           │
│           - Least privilege roles                            │
│           - No default ServiceAccount                        │
│                                                               │
│  Layer 3: Pod Security Standards (container hardening)      │
│           - runAsNonRoot                                     │
│           - readOnlyRootFilesystem                           │
│           - Drop all capabilities                            │
│           - seccomp profile                                  │
│                                                               │
│  Layer 4: Resource Limits (availability)                    │
│           - CPU/Memory requests                              │
│           - CPU/Memory limits                                │
│           - Prevent noisy neighbor                           │
│                                                               │
│  Layer 5: Secrets Management (confidentiality)              │
│           - Secrets from external store (Vault, AWS SM)     │
│           - Never hardcode credentials                       │
│           - Rotate secrets regularly                         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Exercise 6.1: Apply Complete Security Stack

```bash
# Return to default namespace
kubectl config set-context --current --namespace=default

# 1. Network layer
kubectl apply -f 01-default-deny-all.yaml
kubectl apply -f 03-tier-network-policies.yaml

# 2. RBAC layer (from Phase 11)
kubectl apply -f ../11-rbac-security/06-real-world-scenarios.yaml

# 3. Pod Security layer
kubectl apply -f 05-pod-security-standards.yaml

# 4. Deploy secure application
kubectl apply -f 06-security-best-practices.yaml

# Verify all layers
echo "=== Network Policies ==="
kubectl get networkpolicy

echo "=== RBAC ==="
kubectl get serviceaccount
kubectl get role
kubectl get rolebinding

echo "=== Secure Pods ==="
kubectl get pods -o custom-columns=NAME:.metadata.name,USER:.spec.securityContext.runAsUser,NONROOT:.spec.containers[0].securityContext.runAsNonRoot

echo "=== Resource Limits ==="
kubectl get pods -o custom-columns=NAME:.metadata.name,CPU-REQ:.spec.containers[0].resources.requests.cpu,MEM-REQ:.spec.containers[0].resources.requests.memory
```

---

## 🔍 Debugging NetworkPolicies

### Common Issues

#### Issue 1: Policy Not Working (Still Blocked)

```bash
# Check if policy exists
kubectl get networkpolicy

# Check policy details
kubectl describe networkpolicy <name>

# Verify pod labels match podSelector
kubectl get pods --show-labels

# Check logs for DNS issues
kubectl logs <pod>
```

#### Issue 2: DNS Not Working

```bash
# Problem: Egress policy blocks DNS (port 53 UDP)

# Solution: Add DNS exception to egress
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53
```

#### Issue 3: Policy Applied But Traffic Still Works

```bash
# Check if your CNI plugin supports NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|canal'

# Common CNI plugins with NetworkPolicy support:
# ✅ Calico, Cilium, Weave Net, Canal
# ❌ Flannel (default in some clusters - no NetworkPolicy support)

# If your cluster doesn't support NetworkPolicy, install a compatible CNI:
# Example for Calico:
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# Example cluster-specific notes:
# - k3d: Uses Flannel by default (no NetworkPolicy support, install Calico)
# - minikube: Enable NetworkPolicy with `minikube start --cni=calico`
# - kind: NetworkPolicy enabled by default (Kindnet CNI)
# - GKE/EKS/AKS: NetworkPolicy available (enable during cluster creation)

# Note: Check your cluster documentation before changing CNI
```

### Debugging Commands

```bash
# 1. List all NetworkPolicies
kubectl get networkpolicy -A

# 2. Describe specific policy
kubectl describe networkpolicy <name>

# 3. Check pod labels
kubectl get pods --show-labels

# 4. Test connectivity
kubectl exec <pod> -- curl -m 5 <target-url>
kubectl exec <pod> -- nc -zv -w 5 <host> <port>

# 5. Check if CNI supports NetworkPolicy
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -i network
```

---

## ✅ Verification Checklist

After completing this phase:

```bash
# 1. NetworkPolicies applied
kubectl get networkpolicy | grep -c "deny-all"
# Output: 2 (ingress + egress)

# 2. Three-tier security working
kubectl exec deployment/frontend -- curl -m 5 http://api-service:8080
# Output: API Response ✅

kubectl exec deployment/frontend -- nc -zv -w 5 database-service 5432
# Output: Timeout (blocked) ✅

# 3. Pod Security Standards enforced
kubectl get namespace secure-namespace -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
# Output: restricted ✅

# 4. Secure deployment running
kubectl get pods -n secure-namespace
# Output: secure-app-xxx Running ✅

# 5. Best practices followed
kubectl get deployment secure-app-best-practice -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}'
# Output: true ✅
```

---

## 🎓 Key Concepts Summary

### 1. NetworkPolicy = Firewall Rules for Pods
- **Default deny all** = zero-trust foundation
- **Explicit allow** = whitelist approach
- **podSelector** = which pods the policy applies to
- **Ingress** = incoming traffic rules
- **Egress** = outgoing traffic rules

### 2. Three-Tier Security Pattern
```
Frontend (tier: web)
  ↓ (allowed by NetworkPolicy)
API (tier: backend)
  ↓ (allowed by NetworkPolicy)
Database (tier: data)

Frontend → Database (DENIED - no rule exists)
```

### 3. Pod Security Standards
- **Privileged**: For system components only
- **Baseline**: Minimal restrictions
- **Restricted**: Production hardening (use this!)

### 4. Security Best Practices
```yaml
✅ runAsNonRoot: true
✅ allowPrivilegeEscalation: false
✅ readOnlyRootFilesystem: true
✅ capabilities: drop: [ALL]
✅ seccompProfile: RuntimeDefault
✅ Resource limits defined
✅ Secrets from external store
✅ Custom ServiceAccount
✅ Health checks configured
```

---

## 🐛 Common Mistakes & Solutions

| Mistake | Impact | Solution |
|---------|--------|----------|
| No default deny | Any pod can talk to any pod | Apply `01-default-deny-all.yaml` first |
| Forgot DNS egress | Pods can't resolve service names | Add port 53 UDP exception |
| Using :latest tag | Non-reproducible deployments | Use immutable tags (e.g., `nginx:1.25.3`) |
| Running as root | Full host access if compromised | Set `runAsNonRoot: true` |
| No resource limits | Noisy neighbor issues | Define requests and limits |
| Hardcoded secrets | Credentials in Git history | Use SecretKeyRef or external store |

---

## 📚 Additional Resources

- **NetworkPolicy Guide**: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- **Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **CIS Kubernetes Benchmark**: https://www.cisecurity.org/benchmark/kubernetes
- **NSA/CISA Kubernetes Hardening Guide**: https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF

---

## 🚀 Next Steps

- **Practice**: Apply these patterns to your own projects
- **Test**: Try breaking security (penetration testing)
- **Automate**: Use OPA/Gatekeeper to enforce policies
- **Monitor**: Deploy Falco for runtime security monitoring

---

## 🤔 Reflection Questions

1. **Why is default deny all important?**
   - Answer: Zero-trust foundation. Without it, any pod can talk to any pod (lateral movement risk).

2. **What's the difference between Ingress and Egress policies?**
   - **Ingress**: Controls WHO can connect TO this pod
   - **Egress**: Controls WHERE this pod can connect TO

3. **Why block metadata server access?**
   - Answer: Cloud metadata endpoints (169.254.169.254) contain IAM credentials. Compromised pod = credentials leak.

4. **What happens if you apply NetworkPolicy but CNI doesn't support it?**
   - Answer: Policy is created but NOT enforced. Traffic flows normally (dangerous!)

5. **Why use readOnlyRootFilesystem?**
   - Answer: Prevents attacker from writing malicious files (e.g., webshell, backdoor) even if they gain access.

---

**🎉 Congratulations!** You've mastered Kubernetes network security and hardening. You can now design and implement zero-trust architectures in production! 🛡️✨
