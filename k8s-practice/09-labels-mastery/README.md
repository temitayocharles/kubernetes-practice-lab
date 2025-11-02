# Phase 9: Labels & Selectors Mastery 🏷️

## 📚 Why Labels Are "Magic" in Kubernetes

Labels are the **FOUNDATION** of Kubernetes. They enable:
- ✅ Service discovery (Services find Pods)
- ✅ Deployment targeting (ReplicaSets manage Pods)
- ✅ Resource organization (Group related resources)
- ✅ Traffic routing (Canary/Blue-Green deployments)
- ✅ Operational queries (Find all prod databases)
- ✅ RBAC policies (Access control by labels)
- ✅ Network policies (Traffic control by labels)
- ✅ Node affinity (Schedule pods on specific nodes)

**The Magic:** One label change can instantly reroute traffic, change ownership, or isolate resources!

## 🎯 Learning Objectives
- Master label selectors (equality-based & set-based)
- Use labels for multi-tier applications
- Implement traffic routing with labels
- Perform label-based operations at scale
- Debug selector mismatches
- Understand label best practices

## 🏗️ Scenario: Multi-Tier E-Commerce Application

We'll deploy a realistic app with:
- **Frontend** (web UI)
- **API** (backend service)
- **Database** (data tier)
- Multiple **environments** (dev, staging, prod)
- Multiple **versions** (v1, v2)

## 📋 Step-by-Step Exercises

### Exercise 1: Deploy Multi-Tier App with Rich Labels

```bash
# Apply the multi-tier deployment
kubectl apply -f multi-tier-app.yaml

# View all resources
kubectl get all --show-labels

# Notice the rich labeling scheme!
```

### Exercise 2: Query by Labels (The Magic Begins!)

```bash
# Find all frontend pods
kubectl get pods -l tier=frontend

# Find all production resources
kubectl get pods -l environment=production

# Find production frontend pods (AND logic)
kubectl get pods -l tier=frontend,environment=production

# Find v1 OR v2 (set-based selector)
kubectl get pods -l 'version in (v1,v2)'

# Find everything EXCEPT database
kubectl get pods -l 'tier notin (database)'

# Find pods with ANY version label
kubectl get pods -l version

# Find pods WITHOUT version label
kubectl get pods -l '!version'
```

### Exercise 3: Service Routing Magic 🎩✨

This is where the REAL magic happens!

```bash
# Apply services
kubectl apply -f services.yaml

# Initially, service routes to v1
kubectl describe service frontend-service | grep Selector
# Selector: tier=frontend,version=v1

# Test it
kubectl run test --image=curlimages/curl --rm -it -- curl http://frontend-service

# ✨ MAGIC TRICK 1: Instant traffic switch to v2
kubectl patch service frontend-service -p '{"spec":{"selector":{"tier":"frontend","version":"v2"}}}'

# Test again - now hitting v2!
kubectl run test --image=curlimages/curl --rm -it -- curl http://frontend-service

# ✨ MAGIC TRICK 2: Route to ALL versions (remove version selector)
kubectl patch service frontend-service -p '{"spec":{"selector":{"tier":"frontend"}}}'

# Now load-balances across v1 AND v2!
```

### Exercise 4: Label-Based Batch Operations

```bash
# Scale all frontend pods
kubectl scale deployment -l tier=frontend --replicas=5

# Restart all v1 deployments
kubectl rollout restart deployment -l version=v1

# Delete all staging resources
kubectl delete all -l environment=staging

# Get logs from all API pods
for pod in $(kubectl get pods -l tier=api -o name); do
  echo "=== $pod ==="
  kubectl logs $pod | tail -5
done

# Port-forward to any frontend pod
kubectl port-forward $(kubectl get pod -l tier=frontend -o name | head -1) 8080:80
```

### Exercise 5: Advanced Selectors

```bash
# Equality-based (comma = AND)
kubectl get pods -l tier=frontend,environment=production,version=v2

# Set-based (IN, NOTIN, EXISTS)
kubectl get pods -l 'tier in (frontend,api),environment notin (dev)'

# Complex queries
kubectl get pods -l 'tier,environment,version in (v1,v2)'

# Label exists check
kubectl get pods -l canary  # Has 'canary' label
kubectl get pods -l '!canary'  # Doesn't have 'canary' label
```

### Exercise 6: Dynamic Pod Ownership Transfer

```bash
# Deploy v1
kubectl apply -f deployment-v1.yaml

# Manually create a rogue pod with same labels
kubectl run rogue-pod --image=temitayocharles/hello-k8s:latest \
  --labels="tier=frontend,version=v1,app=ecommerce"

# Check: ReplicaSet sees it and reduces other pods!
kubectl get pods -l tier=frontend,version=v1

# ✨ MAGIC: Transfer ownership by changing label
kubectl label pod rogue-pod version=v2 --overwrite

# Now v1 ReplicaSet creates a new pod to replace it!
kubectl get pods -l tier=frontend
```

