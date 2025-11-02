# Phase 6: Persistent Storage

## 📚 Learning Objectives
- Understand PersistentVolumes and PersistentVolumeClaims
- Mount volumes to pods
- Persist data across pod restarts
- Learn difference between Deployment and StatefulSet

## 🚀 Instructions

### Step 1: Create PVC
```bash
kubectl apply -f deployment-with-pvc.yaml
kubectl get pvc
kubectl describe pvc bio-storage
```

### Step 2: Verify Volume Mount
```bash
kubectl get pods
kubectl exec <pod-name> -- df -h | grep /data
kubectl exec <pod-name> -- ls -la /data
```

### Step 3: Write Data
```bash
kubectl exec <pod-name> -- sh -c "echo 'Hello from pod!' > /data/test.txt"
kubectl exec <pod-name> -- cat /data/test.txt
```

### Step 4: Test Persistence
```bash
# Delete pod
kubectl delete pod <pod-name>

# Wait for new pod
kubectl get pods -w

# Check data still exists
kubectl exec <new-pod-name> -- cat /data/test.txt
# ✅ Data persists!
```

## 🧪 StatefulSet Example
For apps needing stable pod names and ordered deployment:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: "web"
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

## 🔍 Key Concepts
- **PV**: Cluster-level storage resource
- **PVC**: Request for storage by user
- **StorageClass**: Dynamic provisioning
- **ReadWriteOnce**: Single node can mount
- **ReadWriteMany**: Multiple nodes can mount
