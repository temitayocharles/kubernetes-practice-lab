# Phase 2: ConfigMaps & Secrets

## 📚 Learning Objectives
- Externalize configuration from container images
- Understand the difference between ConfigMaps and Secrets
- Learn imperative vs declarative config creation
- Inject configuration as environment variables
- Debug configuration issues

## 🎯 What You'll Create
- A ConfigMap with non-sensitive configuration
- A Secret with sensitive data
- A Deployment that consumes both

## 🧠 Why ConfigMaps and Secrets?

### The Problem
```yaml
# ❌ BAD: Hardcoded in Dockerfile
ENV DATABASE_URL=postgres://prod-server:5432/mydb
ENV API_KEY=secret-key-12345
```

### The Solution
```yaml
# ✅ GOOD: Externalized configuration
- configMapRef:
    name: site-config
- secretRef:
    name: site-secret
```

**Benefits:**
- Same image works in dev/staging/prod
- No secrets in version control
- Easy updates without rebuilding images
- Separation of concerns

## 🚀 Step-by-Step Instructions

### Method 1: Imperative (Quick & Easy)

#### Step 1: Create ConfigMap Imperatively
```bash
# Create from literal values
kubectl create configmap site-config \
  --from-literal=SITE_TITLE="My Portfolio" \
  --from-literal=THEME="dark" \
  --from-literal=VERSION="2.0"

# View what was created
kubectl get configmap site-config -o yaml
kubectl describe configmap site-config
```

#### Step 2: Create Secret Imperatively
```bash
# Create from literal values
kubectl create secret generic site-secret \
  --from-literal=CONTACT_EMAIL="yourname@example.com" \
  --from-literal=API_KEY="demo-key-12345"

# View the secret (values are base64 encoded)
kubectl get secret site-secret -o yaml

# Decode a value
kubectl get secret site-secret -o jsonpath='{.data.CONTACT_EMAIL}' | base64 --decode
echo  # Add newline
```

### Method 2: Declarative (Production Way)

#### Step 3: Create from YAML Files
```bash
# Apply the config resources
kubectl apply -f config-resources.yaml

# List all configs and secrets
kubectl get configmaps,secrets

# Compare imperative vs declarative
kubectl get configmap site-config -o yaml
```

#### Step 4: Deploy Application with Configuration
```bash
# Apply the deployment
kubectl apply -f deployment-with-config.yaml

# Watch the rolling update
kubectl rollout status deployment/bio-web

# Apply the service
kubectl apply -f service.yaml
```

### Step 5: Verify Environment Variables
```bash
# Get pod name
kubectl get pods

# Check environment variables inside the pod
kubectl exec <pod-name> -- env | grep SITE_TITLE
kubectl exec <pod-name> -- env | grep CONTACT_EMAIL
kubectl exec <pod-name> -- env | grep POD_NAME

# See all environment variables
kubectl exec <pod-name> -- env | sort
```

## 🔍 Key Concepts

### ConfigMap vs Secret

| Feature | ConfigMap | Secret |
|---------|-----------|--------|
| Purpose | Non-sensitive config | Sensitive data |
| Stored | Plain text | Base64 encoded |
| Max Size | 1 MiB | 1 MiB |
| Use Cases | Feature flags, URLs, themes | Passwords, API keys, certificates |
| Version Control | ✅ Safe | ⚠️ Use sealed-secrets or external vault |

### Injection Methods

#### 1. envFrom (All keys as env vars)
```yaml
envFrom:
- configMapRef:
    name: site-config
```

#### 2. env (Individual keys)
```yaml
env:
- name: CUSTOM_NAME
  valueFrom:
    configMapKeyRef:
      name: site-config
      key: SITE_TITLE
```

#### 3. Volume Mount (Files)
```yaml
volumeMounts:
- name: config-volume
  mountPath: /etc/config
volumes:
- name: config-volume
  configMap:
    name: site-config
```

## 🧪 Experiments to Try

### Experiment 1: Update ConfigMap
```bash
# Edit the ConfigMap
kubectl edit configmap site-config
# Change THEME from "dark" to "light"

# Check if pod sees the change
kubectl exec <pod-name> -- env | grep THEME
# Result: STILL shows "dark"!

# Why? ConfigMaps loaded at pod start are NOT automatically reloaded
# Solution: Force pod recreation
kubectl rollout restart deployment/bio-web

# Now check again
kubectl exec <new-pod-name> -- env | grep THEME
# Result: Now shows "light"!
```

