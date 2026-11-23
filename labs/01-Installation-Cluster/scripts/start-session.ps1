# ==============================================================================
# Rituel du matin (Windows PowerShell) : Démarrage des instances du cluster
# ==============================================================================
[CmdletBinding()]
param(
  [string]$ClusterName = "k8s-formation"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Recherche des instances arrêtées du cluster ($ClusterName)..." -ForegroundColor Cyan

$instanceIds = aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=stopped,stopping" `
  --query "Reservations[].Instances[].InstanceId" `
  --output text

if (-not $instanceIds -or $instanceIds.Trim() -eq "") {
  Write-Host "Aucune instance arrêtée trouvée (ou déjà démarrées)." -ForegroundColor Yellow
} else {
  Write-Host "==> Démarrage des instances : $instanceIds" -ForegroundColor Cyan
  $ids = $instanceIds -split '\s+' | Where-Object { $_ -ne "" }
  aws ec2 start-instances --instance-ids $ids | Out-Null
  Write-Host "Attente de l'état 'running'..." -ForegroundColor Gray
  aws ec2 wait instance-running --instance-ids $ids
}

Write-Host "`n==> Récapitulatif des instances actives et nouvelles adresses IP :" -ForegroundColor Green
aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress]" `
  --output table

$controlIp = aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=k8s-control" "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[0].PublicIpAddress" `
  --output text

Write-Host "`n------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Connexion SSH au Control Plane :"
Write-Host "ssh -i .\labsuser.pem ubuntu@$controlIp"
Write-Host "`nAccès Ingress NodePort HTTP :"
Write-Host "http://${controlIp}:30080"
Write-Host "------------------------------------------------------------------" -ForegroundColor Yellow
