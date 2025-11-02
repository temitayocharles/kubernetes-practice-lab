# Kubernetes Practice Lab - Complete Guided Exercise

## Learning Objectives
By the end of this lab, you will be able to:
- Deploy and manage applications with Deployments and ReplicaSets
- Externalize configuration using ConfigMaps and Secrets
- Understand the relationship between Deployments, Pods, and Services
- Perform rolling updates and rollbacks safely
- Expose applications externally using Ingress
- Manage persistent storage with PersistentVolumeClaims
- Implement health checks and resource management
- Use advanced patterns (HPA, Network Policies, Init Containers)
- Master label-based routing and traffic management
- Choose appropriate service types for different scenarios
- **Implement RBAC for authentication and authorization**
- **Design zero-trust network architectures with NetworkPolicies**
- **Apply Pod Security Standards for production workloads**
- Debug common Kubernetes deployment and security issues

## Time Allocation
- **Core Phases (1-8):** 2-3 hours (guided practice)
- **Advanced Phases (9-10):** 1.5 hours (labels & service types mastery)
- **Security Phases (11-12):** 2-2.5 hours (RBAC & network security)
- **Total:** 6-7 hours for complete mastery

## Prerequisites Checklist
Before starting, ensure you have:
- ✅ Kubernetes cluster running (`kubectl cluster-info`)
- ✅ `kubectl` configured and working (`kubectl version`)
- ✅ Ability to create resources (`kubectl auth can-i create pods`)
- ✅ Text editor ready (VS Code, nano, or vim)
- ✅ Terminal access with bash/zsh

---

## Setup: Create Your Workspace (5 minutes)

### Step 1: Create Your Personal Namespace
```bash
# Replace <yourname> with your actual first name (lowercase, no spaces)
kubectl create namespace <yourname>-lab

# Set this as your default namespace for this session
kubectl config set-context --current --namespace=<yourname>-lab

# Verify you're in the right namespace
kubectl config view --minify | grep namespace:
```

**Checkpoint:** You should see your namespace listed when you run `kubectl get namespaces`

---

# PHASE 1: Basic Deployment & Service (15 minutes)

## Learning Objectives
- Understand how Deployments manage Pods
- Create a ClusterIP Service
- Learn the relationship between Deployments, ReplicaSets, Pods, and Services
- Practice basic kubectl commands

## Files in 01-basic/
- `deployment.yaml` - Deployment with 2 replicas
- `service.yaml` - ClusterIP service

## Step 1.1: Review the Deployment Manifest
```bash
cd 01-basic/

# Examine the deployment structure
cat deployment.yaml
```

**Key Concepts:**
- **Deployment**: Manages ReplicaSets and Pods
- **Replicas**: Number of identical pods to maintain
- **Selector**: How deployment finds its pods
- **Template**: Pod specification

## Step 1.2: Deploy the Application
```bash
# Apply deployment
kubectl apply -f deployment.yaml

# Watch pods come up
kubectl get pods -w
# (Press Ctrl+C when all are Running)

# Check deployment
kubectl get deployments
kubectl describe deployment bio-web
```

**What you should see:**
- 2 pods running
- Deployment shows `2/2 READY`

## Step 1.3: Review the Service Manifest
```bash
# Examine the service structure
cat service.yaml
```

**Key Concepts:**
- **Service**: Provides stable networking for pods
- **Selector**: Finds pods by labels
- **Ports**: Service port (80) → target port (80)
- **Type**: ClusterIP (internal only)

## Step 1.4: Create the Service
```bash
# Apply service
kubectl apply -f service.yaml

# View service
kubectl get service bio-web-service

# Check endpoints (should show 2 pod IPs)
kubectl describe service bio-web-service
```

**Key Concept:** The Service uses selector `app: bio-site` to find Pods. Check pod labels match:
```bash
kubectl get pods --show-labels
```

## Step 1.5: Test Internal Connectivity
```bash
# Create a test pod inside the cluster
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- sh

# Inside the test pod, run:
curl http://bio-web-service
exit
```

**Result:** You should see the response from your application!

## Experiment: What Happens When You Delete a Pod?
```bash
# List pods
kubectl get pods

# Delete one pod
kubectl delete pod <pod-name>

# Immediately check again
kubectl get pods
```

**Observation:** A new pod is already being created! The Deployment ensures 2 replicas are always running.

## Experiment: Scale the Deployment
```bash
# Scale to 5 replicas
kubectl scale deployment bio-web --replicas=5

# Watch it happen
kubectl get pods -w

# Check service endpoints now
kubectl describe service bio-web-service
```

**Observation:** Service now has 5 endpoint IPs!

## Commands Cheat Sheet
```bash
# View resources
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get all

# Describe (detailed info)
kubectl describe pod <pod-name>
kubectl describe deployment bio-web
kubectl describe service bio-web-service

# Logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow

# Execute commands in pod
kubectl exec <pod-name> -- <command>
kubectl exec -it <pod-name> -- sh

# Scale
kubectl scale deployment bio-web --replicas=3
```

## Validation Checklist
- [ ] Deployment shows 2/2 READY replicas
- [ ] Service has 2 endpoints
- [ ] Can curl service from inside cluster
- [ ] Deleted pod automatically recreates
- [ ] Service maintains same ClusterIP after pod restarts

## Reflection Question
What happens to old pods during a rolling update? Did all pods restart at once?

---

# PHASE 2: ConfigMaps & Secrets (20 minutes)

## Learning Objectives
- Externalize configuration from container images
- Understand difference between ConfigMaps and Secrets
- Inject configuration as environment variables
- Learn imperative vs declarative resource creation

## Why ConfigMaps and Secrets?
❌ **Bad:** Hardcoding config in Dockerfile
```dockerfile
ENV DATABASE_URL=postgres://prod-server:5432/mydb
ENV API_KEY=secret-key-12345
```

✅ **Good:** Externalizing configuration
- Same image works in dev/staging/prod
- No secrets in version control
- Easy updates without rebuilding images

## Files in 02-config/
- `config-resources.yaml` - ConfigMap and Secret definitions
- `deployment-with-config.yaml` - Deployment consuming config
- `service.yaml` - Service (same as Phase 1)

## Step 2.1: Review ConfigMap and Secret Manifests
```bash
cd ../02-config/

# Examine the config resources
cat config-resources.yaml
```

**Key Concepts:**
- **ConfigMap**: Plain text key-value pairs (non-sensitive)
- **Secret**: Base64 encoded values (sensitive data)
- **stringData**: Plain text input (auto-encoded for Secrets)

## Step 2.2: Create ConfigMap (Imperative Method)
```bash
kubectl create configmap site-config \
  --from-literal=SITE_TITLE="My Portfolio" \
  --from-literal=THEME="dark" \
  --from-literal=VERSION="2.0"

# View what was created
kubectl get configmap site-config -o yaml
```

