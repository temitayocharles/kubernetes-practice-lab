# PHASE 11: RBAC & Security (60 minutes)

## 🎯 Learning Objectives

After completing this phase, you will understand:
- **What ServiceAccounts are** and why pods need identity
- **Role vs ClusterRole** (namespace-scoped vs cluster-wide)
- **RoleBinding vs ClusterRoleBinding** (how to connect permissions)
- **How to debug RBAC issues** using kubectl commands
- **Why metrics-server had 403 Forbidden errors** and how to fix it yourself

## 🔥 The Real Problem That Brought You Here

Remember the metrics-server showing `1/1 Running` but logs filled with:
```
E1102 03:44:41.996955 "Failed to scrape node" err="request failed, status: \"403 Forbidden\""
```

That was an **RBAC issue**! The metrics-server pod was running with the correct TLS flags, but its ServiceAccount **didn't have permission** to access the kubelet API endpoints (`nodes/metrics`, `nodes/proxy`).

**This phase will teach you:**
1. How RBAC works from the ground up
2. How to diagnose permission errors
3. How to fix the metrics-server issue yourself
4. How to never be blindsided by RBAC again

---

## 📋 Prerequisites

```bash
# Ensure your cluster is running
kubectl cluster-info

# If your cluster is stopped, start it first
# Example commands for different cluster types:
# k3d cluster start <cluster-name>
# minikube start
# kind start cluster

# Verify you can create resources
kubectl auth can-i create serviceaccounts

# Check if metrics-server exists (optional - we'll fix it in this phase)
kubectl get deployment metrics-server -n kube-system
```

---

## 🔐 RBAC Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    RBAC Components                           │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. ServiceAccount (WHO)                                     │
│     ↓                                                         │
│  2. Role/ClusterRole (WHAT permissions)                      │
│     ↓                                                         │
│  3. RoleBinding/ClusterRoleBinding (CONNECT them)            │
│                                                               │
│  Role          = namespace-scoped permissions                │
│  ClusterRole   = cluster-wide permissions                    │
│                                                               │
│  RoleBinding        = binds Role to ServiceAccount           │
│  ClusterRoleBinding = binds ClusterRole to ServiceAccount    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Step 1: Understanding ServiceAccounts (10 minutes)

### What is a ServiceAccount?

Every pod runs with an **identity** (ServiceAccount). By default, pods use the `default` ServiceAccount which has minimal permissions.

### Exercise 1.1: Create Custom ServiceAccounts

```bash
# Apply ServiceAccounts and pods
kubectl apply -f 01-serviceaccount.yaml

# Check ServiceAccounts created
kubectl get serviceaccounts

# You should see:
# NAME         SECRETS   AGE
# default      0         ...
# app-reader   0         ...
# app-admin    0         ...

# Check pods (will stay in ContainerCreating for a bit)
kubectl get pods

# Exec into reader-pod
kubectl exec -it reader-pod -- sh

# Inside the pod, check mounted ServiceAccount token
ls -la /var/run/secrets/kubernetes.io/serviceaccount/
cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 50; echo

# Try to list pods (should FAIL - no permissions yet)
kubectl get pods
# Error: pods is forbidden: User "system:serviceaccount:default:app-reader" cannot list resource "pods"

# Exit the pod
exit
```

### 🧠 What Just Happened?

- The pod runs as ServiceAccount `app-reader`
- Kubernetes automatically mounts a token at `/var/run/secrets/kubernetes.io/serviceaccount/`
- The ServiceAccount has **NO permissions yet** (no Role/RoleBinding)
- kubectl inside the pod tries to use this token and gets **forbidden**

---

## 📝 Step 2: Role & RoleBinding (Namespace-Scoped) (10 minutes)

### What is a Role?

A **Role** defines permissions **within a single namespace**. It specifies:
- **apiGroups**: Which API group (e.g., `""` for core, `apps` for deployments)
- **resources**: Which resources (e.g., `pods`, `services`)
- **verbs**: Which actions (e.g., `get`, `list`, `create`, `delete`)

### Exercise 2.1: Grant Read-Only Pod Access

```bash
# Apply Role and RoleBinding
kubectl apply -f 02-role-readonly.yaml

# Check the Role
kubectl get role pod-reader -o yaml

# Check the RoleBinding
kubectl get rolebinding read-pods-binding -o yaml

# Now exec into reader-pod again
kubectl exec -it reader-pod -- sh

# Try to list pods again (should SUCCEED now)
kubectl get pods
# Should see: reader-pod, admin-pod

# Try to view pod logs
kubectl logs reader-pod
# Should work!

# Try to DELETE a pod (should FAIL - only has get/list/watch)
kubectl delete pod admin-pod
# Error: pods "admin-pod" is forbidden: User "system:serviceaccount:default:app-reader" cannot delete resource "pods"

exit
```

