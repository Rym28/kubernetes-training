#!/bin/bash
# ==============================================================================
# Cluster Kubernetes express sur AWS Academy (Linux / macOS / Git Bash)
#
# Une seule commande enchaîne tout : identifiants AWS -> Terraform (3 EC2)
# -> kubeadm init -> Calico -> kubeadm join -> composants de la formation
# -> kubeconfig sur votre poste.
# Prérequis : le bloc « AWS CLI » du Learner Lab collé dans ~/.aws/credentials.
#
# Usage (depuis la racine du dépôt) :
#   bash labs/01-Installation-Cluster/scripts/create-cluster.sh
#
# Options :
#   --region <région>   us-east-1 (défaut) ou us-west-2
#
# Relançable à volonté : chaque étape déjà faite est sautée (instances
# arrêtées redémarrées, cluster déjà initialisé, workers déjà raccordés…).
# ==============================================================================
set -euo pipefail

REGION="us-east-1"
while [ $# -gt 0 ]; do
  case "$1" in
    --region) REGION="${2:-}"; shift ;;
    -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1 (voir --help)" >&2; exit 1 ;;
  esac
  shift
done
case "$REGION" in us-east-1 | us-west-2) ;; *) echo "Région non autorisée par le Learner Lab : $REGION" >&2; exit 1 ;; esac

START=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
KEY="${TF_DIR}/labsuser.pem"
KNOWN_HOSTS="${TF_DIR}/.known_hosts"
KUBECONFIG_OUT="${TF_DIR}/kubeconfig.yaml"
EXPRESS_VARS="${TF_DIR}/express.auto.tfvars"
AUTO_KEY_NAME="k8s-formation-key"

step() { printf '\n\033[36m==> [%s/8] %s\033[0m\n' "$1" "$2"; }
die() { printf '\n\033[31mERREUR : %s\033[0m\n' "$1" >&2; exit 1; }
ok() { printf '   \033[32m%s\033[0m\n' "$1"; }

# ------------------------------------------------------------------------------
step 1 "Vérification des outils (terraform, aws, ssh, kubectl)"
# ------------------------------------------------------------------------------
for tool in terraform aws ssh scp; do
  command -v "$tool" >/dev/null || die "$tool est absent : installez-le (Atelier 01, exercice 2, étape 3), puis relancez."
  echo "   $tool : OK"
done
HAS_KUBECTL=1
command -v kubectl >/dev/null || { HAS_KUBECTL=0; echo "   kubectl absent : le cluster sera créé, utilisez-le en Option B (SSH)."; }

# ------------------------------------------------------------------------------
step 2 "Identifiants AWS Academy (région ${REGION})"
# ------------------------------------------------------------------------------
# Des variables AWS_* résiduelles primeraient sur le fichier credentials (piège ExpiredToken).
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
aws configure set region "$REGION"

# « sts get-caller-identity » réussit même quand le Learner Lab est arrêté : AWS Academy
# applique alors la politique voc-cancel-cred qui refuse tout le reste. On teste donc un
# vrai appel EC2, comme celui que Terraform fera ensuite.
aws_ok() { aws ec2 describe-vpcs --max-items 1 --query "Vpcs[0].VpcId" --output text >/dev/null 2>&1; }

aws_ok || die "AWS refuse les identifiants de ~/.aws/credentials.
  Learner Lab démarré (voyant vert) > AWS Details > AWS CLI > Show : copiez le bloc,
  collez-le dans ce fichier à la place de l'ancien contenu, enregistrez, puis relancez."
ok "Connecté : $(aws sts get-caller-identity --query Arn --output text)"

# ------------------------------------------------------------------------------
step 3 "Initialisation de Terraform et clé SSH"
# ------------------------------------------------------------------------------
terraform -chdir="$TF_DIR" init -input=false -upgrade=false >/dev/null \
  || die "terraform init a échoué (accès Internet au registre Terraform ?)."

has_nodes=0
terraform -chdir="$TF_DIR" state list 2>/dev/null | grep -q aws_instance && has_nodes=1