## Step 2.3: Create Secret (Imperative Method)
```bash
kubectl create secret generic site-secret \
  --from-literal=CONTACT_EMAIL="yourname@example.com" \
  --from-literal=API_KEY="demo-key-12345"

# View (values are base64 encoded)
kubectl get secret site-secret -o yaml

# Decode a value
kubectl get secret site-secret -o jsonpath='{.data.CONTACT_EMAIL}' | base64 --decode
echo  # Add newline
```

## Step 2.4: Create from YAML (Declarative - Production Way)
```bash
# Apply the YAML file
kubectl apply -f config-resources.yaml

# List all configs and secrets
kubectl get configmaps,secrets
```

**Declarative vs Imperative:**
- **Imperative:** `kubectl create` - quick for testing
- **Declarative:** `kubectl apply -f` - version control friendly, repeatable

## Step 2.5: Review Deployment with Configuration
```bash
# Examine how config is injected
cat deployment-with-config.yaml
```

**Key Concepts:**
- **envFrom**: Injects all keys from ConfigMap/Secret as env vars
- **configMapRef**: References ConfigMap by name
- **secretRef**: References Secret by name

## Step 2.6: Deploy Application with Configuration
```bash
# Apply deployment that consumes config
kubectl apply -f deployment-with-config.yaml

# Watch rollout
kubectl rollout status deployment/bio-web

# Apply service
kubectl apply -f service.yaml
```

## Step 2.7: Verify Environment Variables Injected
```bash
# Get a pod name
kubectl get pods

# Check environment variables
kubectl exec <pod-name> -- env | grep SITE_TITLE
kubectl exec <pod-name> -- env | grep CONTACT_EMAIL
kubectl exec <pod-name> -- env | grep POD_NAME

# See all environment variables
kubectl exec <pod-name> -- env | sort
```

**What you should see:**
- `SITE_TITLE`, `THEME`, `VERSION` from ConfigMap
- `CONTACT_EMAIL`, `API_KEY` from Secret
- `POD_NAME`, `POD_NAMESPACE`, `POD_IP` from Kubernetes metadata

## ConfigMap vs Secret

| Feature | ConfigMap | Secret |
|---------|-----------|--------|
| Purpose | Non-sensitive config | Sensitive data |
| Storage | Plain text | Base64 encoded |
| Max Size | 1 MiB | 1 MiB |
| Use Cases | URLs, feature flags, themes | Passwords, API keys, certificates |
| Git Safe? | ✅ Yes | ⚠️ Use sealed-secrets or vault |

## Experiment: Update ConfigMap
```bash
# Edit ConfigMap
kubectl edit configmap site-config-v2
# Change THEME from "dark" to "light"

# Check if pod sees the change immediately
kubectl exec <pod-name> -- env | grep THEME
# ❌ Still shows "dark"!

# Why? ConfigMaps loaded at startup don't auto-reload
# Solution: Restart deployment
kubectl rollout restart deployment/bio-web

# Check new pod
kubectl get pods
kubectl exec <new-pod-name> -- env | grep THEME
# ✅ Now shows "light"!
```

## Validation Checklist
- [ ] ConfigMap created with key-value pairs
- [ ] Secret created with sensitive data
- [ ] Pods show environment variables from ConfigMap
- [ ] Pods show environment variables from Secret
- [ ] Can decode secret values manually
- [ ] Understand config changes require pod restart

## Reflection Question
What's the difference between the imperative and declarative approach? Which would be easier to track in Git?

---

# PHASE 3: Service Debugging (15 minutes)

## Learning Objectives
- Debug broken services
- Understand selector matching
- Learn the relationship between Services and Endpoints
- Practice troubleshooting methodology

## The Challenge
You'll be given a deployment and a **broken** service. Your job: find and fix the issue!

## Files in 03-services/
- `deployment.yaml` - Working deployment (3 replicas)
- `service-broken.yaml` - ❌ Broken service (intentional!)
- `service-correct.yaml` - ✅ Fixed service (use if stuck)

## Step 3.1: Deploy Application
```bash
cd ../03-services/

# Deploy app
kubectl apply -f deployment.yaml

# Verify pods running
kubectl get pods
kubectl get pods --show-labels
```

**Pods should have label:** `app: bio-site`

## Step 3.2: Apply the BROKEN Service
```bash
# Apply broken service
kubectl apply -f service-broken.yaml

# Check service
kubectl get service bio-web-service-broken
kubectl describe service bio-web-service-broken
```

## Step 3.3: Debug - Why No Endpoints?
```bash
# 🔍 CHECK 1: Does service have endpoints?
kubectl get endpoints bio-web-service-broken
# ❌ <none>  (This is the problem!)

# 🔍 CHECK 2: What's the service selector?
kubectl get service bio-web-service-broken -o jsonpath='{.spec.selector}'
# Shows: {"app":"wrong-label"}

# 🔍 CHECK 3: What labels do pods have?
kubectl get pods --show-labels
# Shows: app=bio-site

# 🔍 CONCLUSION: Selector mismatch!
# Service looks for: app=wrong-label
# Pods have: app=bio-site
```

## Step 3.4: Fix the Service
**Option 1: Apply correct service**
```bash
kubectl apply -f service-correct.yaml
```

**Option 2: Edit in place**
```bash
kubectl edit service bio-web-service-broken
# Change selector from "wrong-label" to "bio-site"
# Save and exit
```

**Option 3: Patch**
```bash
kubectl patch service bio-web-service-broken -p '{"spec":{"selector":{"app":"bio-site"}}}'
```

## Step 3.5: Verify Fix
```bash
# Check endpoints now
kubectl get endpoints bio-web-service-broken
# ✅ Should show 3 pod IPs!

# Test connectivity
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl http://bio-web-service-broken
# ✅ Should work!
```

## The Service Debugging Checklist

When a service isn't working, check in this order:

```bash
# 1. Are pods running?
kubectl get pods

# 2. Do pods have correct labels?
kubectl get pods --show-labels

# 3. Does service exist?
kubectl get service <service-name>

# 4. What's the service selector?
kubectl describe service <service-name> | grep Selector

# 5. Does service have endpoints?
kubectl get endpoints <service-name>

# 6. Do selector and pod labels match?
# Compare outputs from steps 2 and 4
```

## Common Service Problems

| Problem | Symptom | Solution |
|---------|---------|----------|
| Selector mismatch | No endpoints | Fix selector to match pod labels |
| Wrong port | Connection refused | Match targetPort to containerPort |
| Wrong namespace | Service not found | Deploy to correct namespace |
| Pods not ready | No endpoints | Fix app or readiness probes |
| Typo in label | No endpoints | Fix label spelling |

