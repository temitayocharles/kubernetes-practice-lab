# Phase 10: Service Types Deep Dive 🌐

## 📚 Learning Objectives
- Master ClusterIP, NodePort, and LoadBalancer types
- Understand when to use each type
- Practice with k3s servicelb (lightweight LoadBalancer)
- Compare behavior and use cases
- Toggle between service types dynamically

## 🎯 Service Types Comparison

| Type | Accessible From | Use Case | IP Address |
|------|----------------|----------|------------|
| **ClusterIP** | Inside cluster only | Internal microservices, databases | Virtual IP (cluster-internal) |
| **NodePort** | Outside cluster via Node IP:Port | Development, debugging, legacy | Node IP + high port (30000-32767) |
| **LoadBalancer** | Outside cluster via external LB | Production external services | External IP from cloud/servicelb |

## 🚀 Step-by-Step Exercises

### Exercise 1: ClusterIP (Default, Internal Only)

```bash
# Deploy app
kubectl apply -f deployment.yaml

# Create ClusterIP service
kubectl apply -f service-clusterip.yaml

# Check service
kubectl get service clusterip-service
# Notice: EXTERNAL-IP = <none>, TYPE = ClusterIP

# Test from INSIDE cluster
kubectl run test --image=curlimages/curl --rm -it -- curl http://clusterip-service
# ✅ Works!

# Try from OUTSIDE cluster (from your Mac)
curl http://<cluster-ip>
# ❌ Fails! Not accessible externally
```

**When to use ClusterIP:**
- Databases (never expose externally)
- Internal APIs
- Backend services
- Default choice for internal communication

---

### Exercise 2: NodePort (Node IP + Port)

```bash
# Convert to NodePort
kubectl apply -f service-nodeport.yaml

# Check service
kubectl get service nodeport-service
# Notice: TYPE = NodePort, PORT = 80:30080/TCP

# Get node IP
kubectl get nodes -o wide
# Or for k3d: docker inspect k3d-<cluster>-server-0 | grep IPAddress

# Test from outside cluster (your Mac)
curl http://<node-ip>:30080
# ✅ Works!

# Also works via localhost if using k3d with port mapping
curl http://localhost:30080
```

**When to use NodePort:**
- Quick external access for testing
- When LoadBalancer isn't available
- CI/CD pipelines accessing cluster
- Development environments
- Legacy systems expecting specific ports

**Limitations:**
- Ugly port numbers (30000-32767)
- Need to know node IP
- One service per port
- No load balancing across nodes (single node point of failure)

---

### Exercise 3: LoadBalancer (Cloud-Like Experience)

For k3d, we'll use **servicelb** (Klipper LoadBalancer - built into k3s).

```bash
# Enable servicelb if disabled
# Your local-k8s.sh disables it, let's re-enable it

# Method 1: Create new cluster with servicelb enabled
# Or Method 2: Use existing cluster and create LoadBalancer service anyway

# Apply LoadBalancer service
kubectl apply -f service-loadbalancer.yaml

# Check service
kubectl get service loadbalancer-service
# TYPE = LoadBalancer
# EXTERNAL-IP = <pending> or actual IP

# For k3d, servicelb assigns a port on your host
kubectl get service loadbalancer-service
# EXTERNAL-IP might show localhost or node IP

# Test
curl http://<external-ip>:80
```

**How servicelb works:**
1. Creates a DaemonSet pod on every node
2. Binds host port for each LoadBalancer service
3. Provides external access via host IP

**Enable/Disable servicelb script:**
```bash
# Check if servicelb is running
kubectl get daemonset -n kube-system | grep svclb

# If disabled in your cluster, you can:
# Option A: Create new cluster without --disable flag
# Option B: Use MetalLB instead (more realistic for cloud)
```

---

### Exercise 4: Service Type Conversion (Live Migration!)