# Nom de paire de clés déjà retenu par un passage précédent du script
key_name=""
[ -f "$EXPRESS_VARS" ] && key_name="$(sed -n 's/^key_name *= *"\(.*\)"/\1/p' "$EXPRESS_VARS")"

if [ -f "$KEY" ]; then
  echo "   labsuser.pem trouvée."
elif [ "$has_nodes" -eq 1 ]; then
  die "Des instances existent mais labsuser.pem est absente de ${TF_DIR} : téléchargez-la (AWS Details > Download PEM) puis relancez."
else
  echo "   labsuser.pem absente : création de la paire de clés '${AUTO_KEY_NAME}' dans AWS."
  aws ec2 delete-key-pair --key-name "$AUTO_KEY_NAME" >/dev/null 2>&1 || true
  aws ec2 create-key-pair --key-name "$AUTO_KEY_NAME" --query KeyMaterial --output text >"$KEY" \
    || { rm -f "$KEY"; die "Création de la paire de clés refusée : téléchargez labsuser.pem (AWS Details > Download PEM) dans ${TF_DIR} puis relancez."; }
  key_name="$AUTO_KEY_NAME"
fi
chmod 400 "$KEY"

echo "aws_region = \"${REGION}\"" >"$EXPRESS_VARS"
if [ -n "$key_name" ]; then echo "key_name   = \"${key_name}\"" >>"$EXPRESS_VARS"; fi

# ------------------------------------------------------------------------------
step 4 "Création (ou redémarrage) des 3 instances EC2 avec Terraform"
# ------------------------------------------------------------------------------
stopped="$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)"
if [ -n "${stopped//[[:space:]]/}" ]; then
  echo "   Redémarrage des instances arrêtées : ${stopped}"
  # shellcheck disable=SC2086
  aws ec2 start-instances --instance-ids $stopped >/dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-running --instance-ids $stopped
fi

terraform -chdir="$TF_DIR" apply -auto-approve -input=false \
  || die "terraform apply a échoué (voir les indices de l'Atelier 01, exercice 2, étape 6)."

CTRL_IP="$(terraform -chdir="$TF_DIR" output -raw control_plane_public_ip)"
W1_IP="$(terraform -chdir="$TF_DIR" output -raw worker_1_public_ip)"
W2_IP="$(terraform -chdir="$TF_DIR" output -raw worker_2_public_ip)"
NODE_NAMES=(k8s-control k8s-worker-1 k8s-worker-2)
NODE_IPS=("$CTRL_IP" "$W1_IP" "$W2_IP")

# ------------------------------------------------------------------------------
step 5 "Attente des nœuds (SSH puis installation de containerd et kubeadm)"
# ------------------------------------------------------------------------------
# Fichier known_hosts dédié, vidé à chaque passage : une IP réutilisée par un nouveau cluster
# ne bloque pas la connexion.
rm -f "$KNOWN_HOSTS"
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o "UserKnownHostsFile=${KNOWN_HOSTS}"
  -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes)
node() { ssh -n "${SSH_OPTS[@]}" "ubuntu@$1" "$2"; }

for i in 0 1 2; do
  name="${NODE_NAMES[$i]}"
  ip="${NODE_IPS[$i]}"
  echo "   ${name} (${ip}) : attente de SSH..."
  ready=0
  for _ in $(seq 1 40); do
    if node "$ip" true 2>/dev/null; then ready=1; break; fi
    sleep 10
  done
  [ "$ready" -eq 1 ] || die "${name} injoignable en SSH (${ip})."
  echo "   ${name} : attente de la fin de bootstrap.sh (3 à 5 min au premier démarrage)..."
  node "$ip" "cloud-init status --wait >/dev/null 2>&1; command -v kubeadm >/dev/null" \
    || die "bootstrap.sh a échoué sur ${name} : consultez /var/log/cloud-init-output.log sur le nœud."
  ok "${name} : prêt"
done