## Validation Checklist
- [ ] Identified the selector mismatch
- [ ] Fixed the service
- [ ] Service now has 3 endpoints
- [ ] Can successfully curl the service
- [ ] Understand how label selectors work

---

# PHASE 4: Rolling Updates & Rollbacks (20 minutes)

## Learning Objectives
- Perform zero-downtime rolling updates
- Control update strategy (maxSurge, maxUnavailable)
- Roll back failed deployments
- View and manage deployment history

## Files in 04-updates/
- `deployment-v1.yaml` - Initial deployment (v1 image)
- `service.yaml` - Service for the deployment

## Step 4.1: Review Deployment Strategy
```bash
cd ../04-updates/

# Examine the deployment strategy
cat deployment-v1.yaml | grep -A 10 "strategy:"
```

**Key Concepts:**
- **RollingUpdate**: Default strategy
- **maxSurge**: Max extra pods during update (1)
- **maxUnavailable**: Max pods down during update (1)
- **change-cause**: Annotation for tracking changes

## Step 4.2: Deploy Initial Version
```bash
# Deploy v1
kubectl apply -f deployment-v1.yaml

# Apply service
kubectl apply -f service.yaml

# Wait for rollout
kubectl rollout status deployment/bio-web

# Check deployment
kubectl get deployments
kubectl get pods
```

## Step 4.3: Update to v2 (Rolling Update)
**Method 1: Imperative update**
```bash
# Update image
kubectl set image deployment/bio-web bio-container=temitayocharles/hello-k8s:v2 --record

# Watch rollout in real-time
kubectl rollout status deployment/bio-web

# Watch pods change
kubectl get pods -w
# (Press Ctrl+C to stop)
```

**Observation:** Pods terminate and start gradually (rolling update!)

**Method 2: Edit YAML and apply**
```bash
# Edit deployment-v1.yaml, change image tag from v1 to v2
# Then apply
kubectl apply -f deployment-v1.yaml
```

## Step 4.4: Check Rollout History
```bash
# View deployment history
kubectl rollout history deployment/bio-web

# See details of specific revision
kubectl rollout history deployment/bio-web --revision=2
```

## Step 4.5: Rollback to Previous Version
```bash
# Undo last rollout
kubectl rollout undo deployment/bio-web

# Watch rollback
kubectl rollout status deployment/bio-web

# Verify we're back on v1
kubectl describe deployment bio-web | grep Image
```

## Step 4.6: Rollback to Specific Revision
```bash
# List revisions
kubectl rollout history deployment/bio-web

# Rollback to specific revision
kubectl rollout undo deployment/bio-web --to-revision=1
```

## Understanding Rolling Update Strategy
Look at `deployment-v1.yaml`:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Max 1 extra pod during update
    maxUnavailable: 1  # Max 1 pod down during update
```

**What this means:**
- With 3 replicas:
  - `maxSurge: 1` → Can temporarily have 4 pods
  - `maxUnavailable: 1` → Must have at least 2 pods running
- Ensures minimal disruption during updates

## Experiment: Simulate Failed Update
```bash
# Update to non-existent image tag
kubectl set image deployment/bio-web bio-container=temitayocharles/hello-k8s:v999

# Watch what happens
kubectl get pods -w
# Some pods will be in ImagePullBackOff

# Check rollout status
kubectl rollout status deployment/bio-web
# Will timeout

# Rollback the failed update
kubectl rollout undo deployment/bio-web

# Verify recovery
kubectl get pods
```

## Pause and Resume Rollouts
```bash
# Start an update
kubectl set image deployment/bio-web bio-container=temitayocharles/hello-k8s:v3

# Pause it immediately
kubectl rollout pause deployment/bio-web

# Make additional changes while paused
kubectl set env deployment/bio-web NEW_VAR=value

# Resume (all changes applied together)
kubectl rollout resume deployment/bio-web
```

## Validation Checklist
- [ ] Successfully updated from v1 to v2
- [ ] Observed rolling update behavior
- [ ] Rolled back to previous version
- [ ] Viewed rollout history
- [ ] Understand maxSurge and maxUnavailable
- [ ] Can recover from failed updates

## Reflection Question
What happens to old pods during a rolling update? How does Kubernetes ensure zero downtime?

---

# PHASE 5: Ingress & External Access (25 minutes)

## Learning Objectives
- Expose services externally using Ingress
- Configure host-based routing
- Understand Ingress controllers
- Access applications from outside the cluster

## Files in 05-ingress/
- `ingress.yaml` - Ingress resource for bio.local

## Step 5.1: Enable Ingress Controller

**For Minikube:**
```bash
minikube addons enable ingress

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**For k3d/k3s:**
```bash
# Traefik is built-in, check it's running
kubectl get pods -n kube-system | grep traefik
```

## Step 5.2: Review Ingress Manifest
```bash
cd ../05-ingress/

# Examine ingress configuration
cat ingress.yaml
```

**Key Concepts:**
- **Host-based routing**: Routes traffic based on hostname
- **Rewrite target**: URL path rewriting
- **Backend service**: Which service to route to

## Step 5.3: Deploy Application & Service
```bash
# Use deployment from Phase 1
kubectl apply -f ../01-basic/deployment.yaml
kubectl apply -f ../01-basic/service.yaml
```

## Step 5.4: Create Ingress Resource
```bash
# Apply ingress
kubectl apply -f ingress.yaml

# Check ingress status
kubectl get ingress
kubectl describe ingress bio-ingress
```

**What you should see:**
- Ingress with host: `bio.local`
- ADDRESS column (might take a minute to populate)

## Step 5.5: Configure Local DNS
```bash
# Add to /etc/hosts
echo "127.0.0.1 bio.local" | sudo tee -a /etc/hosts

# Verify it was added
cat /etc/hosts | grep bio.local
```

## Step 5.6: Test Access
**For Minikube:**
```bash
# Get Minikube IP
minikube ip

# Test with curl
curl http://bio.local

# Or open in browser
open http://bio.local
```

**For k3d:**
```bash
# Should work directly
curl http://bio.local

# Or open in browser
open http://bio.local
```

## Understanding Ingress Flow
```
Browser (http://bio.local)
    ↓
/etc/hosts resolves to 127.0.0.1
    ↓
Ingress Controller (nginx/traefik)
    ↓
Ingress Rule (bio.local → bio-web-service)
    ↓
Service (bio-web-service)
    ↓
Pods (via endpoints)
```

## Experiment: Multiple Services with Path-Based Routing
Create `ingress-multi.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: bio-web-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service  # Would need to create this
            port:
              number: 8080
```

