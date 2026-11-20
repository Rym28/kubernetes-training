#!/bin/bash
# ==============================================================================
# Clôture définitive : Destruction complète de l'infrastructure Terraform
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
  echo "Erreur : Répertoire Terraform introuvable dans ${TERRAFORM_DIR}" >&2
  exit 1
fi

cd "${TERRAFORM_DIR}"

AUTO_APPROVE=""
if [[ "${1:-}" == "-y" || "${1:-}" == "--auto-approve" ]]; then
  AUTO_APPROVE="-auto-approve"
fi

echo "==> Destruction de l'infrastructure Kubernetes sur AWS via Terraform..."
terraform destroy ${AUTO_APPROVE}
echo "==> Infrastructure détruite avec succès. Crédits AWS préservés."
