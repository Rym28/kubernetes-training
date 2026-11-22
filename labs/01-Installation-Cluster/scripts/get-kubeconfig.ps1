# ==============================================================================
# Récupère le kubeconfig du cluster sur votre poste (Windows PowerShell)
#   1. copie ~/.kube/config de k8s-control dans terraform\kubeconfig.yaml (scp) ;
#   2. remplace l'adresse privée de l'API Server par l'Elastic IP de k8s-control.
# Le certificat de l'API Server contient l'Elastic IP (kubeadm init
# --apiserver-cert-extra-sans) : la vérification TLS reste active.
#
# Usage : ..\scripts\get-kubeconfig.ps1 [-ControlIp <IP_PUBLIQUE_CONTROL>]
#         (sans argument, l'IP est lue dans « terraform output »)
# ==============================================================================
param([string]$ControlIp)
$ErrorActionPreference = "Stop"

$TfDir = (Resolve-Path (Join-Path $PSScriptRoot "..\terraform")).Path
$Key = Join-Path $TfDir "labsuser.pem"
$Out = Join-Path $TfDir "kubeconfig.yaml"

if (-not $ControlIp) {
  $ControlIp = (& terraform "-chdir=$TfDir" output -raw control_plane_public_ip).Trim()
}

if (-not (Test-Path $Key)) {
  throw "Clé introuvable : $Key (voir l'étape 4 de l'Atelier 01)."
}

Write-Host "==> [1/3] Copie du kubeconfig depuis k8s-control ($ControlIp)" -ForegroundColor Cyan
& scp -q -i $Key -o StrictHostKeyChecking=accept-new "ubuntu@${ControlIp}:.kube/config" "$Out.tmp"
if ($LASTEXITCODE -ne 0) { throw "La copie scp a échoué (IP, clé ou session AWS ?)." }

Write-Host "==> [2/3] Remplacement de l'adresse de l'API Server par $ControlIp" -ForegroundColor Cyan
$content = (Get-Content -Raw "$Out.tmp") -replace 'server: https://[^:/]+:6443', "server: https://${ControlIp}:6443"
[System.IO.File]::WriteAllText($Out, $content, (New-Object System.Text.UTF8Encoding $false))
Remove-Item "$Out.tmp"

Write-Host "==> [3/3] Test de la connexion" -ForegroundColor Cyan
$env:KUBECONFIG = $Out
& kubectl get nodes

Write-Host "`nKubeconfig enregistré : $Out" -ForegroundColor Green
Write-Host "La variable KUBECONFIG est définie pour ce terminal. Dans chaque nouveau terminal, placé à la racine du dépôt :"
Write-Host '  $env:KUBECONFIG = "$PWD\labs\01-Installation-Cluster\terraform\kubeconfig.yaml"'