## Validation Checklist
- [ ] Ingress controller is running
- [ ] Ingress resource created
- [ ] /etc/hosts configured
- [ ] Can access application at http://bio.local
- [ ] Understand request flow through Ingress

## Reflection Question
Explain the flow of a request from your browser to a pod when accessing http://bio.local

---

# PHASE 6: Persistent Storage (20 minutes)

## Learning Objectives
- Create and use PersistentVolumeClaims (PVC)
- Mount volumes to pods
- Understand data persistence across pod restarts
- Learn difference between Deployment and StatefulSet

## Files in 06-storage/
- `deployment-with-pvc.yaml` - Deployment with PVC

## Step 6.1: Review PVC Configuration
```bash
cd ../06-storage/

# Examine the PVC and deployment
cat deployment-with-pvc.yaml
```

**Key Concepts:**
- **PersistentVolumeClaim**: Request for storage
- **accessModes**: ReadWriteOnce (single node)
- **storage**: Amount requested (1Gi)
- **volumeMount**: Where to mount in container

## Step 6.2: Create PVC and Deploy
```bash
# Apply (creates both PVC and Deployment)
kubectl apply -f deployment-with-pvc.yaml

# Check PVC status
kubectl get pvc
# Should show "Bound" status

# Check pods
kubectl get pods
```

## Step 6.3: Verify Volume Mount
```bash
# Get pod name
kubectl get pods

# Check mount point
kubectl exec <pod-name> -- df -h | grep /data

# List contents
kubectl exec <pod-name> -- ls -la /data
```

## Step 6.4: Write Data to Persistent Volume
```bash
# Write a file
kubectl exec <pod-name> -- sh -c "echo 'Hello from pod!' > /data/test.txt"

# Read it back
kubectl exec <pod-name> -- cat /data/test.txt
```

## Step 6.5: Test Persistence Across Pod Restarts
```bash
# Delete the pod
kubectl delete pod <pod-name>

# Wait for new pod
kubectl get pods -w

# Get new pod name
kubectl get pods

# Check if data still exists
kubectl exec <new-pod-name> -- cat /data/test.txt
```

**Result:** ✅ Data persists! The file is still there.

## Understanding Persistent Storage

**Volume Types:**
- **emptyDir** - Temporary, deleted when pod dies
- **hostPath** - Node's filesystem (not portable)
- **PersistentVolume** - Cluster-level storage resource
- **PersistentVolumeClaim** - User's request for storage

**Access Modes:**
- **ReadWriteOnce (RWO)** - Single node can mount (most common)
- **ReadOnlyMany (ROX)** - Multiple nodes, read-only
- **ReadWriteMany (RWX)** - Multiple nodes, read-write (needs special storage)

## StatefulSet vs Deployment

**Use StatefulSet when:**
- Need stable pod names (pod-0, pod-1, pod-2)
- Need ordered deployment and scaling
- Each pod needs its own PVC
- Examples: databases, zookeeper, elasticsearch

**Use Deployment when:**
- Pods are interchangeable
- Stateless applications
- Shared storage is okay
- Examples: web servers, APIs

## Validation Checklist
- [ ] PVC created and bound
- [ ] Pod has volume mounted at /data
- [ ] Can write files to /data
- [ ] Data persists after pod deletion
- [ ] Understand when to use PersistentVolumes

---

# PHASE 7: Health Checks & Resource Management (20 minutes)

## Learning Objectives
- Set resource requests and limits
- Implement liveness, readiness, and startup probes
- Understand QoS classes
- Prevent resource starvation

## Files in 07-health-resources/
- `deployment-full.yaml` - Deployment with resources and probes

## Step 7.1: Review Resource and Probe Configuration
```bash
cd ../07-health-resources/

# Examine the complete deployment
cat deployment-full.yaml
```

**Key Concepts:**
- **Requests**: Guaranteed resources
- **Limits**: Maximum resources
- **Liveness Probe**: Restart if unhealthy
- **Readiness Probe**: Remove from service if not ready
- **Startup Probe**: Wait for app to start

## Step 7.2: Deploy with Resources and Probes
```bash
# Apply deployment
kubectl apply -f deployment-full.yaml

# Watch pods start
kubectl get pods -w
```

## Step 7.3: Verify Resource Allocation
```bash
# Check pod resources
kubectl describe pod <pod-name> | grep -A 10 "Requests:"

# Should show:
# Requests:
#   cpu: 100m
#   memory: 64Mi
# Limits:
#   cpu: 200m
#   memory: 128Mi
```

## Step 7.4: Check Probe Configuration
```bash
# Describe pod to see probes
kubectl describe pod <pod-name> | grep -A 10 "Liveness:"
kubectl describe pod <pod-name> | grep -A 10 "Readiness:"
kubectl describe pod <pod-name> | grep -A 10 "Startup:"
```

## Understanding Probes

### Liveness Probe
**Purpose:** Is the app healthy? If not, restart it.
**Use Case:** Detect deadlocks, infinite loops, crashed app

**Example behavior:**
- App crashes → Liveness probe fails → Kubernetes restarts pod

### Readiness Probe
**Purpose:** Is the app ready to serve traffic? If not, remove from service.
**Use Case:** During startup, during database connection issues

**Example behavior:**
- App starting up → Readiness probe fails → Pod not added to service endpoints
- App ready → Readiness probe succeeds → Pod added to service, receives traffic

### Startup Probe
**Purpose:** Has the app finished starting?
**Use Case:** Slow-starting apps (legacy apps, large initialization)

**Example behavior:**
- Protects slow-starting apps from being killed by liveness probe
- Once startup succeeds, liveness/readiness take over

## Resource Requests vs Limits

### Requests (Scheduling)
- Kubernetes **guarantees** this amount
- Used by scheduler to choose node
- `cpu: 100m` = 0.1 CPU core
- `memory: 64Mi` = 64 Mebibytes

### Limits (Enforcement)
- Maximum the container can use
- Container killed if exceeds memory limit
- CPU throttled if exceeds CPU limit

## QoS Classes
```bash
# Check pod's QoS class
kubectl get pod <pod-name> -o jsonpath='{.status.qosClass}'
```

**Classes:**
1. **Guaranteed** - requests == limits for all resources (highest priority)
2. **Burstable** - requests < limits (medium priority)
3. **BestEffort** - no requests or limits (lowest priority, killed first)

## Monitoring Resources
```bash
# Pod resource usage (requires metrics-server)
kubectl top pods

# Node resource usage
kubectl top nodes

# If metrics-server not available:
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

## Experiment: Test Liveness Probe
If your app has a `/healthz` endpoint that can be made to fail:
```bash
# Simulate app failure (if endpoint exists)
kubectl exec <pod-name> -- curl localhost/make-unhealthy

