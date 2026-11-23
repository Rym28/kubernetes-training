# ==============================================================================
# Cluster Kubernetes express sur AWS Academy (Windows PowerShell)
#
# Une seule commande enchaîne tout : outils -> identifiants AWS -> Terraform
# (3 EC2) -> kubeadm init -> Calico -> kubeadm join -> composants de la
# formation -> kubeconfig sur votre poste.
# Prérequis : le bloc « AWS CLI » du Learner Lab collé dans ~/.aws/credentials.
#
# Usage (depuis la racine du dépôt) :
#   powershell -ExecutionPolicy Bypass -File .\labs\01-Installation-Cluster\scripts\create-cluster.ps1
#
# Options :
#   -Region          us-east-1 (défaut) ou us-west-2
#
# Relançable à volonté : chaque étape déjà faite est sautée (instances
# arrêtées redémarrées, cluster déjà initialisé, workers déjà raccordés…).
# ==============================================================================
[CmdletBinding()]
param(
  [ValidateSet("us-east-1", "us-west-2")][string]$Region = "us-east-1"
)

# Les commandes natives (aws, terraform, ssh) sont contrôlées via $LASTEXITCODE.
$ErrorActionPreference = "Continue"
$StartTime = Get-Date

$ScriptDir   = $PSScriptRoot
$TfDir       = (Resolve-Path (Join-Path $ScriptDir "..\terraform")).Path
$Key         = Join-Path $TfDir "labsuser.pem"
$KnownHosts  = Join-Path $TfDir ".known_hosts"
$Kubeconfig  = Join-Path $TfDir "kubeconfig.yaml"
$ExpressVars = Join-Path $TfDir "express.auto.tfvars"
$AutoKeyName = "k8s-formation-key"
$Utf8NoBom   = New-Object System.Text.UTF8Encoding $false

function Write-Step([int]$n, [string]$msg) { Write-Host "`n==> [$n/8] $msg" -ForegroundColor Cyan }
function Stop-Script([string]$msg) { Write-Host "`nERREUR : $msg" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------------------
Write-Step 1 "Vérification des outils (terraform, aws, kubectl, ssh)"
# ------------------------------------------------------------------------------
$WingetIds = [ordered]@{ terraform = "HashiCorp.Terraform"; aws = "Amazon.AWSCLI"; kubectl = "Kubernetes.kubectl" }
foreach ($tool in $WingetIds.Keys) {
  if (Get-Command $tool -ErrorAction SilentlyContinue) { Write-Host "   $tool : OK"; continue }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Stop-Script "$tool est absent et winget n'est pas disponible : installez-le (Atelier 01, exercice 2, étape 3)."
  }
  Write-Host "   $tool absent : installation via winget..." -ForegroundColor Yellow
  & winget install -e --id $WingetIds[$tool] --accept-source-agreements --accept-package-agreements --silent
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Stop-Script "$tool vient d'être installé mais reste introuvable : ouvrez un nouveau terminal et relancez le script."
  }
}
foreach ($tool in "ssh", "scp") {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Stop-Script "Client OpenSSH absent : Paramètres > Système > Fonctionnalités facultatives > Client OpenSSH."
  }
}

# ------------------------------------------------------------------------------
Write-Step 2 "Identifiants AWS Academy (région $Region)"
# ------------------------------------------------------------------------------
# Des variables AWS_* résiduelles primeraient sur le fichier credentials (piège ExpiredToken).
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN, Env:AWS_PROFILE -ErrorAction SilentlyContinue
& aws configure set region $Region

# « sts get-caller-identity » réussit même quand le Learner Lab est arrêté : AWS Academy
# applique alors la politique voc-cancel-cred qui refuse tout le reste. On teste donc un
# vrai appel EC2, comme celui que Terraform fera ensuite.
function Test-AwsSession {
  $null = & aws ec2 describe-vpcs --max-items 1 --query "Vpcs[0].VpcId" --output text 2>&1
  return ($LASTEXITCODE -eq 0)
}

if (-not (Test-AwsSession)) {
  Stop-Script ("AWS refuse les identifiants de $env:USERPROFILE\.aws\credentials.`n" +
    "  Learner Lab démarré (voyant vert) > AWS Details > AWS CLI > Show : copiez le bloc,`n" +
    "  collez-le dans ce fichier à la place de l'ancien contenu, enregistrez, puis relancez.")
}
$arn = & aws sts get-caller-identity --query Arn --output text
Write-Host "   Connecté : $arn" -ForegroundColor Green

# ------------------------------------------------------------------------------
Write-Step 3 "Initialisation de Terraform et clé SSH"
# ------------------------------------------------------------------------------
& terraform "-chdir=$TfDir" init -input=false -upgrade=false | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Script "terraform init a échoué (accès Internet au registre Terraform ?)." }

