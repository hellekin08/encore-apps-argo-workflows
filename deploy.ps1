param(
    [Parameter(Mandatory=$true)]
    [Alias("env")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppName = "argo-workflows"

$OverlayDir = Join-Path $ScriptDir "argo-workflows/app/overlays/$Environment"
$OverlayKustomizationFile = Join-Path $OverlayDir "kustomization.yaml"
$ClusterDir = Join-Path $ScriptDir "argo-workflows/clusters/$Environment"
$ClusterKustomizationFile = Join-Path $ClusterDir "kustomization.yaml"
$GitRepoFile = Join-Path $ClusterDir "gitrepository.yaml"

foreach ($f in @($OverlayKustomizationFile, $GitRepoFile, $ClusterKustomizationFile)) {
    if (-not (Test-Path $f)) {
        Write-Error "Required file not found: $f"
        exit 1
    }
}

$NamespaceContent = Get-Content $ClusterKustomizationFile -Raw
if ($NamespaceContent -match 'namespace:\s*(\S+)') {
    $TargetNS = $Matches[1]
} else {
    Write-Error "Could not extract namespace from $ClusterKustomizationFile"
    exit 1
}

Write-Host "=== Deploying app: $AppName (env: $Environment) ==="
Write-Host "    Target namespace: $TargetNS"

$gitStatus = git status --porcelain 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($gitStatus | Out-String))) {
    Write-Warning "Local Git changes detected. This script deploys the remote branch from Flux GitRepository, not your uncommitted workspace."
}

$nsExists = kubectl get namespace $TargetNS --ignore-not-found -o name
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($nsExists)) {
    Write-Host "[OK] Namespace '$TargetNS' already exists"
} else {
    Write-Host "[..] Namespace '$TargetNS' not found"
    Write-Host "Create the namespace first, then rerun this script."
    exit 1
}

$GitRepoContent = Get-Content $GitRepoFile -Raw
if ($GitRepoContent -match 'secretRef:\s*\n\s*name:\s*(\S+)') {
    $SecretName = $Matches[1]
    $secretExists = kubectl get secret $SecretName -n $TargetNS --ignore-not-found -o name
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($secretExists)) {
        Write-Host "[OK] Git secret '$SecretName' already exists"
    } else {
        Write-Host "[..] Git secret '$SecretName' not found in namespace '$TargetNS'"
        $GhToken = Read-Host "     Enter Git token"
        kubectl create secret generic $SecretName `
            --namespace $TargetNS `
            --from-literal=username=git `
            --from-literal=password=$GhToken
        if ($LASTEXITCODE -ne 0) { exit 1 }
        Write-Host "[OK] Git secret '$SecretName' created"
    }
}

Write-Host "[..] Applying Flux Kustomizations..."
kubectl kustomize --load-restrictor LoadRestrictionsNone $ClusterDir | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "[OK] Flux Kustomizations applied"

Write-Host ""
Write-Host "=== Deployment initiated for '$AppName' (env: $Environment) ==="
Write-Host "    Monitor with:"
Write-Host "    kubectl get kustomization $AppName -n $TargetNS"
Write-Host "    kubectl get helmrelease -n $TargetNS"