# Watch pod restart
kubectl get pods -w
# Pod will transition: Running → Running (restarts: 1)
```

## Validation Checklist
- [ ] Deployment has resource requests and limits
- [ ] Liveness probe configured
- [ ] Readiness probe configured
- [ ] Startup probe configured
- [ ] Understand probe purposes
- [ ] Know QoS class of pods

---

# PHASE 8: Advanced Patterns (30 minutes)

## Learning Objectives
- Implement Horizontal Pod Autoscaling (HPA)
- Configure Network Policies
- Use Pod Anti-Affinity
- Implement Init Containers and Sidecars

## Files in 08-advanced/
- `advanced-deployment.yaml` - All advanced patterns in one file

## Step 8.1: Review Advanced Deployment
```bash
cd ../08-advanced/

# Examine all advanced patterns
cat advanced-deployment.yaml
```

**Key Concepts:**
- **HPA**: Auto-scaling based on CPU/memory
- **NetworkPolicy**: Control pod communication
- **Pod Anti-Affinity**: Spread pods across nodes
- **Init Container**: Setup tasks before main container
- **Sidecar Container**: Additional container in same pod

## Step 8.2: Deploy Advanced Application
```bash
# Apply
kubectl apply -f advanced-deployment.yaml

# Check everything created
kubectl get all
kubectl get hpa
kubectl get networkpolicy
```

## Horizontal Pod Autoscaler (HPA)

### View HPA
```bash
# Check HPA status
kubectl get hpa bio-web-hpa

# Describe for details
kubectl describe hpa bio-web-hpa
```

### Test Autoscaling (Generate Load)
```bash
# Create load generator
kubectl run load-generator --image=busybox --restart=Never -it --rm -- /bin/sh

# Inside the pod, generate load:
while true; do wget -q -O- http://bio-web-service; done
```

**In another terminal, watch HPA:**
```bash
kubectl get hpa -w
# Watch REPLICAS column increase as CPU goes up
```

## Init Containers

### Check Init Container Logs
```bash
# Get pod name
kubectl get pods

# View init container logs
kubectl logs <pod-name> -c init-setup
```

**What it shows:** Init container runs before main container starts.

### Describe Pod to See Init Container
```bash
kubectl describe pod <pod-name>

# Look for "Init Containers:" section
# Status should be "Terminated" with exit code 0
```

## Sidecar Containers

### Check Sidecar Logs
```bash
# View sidecar logs
kubectl logs <pod-name> -c log-sidecar
```

**What it shows:** Sidecar runs alongside main container.

### Multiple Containers in One Pod
```bash
# List containers in pod
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[*].name}'

# Should show: bio-container log-sidecar

# Execute command in specific container
kubectl exec <pod-name> -c bio-container -- ps aux
kubectl exec <pod-name> -c log-sidecar -- ps aux
```

## Network Policies

### Test Network Isolation
```bash
# Try to access service WITHOUT required label
kubectl run test-denied --image=curlimages/curl --rm -it --restart=Never -- curl http://bio-web-service --max-time 5
# ❌ Should timeout (blocked by network policy)

# Try with ALLOWED label
kubectl run test-allowed --image=curlimages/curl --labels=access=allowed --rm -it --restart=Never -- curl http://bio-web-service
# ✅ Should work!
```

**What's happening:**
- Network policy only allows pods with label `access=allowed` to reach `bio-web-service`
- Default deny for pods without the label

## Pod Anti-Affinity

### Check Pod Distribution
```bash
# View which nodes pods are on
kubectl get pods -o wide

# If you have multiple nodes:
# Pods should be spread across different nodes (anti-affinity!)
```

**What's happening:**
- `podAntiAffinity` tries to avoid placing pods on same node
- Improves availability (node failure won't take down all pods)

## Validation Checklist
- [ ] HPA adjusts replicas based on CPU
- [ ] Init container runs before main container
- [ ] Sidecar container runs alongside main container
- [ ] Network policy blocks unauthorized access
- [ ] Network policy allows access with correct label
- [ ] Understand pod anti-affinity purpose

---

# PHASE 9: Labels & Selectors Mastery (45 minutes)

## Learning Objectives
- Master label-based operations
- Implement instant traffic routing with labels
- Use advanced selectors (equality + set-based)
- Understand label strategies for production

## Why Labels Are "Magic"
Labels are the **foundation** of Kubernetes:
- Services find Pods via label selectors
- Deployments manage Pods via label selectors
- Network Policies control traffic via label selectors
- **One label change can instantly reroute all traffic!**

## Files in 09-labels-mastery/
- `multi-tier-app.yaml` - Multi-tier deployment with rich labels
- `services.yaml` - 6 services with different selectors

## Step 9.1: Review Multi-Tier Application
```bash
cd ../09-labels-mastery/

# Examine the labeled application
cat multi-tier-app.yaml
```

**What you'll deploy:**
- Frontend v1 (3 replicas) - production
- Frontend v2 (1 replica) - staging/canary
- API v1 (2 replicas)
- Database (1 replica)

## Step 9.2: Deploy Multi-Tier Application
```bash
# Deploy app
kubectl apply -f multi-tier-app.yaml

# View all resources with labels
kubectl get all --show-labels
```

## Step 9.3: Query by Labels

### Equality-Based Selectors
```bash
# Find all frontend pods
kubectl get pods -l tier=frontend

# Find all production resources
kubectl get pods -l environment=production

# Multiple labels (AND logic)
kubectl get pods -l tier=frontend,environment=production

# Find all v1 pods
kubectl get pods -l version=v1
```

### Set-Based Selectors
```bash
# Find v1 OR v2
kubectl get pods -l 'version in (v1,v2)'

# Find everything EXCEPT database
kubectl get pods -l 'tier notin (database)'

# Find pods WITH version label
kubectl get pods -l version

# Find pods WITHOUT version label
kubectl get pods -l '!version'

# Complex query
kubectl get pods -l 'tier in (frontend,api),environment notin (dev)'
```

## Step 9.4: Service Routing Magic ✨

### Apply Services
```bash
# Apply all services
kubectl apply -f services.yaml

# Check services
kubectl get services
```

### The Magic: Instant Traffic Switching
```bash
# Service routes to v1 initially
kubectl describe service frontend-v1-service | grep Selector
# Shows: tier=frontend,version=v1

# Test v1
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl http://frontend-v1-service

# ✨ MAGIC TRICK 1: Switch to v2 instantly
kubectl patch service frontend-v1-service -p '{"spec":{"selector":{"tier":"frontend","version":"v2"}}}'

# Test again - now hitting v2!
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl http://frontend-v1-service