$hasNodes = [bool]((& terraform "-chdir=$TfDir" state list 2>$null) -match "aws_instance")

# Nom de paire de clés déjà retenu par un passage précédent du script
$keyName = $null
if (Test-Path $ExpressVars) {
  $m = Select-String -Path $ExpressVars -Pattern 'key_name\s*=\s*"([^"]+)"'
  if ($m) { $keyName = $m.Matches[0].Groups[1].Value }
}

if (Test-Path $Key) {
  Write-Host "   labsuser.pem trouvée."
} elseif ($hasNodes) {
  Stop-Script "Des instances existent mais labsuser.pem est absente de $TfDir : téléchargez-la (AWS Details > Download PEM) puis relancez."
} else {
  Write-Host "   labsuser.pem absente : création de la paire de clés '$AutoKeyName' dans AWS."
  $null = & aws ec2 delete-key-pair --key-name $AutoKeyName 2>&1
  $material = & aws ec2 create-key-pair --key-name $AutoKeyName --query KeyMaterial --output text
  if ($LASTEXITCODE -ne 0 -or -not $material) {
    Stop-Script "Création de la paire de clés refusée : téléchargez labsuser.pem (AWS Details > Download PEM) dans $TfDir puis relancez."
  }
  [System.IO.File]::WriteAllText($Key, (($material -join "`n").Trim() + "`n"), $Utf8NoBom)
  $keyName = $AutoKeyName
}
# ssh refuse une clé lisible par d'autres utilisateurs
& icacls $Key /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null

