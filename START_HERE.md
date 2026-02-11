# Start Here

This guide is the shortest path to running, deploying, and maintaining this repo. It is written for future‑you with zero context. Follow in order.

## 1. What This Repo Is
See README for the purpose and context.

## 2. Repo Map (What Lives Where)
- [README.md](README.md): High‑level overview.
- Documentation: [QUICKSTART.md](QUICKSTART.md), [README.md](README.md), [START_HERE.md](START_HERE.md)
- Scripts: [local-k8s.sh](local-k8s.sh), [setup-github.sh](setup-github.sh)

## 3. Quick Local Run
Use the README for local run steps. No Docker Compose file was detected here.

## 5. Config and Secrets
Check README for required environment variables. If you add secrets, place examples in `.env.example`.

## 8. Troubleshooting
- If a build fails, check README and CI logs first.
- Confirm your local env vars match `.env.example`.
- For Kubernetes: check `kubectl get pods` and `kubectl describe` first.

