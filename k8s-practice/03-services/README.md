# Phase 3: Service Debugging & Troubleshooting

## 📚 Learning Objectives
- Master Service debugging techniques
- Understand selector matching
- Learn to identify and fix common Service issues
- Practice intentional breaking and fixing

## 🎯 Challenge: Fix the Broken Service

### The Scenario
You've been given a deployment and service, but something is wrong! Traffic isn't reaching the pods.

## 🚀 Step-by-Step Instructions

### Step 1: Deploy the Application
```bash
# Deploy the app
kubectl apply -f deployment.yaml

# Verify pods are running
kubectl get pods
kubectl get pods -o wide
kubectl get pods --show-labels
```

### Step 2: Apply the BROKEN Service
```bash
# Apply the intentionally broken service
kubectl apply -f service-broken.yaml

# Check the service
kubectl get service bio-web-service-broken
kubectl describe service bio-web-service-broken
```

### Step 3: Spot the Problem
```bash
# 🔍 INVESTIGATION TIME!

# Check endpoints
kubectl get endpoints bio-web-service-broken
# ❌ Output: <none>  (This is the problem!)

# Compare selector with pod labels
kubectl describe service bio-web-service-broken | grep Selector
kubectl get pods --show-labels

# Do they match? NO!
```

### Step 4: Debug Process
```bash
# Let's verify this step-by-step:

# 1. Are pods running?
kubectl get pods
# ✅ Yes, 3/3 running

# 2. Does service exist?
kubectl get service bio-web-service-broken
# ✅ Yes, has ClusterIP

# 3. Does service have endpoints?
kubectl get endpoints bio-web-service-broken
# ❌ NO! This is the problem!

# 4. Why no endpoints?
kubectl describe service bio-web-service-broken
# Selector: app=wrong-label
kubectl get pods --show-labels
# Pods have: app=bio-site
# ❌ MISMATCH!
```

### Step 5: Fix It!
```bash
# Option 1: Fix the service
kubectl apply -f service-correct.yaml

# Option 2: Edit in place
kubectl edit service bio-web-service-broken
# Change selector from "wrong-label" to "bio-site"
# Save and exit

# Verify the fix
kubectl get endpoints bio-web-service-broken
# ✅ Now you should see 3 endpoint IPs!
```

### Step 6: Test Connectivity
```bash
# Test from within cluster
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- sh

# Inside the test pod:
curl http://bio-web-service-broken
# ✅ Should work now!
exit
```

## 🔍 Debugging Methodology

### The Service Debugging Checklist

```bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. CHECK PODS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
kubectl get pods
kubectl get pods --show-labels
# ✅ Are they running?
# ✅ Do they have the expected labels?

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. CHECK SERVICE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
kubectl get service <service-name>
kubectl describe service <service-name>
# ✅ Does it exist?
# ✅ Does it have a ClusterIP?
# ✅ What is the selector?

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. CHECK ENDPOINTS (MOST IMPORTANT!)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
kubectl get endpoints <service-name>
kubectl describe endpoints <service-name>
# ✅ Are there endpoint IPs?
# ✅ Do endpoint IPs match pod IPs?

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. VERIFY SELECTOR MATCHES LABELS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
kubectl get service <service-name> -o yaml | grep -A 5 selector
kubectl get pods -l app=bio-site
# ✅ Does selector match pod labels?

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. TEST CONNECTIVITY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# From another pod:
kubectl run test --image=curlimages/curl --rm -it -- curl http://<service-name>

# From pod directly to check app works:
kubectl port-forward pod/<pod-name> 8080:80
# Open browser: http://localhost:8080
```

## 🧪 More Debugging Scenarios

### Scenario 1: Port Mismatch
```yaml
# Service
ports:
- port: 80
  targetPort: 8080  # ❌ But container uses port 80!

# Fix: Match targetPort to containerPort
targetPort: 80
```