# ✨ MAGIC TRICK 2: Route to ALL versions
kubectl patch service frontend-v1-service -p '{"spec":{"selector":{"tier":"frontend"}}}'
# Now load-balances across v1 AND v2!
```

**What just happened:**
- Changed service selector
- **Zero downtime** - no pod restarts
- **Instant effect** - next request uses new routing
- Perfect for blue-green deployments!

## Step 9.5: Traffic Splitting (Canary Rollout)
```bash
# Deploy with 3 v1 pods, 1 v2 pod
kubectl scale deployment frontend-v1 --replicas=3
kubectl scale deployment frontend-v2 --replicas=1

# Use service that selects BOTH versions
kubectl get service frontend-service

# Test traffic distribution
for i in {1..20}; do
  kubectl run test-$i --image=curlimages/curl --rm --restart=Never -- \
    curl -s http://frontend-service | grep -o "version.*"
done
```

**Result:** Roughly 75% v1, 25% v2 (3:1 ratio)

## Step 9.6: Batch Operations
```bash
# Scale ALL frontend deployments at once
kubectl scale deployment -l tier=frontend --replicas=5

# Restart ALL v1 deployments
kubectl rollout restart deployment -l version=v1

# Get logs from ALL API pods
for pod in $(kubectl get pods -l tier=api -o name); do
  echo "=== $pod ==="
  kubectl logs $pod | tail -5
done

# Delete ALL staging resources (CAREFUL!)
kubectl delete all -l environment=staging
```

## Step 9.7: Label-Based Debugging

### Scenario: Service Has No Endpoints
```bash
# Problem: Service not working
kubectl get endpoints frontend-v1-service
# <none>

# Debug: Check selector
kubectl get service frontend-v1-service -o jsonpath='{.spec.selector}'
# Shows what service is looking for

# Debug: Check pod labels
kubectl get pods --show-labels
# Shows what pods actually have

# Solution: Fix selector OR fix pod labels
kubectl label pods -l tier=frontend version=v1
# Now endpoints appear!
```

## Label Best Practices

### Recommended Label Keys
```yaml
labels:
  # Kubernetes recommended
  app.kubernetes.io/name: myapp
  app.kubernetes.io/version: v2
  app.kubernetes.io/component: frontend
  app.kubernetes.io/part-of: ecommerce
  app.kubernetes.io/managed-by: kubectl

  # Organizational
  team: platform
  environment: production
  cost-center: engineering

  # Functional
  tier: frontend
  version: v2
  track: stable
```

### Label Strategy Examples

**Multi-environment:**
```bash
kubectl get pods -l environment=production
kubectl get pods -l environment=staging
kubectl get pods -l environment=dev
```

**Cost allocation:**
```bash
kubectl get all -l cost-center=engineering
kubectl get all -l cost-center=marketing
```

**Team ownership:**
```bash
kubectl get all -l team=platform
kubectl get all -l team=data
```

## Validation Checklist
- [ ] Understand equality-based selectors
- [ ] Understand set-based selectors
- [ ] Can perform instant traffic routing
- [ ] Can do batch operations with labels
- [ ] Understand label-based debugging
- [ ] Know label best practices

---

# PHASE 10: Service Types Deep Dive (40 minutes)

## Learning Objectives
- Master all service types (ClusterIP, NodePort, LoadBalancer)
- Understand when to use each type
- Convert between types without downtime
- Work with servicelb (k3s LoadBalancer)

## Service Types Comparison

| Type | External Access | Port | Use Case | Cloud Cost |
|------|----------------|------|----------|------------|
| **ClusterIP** | ❌ No | 80 (any) | Internal services | Free |
| **NodePort** | ✅ Yes | 30000-32767 | Dev/testing | Free |
| **LoadBalancer** | ✅ Yes | 80/443 | Production | $$$ |

## Files in 10-service-types/
- `deployment.yaml` - Base application
- `service-clusterip.yaml` - Internal-only service
- `service-nodeport.yaml` - External with high port
- `service-loadbalancer.yaml` - Production external
- `multi-service-app.yaml` - 4-tier app with mixed types
- `servicelb-toggle.sh` - Utility script

## Step 10.1: Review Service Types
```bash
cd ../10-service-types/

# Examine all service types
cat service-clusterip.yaml
cat service-nodeport.yaml
cat service-loadbalancer.yaml
```

## Step 10.2: ClusterIP (Internal Only)
```bash
# Deploy app
kubectl apply -f deployment.yaml

# Create ClusterIP service
kubectl apply -f service-clusterip.yaml

# Check service
kubectl get service clusterip-service
# Note: EXTERNAL-IP = <none>

# Test from INSIDE cluster
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl http://clusterip-service
# ✅ Works!

# Try from OUTSIDE cluster (your Mac)
curl http://<cluster-ip>
# ❌ Fails! Not accessible externally
```

**When to use ClusterIP:**
- Databases (never expose externally)
- Internal APIs
- Backend services
- **Default choice** for internal communication

## Step 10.3: NodePort (External with High Port)
```bash
# Convert to NodePort
kubectl apply -f service-nodeport.yaml

# Check service
kubectl get service nodeport-service
# Note: TYPE = NodePort, PORT = 80:30080/TCP

# Test from outside cluster
curl http://localhost:30080
# ✅ Works!
```

**When to use NodePort:**
- Quick external access for testing
- Development environments
- CI/CD pipelines
- When LoadBalancer isn't available

**Limitations:**
- Ugly port numbers (30000-32767)
- Need to know node IP
- One service per port

## Step 10.4: LoadBalancer (Cloud-Like)
```bash
# Apply LoadBalancer service
kubectl apply -f service-loadbalancer.yaml

# Check service
kubectl get service loadbalancer-service
# EXTERNAL-IP might show <pending> or actual IP
```

### Check servicelb Status
```bash
# Use the utility script
chmod +x servicelb-toggle.sh
./servicelb-toggle.sh status
```

### Test LoadBalancer Functionality
```bash
# Test with script
./servicelb-toggle.sh test

# Check created resources
kubectl get service lb-test-service

# Clean up test
./servicelb-toggle.sh cleanup
```

**How servicelb works (k3s):**
1. Creates DaemonSet pod on each node
2. Binds host port for LoadBalancer service
3. Provides external access via host IP

**In cloud (AWS/GCP/Azure):**
- Automatically provisions cloud load balancer
- Costs ~$20/month per LoadBalancer service

## Step 10.5: Live Service Type Conversion
```bash
# Start with ClusterIP
kubectl apply -f service-clusterip.yaml

# Convert to NodePort (no downtime!)
kubectl patch service clusterip-service -p '{"spec":{"type":"NodePort"}}'

# Check - now has NodePort
kubectl get service clusterip-service