### Experiment 2: Create from File
```bash
# Create a config file
cat > app.properties <<EOF
database.host=localhost
database.port=5432
database.name=myapp
EOF

# Create ConfigMap from file
kubectl create configmap app-config --from-file=app.properties

# View it
kubectl describe configmap app-config
```

### Experiment 3: Mix Multiple Sources
```bash
# Create another ConfigMap
kubectl create configmap extra-config --from-literal=FEATURE_FLAG=enabled

# Update deployment to use both
kubectl edit deployment bio-web
# Add another configMapRef under envFrom

# Verify both configs are loaded
kubectl exec <pod-name> -- env | grep -E 'SITE_TITLE|FEATURE_FLAG'
```

### Experiment 4: Intentional Conflict
```bash
# Create a ConfigMap with overlapping key
kubectl create configmap override-config --from-literal=SITE_TITLE="OVERRIDDEN"

# Add it AFTER site-config in the deployment
# Last one wins!
```

## 🐛 Troubleshooting

### Pod Won't Start - ConfigMap Not Found
```bash
# Error: "configmap 'site-config' not found"

# Check if ConfigMap exists
kubectl get configmaps

# Check namespace (common mistake!)
kubectl get configmaps -A | grep site-config

# Fix: Create the ConfigMap or correct the name
```

### Secret Values Not Decoding
```bash
# View secret
kubectl get secret site-secret -o yaml

# Decode manually
echo "eW91cm5hbWVAZXhhbXBsZS5jb20=" | base64 --decode

# Or use jsonpath
kubectl get secret site-secret -o jsonpath='{.data.CONTACT_EMAIL}' | base64 --decode
```

### ConfigMap Changes Not Reflected
```bash
# Problem: Updated ConfigMap but pod shows old values

# Solution 1: Restart deployment
kubectl rollout restart deployment/bio-web

# Solution 2: Use volume mounts (auto-updates after ~1 minute)
# Solution 3: Use a tool like Reloader (watches ConfigMaps)
```

## 📊 Commands Cheat Sheet

### ConfigMaps
```bash
# Create
kubectl create configmap NAME --from-literal=KEY=VALUE
kubectl create configmap NAME --from-file=path/to/file
kubectl apply -f configmap.yaml

# View
kubectl get configmaps
kubectl describe configmap NAME
kubectl get configmap NAME -o yaml

# Edit
kubectl edit configmap NAME

# Delete
kubectl delete configmap NAME
```

### Secrets
```bash
# Create
kubectl create secret generic NAME --from-literal=KEY=VALUE
kubectl create secret generic NAME --from-file=path/to/file
kubectl apply -f secret.yaml

# View
kubectl get secrets
kubectl describe secret NAME
kubectl get secret NAME -o yaml
kubectl get secret NAME -o jsonpath='{.data.KEY}' | base64 --decode

# Delete
kubectl delete secret NAME
```

## ✅ Validation Checklist
- [ ] ConfigMap created with multiple key-value pairs
- [ ] Secret created with sensitive data
- [ ] Pods show environment variables from ConfigMap
- [ ] Pods show environment variables from Secret
- [ ] Understand why pods don't auto-reload config changes
- [ ] Can decode secret values manually

## 🎓 Reflection Questions
1. What happens if you delete a ConfigMap while pods are using it?
2. Why are Secrets base64 encoded (is it encryption)?
3. How would you rotate a secret without downtime?
4. What's better: envFrom or individual env entries? When?
5. Should you commit secrets to Git? What are alternatives?

## 💡 Best Practices

### ✅ DO
- Use descriptive names: `postgres-config`, `api-credentials`
- Version your configs: `site-config-v2`
- Use sealed-secrets or external vaults for production
- Document what each key does
- Keep secrets out of Git

### ❌ DON'T
- Don't put secrets in regular ConfigMaps
- Don't commit raw secrets to version control
- Don't reuse the same secret across environments
- Don't store large files (>1MB) in ConfigMaps
- Don't assume config changes auto-reload

## ➡️ Next Steps
Once you're comfortable, move to:
- **Phase 3**: Service Debugging (intentional breaks and fixes)
- **Phase 4**: Rolling Updates (ConfigMap versioning strategy)