```bash
# Start with ClusterIP
kubectl apply -f service-clusterip.yaml

# Test: Not accessible externally
curl http://localhost  # Fails

# ✨ CONVERT to NodePort (no downtime!)
kubectl patch service clusterip-service -p '{"spec":{"type":"NodePort"}}'

# Kubernetes automatically assigns a NodePort
kubectl get service clusterip-service
# Now accessible!
curl http://localhost:<node-port>

# ✨ CONVERT to LoadBalancer
kubectl patch service clusterip-service -p '{"spec":{"type":"LoadBalancer"}}'

# ✨ CONVERT back to ClusterIP
kubectl patch service clusterip-service -p '{"spec":{"type":"ClusterIP"}}'
```

---

### Exercise 5: Multi-Service Scenario (Mixed Types)

Real-world architecture:
```bash
# Apply all services
kubectl apply -f multi-service-app.yaml

# Result:
# - frontend: LoadBalancer (public-facing)
# - api: NodePort (for admin access)
# - database: ClusterIP (internal only)
# - cache: ClusterIP (internal only)

kubectl get services

# Frontend accessible to users
curl http://<frontend-lb-ip>

# API accessible for ops
curl http://<node-ip>:<api-nodeport>/api

# Database NOT accessible externally
curl http://<db-ip>  # Fails
```

---

### Exercise 6: Port Mapping Variations

```bash
# Apply service with different port mappings
kubectl apply -f service-port-variations.yaml

# Service listens on port 80, forwards to pod port 8080
# Clients connect to: http://service:80
# Pods listen on: 8080
```

Example:
```yaml
spec:
  ports:
  - name: http
    port: 80        # Service port (what clients use)
    targetPort: 8080  # Pod port (what container listens on)
    nodePort: 30080   # Node port (optional, for NodePort type)
```

---

### Exercise 7: servicelb Exploration (k3s Specific)

```bash
# Deploy with LoadBalancer
kubectl apply -f service-loadbalancer.yaml

# Watch servicelb create helper pods
kubectl get pods -n kube-system -l app=svclb
# You'll see svclb-<service-name>-<node> pods

# Describe one
kubectl describe pod -n kube-system <svclb-pod>
# Notice: It's a DaemonSet binding host ports

# Check service again
kubectl get service loadbalancer-service -o wide
# EXTERNAL-IP shows where to access it
```

**servicelb behavior:**
- Lightweight (no MetalLB overhead)
- Works immediately (no config)
- Limited features (no IP pools, no BGP)
- Perfect for local development

---

### Exercise 8: Simulate Cloud LoadBalancer Behavior

If servicelb is disabled, use this workaround:

```bash
# Use kubectl port-forward to simulate LoadBalancer
kubectl port-forward service/loadbalancer-service 8080:80 &

# Now accessible locally
curl http://localhost:8080

# Stop port-forward
pkill -f "port-forward"
```

Or use NodePort as LoadBalancer alternative:
```bash
# Create NodePort service
kubectl apply -f service-nodeport.yaml

# For k3d, map node port to host
# This is already done if you created cluster with:
# --port "30000-30100:30000-30100@server:0"
```

---

## 🔍 Service Type Decision Tree

```
Need external access?
├─ NO → Use ClusterIP (default)
│   └─ Examples: databases, internal APIs, caches
│
└─ YES → Need cloud-like experience?
    ├─ YES → Use LoadBalancer
    │   ├─ Cloud (AWS/GCP/Azure): Automatically provisions cloud LB
    │   └─ Local (k3d/Minikube): Use servicelb or MetalLB
    │
    └─ NO → Use NodePort
        └─ Good for: dev, testing, CI/CD, legacy systems
```

## 📊 Feature Comparison