### 🧠 Key Takeaways

- **Role**: Defines permissions (what can be done)
- **RoleBinding**: Connects the Role to a ServiceAccount (who can do it)
- Permissions are **additive only** (no deny rules)
- Missing verbs = forbidden errors

### 📊 Debugging Command

```bash
# Check if ServiceAccount can perform an action
kubectl auth can-i get pods --as=system:serviceaccount:default:app-reader
# Output: yes

kubectl auth can-i delete pods --as=system:serviceaccount:default:app-reader
# Output: no

kubectl auth can-i list pods --as=system:serviceaccount:default:app-reader -n kube-system
# Output: no (Role is namespace-scoped to 'default' only)
```

---

## 📝 Step 3: ClusterRole & ClusterRoleBinding (Cluster-Wide) (10 minutes)

### What is a ClusterRole?

A **ClusterRole** defines permissions **across ALL namespaces** or for cluster-scoped resources (nodes, namespaces, etc.).

### Exercise 3.1: Grant Deployment Management Across All Namespaces

```bash
# Apply ClusterRole and ClusterRoleBinding
kubectl apply -f 03-clusterrole-admin.yaml

# Check ClusterRole
kubectl get clusterrole deployment-manager -o yaml

# Exec into admin-pod
kubectl exec -it admin-pod -- sh

# List deployments in default namespace
kubectl get deployments
# Should work!

# List deployments in kube-system namespace
kubectl get deployments -n kube-system
# Should work! (ClusterRole = all namespaces)

# Try to create a deployment
kubectl create deployment test-deploy --image=nginx --replicas=2
# Should work!

# Clean up
kubectl delete deployment test-deploy

exit
```

### 📊 Role vs ClusterRole Comparison

```bash
# Test app-reader (has Role in 'default' namespace only)
kubectl auth can-i get pods --as=system:serviceaccount:default:app-reader
# Output: yes

kubectl auth can-i get pods --as=system:serviceaccount:default:app-reader -n kube-system
# Output: no (Role is namespace-scoped)

# Test app-admin (has ClusterRole - all namespaces)
kubectl auth can-i get deployments --as=system:serviceaccount:default:app-admin
# Output: yes

kubectl auth can-i get deployments --as=system:serviceaccount:default:app-admin -n kube-system
# Output: yes (ClusterRole works everywhere)
```

---

## 📝 Step 4: Fix the Metrics-Server 403 Forbidden Issue (15 minutes)

### 🔍 The Investigation

Let's check the current metrics-server RBAC:

```bash
# Check if metrics-server ClusterRole exists
kubectl get clusterrole system:metrics-server -o yaml

# Check the 'rules' section
# You might see:
# rules:
# - apiGroups: [""]
#   resources:
#   - pods
#   - nodes
#   - nodes/stats       # Present ✅
#   # nodes/metrics     # ⚠️ MISSING!
#   # nodes/proxy       # ⚠️ MISSING!
#   verbs: ["get", "list", "watch"]
```

### 🐛 The Root Cause

The metrics-server ServiceAccount is **missing permissions** for:
- `nodes/metrics` - Kubelet metrics API endpoint
- `nodes/proxy` - Proxying requests to kubelet

Even with `--kubelet-insecure-tls` flag, the ServiceAccount **can't access** these endpoints!

### 💡 The Fix

```bash
# Apply the corrected RBAC configuration
kubectl apply -f 04-metrics-server-rbac-fix.yaml

# This creates:
# 1. ServiceAccount (metrics-server)
# 2. ClusterRole with ALL needed permissions (including nodes/metrics, nodes/proxy)
# 3. ClusterRoleBinding (connects them)
# 4. APIService registration

# Restart metrics-server to pick up new permissions
kubectl rollout restart deployment metrics-server -n kube-system

# Wait for pod to be ready (60 seconds)
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# Check logs (should see NO more 403 errors)
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=30

# Test metrics API
kubectl top nodes
# Should work now! ✅

kubectl top pods -A
# Should work! ✅
```

### 🧠 What We Fixed

**Before:**
```yaml
rules:
- apiGroups: [""]
  resources:
  - nodes/stats    # Not enough!
```

