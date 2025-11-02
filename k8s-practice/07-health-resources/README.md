# Phase 7: Health Checks & Resource Management

## 📚 Learning Objectives
- Set resource requests and limits
- Implement liveness, readiness, and startup probes
- Understand QoS classes
- Prevent resource starvation

## 🚀 Instructions

### Step 1: Deploy with Resources
```bash
kubectl apply -f deployment-full.yaml
kubectl get pods
kubectl describe pod <pod-name> | grep -A 10 "Requests:"
```

### Step 2: Observe Probes
```bash
# Watch probe behavior
kubectl get pods -w

# Check probe status
kubectl describe pod <pod-name> | grep -A 20 "Conditions:"

# See events
kubectl get events --sort-by='.lastTimestamp'
```

### Step 3: Test Liveness Probe
```bash
# Simulate app crash (if your app has /crash endpoint)
kubectl exec <pod-name> -- curl localhost/crash

# Watch pod restart
kubectl get pods -w
# Pod will be restarted by liveness probe
```

## 🔍 Resource Concepts

### CPU Units
- `100m` = 0.1 CPU core (100 millicores)
- `1` = 1 full CPU core
- `2` = 2 full CPU cores

### Memory Units
- `64Mi` = 64 Mebibytes (MiB)
- `1Gi` = 1 Gibibyte (GiB)
- Kubernetes uses binary units (1024-based)

### QoS Classes
1. **Guaranteed**: requests == limits for all resources
2. **Burstable**: requests < limits
3. **BestEffort**: No requests or limits set

```bash
# Check QoS class
kubectl get pod <pod-name> -o jsonpath='{.status.qosClass}'
```

## 🧪 Probe Types

### Liveness Probe
**Purpose:** Is the app healthy? If not, restart it.
**Use Case:** Detect deadlocks, infinite loops

### Readiness Probe
**Purpose:** Can the app handle traffic? If not, remove from service.
**Use Case:** During startup, during database connection issues

### Startup Probe
**Purpose:** Has the app finished starting?
**Use Case:** Slow-starting apps (legacy apps, large initialization)

## 📊 Monitoring Resources
```bash
# Pod resource usage
kubectl top pods

# Node resource usage
kubectl top nodes

# Describe to see requests/limits
kubectl describe node <node-name>
```

## 💡 Best Practices
- Always set requests (for scheduling)
- Set limits to prevent resource hogging
- Use readiness probes (prevents serving traffic when not ready)
- Use liveness probes cautiously (can cause restart loops)
- Startup probes for slow-starting apps
- Test probe thresholds in staging first
