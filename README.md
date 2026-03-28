# Argo Workflows Flux Deployment

## Prerequisites

- `kubectl` configured with access to the target cluster
- The target namespace already exists
- A Git token with read access to this repository if the Flux source is private

## Folder Structure

```text
argo-workflows/
|-- app/
|   |-- base/                # Shared HelmRepository + HelmRelease
|   `-- overlays/<env>/      # Environment-specific HelmRelease patches
`-- clusters/<env>/          # Flux GitRepository + Kustomization per environment

deploy.sh                    # Bash deploy script
deploy.ps1                   # PowerShell deploy script
```

## Deploying Argo Workflows

### Bash

```bash
bash deploy.sh --env dev
```

### PowerShell

```powershell
.\deploy.ps1 -Environment dev
```

## What the script does

1. Reads the target namespace from `argo-workflows/clusters/<env>/kustomization.yaml`
2. Checks whether that namespace already exists
3. Checks whether the Git auth secret exists and prompts for a token if missing
4. Applies the Flux `GitRepository` and `Kustomization` from `argo-workflows/clusters/<env>`

If the namespace does not exist, the script prints a message and exits. It does not create the namespace.

## Deployment Notes

- The Helm release uses the `argo/argo-workflows` chart from `https://argoproj.github.io/argo-helm`
- The base release is configured as a namespace-scoped installation with `singleNamespace: true`
- CRDs are managed by the chart
- The Argo server uses `authModes: [server]`
- Environment overlays only patch the controller instance ID so each environment stays isolated

As committed, the chart does not expose Argo Workflows through an ingress. Add environment-specific `spec.values.server.ingress` settings in the overlay patch if you want external access.

## Monitoring

```bash
kubectl get kustomization argo-workflows -n cx-workflows-encore-ns
kubectl get helmrelease -n cx-workflows-encore-ns
kubectl get pods -n cx-workflows-encore-ns
```

## Deploying to other environments

```bash
bash deploy.sh --env test
bash deploy.sh --env prod
```

## Cleanup

```bash
kubectl delete kustomization.kustomize.toolkit.fluxcd.io argo-workflows -n cx-workflows-encore-ns
kubectl delete gitrepository encore-apps-argo-workflows -n cx-workflows-encore-ns
kubectl delete helmrelease argo-workflows -n cx-workflows-encore-ns
kubectl delete helmrepository argo -n cx-workflows-encore-ns
```

If a resource gets stuck deleting, remove its finalizer:

```bash
kubectl patch <resource-type> <name> -n cx-workflows-encore-ns --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/finalizers\"}]"
```

## Flux

```bash
flux reconcile source git encore-apps-argo-workflows -n cx-workflows-encore-ns
flux reconcile kustomization argo-workflows -n cx-workflows-encore-ns
flux reconcile helmrelease argo-workflows -n cx-workflows-encore-ns
```

```bash
flux suspend kustomization argo-workflows -n cx-workflows-encore-ns
flux resume kustomization argo-workflows -n cx-workflows-encore-ns

flux suspend helmrelease argo-workflows -n cx-workflows-encore-ns
flux resume helmrelease argo-workflows -n cx-workflows-encore-ns
```