**After:**
```yaml
rules:
- apiGroups: [""]
  resources:
  - nodes/stats
  - nodes/metrics  # ✅ Added
  - nodes/proxy    # ✅ Added
```

---

## 📝 Step 5: RBAC Debugging Exercise (10 minutes)

Practice diagnosing and fixing broken RBAC configurations.

### Exercise 5.1: Intentionally Broken Role

```bash
# Apply broken Role
kubectl apply -f 05-rbac-debugging-exercise.yaml

# This creates a Role that can only 'get' and 'list' pods
# But NOT 'create' or 'delete'

# Test permissions
kubectl auth can-i create pods --as=system:serviceaccount:default:app-reader
# Output: no ❌

kubectl auth can-i delete pods --as=system:serviceaccount:default:app-reader
# Output: no ❌

# The problem: Missing verbs in the Role!

# Apply the FIXED version
kubectl apply -f 05-rbac-debugging-exercise.yaml

# Look for the 'fixed-pod-manager' Role
kubectl get role fixed-pod-manager -o yaml

# Now update the RoleBinding to use the fixed Role
kubectl patch rolebinding broken-pod-manager-binding -p '{"roleRef":{"name":"fixed-pod-manager"}}'

# Test again
kubectl auth can-i create pods --as=system:serviceaccount:default:app-reader
# Output: yes ✅ (if using the fixed RoleBinding)
```

### 🔍 Debugging Commands Cheat Sheet

```bash
# 1. Check if a ServiceAccount can do something
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name>

# Examples:
kubectl auth can-i get pods --as=system:serviceaccount:default:app-reader
kubectl auth can-i create deployments --as=system:serviceaccount:default:app-admin
kubectl auth can-i delete secrets --as=system:serviceaccount:default:deployer-sa

# 2. List all verbs a ServiceAccount can do on a resource
kubectl auth can-i --list --as=system:serviceaccount:default:app-reader

# 3. Check Role/ClusterRole details
kubectl get role <name> -o yaml
kubectl get clusterrole <name> -o yaml

# 4. Check RoleBinding/ClusterRoleBinding details
kubectl get rolebinding <name> -o yaml
kubectl get clusterrolebinding <name> -o yaml

# 5. Find all RoleBindings for a ServiceAccount
kubectl get rolebindings -o json | jq '.items[] | select(.subjects[]?.name=="app-reader") | .metadata.name'

# 6. Find all ClusterRoleBindings for a ServiceAccount
kubectl get clusterrolebindings -o json | jq '.items[] | select(.subjects[]?.name=="app-reader") | .metadata.name'
```

---

## 📝 Step 6: Real-World Scenarios (5 minutes)

### Apply Pre-Built Roles

```bash
# Apply developer and deployer roles
kubectl apply -f 06-real-world-scenarios.yaml

# Check what each can do

# Developer role:
kubectl auth can-i --list --as=system:serviceaccount:default:developer-sa | grep pods
# Should see: get, list, watch, create (for pods/exec)

# Deployer role:
kubectl auth can-i create deployments --as=system:serviceaccount:default:deployer-sa
# Output: yes

kubectl auth can-i delete secrets --as=system:serviceaccount:default:deployer-sa
# Output: no (deployers can only read secrets, not delete)
```

### 🏢 When to Use Each Role Type

| Scenario | Use | Example |
|----------|-----|---------|
| CI/CD deployment pipeline | Role + RoleBinding | Deploy to `production` namespace only |
| Monitoring system (Prometheus) | ClusterRole + ClusterRoleBinding | Read metrics from all namespaces |
| Developer viewing logs | Role + RoleBinding | Read pods/logs in `dev` namespace |
| Platform admin | ClusterRole + ClusterRoleBinding | Manage all cluster resources |

---

## 🎓 Key Concepts Summary

### 1. ServiceAccount = Identity
- Every pod runs as a ServiceAccount
- Token is automatically mounted at `/var/run/secrets/kubernetes.io/serviceaccount/`
- Default ServiceAccount has minimal permissions

### 2. Role = Permissions (Namespace-Scoped)
- Defines **what** can be done
- Only applies within **one namespace**
- Uses: apiGroups, resources, verbs

### 3. ClusterRole = Permissions (Cluster-Wide)
- Defines **what** can be done
- Applies **across all namespaces** or cluster-scoped resources
- Uses: apiGroups, resources, verbs

### 4. RoleBinding = Connection (Namespace-Scoped)
- Connects a Role to a ServiceAccount
- Only works within **one namespace**