### Exercise 7: Label-Based Traffic Splitting

```bash
# Deploy v1 with 3 replicas
kubectl apply -f deployment-v1.yaml
kubectl scale deployment frontend-v1 --replicas=3

# Deploy v2 with 1 replica (25% traffic)
kubectl apply -f deployment-v2.yaml
kubectl scale deployment frontend-v2 --replicas=1

# Service selects BOTH (only tier label)
kubectl apply -f service-both-versions.yaml

# Result: 75% v1, 25% v2 (3:1 ratio)

# Test traffic distribution
for i in {1..20}; do
  kubectl run test-$i --image=curlimages/curl --rm --restart=Never -- \
    curl -s http://frontend-service | grep version
done
```

### Exercise 8: Label-Based Debugging

```bash
# Problem: Service has no endpoints!
kubectl get endpoints frontend-service
# <none>

# Debug process:
# 1. What's the service selector?
kubectl get service frontend-service -o jsonpath='{.spec.selector}'

# 2. What labels do pods have?
kubectl get pods --show-labels

# 3. Do they match?
kubectl get pods -l tier=frontend,version=v1
# If empty = MISMATCH!

# 4. Fix by updating service selector OR pod labels
kubectl label pods -l tier=frontend version=v1
```

### Exercise 9: Organizational Labels (Real-World)

```bash
# Apply realistic labeling scheme
kubectl apply -f enterprise-labels.yaml

# Now you can query like a pro:

# All resources owned by platform team
kubectl get all -l team=platform

# All critical production services
kubectl get all -l environment=production,criticality=high

# All resources for customer-X
kubectl get all -l customer=customer-x

# Monthly cost allocation
kubectl get all -l cost-center=engineering

# Find everything for a specific feature
kubectl get all -l feature=checkout

# Compliance: Find all PCI-DSS resources
kubectl get all -l compliance=pci-dss
```

### Exercise 10: Label Inheritance & Propagation

```bash
# Labels on Deployment
kubectl label deployment frontend-v1 release-date="2024-11-01"

# Check: Labels DON'T automatically propagate to pods
kubectl get pods --show-labels | grep release-date
# Not there!

# Solution: Update pod template
kubectl patch deployment frontend-v1 -p \
  '{"spec":{"template":{"metadata":{"labels":{"release-date":"2024-11-01"}}}}}'

# Now new pods get the label (existing pods don't change until recreated)
kubectl get pods --show-labels | grep release-date
```

## 🎓 Label Selector Syntax Reference

### Equality-Based
```bash
# Single label
kubectl get pods -l environment=production

# Multiple labels (AND)
kubectl get pods -l environment=production,tier=frontend

# NOT equal (only in YAML matchExpressions)
# See selector examples in files
```

### Set-Based
```bash
# IN
kubectl get pods -l 'environment in (production,staging)'

# NOTIN
kubectl get pods -l 'tier notin (database,cache)'

# EXISTS
kubectl get pods -l version

# NOT EXISTS
kubectl get pods -l '!version'
```

### In YAML (matchExpressions)
```yaml
selector:
  matchLabels:
    app: myapp
  matchExpressions:
  - key: environment
    operator: In
    values: [production, staging]
  - key: tier
    operator: NotIn
    values: [database]
  - key: version
    operator: Exists
```

## 💡 Label Best Practices

### ✅ DO
1. **Use standard label keys:**
   - `app.kubernetes.io/name`: Application name
   - `app.kubernetes.io/instance`: Unique instance name
   - `app.kubernetes.io/version`: Application version
   - `app.kubernetes.io/component`: Component (database, cache, etc.)
   - `app.kubernetes.io/part-of`: Higher-level application name
   - `app.kubernetes.io/managed-by`: Tool managing the resource

2. **Use organizational labels:**
   - `team`: owning-team
   - `environment`: dev/staging/prod
   - `cost-center`: for billing
   - `criticality`: low/medium/high

3. **Use functional labels:**
   - `tier`: frontend/backend/data
   - `version`: v1/v2/v3
   - `release`: canary/stable/beta

### ❌ DON'T
- Don't use labels for large/non-identifying data (use annotations)
- Don't change selector labels on Services (creates downtime)
- Don't use special characters (only alphanumeric, `-`, `_`, `.`)
- Don't make labels too specific (hurts reusability)
- Don't forget to label ALL related resources

## 🧠 Label Strategy Matrix