# Convert to LoadBalancer
kubectl patch service clusterip-service -p '{"spec":{"type":"LoadBalancer"}}'

# Convert back to ClusterIP
kubectl patch service clusterip-service -p '{"spec":{"type":"ClusterIP"}}'
```

**Key point:** Service type conversion is **seamless** - no pod restarts!

## Step 10.6: Multi-Service Architecture
```bash
# Deploy 4-tier app with mixed service types
kubectl apply -f multi-service-app.yaml

# Check all services
kubectl get services

# Result:
# - frontend: LoadBalancer (public-facing)
# - api: NodePort (admin/ops access)
# - database: ClusterIP (internal only)
# - cache: ClusterIP (internal only)
```

**Real-world pattern:**
- Public services: LoadBalancer
- Admin interfaces: NodePort
- Internal services: ClusterIP

## Cost Optimization Strategy

### ❌ Expensive: Multiple LoadBalancers
```
Service A: LoadBalancer ($20/month)
Service B: LoadBalancer ($20/month)
Service C: LoadBalancer ($20/month)
Total: $60/month
```

### ✅ Smart: One Ingress
```
Ingress Controller: LoadBalancer ($20/month)
  ├─ Service A: ClusterIP (free)
  ├─ Service B: ClusterIP (free)
  └─ Service C: ClusterIP (free)
Total: $20/month
```

## Session Affinity (Sticky Sessions)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-service
spec:
  type: LoadBalancer
  sessionAffinity: ClientIP  # Sticky sessions!
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600  # 1 hour
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 80
```

## Decision Tree

```
Need external access?
├─ NO
│  └─ Use ClusterIP (databases, internal APIs)
│
└─ YES
   └─ Production or testing?
      ├─ Production
      │  └─ Use LoadBalancer
      │     (or better: use Ingress to save costs)
      │
      └─ Testing/Dev
         └─ Use NodePort (quick and free)
```

## Validation Checklist
- [ ] Tested ClusterIP (internal only)
- [ ] Tested NodePort (external access)
- [ ] Tested LoadBalancer (with servicelb)
- [ ] Converted between service types live
- [ ] Understand cost implications
- [ ] Know when to use each type

---

# PHASE 11: RBAC & Security (60 minutes)

## Learning Objectives
- Understand ServiceAccounts and pod identity
- Master Role vs ClusterRole (namespace vs cluster-wide)
- Debug RBAC permission issues
- Fix the metrics-server 403 Forbidden issue yourself

## 🔥 The Real Problem
Remember metrics-server showing `1/1 Running` but `403 Forbidden` in logs? That was RBAC! The ServiceAccount didn't have permissions for `nodes/metrics` and `nodes/proxy`. This phase teaches you how to never be blindsided by RBAC again.

## Files in 11-rbac-security/
- `01-serviceaccount.yaml` - ServiceAccount basics
- `02-role-readonly.yaml` - Namespace-scoped permissions
- `03-clusterrole-admin.yaml` - Cluster-wide permissions
- `04-metrics-server-rbac-fix.yaml` - **The fix for 403 errors**
- `05-rbac-debugging-exercise.yaml` - Practice broken RBAC
- `06-real-world-scenarios.yaml` - Developer/deployer roles

## Key Concepts

### RBAC Components
```
1. ServiceAccount (WHO) - Identity for pods
2. Role/ClusterRole (WHAT) - Permissions definition
3. RoleBinding/ClusterRoleBinding (CONNECT) - Links them together
```

### Role vs ClusterRole
- **Role**: Namespace-scoped (one namespace only)
- **ClusterRole**: Cluster-wide (all namespaces)

## Quick Start

### Step 11.1: ServiceAccount Basics
```bash
cd 11-rbac-security

# Create ServiceAccounts and test pods
kubectl apply -f 01-serviceaccount.yaml

# Exec into reader-pod
kubectl exec -it reader-pod -- sh

# Try listing pods (will FAIL - no permissions yet)
kubectl get pods
# Error: forbidden

exit
```

### Step 11.2: Grant Read-Only Access
```bash
# Apply Role and RoleBinding
kubectl apply -f 02-role-readonly.yaml

# Now try again
kubectl exec -it reader-pod -- kubectl get pods
# SUCCESS! ✅
```

### Step 11.3: Fix Metrics-Server
```bash
# Apply the corrected RBAC (includes nodes/metrics, nodes/proxy)
kubectl apply -f 04-metrics-server-rbac-fix.yaml

# Restart metrics-server
kubectl rollout restart deployment metrics-server -n kube-system

# Wait 60 seconds, then test
kubectl top nodes
# Should work! ✅
```

## RBAC Debugging Commands
```bash
# Check if ServiceAccount can do something
kubectl auth can-i get pods --as=system:serviceaccount:default:app-reader
# Output: yes or no

# List all permissions for a ServiceAccount
kubectl auth can-i --list --as=system:serviceaccount:default:app-reader

# Check logs for forbidden errors
kubectl logs <pod> | grep -i forbidden
```

## Validation Checklist
- [ ] Understand ServiceAccounts provide pod identity
- [ ] Know difference between Role and ClusterRole
- [ ] Can debug RBAC issues with kubectl auth can-i
- [ ] Fixed metrics-server 403 Forbidden errors
- [ ] Created developer and deployer roles
- [ ] Never be blindsided by RBAC again! 🔐

See `11-rbac-security/README.md` for complete step-by-step guide.

---

# PHASE 12: Network Policies & Security Hardening (75 minutes)

## Learning Objectives
- Master NetworkPolicies for zero-trust networking
- Implement three-tier application security
- Apply Pod Security Standards (restricted profile)
- Block metadata server access (AWS/GCP/Azure)
- Follow security best practices for production

## 🛡️ Zero-Trust Architecture
Without NetworkPolicies, any pod can talk to any pod. With NetworkPolicies, you implement **default deny all** and explicitly allow only required traffic.

## Files in 12-network-security/
- `01-default-deny-all.yaml` - Block all traffic (foundation)
- `02-three-tier-app.yaml` - Frontend → API → Database
- `03-tier-network-policies.yaml` - Explicit allow rules
- `04-advanced-policies.yaml` - Namespace/IP/metadata blocking
- `05-pod-security-standards.yaml` - Restricted profile enforcement
- `06-security-best-practices.yaml` - Insecure vs Secure comparison

## Key Concepts

### NetworkPolicy Components
```
1. podSelector - Which pods the policy applies to
2. policyTypes - [Ingress, Egress]
3. ingress rules - WHO can connect TO this pod
4. egress rules - WHERE this pod can connect TO
```

### Three-Tier Security Pattern
```
Frontend (tier: web) ✅ allowed
  ↓
API (tier: backend) ✅ allowed
  ↓
Database (tier: data)

Frontend → Database ❌ DENIED (no rule exists)
```