$vars = "aws_region = `"$Region`"`n"
if ($keyName) { $vars += "key_name   = `"$keyName`"`n" }
[System.IO.File]::WriteAllText($ExpressVars, $vars, $Utf8NoBom)

# ------------------------------------------------------------------------------
Write-Step 4 "Création (ou redémarrage) des 3 instances EC2 avec Terraform"
# ------------------------------------------------------------------------------
$stopped = & aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=Kubernetes-Administration" "Name=instance-state-name,Values=stopped" `
  --query "Reservations[].Instances[].InstanceId" --output text
if ($stopped -and $stopped.Trim()) {
  $ids = $stopped.Trim() -split '\s+'
  Write-Host "   Redémarrage des instances arrêtées : $($ids -join ', ')"
  & aws ec2 start-instances --instance-ids $ids | Out-Null
  & aws ec2 wait instance-running --instance-ids $ids
}

& terraform "-chdir=$TfDir" apply -auto-approve -input=false
if ($LASTEXITCODE -ne 0) { Stop-Script "terraform apply a échoué (voir les indices de l'Atelier 01, exercice 2, étape 6)." }

$CtrlIp = (& terraform "-chdir=$TfDir" output -raw control_plane_public_ip).Trim()
$W1Ip   = (& terraform "-chdir=$TfDir" output -raw worker_1_public_ip).Trim()
$W2Ip   = (& terraform "-chdir=$TfDir" output -raw worker_2_public_ip).Trim()
$Nodes  = [ordered]@{ "k8s-control" = $CtrlIp; "k8s-worker-1" = $W1Ip; "k8s-worker-2" = $W2Ip }

# ------------------------------------------------------------------------------
Write-Step 5 "Attente des nœuds (SSH puis installation de containerd et kubeadm)"
# ------------------------------------------------------------------------------
# Fichier known_hosts dédié, vidé à chaque passage : une IP réutilisée par un nouveau cluster
# ne bloque pas la connexion.
if (Test-Path $KnownHosts) { Remove-Item $KnownHosts -Force }
$SshOpts = @("-i", $Key, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=$KnownHosts",
             "-o", "ConnectTimeout=10", "-o", "LogLevel=ERROR", "-o", "BatchMode=yes")

function Invoke-Node([string]$ip, [string]$cmd) {
  & ssh @SshOpts "ubuntu@$ip" $cmd | Out-Host
  return $LASTEXITCODE
}

foreach ($name in $Nodes.Keys) {
  $ip = $Nodes[$name]
  Write-Host "   $name ($ip) : attente de SSH..."
  $ok = $false
  for ($i = 0; $i -lt 40; $i++) {
    & ssh @SshOpts "ubuntu@$ip" "true" 2>$null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 10
  }
  if (-not $ok) { Stop-Script "$name injoignable en SSH ($ip)." }
  Write-Host "   $name : attente de la fin de bootstrap.sh (3 à 5 min au premier démarrage)..."
  if ((Invoke-Node $ip "cloud-init status --wait >/dev/null 2>&1; command -v kubeadm >/dev/null") -ne 0) {
    Stop-Script "bootstrap.sh a échoué sur $name : consultez /var/log/cloud-init-output.log sur le nœud."
  }
  Write-Host "   $name : prêt" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
Write-Step 6 "Cluster kubeadm : init du control plane, Calico, join des workers"
# ------------------------------------------------------------------------------
& scp @SshOpts (Join-Path $ScriptDir "init-control-plane.sh") (Join-Path $ScriptDir "setup-addons.sh") "ubuntu@${CtrlIp}:/tmp/"
if ($LASTEXITCODE -ne 0) { Stop-Script "Copie des scripts vers k8s-control impossible." }
$null = Invoke-Node $CtrlIp 'sed -i ''s/\r$//'' /tmp/init-control-plane.sh /tmp/setup-addons.sh'

if ((Invoke-Node $CtrlIp "test -f /etc/kubernetes/admin.conf && echo '   Control plane deja initialise.' || bash /tmp/init-control-plane.sh") -ne 0) {
  Stop-Script "kubeadm init a échoué sur k8s-control (voir la sortie ci-dessus)."
}

$join = (& ssh @SshOpts "ubuntu@$CtrlIp" "sudo kubeadm token create --print-join-command" | Select-Object -Last 1)
if ($LASTEXITCODE -ne 0 -or -not $join) { Stop-Script "Impossible d'obtenir la commande kubeadm join." }
$join = $join.Trim()

foreach ($name in "k8s-worker-1", "k8s-worker-2") {
  Write-Host "   Raccordement de $name..."
  if ((Invoke-Node $Nodes[$name] "test -f /etc/kubernetes/kubelet.conf && echo '   Deja raccorde.' || sudo $join") -ne 0) {
    Stop-Script "kubeadm join a échoué sur $name."
  }
}

Write-Host "   Attente des 3 nœuds Ready (Calico)..."
if ((Invoke-Node $CtrlIp "kubectl wait --for=condition=Ready nodes --all --timeout=600s") -ne 0) {
  Stop-Script "Les nœuds ne sont pas Ready après 10 min : kubectl get pods -n calico-system sur k8s-control."
}

# ------------------------------------------------------------------------------
Write-Step 7 "Composants de la formation (Helm, local-path, Ingress NGINX, alias k)"
# ------------------------------------------------------------------------------
if ((Invoke-Node $CtrlIp "kubectl get namespace ingress-nginx >/dev/null 2>&1 && echo '   Composants deja installes.' || bash /tmp/setup-addons.sh >/tmp/setup-addons.log 2>&1 || { tail -n 30 /tmp/setup-addons.log; exit 1; }") -ne 0) {
  Stop-Script "setup-addons.sh a échoué (journal complet : /tmp/setup-addons.log sur k8s-control)."
}
Write-Host "   Composants installés." -ForegroundColor Green

# ------------------------------------------------------------------------------
Write-Step 8 "Kubeconfig sur votre poste"
# ------------------------------------------------------------------------------
& scp @SshOpts "ubuntu@${CtrlIp}:.kube/config" "$Kubeconfig.tmp"
if ($LASTEXITCODE -ne 0) { Stop-Script "Copie du kubeconfig impossible." }
$content = (Get-Content -Raw "$Kubeconfig.tmp") -replace 'server: https://[^:/]+:6443', "server: https://${CtrlIp}:6443"
[System.IO.File]::WriteAllText($Kubeconfig, $content, $Utf8NoBom)
Remove-Item "$Kubeconfig.tmp"

& kubectl --kubeconfig $Kubeconfig get nodes -o wide
if ($LASTEXITCODE -ne 0) {
  Write-Host "   kubectl ne joint pas l'API Server depuis votre poste (port 6443 filtré ?) : travaillez en Option B (SSH)." -ForegroundColor Yellow
}

$elapsed = [int]((Get-Date) - $StartTime).TotalMinutes
Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host " Cluster prêt en $elapsed min : k8s-control + k8s-worker-1 + k8s-worker-2" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "`nDans chaque terminal où vous utilisez kubectl :"
Write-Host "  `$env:KUBECONFIG = `"$Kubeconfig`""
Write-Host "`nSSH sur le control plane (Option B) :"
Write-Host "  ssh -i `"$Key`" ubuntu@$CtrlIp"
Write-Host "`nIngress NGINX : http://${CtrlIp}:30080"
Write-Host "`nLe soir : .\labs\01-Installation-Cluster\scripts\stop-session.ps1"
Write-Host "Le matin : relancez simplement ce script (il redémarre les instances)."
Write-Host "Fin de formation : .\labs\01-Installation-Cluster\scripts\destroy-cluster.ps1 -AutoApprove"
