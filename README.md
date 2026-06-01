# DevOps Challenge — GitOps Repo

Single source of truth for what runs in the cluster. ArgoCD watches `apps/sample-nodejs/` and reconciles every change automatically. CI in the [app repo](https://github.com/IdoShoshani/sample-nodejs) promotes a release by committing an `image.tag` bump here — there is no `kubectl` in the pipeline.

## Why a separate GitOps repo

- **Decouples app source from cluster state.** App code evolves at a different cadence than deployment intent.
- **Audit trail = git history.** Every entry in `git log` here is a deploy event, signed by the actor (ci-bot or a human).
- **No cluster credentials in CI.** CI just commits a YAML edit; ArgoCD running in-cluster does the actual rollout.
- **Trivial rollback.** `git revert <bump-commit>` and ArgoCD self-heals back.

## Layout

```
devops-challenge-gitops/
├── apps/sample-nodejs/
│   ├── Chart.yaml
│   ├── values.yaml              # CI bumps image.tag here
│   ├── .helmignore
│   └── templates/
│       ├── _helpers.tpl          # name/fullname/chart/labels helpers (fullname is additive, future-proof)
│       ├── deployment.yaml       # /ready + /live probes, resources, envFrom, Prometheus annotations
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── configmap.yaml
│       └── secret.yaml
├── argocd/
│   └── application.yaml          # ArgoCD Application: auto-sync, prune, self-heal
├── .gitignore
└── README.md
```

## Chart highlights

- **Deployment** (not StatefulSet) — stateless HTTP service. Free rolling updates and HPA-ready.
- **Probes** — `httpGet /ready` (readiness) and `httpGet /live` (liveness), both on the app's built-in routes.
- **Resources** — CPU 50m/200m, memory 64Mi/128Mi (right-sized for a hello-world Express app).
- **Security** — `runAsNonRoot: true`, `runAsUser: 1000`.
- **Config** via `envFrom` ConfigMap + Secret (`PORT`, `NODE_ENV`, `API_KEY`).
- **Metrics** — Prometheus pod annotations (`prometheus.io/scrape`, `port`, `path`) when `metrics.enabled`.
- **Ingress** — `nginx` ingressClassName, host `sample-nodejs.local`.

## ArgoCD Application (`argocd/application.yaml`)

- `repoURL`: this repo
- `path`: `apps/sample-nodejs`, Helm valueFiles: `values.yaml`
- Destination: in-cluster (`https://kubernetes.default.svc`), namespace `sample-nodejs`
- Sync policy: `automated: { prune: true, selfHeal: true }`, `CreateNamespace=true`

## Bring-up on the real cluster (RKE2 home lab as used)

Prereqs: `kubectl` context pointing at the cluster, `ingress-nginx` installed (RKE2 default includes it in `hostNetwork` mode).

```bash
# 1. App namespace
kubectl create namespace sample-nodejs

# 2. ArgoCD (server-side apply — manifests contain a large CRD)
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --namespace argocd --for=condition=available deployment/argocd-server --timeout=240s

# 3. Register this (private) GitOps repo with ArgoCD using a fine-grained PAT (Contents: Read)
read -s -p "Paste GITOPS_PAT: " PAT && echo
kubectl -n argocd create secret generic gitops-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/IdoShoshani/devops-challenge-gitops.git \
  --from-literal=username=IdoShoshani \
  --from-literal=password="$PAT" \
  && kubectl -n argocd label secret gitops-repo argocd.argoproj.io/secret-type=repository
unset PAT

# 4. Apply the Application
kubectl apply -f argocd/application.yaml

# 5. Verify
kubectl -n argocd get application sample-nodejs \
  -o jsonpath='{.status.sync.status} {.status.health.status}'; echo
kubectl -n sample-nodejs get pods,svc,ingress
```

### Reach the app

On the same LAN as the cluster, point `sample-nodejs.local` at any node IP, e.g. `10.0.0.152`:

```bash
echo "10.0.0.152 sample-nodejs.local" | sudo tee -a /etc/hosts

# macOS reserves .local for mDNS, so curl/browser hangs without --resolve:
curl --resolve sample-nodejs.local:80:10.0.0.152 http://sample-nodejs.local/my-app
# -> Hello, World!
```

## End-to-end GitOps loop (proof)

1. Edit `app.js` in the app repo (e.g. change `/about`), open a PR, merge to `main`.
2. CI runs: `test` → `sast` → `release` (build, Trivy gate, push `idoshoshani123/sample-nodejs:<tag>`, git tag) → `promote` (commit `image.tag` bump here).
3. ArgoCD reconciles the new commit (manual refresh trigger: `kubectl -n argocd annotate application sample-nodejs argocd.argoproj.io/refresh=hard --overwrite`).
4. New pods roll out; old ones go to `Terminating` then disappear.
5. `curl --resolve sample-nodejs.local:80:<node-ip> http://sample-nodejs.local/about` reflects the change.

Verified live: image bumped from `1.0.0-6` → `1.0.0-8`, `/about` returned the new text after the `Synced Progressing → Healthy` transition.

## Deviations / things to know

- **`kind/kind-config.yaml` is provided** as an alternative for anyone who doesn't have an existing cluster, but it was **not used** here — bring-up above is for an existing RKE2 cluster.
- **No `dockerhub-pull-secret`** in this chart: the image repo is public (`idoshoshani123/sample-nodejs`). `values.yaml` sets `imagePullSecrets: []`. To switch to a private image repo: set the Docker Hub repo private, restore `imagePullSecrets: [{name: dockerhub-pull-secret}]` here, and create the secret in the namespace.
- **`API_KEY` in `secret.yaml`** is a placeholder demo value (`changeme`). Real secrets should live in SealedSecrets or an external secret store.
- **ArgoCD repo poll is 3 minutes by default.** Either tolerate up to that latency, or set a GitHub webhook on this repo pointing at ArgoCD's `/api/webhook`.

## Links

- App repo (source + CI): https://github.com/IdoShoshani/sample-nodejs
- This GitOps repo *(private)*: https://github.com/IdoShoshani/devops-challenge-gitops
- Image: https://hub.docker.com/r/idoshoshani123/sample-nodejs