## Quick Start

### Step 12.1: Default Deny All
```bash
cd 12-network-security

# Deploy three-tier app
kubectl apply -f 02-three-tier-app.yaml

# Test: Frontend can reach database (insecure!)
kubectl exec deployment/frontend -- nc -zv database-service 5432
# Success (⚠️ security issue)

# Apply default deny
kubectl apply -f 01-default-deny-all.yaml

# Test: Now blocked
kubectl exec deployment/frontend -- nc -zv -w 5 database-service 5432
# Timeout ✅ (blocked by NetworkPolicy)
```

### Step 12.2: Explicit Allow Rules
```bash
# Apply three-tier security policies
kubectl apply -f 03-tier-network-policies.yaml

# Now Frontend → API works
kubectl exec deployment/frontend -- curl -m 5 http://api-service:8080
# Output: API Response ✅

# But Frontend → Database still blocked
kubectl exec deployment/frontend -- nc -zv -w 5 database-service 5432
# Timeout ✅ (security win!)
```

### Step 12.3: Pod Security Standards
```bash
# Apply restricted profile namespace
kubectl apply -f 05-pod-security-standards.yaml

# Try to deploy insecure pod (will fail)
kubectl apply -n secure-namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
  - name: app
    image: nginx
    securityContext:
      privileged: true  # ❌ Violates policy
EOF
# Error: violates PodSecurity "restricted:latest" ✅
```

## Security Best Practices Checklist
```yaml
✅ runAsNonRoot: true (never run as root)
✅ allowPrivilegeEscalation: false
✅ readOnlyRootFilesystem: true
✅ capabilities: drop: [ALL]
✅ seccompProfile: RuntimeDefault
✅ Resource limits defined
✅ Secrets from SecretKeyRef (not hardcoded)
✅ Custom ServiceAccount (not default)
✅ Health checks configured
✅ Immutable image tags (not :latest)
```

## Validation Checklist
- [ ] Applied default deny all (ingress + egress)
- [ ] Three-tier security working (Frontend → API ✅, Frontend → DB ❌)
- [ ] Pod Security Standards enforced (restricted profile)
- [ ] Metadata server blocked (169.254.169.254)
- [ ] Secure deployment running with all best practices

See `12-network-security/README.md` for complete step-by-step guide.

---

# 📊 Commands Reference

## Essential kubectl Commands

### Resource Management
```bash
# Apply
kubectl apply -f file.yaml
kubectl apply -f directory/

# Get
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get all
kubectl get all --show-labels

# Describe (detailed info)
kubectl describe pod <name>
kubectl describe deployment <name>
kubectl describe service <name>

# Delete
kubectl delete -f file.yaml
kubectl delete pod <name>
kubectl delete all -l app=myapp
```

### Debugging
```bash
# Logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow
kubectl logs <pod-name> -c <container>  # Multi-container

# Execute commands
kubectl exec <pod-name> -- <command>
kubectl exec -it <pod-name> -- sh

# Port forwarding
kubectl port-forward pod/<name> 8080:80
kubectl port-forward service/<name> 8080:80
```

### Deployments
```bash
# Update
kubectl set image deployment/<name> container=image:tag

# Scale
kubectl scale deployment/<name> --replicas=5

# Rollout
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>
kubectl rollout restart deployment/<name>
```

### Labels & Selectors
```bash
# Query
kubectl get pods -l app=myapp
kubectl get pods -l 'tier in (frontend,api)'
kubectl get pods -l app=myapp,version=v2

# Modify
kubectl label pods <name> version=v2
kubectl label pods --all environment=production
kubectl label pods <name> version-  # Remove label
```

### ConfigMaps & Secrets
```bash
# Create
kubectl create configmap <name> --from-literal=KEY=VALUE
kubectl create secret generic <name> --from-literal=KEY=VALUE

# View
kubectl get configmap <name> -o yaml
kubectl get secret <name> -o yaml

# Decode secret
kubectl get secret <name> -o jsonpath='{.data.KEY}' | base64 --decode
```

---

# 🎓 Learning Outcomes

By completing this lab, you can:
- ✅ Deploy and manage applications with Deployments and ReplicaSets
- ✅ Externalize configuration using ConfigMaps and Secrets
- ✅ Understand the relationship between Deployments, Pods, and Services
- ✅ Perform rolling updates and rollbacks safely
- ✅ Expose applications externally using Ingress
- ✅ Manage persistent storage with PersistentVolumeClaims
- ✅ Implement health checks and resource management
- ✅ Use advanced patterns (HPA, Network Policies, Init Containers)
- ✅ Master label-based routing and traffic management
- ✅ Choose appropriate service types for different scenarios
- ✅ Debug common Kubernetes deployment issues

---

# 🐛 General Troubleshooting

## Pod Won't Start
```bash
# Check pod status
kubectl get pods
# See detailed events
kubectl describe pod <pod-name>
# Check logs
kubectl logs <pod-name>
# Common issues:
# - Image pull errors: Check Docker Hub image name/tag
# - CrashLoopBackOff: Check container logs
# - Pending: Check resource availability
# - CreateContainerConfigError: ConfigMap/Secret not found
```

## Service Not Routing Traffic
```bash
# Check service selector matches pod labels
kubectl describe service <service-name>
# Verify endpoints exist
kubectl get endpoints <service-name>
# Test connectivity
kubectl run test --image=curlimages/curl --rm -it -- curl http://<service-name>
```

## Ingress Not Working
```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx
# Verify ingress resource
kubectl describe ingress <ingress-name>
# Check /etc/hosts entry
cat /etc/hosts | grep <hostname>
# Test with curl
curl -v http://<hostname>
```

---

# ✅ Completion Checklist

Track your progress:

- [ ] **Phase 1**: Basic Deployment & Service (15 min)
- [ ] **Phase 2**: ConfigMaps & Secrets (20 min)
- [ ] **Phase 3**: Service Debugging (15 min)
- [ ] **Phase 4**: Rolling Updates & Rollbacks (20 min)
- [ ] **Phase 5**: Ingress & External Access (25 min)
- [ ] **Phase 6**: Persistent Storage (20 min)
- [ ] **Phase 7**: Health & Resources (20 min)
- [ ] **Phase 8**: Advanced Patterns (30 min)
- [ ] **Phase 9**: Labels Mastery (45 min)
- [ ] **Phase 10**: Service Types (40 min)
- [ ] **Phase 11**: RBAC & Security (60 min) 🔐
- [ ] **Phase 12**: Network Policies & Security Hardening (75 min) 🛡️

**Total Time:** 6-7 hours for complete mastery

---

**You're now ready to work with Kubernetes in production!** 🚀