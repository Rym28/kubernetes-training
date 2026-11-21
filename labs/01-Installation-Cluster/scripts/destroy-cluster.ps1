# ==============================================================================
# Clôture définitive : Destruction complète de l'infrastructure Terraform
# ==============================================================================
[CmdletBinding()]
param(
  [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Resolve-Path (Join-Path $scriptDir "..\terraform")

if (!(Test-Path $terraformDir)) {
  Write-Error "Répertoire Terraform introuvable : $terraformDir"
  exit 1
}

Push-Location $terraformDir
try {
  Write-Host "==> Destruction de l'infrastructure Kubernetes sur AWS via Terraform..." -ForegroundColor Cyan
  if ($AutoApprove) {
    terraform destroy -auto-approve
  } else {
    terraform destroy
  }
  Write-Host "==> Infrastructure détruite avec succès. Crédits AWS préservés." -ForegroundColor Green
} finally {
  Pop-Location
}
