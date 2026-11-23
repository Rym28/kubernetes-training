# ==============================================================================
# Rituel du soir (Windows PowerShell) : Arrêt des instances du cluster pour préserver les crédits
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "==> Recherche des instances actives du cluster Kubernetes-Administration..." -ForegroundColor Cyan

$instanceIds = aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=running,pending" `
  --query "Reservations[].Instances[].InstanceId" `
  --output text

if (-not $instanceIds -or $instanceIds.Trim() -eq "") {
  Write-Host "Aucune instance en cours d'exécution trouvée." -ForegroundColor Yellow
} else {
  Write-Host "==> Arrêt des instances : $instanceIds" -ForegroundColor Cyan
  $ids = $instanceIds -split '\s+' | Where-Object { $_ -ne "" }
  aws ec2 stop-instances --instance-ids $ids | Out-Null
  Write-Host "Attente de l'arrêt complet..." -ForegroundColor Gray
  aws ec2 wait instance-stopped --instance-ids $ids
  Write-Host "Instances arrêtées avec succès. Seul le stockage EBS est facturé." -ForegroundColor Green
}
