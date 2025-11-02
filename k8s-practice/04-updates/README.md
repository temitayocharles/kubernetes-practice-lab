# Phase 4: Rolling Updates & Rollbacks

## 📚 Learning Objectives
- Perform zero-downtime rolling updates
- Control update strategy with maxSurge and maxUnavailable
- Roll back failed deployments
- Understand deployment history and revisions

## 🚀 Commands

### Deploy Initial Version
```bash
kubectl apply -f deployment-v1.yaml
kubectl apply -f service.yaml
kubectl rollout status deployment/bio-web
```

### Update to v2
```bash
# Method 1: Update YAML and apply
# Edit deployment-v1.yaml, change image to v2
kubectl apply -f deployment-v1.yaml

# Method 2: Imperative update
kubectl set image deployment/bio-web bio-container=temitayocharles/hello-k8s:v2 --record

# Watch the rollout
kubectl rollout status deployment/bio-web
kubectl get pods -w
```

### Check History
```bash
kubectl rollout history deployment/bio-web
kubectl rollout history deployment/bio-web --revision=2
```

### Rollback
```bash
# Undo last change
kubectl rollout undo deployment/bio-web

# Rollback to specific revision
kubectl rollout undo deployment/bio-web --to-revision=1
```

### Pause/Resume Rollout
```bash
kubectl rollout pause deployment/bio-web
# Make changes...
kubectl rollout resume deployment/bio-web
```

## 🧪 Experiments
1. Update with wrong image tag (will fail) - practice rollback
2. Change maxSurge/maxUnavailable and observe behavior
3. Use `--record` flag to track change causes