# ------------------------------------------------------------------------------
step 6 "Cluster kubeadm : init du control plane, Calico, join des workers"
# ------------------------------------------------------------------------------
scp "${SSH_OPTS[@]}" "${SCRIPT_DIR}/init-control-plane.sh" "${SCRIPT_DIR}/setup-addons.sh" "ubuntu@${CTRL_IP}:/tmp/" \
  || die "Copie des scripts vers k8s-control impossible."
node "$CTRL_IP" "sed -i 's/\r$//' /tmp/init-control-plane.sh /tmp/setup-addons.sh"

node "$CTRL_IP" "test -f /etc/kubernetes/admin.conf && echo '   Control plane deja initialise.' || bash /tmp/init-control-plane.sh" \
  || die "kubeadm init a échoué sur k8s-control (voir la sortie ci-dessus)."

JOIN="$(node "$CTRL_IP" "sudo kubeadm token create --print-join-command" | tail -n 1 | tr -d '\r')"
[ -n "$JOIN" ] || die "Impossible d'obtenir la commande kubeadm join."

for i in 1 2; do
  echo "   Raccordement de ${NODE_NAMES[$i]}..."
  node "${NODE_IPS[$i]}" "test -f /etc/kubernetes/kubelet.conf && echo '   Deja raccorde.' || sudo ${JOIN}" \
    || die "kubeadm join a échoué sur ${NODE_NAMES[$i]}."
done

echo "   Attente des 3 nœuds Ready (Calico)..."
node "$CTRL_IP" "kubectl wait --for=condition=Ready nodes --all --timeout=600s" \
  || die "Les nœuds ne sont pas Ready après 10 min : kubectl get pods -n calico-system sur k8s-control."

# ------------------------------------------------------------------------------
step 7 "Composants de la formation (Helm, local-path, Ingress NGINX, alias k)"
# ------------------------------------------------------------------------------
node "$CTRL_IP" "kubectl get namespace ingress-nginx >/dev/null 2>&1 && echo '   Composants deja installes.' || bash /tmp/setup-addons.sh >/tmp/setup-addons.log 2>&1 || { tail -n 30 /tmp/setup-addons.log; exit 1; }" \
  || die "setup-addons.sh a échoué (journal complet : /tmp/setup-addons.log sur k8s-control)."
ok "Composants installés."

# ------------------------------------------------------------------------------
step 8 "Kubeconfig sur votre poste"
# ------------------------------------------------------------------------------
scp "${SSH_OPTS[@]}" "ubuntu@${CTRL_IP}:.kube/config" "${KUBECONFIG_OUT}.tmp" || die "Copie du kubeconfig impossible."
sed -E "s#(server: https://)[^:/]+(:6443)#\1${CTRL_IP}\2#" "${KUBECONFIG_OUT}.tmp" >"$KUBECONFIG_OUT"
rm -f "${KUBECONFIG_OUT}.tmp"
chmod 600 "$KUBECONFIG_OUT"

if [ "$HAS_KUBECTL" -eq 1 ]; then
  kubectl --kubeconfig "$KUBECONFIG_OUT" get nodes -o wide \
    || echo "   kubectl ne joint pas l'API Server depuis votre poste (port 6443 filtré ?) : travaillez en Option B (SSH)."
fi

ELAPSED=$((($(date +%s) - START) / 60))
printf '\n\033[32m==================================================================\n'
printf ' Cluster prêt en %s min : k8s-control + k8s-worker-1 + k8s-worker-2\n' "$ELAPSED"
printf '==================================================================\033[0m\n'
echo ""
echo "Dans chaque terminal où vous utilisez kubectl :"
echo "  export KUBECONFIG=\"${KUBECONFIG_OUT}\""
echo ""
echo "SSH sur le control plane (Option B) :"
echo "  ssh -i \"${KEY}\" ubuntu@${CTRL_IP}"
echo ""
echo "Ingress NGINX : http://${CTRL_IP}:30080"
echo ""
echo "Le soir : bash labs/01-Installation-Cluster/scripts/stop-session.sh"
echo "Le matin : relancez simplement ce script (il redémarre les instances)."
echo "Fin de formation : bash labs/01-Installation-Cluster/scripts/destroy-cluster.sh"