### 5. ClusterRoleBinding = Connection (Cluster-Wide)
- Connects a ClusterRole to a ServiceAccount
- Works **across all namespaces**

### 6. Debugging RBAC
```bash
# Always use kubectl auth can-i first!
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>

# Check logs for "forbidden" errors
kubectl logs <pod> | grep -i forbidden

# Verify Role/ClusterRole rules
kubectl get role <name> -o yaml
kubectl describe clusterrole <name>
```

---

## 🐛 Common RBAC Issues & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `pods is forbidden` | Missing `get`/`list` verb in Role | Add verb to Role rules |
| `403 Forbidden` in logs | ServiceAccount lacks permissions | Check ClusterRole has correct resources |
| `cannot create resource "pods/exec"` | Missing `pods/exec` resource | Add `pods/exec` to resources list |
| Works in one namespace, fails in another | Using Role instead of ClusterRole | Use ClusterRole + ClusterRoleBinding |
| `the server doesn't have a resource type "nodes/metrics"` | Resource name typo | Use `nodes/metrics` not `node/metrics` |

---

## ✅ Verification Checklist

After completing this phase, verify:

```bash
# 1. ServiceAccounts exist
kubectl get serviceaccount | grep -E 'app-reader|app-admin|developer-sa|deployer-sa'

# 2. Roles created
kubectl get role

# 3. ClusterRoles created
kubectl get clusterrole | grep -E 'deployment-manager|system:metrics-server'

# 4. RoleBindings created
kubectl get rolebinding

# 5. ClusterRoleBindings created
kubectl get clusterrolebinding | grep -E 'admin-deployment-manager|system:metrics-server'

# 6. Metrics-server working
kubectl top nodes
# Should return CPU and memory usage (not "Metrics API not available")

kubectl logs -n kube-system -l k8s-app=metrics-server --tail=10
# Should see NO "403 Forbidden" errors
```

---

## 🧹 Cleanup (Optional)

```bash
# Remove all practice resources
kubectl delete -f 01-serviceaccount.yaml
kubectl delete -f 02-role-readonly.yaml
kubectl delete -f 03-clusterrole-admin.yaml
kubectl delete -f 05-rbac-debugging-exercise.yaml
kubectl delete -f 06-real-world-scenarios.yaml

# Keep metrics-server RBAC fix (04-metrics-server-rbac-fix.yaml)
# Don't delete this - it's the fix for your cluster!
```

---

## 🎯 Learning Outcomes

After completing this phase, you should be able to:

✅ **Explain** why pods need ServiceAccounts  
✅ **Differentiate** between Role and ClusterRole  
✅ **Create** RBAC policies for real-world scenarios  
✅ **Debug** 403 Forbidden errors using kubectl auth can-i  
✅ **Fix** metrics-server RBAC issues confidently  
✅ **Design** least-privilege access for CI/CD pipelines  
✅ **Never be blindsided by RBAC errors again!**

---

## 🤔 Reflection Questions

1. **Why did metrics-server fail even with `--kubelet-insecure-tls` flag?**
   - Answer: TLS flag handles certificate validation, but RBAC controls **permission** to access the API endpoint. Both are needed!

2. **When should you use Role vs ClusterRole?**
   - Answer: Use Role when permissions are needed in **one namespace only**. Use ClusterRole for cluster-wide access or cluster-scoped resources (nodes, namespaces, PVs).

3. **What happens if you create a Role but forget the RoleBinding?**
   - Answer: Nothing works! The Role defines permissions, but without RoleBinding, no ServiceAccount is **connected** to those permissions.

4. **How do you debug "pods is forbidden" errors?**
   - Answer: 
     1. Identify the ServiceAccount: `kubectl get pod <name> -o yaml | grep serviceAccountName`
     2. Check permissions: `kubectl auth can-i get pods --as=system:serviceaccount:<ns>:<sa>`
     3. Fix: Add missing verb/resource to Role/ClusterRole

---

## 📚 Additional Resources

- **Official Docs**: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- **RBAC Best Practices**: https://kubernetes.io/docs/concepts/security/rbac-good-practices/
- **kubectl auth can-i**: https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access

---

## 🚀 Next Steps

- **Phase 12** (Future): Network Policies & Security Hardening
- **Practice**: Apply RBAC to your own projects
- **Challenge**: Create a read-only ServiceAccount that can view pods but not secrets

---

**🎉 Congratulations!** You've mastered RBAC and fixed the metrics-server issue yourself. You now understand how Kubernetes controls access and can confidently debug permission errors. Never be blindsided by 403 Forbidden again! 🔐✨
