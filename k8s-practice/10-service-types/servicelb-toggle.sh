#!/bin/bash
# Toggle servicelb in k3d cluster

set -e

ACTION="${1:-status}"

case $ACTION in
  enable)
    echo "🔧 Enabling servicelb..."
    echo "Note: servicelb is enabled by default in k3s"
    echo "If it was disabled during cluster creation, you'll need to:"
    echo "  1. Recreate cluster without --k3s-arg '--disable=servicelb@server:0'"
    echo "  2. Or use MetalLB as an alternative"
    
    # Check if any svclb pods exist
    if kubectl get daemonset -n kube-system 2>/dev/null | grep -q svclb; then
      echo "✅ servicelb is already enabled"
    else
      echo "⚠️  servicelb not found"
      echo "To enable, recreate cluster with servicelb enabled"
    fi
    ;;
    
  disable)
    echo "🛑 Disabling servicelb..."
    echo "Note: You cannot disable servicelb at runtime"
    echo "It must be disabled during cluster creation with:"
    echo "  --k3s-arg '--disable=servicelb@server:0'"
    
    # Check current state
    if kubectl get daemonset -n kube-system 2>/dev/null | grep -q svclb; then
      echo "⚠️  servicelb is currently running"
      echo "To disable, recreate cluster with the disable flag"
    else
      echo "✅ servicelb is already disabled"
    fi
    ;;
    
  status)
    echo "🔍 Checking servicelb status..."
    echo ""
    
    # Check for svclb DaemonSets
    echo "=== ServiceLB DaemonSets ==="
    kubectl get daemonset -n kube-system 2>/dev/null | grep svclb || echo "No servicelb DaemonSets found"
    echo ""
    
    # Check for LoadBalancer services
    echo "=== LoadBalancer Services ==="
    kubectl get services --all-namespaces --field-selector spec.type=LoadBalancer
    echo ""
    
    # Check svclb pods
    echo "=== ServiceLB Pods ==="
    kubectl get pods -n kube-system -l app=svclb 2>/dev/null || echo "No servicelb pods found"
    echo ""
    
    if kubectl get daemonset -n kube-system 2>/dev/null | grep -q svclb; then
      echo "✅ servicelb is ENABLED"
    else
      echo "❌ servicelb is DISABLED"
      echo ""
      echo "Alternative options:"
      echo "  1. Use MetalLB (kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.0/config/manifests/metallb-native.yaml)"
      echo "  2. Use NodePort services"
      echo "  3. Use kubectl port-forward"
      echo "  4. Use Ingress with a LoadBalancer ingress controller"
    fi
    ;;
    
  test)
    echo "🧪 Testing LoadBalancer functionality..."
    
    # Create test service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: lb-test-pod
  labels:
    app: lb-test
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: lb-test-service
spec:
  type: LoadBalancer
  selector:
    app: lb-test
  ports:
  - port: 80
    targetPort: 80
EOF
    
    echo "✅ Created test pod and LoadBalancer service"
    echo ""
    echo "Waiting for LoadBalancer IP..."
    kubectl wait --for=condition=ready pod/lb-test-pod --timeout=60s
    sleep 5
    
    echo ""
    echo "=== LoadBalancer Service Status ==="
    kubectl get service lb-test-service
    
    EXTERNAL_IP=$(kubectl get service lb-test-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" == "null" ]; then
      echo ""
      echo "⚠️  No external IP assigned"
      echo "This usually means servicelb is disabled or not working"
      echo ""
      echo "Trying NodePort access instead..."
      NODE_PORT=$(kubectl get service lb-test-service -o jsonpath='{.spec.ports[0].nodePort}')
      echo "Access via: http://localhost:$NODE_PORT"
    else
      echo ""
      echo "✅ External IP assigned: $EXTERNAL_IP"
      echo "Test with: curl http://$EXTERNAL_IP"
    fi
    
    echo ""
    echo "To clean up:"
    echo "  kubectl delete pod lb-test-pod"
    echo "  kubectl delete service lb-test-service"
    ;;
    
  cleanup)
    echo "🧹 Cleaning up test resources..."
    kubectl delete pod lb-test-pod --ignore-not-found=true
    kubectl delete service lb-test-service --ignore-not-found=true
    echo "✅ Cleanup complete"
    ;;
    
  *)
    echo "Usage: $0 {enable|disable|status|test|cleanup}"
    echo ""
    echo "Commands:"
    echo "  status   - Check if servicelb is enabled (default)"
    echo "  enable   - Show how to enable servicelb"
    echo "  disable  - Show how to disable servicelb"
    echo "  test     - Create test LoadBalancer service"
    echo "  cleanup  - Remove test resources"
    echo ""
    echo "Examples:"
    echo "  $0 status    # Check current state"
    echo "  $0 test      # Test LoadBalancer functionality"
    echo "  $0 cleanup   # Remove test resources"
    exit 1
    ;;
esac
