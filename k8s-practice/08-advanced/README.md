# Phase 8: Advanced Patterns

## 📚 Learning Objectives
- Horizontal Pod Autoscaling (HPA)
- Network Policies
- Pod Affinity/Anti-Affinity
- Init Containers
- Sidecar Pattern

## 🚀 Instructions

### Horizontal Pod Autoscaler
```bash
kubectl apply -f advanced-deployment.yaml

# Watch HPA
kubectl get hpa -w

# Generate load to trigger scaling
kubectl run -it load-generator --rm --image=busybox --restart=Never -- /bin/sh
# Inside pod:
while true; do wget -q -O- http://bio-web-service; done
```

### Network Policies
```bash
# Apply network policy
kubectl apply -f advanced-deployment.yaml

# Test: Without label (should fail)
kubectl run test --image=curlimages/curl --rm -it -- curl http://bio-web-service
# ❌ Timeout

# Test: With label (should work)
kubectl run test --image=curlimages/curl --labels=access=allowed --rm -it -- curl http://bio-web-service
# ✅ Success
```

### Init Containers
```bash
# Check init container logs
kubectl logs <pod-name> -c init-setup

# Init containers run to completion before main container starts
kubectl describe pod <pod-name>
# Look for "Init Containers:" section
```

### Sidecar Pattern
```bash
# Check sidecar logs
kubectl logs <pod-name> -c log-sidecar

# Both containers share same pod lifecycle
kubectl exec <pod-name> -c bio-container -- ps aux
kubectl exec <pod-name> -c log-sidecar -- ps aux
```

### Pod Anti-Affinity
```bash
# Check pod distribution
kubectl get pods -o wide

# Pods should be spread across different nodes
# If you have multiple nodes
```

## 🔍 Advanced Concepts

### HPA Metrics
- CPU utilization
- Memory utilization
- Custom metrics (Prometheus)
- External metrics

### Network Policy Rules
- **Ingress**: Incoming traffic control
- **Egress**: Outgoing traffic control
- **Default deny**: Secure by default

### Use Cases

#### Init Containers
- Database schema migrations
- Waiting for dependencies
- Configuration setup
- Security scanning

#### Sidecar Containers
- Log shipping
- Metrics collection
- Service mesh proxies (Istio, Linkerd)
- Configuration reload

## 📊 Monitoring
```bash
# HPA status
kubectl get hpa
kubectl describe hpa bio-web-hpa

# Network policy
kubectl get networkpolicy
kubectl describe networkpolicy bio-web-netpol

# Pod distribution
kubectl get pods -o wide
```

## 💡 Production Patterns
- Always use HPA for variable load
- Network policies for zero-trust security
- Anti-affinity for high availability
- Init containers for setup tasks
- Sidecars for cross-cutting concerns