| Feature | ClusterIP | NodePort | LoadBalancer |
|---------|-----------|----------|--------------|
| External Access | ❌ | ✅ | ✅ |
| Stable External IP | ❌ | ⚠️ (Node IP) | ✅ |
| Standard Ports (80/443) | ✅ | ❌ (30000+) | ✅ |
| Internal Access | ✅ | ✅ | ✅ |
| Cloud Cost | Free | Free | 💰 $$ |
| Production-Ready | Internal only | No | Yes |
| Use in Local Dev | ✅ | ✅ | ⚠️ (needs servicelb/MetalLB) |

## 🧪 Advanced Scenarios

### Scenario 1: Progressive Exposure

```bash
# Start internal only
kubectl create service clusterip myapp --tcp=80:80

# Expose for testing (NodePort)
kubectl patch service myapp -p '{"spec":{"type":"NodePort"}}'

# Go to production (LoadBalancer)
kubectl patch service myapp -p '{"spec":{"type":"LoadBalancer"}}'

# Rollback if issues
kubectl patch service myapp -p '{"spec":{"type":"ClusterIP"}}'
```

### Scenario 2: Multi-Port Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: multi-port-service
spec:
  type: NodePort
  selector:
    app: myapp
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30080
  - name: https
    port: 443
    targetPort: 8443
    nodePort: 30443
  - name: metrics
    port: 9090
    targetPort: 9090
    nodePort: 30090
```

### Scenario 3: Session Affinity (Sticky Sessions)

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

## 💡 Best Practices

### ✅ DO
- Use ClusterIP by default
- Use LoadBalancer for production external services
- Use NodePort for temporary testing only
- Set resource quotas to limit LoadBalancer creation
- Use Ingress instead of many LoadBalancer services (cost savings)
- Document which services need external access

### ❌ DON'T
- Don't use NodePort in production (ugly ports, no HA)
- Don't expose databases via LoadBalancer
- Don't create LoadBalancer for every service (expensive in cloud)
- Don't hardcode NodePort values (let Kubernetes assign)

## 🎓 Comparison with Ingress

**Why not use LoadBalancer for everything?**

Cloud costs:
- 1 LoadBalancer service = 1 cloud LB = ~$20/month
- 10 LoadBalancer services = $200/month! 💸

Better approach:
```
1 LoadBalancer (Ingress Controller)
  └─ Ingress resource (free!)
      ├─ Service 1 (ClusterIP)
      ├─ Service 2 (ClusterIP)
      └─ Service 3 (ClusterIP)

Total cost: $20/month for unlimited services
```

## ✅ Mastery Checklist

- [ ] Understand when to use each service type
- [ ] Can convert between service types without downtime
- [ ] Know the port mapping flow (NodePort → Service → Pod)
- [ ] Tested ClusterIP (internal only)
- [ ] Tested NodePort (external access via node IP)
- [ ] Tested LoadBalancer (with servicelb or port-forward)
- [ ] Understand servicelb (k3s) vs MetalLB vs Cloud LB
- [ ] Know when to use Ingress instead of LoadBalancer
- [ ] Can debug service networking issues
- [ ] Understand session affinity

## 🔧 Troubleshooting

### LoadBalancer Stuck at <pending>
```bash
# Reason: No LoadBalancer controller available
# Solutions:
# 1. Use servicelb (k3s built-in)
# 2. Install MetalLB
# 3. Use NodePort instead
# 4. Use port-forward for local testing

# Check if servicelb is enabled
kubectl get daemonset -n kube-system | grep svclb
```

### NodePort Not Accessible
```bash
# Check firewall
# Check node IP is correct
kubectl get nodes -o wide

# Check port is in range
kubectl get service -o wide  # NodePort must be 30000-32767

# For k3d, check port mapping
docker ps | grep k3d
```

### ClusterIP Not Working
```bash
# Check endpoints
kubectl get endpoints <service-name>

# Check pod labels match service selector
kubectl get pods --show-labels
kubectl describe service <service-name>
```

## ➡️ Next Steps
- **Phase 11**: Annotations Deep Dive
- **Phase 12**: Canary Deployments (combining labels + services)