### Scenario 2: Wrong Namespace
```bash
# Create service in wrong namespace
kubectl create namespace wrong-ns
kubectl apply -f service-correct.yaml -n wrong-ns

# Try to access (will fail)
kubectl run test --image=curlimages/curl --rm -it -- curl http://bio-web-service

# Fix: Create in correct namespace
kubectl apply -f service-correct.yaml -n <correct-namespace>
```

### Scenario 3: Pods Not Ready
```bash
# Check pod readiness
kubectl get pods
# NAME                       READY   STATUS    
# bio-web-5f7b8c9d4-abc12    0/1     Running

# Pods exist but not ready = No endpoints!
kubectl describe pod <pod-name>
# Check readiness probe status

# Service only routes to READY pods
```

### Scenario 4: Multiple Selectors
```yaml
# Service with multiple label requirements
selector:
  app: bio-site
  environment: production  # ❌ Pods don't have this label!

# Fix: Add label to pods or remove from selector
```

## 🐛 Common Service Problems & Solutions

| Problem | Symptom | Solution |
|---------|---------|----------|
| Selector mismatch | No endpoints | Fix selector to match pod labels |
| Wrong port | Connection refused | Match targetPort to containerPort |
| Wrong namespace | Service not found | Deploy to correct namespace |
| Pods not ready | No endpoints | Fix readiness probes or app issues |
| Service doesn't exist | DNS resolution fails | Create the service |
| Wrong service type | Can't access externally | Change to NodePort/LoadBalancer |

## 📊 Advanced Debugging Commands

### Service Details
```bash
# Get full service YAML
kubectl get service <name> -o yaml

# Get service selector
kubectl get service <name> -o jsonpath='{.spec.selector}'

# Get service endpoints
kubectl get endpoints <name> -o yaml

# Watch endpoints change
kubectl get endpoints <name> -w
```

### Pod Matching
```bash
# Find pods matching selector
kubectl get pods -l app=bio-site

# Show all labels
kubectl get pods --show-labels

# Filter by multiple labels
kubectl get pods -l app=bio-site,tier=frontend

# Check which service a pod belongs to
kubectl get pods -o wide --show-labels
```

### Network Testing
```bash
# Test service from another pod
kubectl run test --image=nicolaka/netshoot --rm -it -- bash
# Inside: curl http://bio-web-service
# Inside: nslookup bio-web-service
# Inside: ping bio-web-service

# Test pod directly (bypass service)
kubectl run test --image=curlimages/curl --rm -it -- curl http://<pod-ip>

# Port-forward to test locally
kubectl port-forward service/bio-web-service 8080:80
# Open: http://localhost:8080
```

## ✅ Validation Checklist
- [ ] Identified the broken selector
- [ ] Fixed the service and verified endpoints appeared
- [ ] Successfully accessed app through service
- [ ] Understand why endpoints were empty
- [ ] Can debug service issues independently

## 🎓 Reflection Questions
1. Why don't services route to pods that aren't ready?
2. What happens if you have pods with the label but they're in a different namespace?
3. Can a single service route to pods from multiple deployments?
4. What's the difference between `port` and `targetPort`?
5. How does Kubernetes DNS work for services?

## 💡 Pro Tips

### Quick Health Check
```bash
# One-liner to check if service is healthy
kubectl get service,endpoints,pods -l app=bio-site
```

### Service Without Selector (Advanced)
```yaml
# Manual endpoints for external services
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  ports:
  - port: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-db
subsets:
- addresses:
  - ip: 192.168.1.100
  ports:
  - port: 5432
```

### Service Discovery
```bash
# Services are accessible via DNS:
# Format: <service-name>.<namespace>.svc.cluster.local

# From same namespace:
curl http://bio-web-service

# From different namespace:
curl http://bio-web-service.default.svc.cluster.local
```

## ➡️ Next Steps
Move to:
- **Phase 4**: Rolling Updates & Rollbacks
- Learn zero-downtime deployments and safe rollback strategies