| Use Case | Label Pattern | Example |
|----------|---------------|---------|
| Service routing | `tier`, `version` | `tier=frontend,version=v2` |
| Environment separation | `environment` | `environment=production` |
| Team ownership | `team` | `team=platform` |
| Cost allocation | `cost-center` | `cost-center=engineering` |
| Compliance tracking | `compliance` | `compliance=pci-dss` |
| Feature flagging | `feature` | `feature=new-checkout` |
| Canary deployment | `track` | `track=canary` |
| Multi-tenancy | `customer`, `tenant` | `customer=acme-corp` |

## 🔬 Advanced Experiments

### Experiment 1: Blue-Green Deployment with Labels
```bash
# Deploy blue (current production)
kubectl apply -f deployment-blue.yaml
kubectl apply -f service-production.yaml  # Points to blue

# Deploy green (new version, testing)
kubectl apply -f deployment-green.yaml
kubectl apply -f service-test.yaml  # Points to green

# Test green
kubectl run test --image=curlimages/curl --rm -it -- curl http://test-service

# ✨ INSTANT SWITCH: Production now uses green
kubectl patch service production-service -p '{"spec":{"selector":{"color":"green"}}}'

# Rollback instantly if issues
kubectl patch service production-service -p '{"spec":{"selector":{"color":"blue"}}}'
```

### Experiment 2: Label-Based Node Selection
```bash
# Label a node
kubectl label node <node-name> disk=ssd

# Schedule pods on SSD nodes
kubectl apply -f deployment-with-node-selector.yaml
# nodeSelector:
#   disk: ssd
```

### Experiment 3: Multi-Version Coexistence
```bash
# Run v1, v2, v3 simultaneously
kubectl apply -f deployment-v1.yaml
kubectl apply -f deployment-v2.yaml
kubectl apply -f deployment-v3.yaml

# Different services for different customers
kubectl apply -f service-customer-a.yaml  # Points to v1
kubectl apply -f service-customer-b.yaml  # Points to v2
kubectl apply -f service-beta-users.yaml  # Points to v3
```

## 📊 Monitoring & Operations

### View Label Usage
```bash
# All unique label keys
kubectl get pods -o json | jq -r '.items[].metadata.labels | keys[]' | sort -u

# Count pods per version
kubectl get pods -l version --no-headers | awk '{print $1}' | cut -d'-' -f3 | sort | uniq -c

# Show label distribution
kubectl get pods --show-labels | awk '{print $NF}' | tr ',' '\n' | sort | uniq -c
```

### Bulk Label Operations
```bash
# Add label to all pods in namespace
kubectl label pods --all environment=production

# Remove label
kubectl label pods --all version-

# Update existing label
kubectl label pods --all tier=backend --overwrite

# Label based on condition
kubectl label pods -l tier=frontend region=us-west --overwrite
```

## ✅ Mastery Checklist

By the end of this phase, you should be able to:
- [ ] Explain how Services use label selectors
- [ ] Write complex label queries (equality + set-based)
- [ ] Use labels for instant traffic routing
- [ ] Perform batch operations with label selectors
- [ ] Design a label strategy for an organization
- [ ] Debug selector mismatch issues
- [ ] Implement blue-green deployments with labels
- [ ] Use labels for multi-environment management
- [ ] Understand label propagation (or lack thereof)
- [ ] Apply label best practices

## 🎓 Real-World Scenarios

### Scenario 1: Emergency Traffic Drain
```bash
# Remove pods from service without deleting them
kubectl label pods -l tier=frontend,version=v2 version=v2-drained --overwrite

# Service no longer routes to them (missing v2 label)
# Debug/fix pods, then restore label
kubectl label pods -l version=v2-drained version=v2 --overwrite
```

### Scenario 2: Gradual Rollout
```bash
# Start with 1 v2 pod (10% traffic if 9 v1 pods exist)
kubectl scale deployment frontend-v2 --replicas=1

# Increase gradually
kubectl scale deployment frontend-v2 --replicas=3  # 30%
kubectl scale deployment frontend-v2 --replicas=5  # 50%
kubectl scale deployment frontend-v2 --replicas=10 # 100%
kubectl scale deployment frontend-v1 --replicas=0  # Remove old
```

### Scenario 3: Feature Flag with Labels
```bash
# Deploy feature behind label
kubectl apply -f deployment-new-feature.yaml
# Pods have: feature=new-checkout

# Only beta users' service uses it
kubectl apply -f service-beta.yaml
# Selector: tier=frontend,feature=new-checkout

# Roll out to all
kubectl patch service frontend-service -p \
  '{"spec":{"selector":{"tier":"frontend","feature":"new-checkout"}}}'
```

## ➡️ Next Steps
- **Phase 10**: Service Types Comparison (ClusterIP, NodePort, LoadBalancer)
- **Phase 11**: Annotations Deep Dive (metadata that's not for selection)
- **Phase 12**: Canary Deployments (progressive delivery with labels)
