# Phase 5: Ingress & External Access

## 📚 Learning Objectives
- Expose services externally using Ingress
- Configure host-based and path-based routing
- Understand Ingress controllers

## 🚀 Setup

### Enable Ingress (if using Minikube)
```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx
```

### For k3d (built-in Traefik)
```bash
# Traefik is already enabled
kubectl get pods -n kube-system | grep traefik
```

## 📋 Instructions

### Step 1: Deploy Application
```bash
kubectl apply -f ../01-basic/deployment.yaml
kubectl apply -f ../01-basic/service.yaml
```

### Step 2: Create Ingress
```bash
kubectl apply -f ingress.yaml
kubectl get ingress
kubectl describe ingress bio-ingress
```

### Step 3: Configure Local DNS
```bash
# Add to /etc/hosts
echo "127.0.0.1 bio.local" | sudo tee -a /etc/hosts

# Verify
cat /etc/hosts | grep bio.local
```

### Step 4: Test Access
```bash
# Using curl
curl http://bio.local

# Or open in browser
open http://bio.local
```

## 🧪 Multi-Service Routing

### Path-Based Routing
```yaml
spec:
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Host-Based Routing
```yaml
spec:
  rules:
  - host: api.myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
  - host: www.myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

## 🔍 Troubleshooting
- If ingress shows no ADDRESS, check ingress controller is running
- Verify /etc/hosts entry exists
- Check service exists and has endpoints
- For k3d, use `kubectl port-forward -n kube-system svc/traefik 8080:80` then access `http://localhost:8080`
