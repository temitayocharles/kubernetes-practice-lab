# Phase 1: Basic Deployment & Service

## 📚 Learning Objectives
- Understand Deployment basics
- Create a ClusterIP Service
- Learn the relationship between Deployments, Pods, and Services
- Practice basic kubectl commands

## 🎯 What You'll Create
- A Deployment with 2 replicas of your bio site
- A ClusterIP Service to provide stable networking

## 📋 Prerequisites
```bash
# Make sure your cluster is running
kubectl cluster-info

# Create your namespace (replace <yourname> with your actual name)
kubectl create namespace <yourname>-lab
kubectl config set-context --current --namespace=<yourname>-lab
```

## 🚀 Step-by-Step Instructions

### Step 1: Deploy the Application
```bash
# Apply the deployment
kubectl apply -f deployment.yaml

# Watch the pods come up
kubectl get pods -w
# Press Ctrl+C to stop watching

# Check deployment status
kubectl get deployments
kubectl describe deployment bio-web
```

### Step 2: Create the Service
```bash
# Apply the service
kubectl apply -f service.yaml

# View the service
kubectl get service bio-web-service
kubectl describe service bio-web-service

# Notice the "Endpoints" - these are your pod IPs!
```

### Step 3: Test Internal Connectivity
```bash
# Get the service cluster IP
kubectl get service bio-web-service -o wide

# Test from within the cluster using a temporary pod
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- sh

# Inside the test pod, run:
curl http://bio-web-service
exit
```

## 🔍 Key Concepts

### Deployment
- Manages ReplicaSets which manage Pods
- Ensures desired number of replicas are running
- Handles rolling updates and rollbacks

### Service (ClusterIP)
- Provides a stable IP address for a set of Pods
- Load balances traffic across Pod replicas
- Uses label selectors to find Pods

### Label Selectors
- The Service selector (`app: bio-site`) must match the Pod labels
- This is how Services know which Pods to route traffic to

## 🧪 Experiments to Try

### Experiment 1: Scale Up
```bash
# Scale to 5 replicas
kubectl scale deployment bio-web --replicas=5

# Watch pods scale up
kubectl get pods -w

# Check service endpoints
kubectl describe service bio-web-service
# You should see 5 endpoint IPs now!
```

### Experiment 2: Delete a Pod
```bash
# List pods
kubectl get pods

# Delete one pod
kubectl delete pod <pod-name>

# Immediately check pods again
kubectl get pods
# Notice: A new pod is already being created to maintain 5 replicas!
```

### Experiment 3: View Pod Details
```bash
# Get detailed info about a pod
kubectl describe pod <pod-name>

# View pod logs
kubectl logs <pod-name>

# Execute commands inside a pod
kubectl exec -it <pod-name> -- sh
# Try: ps aux, ls /usr/share/nginx/html, env
```

## ✅ Validation Checklist
- [ ] Deployment shows 2/2 READY replicas
- [ ] Service has 2 endpoints listed
- [ ] Can curl the service from a test pod
- [ ] Deleted pods automatically recreate
- [ ] Service maintains same ClusterIP even after pod restarts

## 🐛 Troubleshooting

### Pods Not Starting
```bash
# Check pod status
kubectl get pods

# See detailed events
kubectl describe pod <pod-name>

# Common issues:
# - ImagePullBackOff: Check image name/tag
# - CrashLoopBackOff: Check container logs
# - Pending: Check resource availability
```

### Service Not Routing
```bash
# Verify selector matches pod labels
kubectl describe service bio-web-service | grep Selector
kubectl get pods --show-labels

# Check if endpoints exist
kubectl get endpoints bio-web-service
```

## 📊 Commands Cheat Sheet
```bash
# View resources
kubectl get all
kubectl get pods -o wide
kubectl get deployments
kubectl get services

# Describe resources
kubectl describe deployment bio-web
kubectl describe service bio-web-service
kubectl describe pod <pod-name>

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow logs

# Execute commands
kubectl exec <pod-name> -- <command>
kubectl exec -it <pod-name> -- sh

# Delete resources
kubectl delete deployment bio-web
kubectl delete service bio-web-service
# Or delete everything:
kubectl delete -f .
```

## 🎓 Reflection Questions
1. What happens when you delete a pod? Why doesn't your application go down?
2. How does the Service know which Pods to route traffic to?
3. What is the difference between a Deployment and a Pod?
4. Why use 2 replicas instead of 1?
5. Can you access the service from outside the cluster with ClusterIP type?

## ➡️ Next Steps
Once you're comfortable with this phase, move on to:
- **Phase 2**: ConfigMaps and Secrets (externalizing configuration)
- Learn how to inject environment variables without hardcoding them in images
